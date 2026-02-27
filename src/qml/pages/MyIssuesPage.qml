/**
 * MyIssuesPage.qml
 *
 * Página para listar issues do usuário e atualizar issues selecionadas
 * Refatorado seguindo Clean Code e SOLID
 * Usa componentes reutilizáveis e controllers
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami
import "../components/forms"
import "../components/lists"
import "../components/controls"
import "../components/panes"
import "../utils/DialogHelpers.js" as DialogHelpers
import "../utils/FormatUtils.js" as FormatUtils
import "../utils/MyIssuesPageLogic.js" as MyIssuesPageLogic

Kirigami.Page {
    id: page

    title: qsTr("Minhas Issues")

    // Habilitar foco para capturar atalhos de teclado
    focus: true

    property var applicationWindow: null
    // Issue selecionada atualmente
    property string selectedIssueKey: ""

    // Status original da issue (para comparar antes de atualizar)
    property string originalStatus: ""

    // Estado do processamento
    property bool isProcessing: false

    // Propriedades compartilhadas para sincronizar epic entre abas
    property string sharedEpicKey: ""
    property string sharedEpicSummary: ""

    signal epicSelected(string key, string summary)
    // Estado de carregamento dos detalhes da issue (parte inferior)
    property bool isDetailsLoading: false

    // Cache: true = já houve busca (mesmo vazia); evita recarregar ao trocar de aba
    property bool hasCachedData: false

    // Recebidos do Main (passados explicitamente)
    property var issueModel: null
    property var jiraService: null
    property var clipboardHelper: null
    property var gitCommandHelper: null
    property var myIssuesModel: null
    property var timerService: null
    property var timerModel: null
    property var worklogSyncService: null
    property var hideWindowFn: null
    property var githubService: null

    // Estado para fluxo de transição em duas fases (TO DO → … → IN PROGRESS → diálogo → target)
    property string _pendingTwoPhaseTarget: ""
    // Estado para "sync depois update" (uma fase ou duas): { issueKey, fieldData?, worklogData?, epicKey?, originalStatus?, isTwoPhase, targetStatus? }
    property var _pendingUpdateAfterSync: null
    // Lista de worklogs pendentes usada ao clicar Sincronizar (para obter sessionIds)
    property var _pendingWorklogsList: []
    // Flag para indicar que estamos em uma transição de duas fases
    property bool _isTwoPhaseTransition: false
    // Issue key para iniciar timer após transição automática para IN PROGRESS
    property string _pendingTimerStartIssueKey: ""
    // Quando true, o erro do jiraService já foi mostrado no ProcessDialog; evita abrir ErrorDialog por cima
    property bool _jiraErrorShownInProcessDialog: false
    // Quick actions (Cancel/Block/Unblock): true enquanto o diálogo está aberto; usado para refresh + toast em issueUpdated e ErrorDialog em errorOccurred
    property bool _quickActionInProgress: false
    // Tipo da última quick action ("cancel" | "block" | "unblock") para atualizar lista e status imediatamente
    property string _lastQuickActionType: ""
    property var _ctxVoiceInputService: typeof voiceInputService !== "undefined" ? voiceInputService : null // qmllint disable unqualified
    /** Quando definido (ex.: aba work item), usa este em vez do contexto. */
    property var voiceInputServiceOverride: null
    property var _effectiveVoiceInputService: (voiceInputServiceOverride !== null && voiceInputServiceOverride !== undefined) ? voiceInputServiceOverride : _ctxVoiceInputService

    // Diálogo unificado de processo (update: confirm/progress/success/error)
    property var _processDialog: null
    property var _processDialogComponent: null
    property var _pendingProcessDialogAction: null  // function(dlg) chamada quando o diálogo estiver pronto (estratégia IssueFormPage: criar na ação)
    // Diálogo de progresso da busca (separado para não conflitar com update)
    property var searchProgressDialog: null

    // Controller para lógica de negócio
    property var controller: null

    // Property aliases para permitir acesso externo aos componentes
    property alias issueSearchForm: issueSearchForm
    property alias issueList: issueList
    property alias detailPane: detailPane

    // Função pública para cancelar (usada pelo botão global e pela tecla ESC)
    // Esconde a janela ao invés de fechar a aplicação
    function onCancelRequested() {
        if (page.hideWindowFn && typeof page.hideWindowFn === "function") {
            page.hideWindowFn(); // qmllint disable use-proper-function
        }
    }

    // Status atual da issue selecionada (para visibilidade dos botões de quick action no header)
    readonly property string _quickActionStatus: {
        var s = (page.originalStatus || "").trim() || (page.issueModel ? (page.issueModel.statusInicial || "").trim() : "");
        return String(s).toUpperCase();
    }

    // Ações da página (Kirigami 6 usa 'actions' ao invés de 'mainAction').
    // Bloquear / Desbloquear / Cancelar ficam no header global (MainHeader), ao lado de "Atualizar task".
    actions: [
        Kirigami.Action {
            id: refreshAction
            text: qsTr("Buscar")
            icon.name: "search"
            enabled: !(page.myIssuesModel && page.myIssuesModel.isLoading)
            onTriggered: {
                if (page.issueSearchForm) {
                    var query = page.issueSearchForm.getQuery();
                    page.refreshIssues(query);
                }
            }
        }
    ]

    // Função pública para botão global (Main.qml)
    function refreshIssuesFromToolbar() {
        if (page.issueSearchForm) {
            var query = page.issueSearchForm.getQuery();
            page.refreshIssues(query);
        }
    }

    // Inicia timer para issueKey; só tenta transição para IN PROGRESS se o status atual for *anterior* a IN PROGRESS.
    // Se já estiver em IN PROGRESS ou posterior, inicia o timer diretamente.
    function _startTimerAfterInProgress(issueKey) {
        if (!page.timerService || !issueKey) return;

        // Quando temos o status da issue (ex.: issue selecionada e detalhes carregados), evitar transição se já for IN PROGRESS ou depois
        if (page.selectedIssueKey === issueKey && page.issueModel && page.issueModel.statusSequence && page.originalStatus) {
            var seq = page.issueModel.statusSequence;
            var inDevIdx = seq.indexOf("IN PROGRESS");
            if (inDevIdx >= 0) {
                var currentIdx = seq.indexOf(page.originalStatus);
                if (currentIdx >= inDevIdx) {
                    page.timerService.start(issueKey);
                    return;
                }
            }
        }

        if (!page.jiraService || !page.jiraService.transitionToInProgressIfNeeded(issueKey)) {
            page.timerService.start(issueKey);
            return;
        }
        page._pendingTimerStartIssueKey = issueKey;
        page._jiraErrorShownInProcessDialog = true;  // Erros deste fluxo só no ProcessDialog; evita ErrorDialog duplicado
        page._ensureProcessDialogThen(function (dlg) {
            if (!dlg.opened) dlg.openInProgress(qsTr("Transicionando para IN PROGRESS..."));
            else dlg.updateProgress(0, qsTr("Transicionando para IN PROGRESS..."));
        });
    }

    // Função pública para iniciar timer do header (Main.qml)
    function startTimerFromToolbar() {
        if (!page.timerService || !page.timerModel || !page.selectedIssueKey) {
            return;
        }

        // Se está em pausa, cancelar pausa e iniciar timer
        if (page.timerModel && page.timerModel.isOnBreak) {
            page.timerService.cancelBreak();
            Qt.callLater(function () {
                if (page.timerService && page.selectedIssueKey) {
                    page._startTimerAfterInProgress(page.selectedIssueKey);
                }
            });
            return;
        }

        // Se já há timer ativo para esta issue
        if (page.timerModel.issueKey === page.selectedIssueKey && page.timerModel.state !== "idle") {
            if (page.timerModel.state === "running") {
                page.timerService.stop();
            }
        } else
        // Se há timer ativo para outra issue, parar e iniciar novo
        if (page.timerModel.state !== "idle" && page.timerModel.issueKey !== page.selectedIssueKey) {
            page.timerService.stop();
            Qt.callLater(function () {
                if (page.timerService && page.selectedIssueKey) {
                    page._startTimerAfterInProgress(page.selectedIssueKey);
                }
            });
        } else
        // Iniciar novo timer
        {
            page._startTimerAfterInProgress(page.selectedIssueKey);
        }
    }

    // Atalhos locais (Ctrl+Enter e ESC)
    Keys.onPressed: function (event) {
        // Ctrl+Enter: atualizar lista
        if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
            page.refreshIssuesFromToolbar();
            event.accepted = true;
            return;
        }

        // ESC: cancelar
        if (event.key === Qt.Key_Escape) {
            page.onCancelRequested();
            event.accepted = true;
        }
    }

    /** @param {string} query - Query de busca
        @param {boolean} showProgress - Se true, mostra "Buscando issues...". Se ProcessDialog já estiver aberto, usa-o (sem sobrepor); senão usa ProgressDialog. Use false para actualizar em background. */
    function refreshIssues(query, showProgress) {
        if (!page.myIssuesModel) {
            return;
        }

        var showProgressDialog = showProgress !== false;

        DialogHelpers.hideProgress(page.searchProgressDialog);
        page.searchProgressDialog = null;

        var finishAndSelectFirst = function () {
            Qt.callLater(function () {
                if (page.myIssuesModel && page.myIssuesModel.issues && page.myIssuesModel.issues.length > 0) {
                    var firstIssue = page.myIssuesModel.issues[0];
                    if (firstIssue && firstIssue.key && page.issueList) {
                        page.issueList.selectIssue(firstIssue.key);
                    }
                }
            });
        };

        if (showProgressDialog && page._processDialog && page._processDialog.opened) {
            // Recarregamento dentro do mesmo ProcessDialog (ex.: após transição de status)
            page._processDialog.transitionToProgress(qsTr("Buscando issues..."));
            page._processDialog.updateProgress(0, qsTr("Buscando issues..."));

            var loadingConnection = function (isLoading) {
                if (isLoading) {
                    if (page._processDialog) {
                        page._processDialog.updateProgress(50, qsTr("Buscando issues..."));
                    }
                } else {
                    Qt.callLater(function () {
                        if (page.myIssuesModel) page.hasCachedData = true;
                        if (page._processDialog) {
                            page._processDialog.updateProgress(100, qsTr("Busca concluída!"));
                            Qt.callLater(function () {
                                page._processDialog.close();
                                finishAndSelectFirst();
                            });
                        }
                        if (page.myIssuesModel) {
                            page.myIssuesModel.loadingChanged.disconnect(loadingConnection);
                        }
                    });
                }
            };

            if (page.myIssuesModel) {
                page.myIssuesModel.loadingChanged.connect(loadingConnection);
            }
        } else if (showProgressDialog) {
            page.searchProgressDialog = DialogHelpers.showProgress(page, "../components/dialogs/ProgressDialog.qml");
        }

        if (page.searchProgressDialog) {
            page.searchProgressDialog.updateProgress(0, qsTr("Buscando issues..."));

            var loadingConnection = function (isLoading) {
                if (isLoading) {
                    if (page.searchProgressDialog) {
                        page.searchProgressDialog.updateProgress(50, qsTr("Buscando issues..."));
                    }
                } else {
                    Qt.callLater(function () {
                        if (page.myIssuesModel) page.hasCachedData = true;
                        if (page.searchProgressDialog) {
                            page.searchProgressDialog.updateProgress(100, qsTr("Busca concluída!"));
                            Qt.callLater(function () {
                                DialogHelpers.hideProgress(page.searchProgressDialog);
                                page.searchProgressDialog = null;
                                finishAndSelectFirst();
                            });
                        }
                        if (page.myIssuesModel) {
                            page.myIssuesModel.loadingChanged.disconnect(loadingConnection);
                        }
                    });
                }
            };

            if (page.myIssuesModel) {
                page.myIssuesModel.loadingChanged.connect(loadingConnection);
            }
        }

        // Se showProgress=false (background), conectar para setar hasCachedData ao concluir
        if (!showProgressDialog && page.myIssuesModel) {
            var cacheConnection = function (isLoading) {
                if (!isLoading) {
                    page.hasCachedData = true;
                    if (page.myIssuesModel) {
                        page.myIssuesModel.loadingChanged.disconnect(cacheConnection);
                    }
                }
            };
            page.myIssuesModel.loadingChanged.connect(cacheConnection);
        }

        // Iniciar busca
        if (page.controller) {
            page.controller.searchIssues(query || "");
        } else {
            page.myIssuesModel.refreshIssues(query || "");
        }
    }

    // Criar controller; ProcessDialog é criado quando necessário via _ensureProcessDialogThen (como IssueFormPage + DialogHelpers)
    Component.onCompleted: {
        var dialogComp = Qt.createComponent("../components/dialogs/ProcessDialog.qml");
        if (typeof console !== "undefined" && console.log) {
            console.log("[MyIssuesPage] ProcessDialog createComponent status:", dialogComp.status, "error:", dialogComp.status === Component.Error ? dialogComp.errorString() : "");
        }
        function onProcessDialogComponentReady() {
            if (dialogComp.status !== Component.Ready) return;
            if (typeof console !== "undefined" && console.log) {
                console.log("[MyIssuesPage] ProcessDialog component Ready, creating instance");
            }
            page._processDialogComponent = dialogComp;
            if (page._processDialog) {
                if (typeof console !== "undefined" && console.log) {
                    console.log("[MyIssuesPage] ProcessDialog already exists, running pending if any");
                }
                page._runPendingProcessDialogAction();
                return;
            }
            var parent = page.parent || page;
            if (typeof console !== "undefined" && console.log) {
                console.log("[MyIssuesPage] createObject parent:", parent ? "set" : "null", "page.parent:", page.parent ? "set" : "null");
            }
            var dlg = dialogComp.createObject(parent, { applicationWindow: page.applicationWindow });
            if (dlg) {
                dlg.applicationWindow = Qt.binding(function () { return page.applicationWindow });
                dlg.cancelClicked.connect(page._onPendingWorklogsDialogCancel);
                dlg.skipSyncClicked.connect(page._onPendingWorklogsDialogSkip);
                dlg.syncClicked.connect(page._onPendingWorklogsDialogSync);
                dlg.closed.connect(function () {
                    page._jiraErrorShownInProcessDialog = false;
                });
                page._processDialog = dlg;
                if (typeof console !== "undefined" && console.log) {
                    console.log("[MyIssuesPage] ProcessDialog instance created, running pending action");
                }
                page._runPendingProcessDialogAction();
            } else {
                if (typeof console !== "undefined" && console.warn) {
                    console.warn("[MyIssuesPage] ProcessDialog createObject returned null");
                }
            }
        }
        if (dialogComp.status === Component.Ready) {
            onProcessDialogComponentReady();
        } else {
            if (typeof console !== "undefined" && console.log) {
                console.log("[MyIssuesPage] ProcessDialog component not Ready, connecting statusChanged");
            }
            dialogComp.statusChanged.connect(function () {
                if (typeof console !== "undefined" && console.log) {
                    console.log("[MyIssuesPage] ProcessDialog statusChanged:", dialogComp.status);
                }
                if (dialogComp.status === Component.Ready) onProcessDialogComponentReady();
            });
        }

        var component = Qt.createComponent("../controllers/MyIssuesController.qml");
        if (component.status === Component.Ready) {
            page.controller = component.createObject(page, {
                jiraService: page.jiraService,
                myIssuesModel: page.myIssuesModel,
                issueModel: page.issueModel,
                enabled: true
            });

            if (page.controller) {
                page.controller.updateStarted.connect(function () {
                    page.isProcessing = true;
                    page._ensureProcessDialogThen(function (dlg) {
                        if (dlg.opened) {
                            dlg.transitionToProgress(qsTr("Atualizando issue..."));
                        } else {
                            dlg.openInProgress(qsTr("Atualizando issue..."));
                        }
                    });
                });

                page.controller.updateCompleted.connect(function (issueKey) {
                    page.isProcessing = false;
                    if (page._processDialog) {
                        page._processDialog.transitionToSuccess(issueKey, "", true);
                    }
                    // Atualizar item na lista em memória (não refazer busca)
                    var summary = (page.issueModel && page.issueModel.summary) ? page.issueModel.summary : "";
                    var status = (page.issueModel && page.issueModel.statusInicial) ? page.issueModel.statusInicial : "";
                    var prioridade = (page.issueModel && page.issueModel.prioridade) ? page.issueModel.prioridade : "";
                    if (page.myIssuesModel && issueKey && typeof page.myIssuesModel.updateIssueInList === "function") {
                        page.myIssuesModel.updateIssueInList(issueKey, summary, status, prioridade, "");
                    }
                });

                page.controller.updateFailed.connect(function (errorMessage) {
                    if (page.applicationWindow && page.applicationWindow._jiraErrorShownInCreateFlow) {
                        return;
                    }
                    if (typeof console !== "undefined" && console.log) {
                        console.log("[MyIssuesPage] controller.updateFailed -> ProcessDialog.transitionToError");
                    }
                    page.isProcessing = false;
                    if (page._processDialog) {
                        page._processDialog.transitionToError(errorMessage);
                    }
                });

                page.controller.issueSelected.connect(function (issueKey, issueData) {
                    if (issueKey && page.issueList) {
                        page.issueList.selectIssue(issueKey);
                    }
                });
            }
        }
    }

    // Mesma hierarquia que IssueFormPage: ScrollView > Item > ColumnLayout (margens no ColumnLayout)
    Controls.SplitView {
        id: splitView
        anchors.fill: parent
        orientation: Qt.Horizontal
        handle: SplitViewHandle { }

        // Coluna Esquerda (40% - Master): Busca, Lista e Botão Timer
        Controls.ScrollView {
            id: leftScrollView
            Controls.SplitView.preferredWidth: parent.width * 0.4
            Controls.SplitView.minimumWidth: 300
            Controls.SplitView.fillHeight: true
            clip: true
            contentWidth: availableWidth

                Item {
                    width: leftScrollView.availableWidth
                // Garantir altura mínima = viewport para o list preencher o pane (evita espaço vazio abaixo da lista)
                height: Math.max(leftColumnLayout.implicitHeight, leftScrollView.availableHeight)

                ColumnLayout {
                    id: leftColumnLayout
                    anchors.fill: parent
                    anchors.leftMargin: Kirigami.Units.largeSpacing
                    anchors.rightMargin: Kirigami.Units.largeSpacing
                    spacing: Kirigami.Units.largeSpacing

                    // Busca de issues usando componente reutilizável
                    IssueSearchForm {
                        id: issueSearchForm
                        Layout.fillWidth: true
                        enabled: !page.isProcessing
                        isLoading: page.myIssuesModel ? page.myIssuesModel.isLoading : false
                        placeholderText: qsTr("Buscar issues por resumo ou chave...")

                        onSearchRequested: function (query) {
                            page.refreshIssues(query);
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        Controls.Label {
                            text: qsTr("Issues atribuídas a você")
                            font.bold: true
                            Layout.fillWidth: true
                        }

                        Controls.Label {
                            text: qsTr("Ordenar:")
                            Layout.preferredWidth: 50
                        }

                        Controls.ComboBox {
                            id: sortCombo
                            Layout.preferredWidth: 120
                            model: [qsTr("Prioridade"), qsTr("Status"), qsTr("Chave")]
                            currentIndex: 0
                            onActivated: function(index) {
                                if (page.myIssuesModel) {
                                    var criteria = ["priority", "status", "key"][index]
                                    page.myIssuesModel.setSortBy(criteria)
                                }
                            }
                        }
                    }

                    // Lista de issues usando componente reutilizável
                    Item {
                        id: issueListContainer
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumHeight: 200

                        IssueList {
                            id: issueList
                            anchors.fill: parent
                            enabled: !page.isProcessing
                            model: page.myIssuesModel ? page.myIssuesModel.issues : []
                            sourceModel: page.myIssuesModel
                            isLoading: page.myIssuesModel ? page.myIssuesModel.isLoading : false
                            timerModel: page.timerModel
                            timerService: page.timerService

                            onStartTimerRequested: function (issueKey) {
                                if (issueKey && page && page.timerService)
                                    page._startTimerAfterInProgress(issueKey)
                            }
                            onIssueSelected: function (issueKey, issueData) {
                                page.selectedIssueKey = issueKey || "";
                                if (!issueKey) return;
                                Qt.callLater(function() { page.loadIssueDetails(issueKey); });
                            }
                        }
                    }
                }
            }
        }

        // Coluna Direita (60% - Detail)
        MyIssuesDetailPane {
            id: detailPane
            myIssuesPage: page
            applicationWindow: page.applicationWindow
            issueModel: page.issueModel
            selectedIssueKey: page.selectedIssueKey
            isProcessing: page.isProcessing
            isDetailsLoading: page.isDetailsLoading
            jiraService: page.jiraService
            clipboardHelper: page.clipboardHelper
            gitCommandHelper: page.gitCommandHelper
            voiceInputService: page._effectiveVoiceInputService
            githubService: page.githubService
            sharedEpicKey: page.sharedEpicKey
            sharedEpicSummary: page.sharedEpicSummary
            savedStatus: page.originalStatus

            onEpicSelected: function (key, summary) {
                page.epicSelected(key, summary);
            }
        }
    }

    // Log do fluxo Expandir com IA (voiceInputService)
    Connections {
        target: page._effectiveVoiceInputService || null
        function onFieldsFilled() {
            if (typeof console !== "undefined" && console.log) {
                var m = page.issueModel
                console.log("[MyIssuesPage] fieldsFilled received; issueModel=", !!m, "summaryLen=", m ? (m.summary || "").length : 0, "descriptionLen=", m ? (m.description || "").length : 0)
            }
        }
    }

    // Conectar signals do jiraService
    Connections {
        target: page.jiraService

        function onProgressUpdated(percentage, message) {
            if (page._processDialog) {
                page._processDialog.updateProgress(percentage, message);
            }
        }

        function onIssueUpdated(issueKey) {
            // Quando transitionFromInProgressToTarget completa (fase 2 de duas fases),
            // mostrar sucesso no mesmo ProcessDialog.
            // qmllint disable missing-property
            if (page._processDialog && page.isProcessing && page._isTwoPhaseTransition) {
            // qmllint enable missing-property
                page.isProcessing = false;
                page._isTwoPhaseTransition = false;
                page._processDialog.transitionToSuccess(issueKey, "", true);
                // Atualizar item na lista em memória (não refazer busca)
                var summary = (page.issueModel && page.issueModel.summary) ? page.issueModel.summary : "";
                var status = (page.issueModel && page.issueModel.statusInicial) ? page.issueModel.statusInicial : "";
                var prioridade = (page.issueModel && page.issueModel.prioridade) ? page.issueModel.prioridade : "";
                if (page.myIssuesModel && issueKey && typeof page.myIssuesModel.updateIssueInList === "function") {
                    page.myIssuesModel.updateIssueInList(issueKey, summary, status, prioridade, "");
                }
            } else if (page._lastQuickActionType !== "") {
                // Quick action concluída: atualizar lista e status imediatamente (sem esperar refresh)
                var newStatus = "";
                if (page._lastQuickActionType === "cancel") {
                    newStatus = "CANCELED";
                } else if (page._lastQuickActionType === "block") {
                    newStatus = "BLOCKED";
                } else if (page._lastQuickActionType === "unblock") {
                    newStatus = "IN PROGRESS";
                }
                if (newStatus && page.myIssuesModel && issueKey && typeof page.myIssuesModel.updateIssueInList === "function") {
                    var summary = (page.issueModel && page.issueModel.summary) ? page.issueModel.summary : "";
                    var prioridade = (page.issueModel && page.issueModel.prioridade) ? page.issueModel.prioridade : "";
                    page.myIssuesModel.updateIssueInList(issueKey, summary, newStatus, prioridade, "");
                }
                if (page.selectedIssueKey === issueKey) {
                    page.originalStatus = newStatus;
                    if (page.issueModel) {
                        page.issueModel.statusInicial = newStatus;
                    }
                }
                page._lastQuickActionType = "";
                page._quickActionInProgress = false;
                // Atualizar detalhes em background (para manter dados em sync)
                if (page.selectedIssueKey === issueKey && typeof page.loadIssueDetails === "function") {
                    page.loadIssueDetails(issueKey);
                }
                if (page.applicationWindow && typeof page.applicationWindow.showPassiveNotification === "function") {
                    page.applicationWindow.showPassiveNotification(qsTr("Issue %1 atualizada").arg(issueKey || ""), 4000);
                }
            }
        }

        function onInProgressReady(issueKey) {
            if (page._pendingTimerStartIssueKey && page._pendingTimerStartIssueKey === issueKey) {
                page._pendingTimerStartIssueKey = "";
                if (page._processDialog) page._processDialog.close();
                if (page.timerService) page.timerService.start(issueKey);
                // Recarregar dados da issue e a lista para refletir o novo status (IN PROGRESS)
                if (page.selectedIssueKey === issueKey && page.loadIssueDetails) {
                    page.loadIssueDetails(issueKey);
                }
                if (page.issueSearchForm) {
                    var query = page.issueSearchForm.getQuery();
                    page.refreshIssues(query);
                }
            }
        }

        function onErrorOccurred(errorMessage) {
            if (typeof console !== "undefined" && console.log) {
                console.log("[MyIssuesPage] jiraService.onErrorOccurred. _pendingTimerStartIssueKey=", page._pendingTimerStartIssueKey || "");
            }
            if (page._quickActionInProgress || page._lastQuickActionType !== "") {
                page._quickActionInProgress = false;
                page._lastQuickActionType = "";
                DialogHelpers.showError(page, "../components/dialogs/ErrorDialog.qml", errorMessage || qsTr("Erro ao transicionar"), "MyIssuesPage.quickAction");
            } else if (page._pendingTimerStartIssueKey) {
                page._pendingTimerStartIssueKey = "";
                if (typeof console !== "undefined" && console.log) {
                    console.log("[MyIssuesPage] jiraService.onErrorOccurred -> ProcessDialog.transitionToError");
                }
                if (page._processDialog) {
                    page._processDialog.transitionToError(errorMessage || qsTr("Erro ao transicionar"));
                } else {
                    page._ensureProcessDialogThen(function (dlg) {
                        dlg.transitionToError(errorMessage || qsTr("Erro ao transicionar"));
                    });
                }
            }
        }

        function onReachedInProgress(issueKey) {
            if (!issueKey || issueKey !== page.selectedIssueKey) return;
            var checkEnabled = page.jiraService.worklogCheckEnabled && page.jiraService.worklogCheckEnabled();
            var pending = (page.worklogSyncService && page.worklogSyncService.get_pending_worklogs_for_issue(issueKey)) || [];
            if (pending.length > 0 && checkEnabled) {
                var showDialog = page.jiraService.worklogCheckShowDialog && page.jiraService.worklogCheckShowDialog();
                if (showDialog) {
                    var totalFormatted = page._formatTotalFromPending(pending);
                    var targetStatus = page._pendingTwoPhaseTarget;
                    var blockIfPending = page.jiraService.worklogCheckBlockIfPending && page.jiraService.worklogCheckBlockIfPending();
                    page._pendingUpdateAfterSync = { issueKey: issueKey, isTwoPhase: true, targetStatus: targetStatus };
                    page._pendingWorklogsList = pending;
                    page._ensureProcessDialogThen(function (dlg) {
                        dlg.transitionToConfirm(pending, totalFormatted, targetStatus, blockIfPending);
                    });
                    return;
                }
                page._pendingUpdateAfterSync = { issueKey: issueKey, isTwoPhase: true, targetStatus: page._pendingTwoPhaseTarget };
                var sessionIds = pending.map(function(p) { return p.id; });
                page.worklogSyncService.sync_pending_worklogs(sessionIds);
            } else {
                // Sem pendentes: continuar para fase 2
                var targetStatus = page._pendingTwoPhaseTarget;
                page._pendingTwoPhaseTarget = "";
                if (page._processDialog) page._processDialog.updateProgress(0, qsTr("Transicionando para %1...").arg(targetStatus));
                page.jiraService.transitionFromInProgressToTarget(issueKey, targetStatus);
            }
        }
    }

    Connections {
        target: page.worklogSyncService || null
        function onSyncCompleted() {
            page._finishPendingUpdateAfterSync();
        }
        function onSyncError(sessionId, errorMessage) {
            page._pendingWorklogsList = [];
            if (page._pendingUpdateAfterSync && page._pendingUpdateAfterSync.isTwoPhase) {
                page._pendingTwoPhaseTarget = "";
                page._isTwoPhaseTransition = false;
            }
            page._pendingUpdateAfterSync = null;
            page.isProcessing = false;
            if (page._processDialog) {
                page._processDialog.transitionToError(errorMessage || qsTr("Erro ao sincronizar worklog"));
            }
        }
    }

    // Conectar signals do myIssuesModel para fechar diálogo de busca
    Connections {
        target: page.myIssuesModel

        function onErrorOccurred(errorMessage) {
            if (typeof console !== "undefined" && console.log) {
                console.log("[MyIssuesPage] myIssuesModel.onErrorOccurred. _jiraErrorShownInProcessDialog=", page._jiraErrorShownInProcessDialog);
            }
            if (page._jiraErrorShownInProcessDialog) {
                if (typeof console !== "undefined" && console.log) {
                    console.log("[MyIssuesPage] myIssuesModel.onErrorOccurred -> SKIP (erro já no ProcessDialog)");
                }
                return;
            }
            if (typeof console !== "undefined" && console.log) {
                console.log("[MyIssuesPage] myIssuesModel.onErrorOccurred -> DialogHelpers.showError (erro na busca de issues)");
            }
            DialogHelpers.hideProgress(page.searchProgressDialog);
            page.searchProgressDialog = null;
            DialogHelpers.showError(page, "../components/dialogs/ErrorDialog.qml", errorMessage, "MyIssuesPage.myIssuesModel");
        }
    }

    // Funções auxiliares
    function loadIssueDetails(issueKey) {
        if (!issueKey || !page.jiraService) {
            return;
        }
        // Delegar carregamento para o JiraService em modo assíncrono.
        // O overlay e o preenchimento dos campos são controlados pelos
        // sinais issueDetailsStarted / issueDetailsLoaded abaixo.
        page.jiraService.getIssueDetailsAsync(issueKey);
    }

    // Função pública para atualizar issue (chamada pelo botão global / atalho)
    function updateIssue() {
        if (typeof console !== "undefined" && console.log) {
            console.log("[MyIssuesPage] updateIssue called, selectedIssueKey=", page.selectedIssueKey || "");
        }
        if (!page.selectedIssueKey || page.selectedIssueKey === "") {
            page._ensureProcessDialogThen(function (dlg) {
                dlg.transitionToError(qsTr("Por favor, selecione uma task para atualizar"));
            });
            return;
        }
        if (!page.controller) {
            page._ensureProcessDialogThen(function (dlg) {
                dlg.transitionToError(qsTr("Controller não disponível"));
            });
            return;
        }

        var issueKey = page.selectedIssueKey;
        var fieldData = page.detailPane.getFieldData();
        var worklogData = page.detailPane.getWorklogData();
        var epicKey = page.detailPane.getEpicKey();
        var originalStatus = page.originalStatus;
        var targetStatus = (fieldData && fieldData.status) ? fieldData.status : "";

        function doUpdateBody() {
            if (typeof console !== "undefined" && console.log) {
                console.log("[MyIssuesPage] updateIssue: originalStatus=", originalStatus, "targetStatus=", targetStatus);
            }
            if (!targetStatus || targetStatus === originalStatus) {
                if (typeof console !== "undefined" && console.log) {
                    console.log("[MyIssuesPage] updateIssue: no status change, calling controller.updateIssue");
                }
                page.controller.updateIssue(issueKey, fieldData, worklogData, epicKey, originalStatus);
                return;
            }
            if (page.jiraService.needsTwoPhaseTransition(originalStatus, targetStatus)) {
                page._pendingTwoPhaseTarget = targetStatus;
                page._isTwoPhaseTransition = true;
                page._ensureProcessDialogThen(function (dlg) {
                    dlg.openInProgress(qsTr("Transicionando para IN PROGRESS..."));
                });
                page.controller.startTwoPhaseUpdate(issueKey, fieldData, worklogData, epicKey, originalStatus);
                return;
            }
            var checkEnabled = page.jiraService.worklogCheckEnabled && page.jiraService.worklogCheckEnabled();
            var requiresCheck = page.jiraService.requiresWorklogCheckBeforeTransition && page.jiraService.requiresWorklogCheckBeforeTransition(originalStatus, targetStatus);
            if (typeof console !== "undefined" && console.log) {
                console.log("[MyIssuesPage] updateIssue: checkEnabled=", checkEnabled, "requiresCheck=", requiresCheck, "worklogSyncService=", !!page.worklogSyncService);
            }
            if (checkEnabled && requiresCheck && page.worklogSyncService) {
                var pending = page.worklogSyncService.get_pending_worklogs_for_issue(issueKey) || [];
                if (typeof console !== "undefined" && console.log) {
                    console.log("[MyIssuesPage] updateIssue: pending worklogs count=", pending.length);
                }
                if (pending.length > 0) {
                    var showDialog = page.jiraService.worklogCheckShowDialog && page.jiraService.worklogCheckShowDialog();
                    if (typeof console !== "undefined" && console.log) {
                        console.log("[MyIssuesPage] updateIssue: showDialog=", showDialog, "calling _ensureProcessDialogThen(openInConfirm)");
                    }
                    if (showDialog) {
                        var totalFormatted = page._formatTotalFromPending(pending);
                        var blockIfPending = page.jiraService.worklogCheckBlockIfPending && page.jiraService.worklogCheckBlockIfPending();
                        page._pendingUpdateAfterSync = { issueKey: issueKey, fieldData: fieldData, worklogData: worklogData, epicKey: epicKey, originalStatus: originalStatus, isTwoPhase: false };
                        page._pendingWorklogsList = pending;
                        page._ensureProcessDialogThen(function (dlg) {
                            if (typeof console !== "undefined" && console.log) {
                                console.log("[MyIssuesPage] updateIssue: callback running, calling dlg.openInConfirm");
                            }
                            dlg.openInConfirm(pending, totalFormatted, targetStatus, blockIfPending);
                        });
                        return;
                    }
                    page._pendingUpdateAfterSync = { issueKey: issueKey, fieldData: fieldData, worklogData: worklogData, epicKey: epicKey, originalStatus: originalStatus, isTwoPhase: false };
                    page.isProcessing = true;
                    page._ensureProcessDialogThen(function (dlg) {
                        dlg.openInProgress(qsTr("Sincronizando worklogs..."));
                    });
                    var sessionIds = pending.map(function(p) { return p.id; });
                    page.worklogSyncService.sync_pending_worklogs(sessionIds);
                    return;
                }
            }
            page.controller.updateIssue(issueKey, fieldData, worklogData, epicKey, originalStatus);
        }

        var deletedIds = (page.detailPane._deletedAttachmentIds || []).slice();
        if (deletedIds.length > 0) {
            page.detailPane._deletedAttachmentIds = []
            var remaining = deletedIds.length
            function onOneDeleteDone() {
                remaining--
                if (remaining <= 0) {
                    doUpdateBody()
                }
            }
            for (var i = 0; i < deletedIds.length; i++) {
                (function (id) {
                    var onDeleted, onFailed
                    onDeleted = function () {
                        page.jiraService.attachmentDeleted.disconnect(onDeleted)
                        page.jiraService.attachmentDeleteFailed.disconnect(onFailed)
                        onOneDeleteDone()
                    }
                    onFailed = function () {
                        page.jiraService.attachmentDeleted.disconnect(onDeleted)
                        page.jiraService.attachmentDeleteFailed.disconnect(onFailed)
                        onOneDeleteDone()
                    }
                    page.jiraService.attachmentDeleted.connect(onDeleted)
                    page.jiraService.attachmentDeleteFailed.connect(onFailed)
                    page.jiraService.deleteAttachment(id)
                })(deletedIds[i])
            }
        } else {
            doUpdateBody()
        }
    }

    function _formatTotalFromPending(pending) {
        if (!pending || pending.length === 0) return "";
        var totalSec = 0;
        for (var i = 0; i < pending.length; i++) totalSec += (pending[i].duration_seconds || 0);
        return FormatUtils.formatDuration(Math.floor(totalSec / 60));
    }

    // Garantir ProcessDialog antes de usar (como IssueFormPage: diálogo na ação; se componente ainda Loading, enfileira callback)
    function _ensureProcessDialogThen(callback) {
        if (typeof callback !== "function") return;
        if (typeof console !== "undefined" && console.log) {
            console.log("[MyIssuesPage] _ensureProcessDialogThen: _processDialog=", !!page._processDialog, "_processDialogComponent=", !!page._processDialogComponent, "componentStatus=", page._processDialogComponent ? page._processDialogComponent.status : "n/a");
        }
        if (page._processDialog) {
            if (typeof console !== "undefined" && console.log) {
                console.log("[MyIssuesPage] _ensureProcessDialogThen: using existing dialog");
            }
            callback(page._processDialog);
            return;
        }
        if (page._processDialogComponent && page._processDialogComponent.status === Component.Ready) {
            if (typeof console !== "undefined" && console.log) {
                console.log("[MyIssuesPage] _ensureProcessDialogThen: creating dialog from component, parent=", page.parent ? "set" : "null");
            }
            var parent = page.parent || page;
            var dlg = page._processDialogComponent.createObject(parent, { applicationWindow: page.applicationWindow });
            if (dlg) {
                dlg.applicationWindow = Qt.binding(function () { return page.applicationWindow });
                dlg.cancelClicked.connect(page._onPendingWorklogsDialogCancel);
                dlg.skipSyncClicked.connect(page._onPendingWorklogsDialogSkip);
                dlg.syncClicked.connect(page._onPendingWorklogsDialogSync);
                dlg.closed.connect(function () {
                    page._jiraErrorShownInProcessDialog = false;
                });
                page._processDialog = dlg;
                if (typeof console !== "undefined" && console.log) {
                    console.log("[MyIssuesPage] _ensureProcessDialogThen: dialog created, calling callback");
                }
                callback(dlg);
            } else {
                if (typeof console !== "undefined" && console.warn) {
                    console.warn("[MyIssuesPage] _ensureProcessDialogThen: createObject returned null");
                }
            }
            return;
        }
        if (typeof console !== "undefined" && console.log) {
            console.log("[MyIssuesPage] _ensureProcessDialogThen: queuing callback (component not ready)");
        }
        page._pendingProcessDialogAction = callback;
    }

    function _runPendingProcessDialogAction() {
        if (typeof console !== "undefined" && console.log) {
            console.log("[MyIssuesPage] _runPendingProcessDialogAction: _processDialog=", !!page._processDialog, "pending=", !!page._pendingProcessDialogAction);
        }
        if (!page._processDialog || !page._pendingProcessDialogAction) return;
        var fn = page._pendingProcessDialogAction;
        page._pendingProcessDialogAction = null;
        fn(page._processDialog);
    }

    function _onPendingWorklogsDialogSync() {
        var sessionIds = (page._pendingWorklogsList || []).map(function(p) { return p.id; });
        page._pendingWorklogsList = [];
        if (!sessionIds || sessionIds.length === 0) {
            page._finishPendingUpdateAfterSync();
            return;
        }
        page.isProcessing = true;
        if (page.worklogSyncService) page.worklogSyncService.sync_pending_worklogs(sessionIds);
    }

    function _onPendingWorklogsDialogSkip() {
        page._pendingWorklogsList = [];
        if (page._pendingTwoPhaseTarget && page._pendingUpdateAfterSync && page._pendingUpdateAfterSync.isTwoPhase) {
            page.isProcessing = true;
            var targetStatus = page._pendingUpdateAfterSync.targetStatus;
            if (page._processDialog) {
                if (page._processDialog.opened) {
                    page._processDialog.transitionToProgress(qsTr("Transicionando para %1...").arg(targetStatus));
                } else {
                    page._processDialog.openInProgress(qsTr("Transicionando para %1...").arg(targetStatus));
                }
            }
            var issueKey = page._pendingUpdateAfterSync.issueKey;
            page._pendingUpdateAfterSync = null;
            page._pendingTwoPhaseTarget = "";
            page.jiraService.transitionFromInProgressToTarget(issueKey, targetStatus);
        } else {
            page._finishPendingUpdateAfterSync();
        }
    }

    function _onPendingWorklogsDialogCancel() {
        page._pendingWorklogsList = [];
        page._pendingUpdateAfterSync = null;
        if (page._pendingTwoPhaseTarget) {
            page._pendingTwoPhaseTarget = "";
            page._isTwoPhaseTransition = false;
            page.isProcessing = false;
            if (page._processDialog) page._processDialog.close();
        }
    }

    function _finishPendingUpdateAfterSync() {
        if (!page._pendingUpdateAfterSync) return;
        var p = page._pendingUpdateAfterSync;
        page._pendingUpdateAfterSync = null;
        if (p.isTwoPhase && p.targetStatus) {
            if (page._processDialog) {
                if (!page._processDialog.opened) {
                    page.isProcessing = true;
                    page._processDialog.openInProgress(qsTr("Transicionando para %1...").arg(p.targetStatus));
                } else {
                    page._processDialog.updateProgress(0, qsTr("Transicionando para %1...").arg(p.targetStatus));
                }
            }
            page._pendingTwoPhaseTarget = "";
            page.jiraService.transitionFromInProgressToTarget(p.issueKey, p.targetStatus);
        } else {
            // Fluxo único: sync já terminou; mostrar "Atualizando issue..." no mesmo dialog e depois "Task atualizada com sucesso"
            if (page._processDialog && page._processDialog.opened) {
                page._processDialog.transitionToProgress(qsTr("Atualizando issue..."));
            }
            page.controller.updateIssue(p.issueKey, p.fieldData, p.worklogData, p.epicKey, p.originalStatus);
        }
    }

    function resetFields() {
        page.detailPane.resetFields();
        page.originalStatus = "";
    }

    function openCreateBranchDialog() {
        if (!page.selectedIssueKey || !page.githubService || !page.githubService.available) return
        var singleRepo = ""
        var d = page.detailPane ? page.detailPane.developmentData : null
        if (d && d.repositories) {
            var repos = Array.isArray(d.repositories) ? d.repositories : Array.from(d.repositories || [])
            if (repos.length === 1) {
                var r = repos[0]
                singleRepo = (r && r.name) ? r.name : ""
            }
        }
        // qmllint disable missing-property
        if (createBranchDialogLoader.item && typeof createBranchDialogLoader.item.openWith === "function") {
            createBranchDialogLoader.item.openWith(
                page.selectedIssueKey,
                page.issueModel ? page.issueModel.summary : "",
                singleRepo,
                page.githubService
            )
        }
        // qmllint enable missing-property
    }

    Loader {
        id: createBranchDialogLoader
        active: page.selectedIssueKey !== "" && page.githubService && page.githubService.available
        source: "../components/dialogs/CreateBranchDialog.qml"
        onLoaded: if (item) item.visible = false
    }

    // Reagir aos sinais assíncronos de carregamento de detalhes de issue
    Connections {
        target: page.jiraService

        function onIssueDetailsStarted(issueKey) {
            // Sempre que iniciar o carregamento de detalhes, limpar campos
            // e exibir overlay.
            page.isDetailsLoading = true;
            page.resetFields();
        }

        function onIssueDetailsLoaded(details) {
            try {
                if (!details || !details.key) {
                    return;
                }
                // Corrigir prioridade na lista quando a busca não retornou (ex.: search/jql)
                if (page.myIssuesModel && details.key && typeof page.myIssuesModel.updateIssueInList === "function") {
                    var summary = String(details.summary || "");
                    var status = String(details.status || "");
                    var priority = String(details.priority || "");
                    var priorityId = String(details.priorityId || "");
                    if (priority || priorityId) {
                        page.myIssuesModel.updateIssueInList(details.key, summary, status, priority, priorityId);
                    }
                }
                var dev = details.development;
                var devStr = dev ? ("branches:" + (dev.branches ? dev.branches.length : 0) + " prs:" + (dev.pullRequests ? dev.pullRequests.length : 0)) : "null";
                console.log("[ Development ] details.development:", devStr, dev ? dev : "");
                page.originalStatus = String(details.status || "");
                MyIssuesPageLogic.applyIssueDetailsToForm(details, page.detailPane);
                if (details.development && details.development.pullRequests && details.development.pullRequests.length > 0 && page.jiraService && typeof page.jiraService.enrichPullRequests === "function") {
                    page.jiraService.enrichPullRequests(page.selectedIssueKey, details.development.pullRequests);
                }
                if (details.development && details.development.branches && details.development.branches.length > 0 && page.jiraService && typeof page.jiraService.enrichBranches === "function") {
                    console.log("[ Development ] calling enrichBranches branches=" + details.development.branches.length);
                    page.jiraService.enrichBranches(page.selectedIssueKey, details.development.branches);
                }
            } finally {
                page.isDetailsLoading = false;
            }
        }

        function onDevelopmentEnriched(issueKey, enrichedList) {
            if (issueKey && issueKey === page.selectedIssueKey && page.detailPane) {
                page.detailPane.enrichedPrs = enrichedList || null;
            }
        }

        function onDevelopmentBranchesEnriched(issueKey, enrichedList) {
            var count = enrichedList ? (Array.isArray(enrichedList) ? enrichedList.length : 0) : 0;
            console.log("[ Development ] onDevelopmentBranchesEnriched issueKey=" + (issueKey || "") + " count=" + count);
            if (issueKey && issueKey === page.selectedIssueKey && page.detailPane) {
                page.detailPane.enrichedBranches = enrichedList || null;
            }
        }
    }
}
