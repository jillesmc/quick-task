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
import "../utils/MyIssuesPageLogic.js" as MyIssuesPageLogic

Kirigami.Page {
    id: page

    title: qsTr("Minhas Issues")

    // Habilitar foco para capturar atalhos de teclado
    focus: true

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

    // Flag para controlar busca automática inicial (apenas uma vez)
    property bool initialSearchDone: false

    // Recebidos do Main (passados explicitamente)
    property var issueModel: null
    property var jiraService: null
    property var myIssuesModel: null
    property var timerService: null
    property var timerModel: null
    property var hideWindowFn: null

    // Diálogos (progressDialog e searchProgressDialog gerenciados via DialogHelpers)
    property var progressDialog: null
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

    // Ações da página (Kirigami 6 usa 'actions' ao invés de 'mainAction')
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
                    page.timerService.start(page.selectedIssueKey);
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
            // Parar timer atual e iniciar novo
            page.timerService.stop();
            // Usar callLater para garantir que o stop termine antes de iniciar
            Qt.callLater(function () {
                if (page.timerService && page.selectedIssueKey) {
                    page.timerService.start(page.selectedIssueKey);
                }
            });
        } else
        // Iniciar novo timer
        {
            page.timerService.start(page.selectedIssueKey);
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

    function refreshIssues(query) {
        if (!page.myIssuesModel) {
            return;
        }

        DialogHelpers.hideProgress(page.searchProgressDialog);
        page.searchProgressDialog = null;

        page.searchProgressDialog = DialogHelpers.showProgress(page, "../components/dialogs/ProgressDialog.qml");
        if (page.searchProgressDialog) {
            page.searchProgressDialog.updateProgress(0, "Buscando issues...");

            var loadingConnection = function (isLoading) {
                if (isLoading) {
                    if (page.searchProgressDialog) {
                        page.searchProgressDialog.updateProgress(50, "Buscando issues...");
                    }
                } else {
                    Qt.callLater(function () {
                        if (page.searchProgressDialog) {
                            page.searchProgressDialog.updateProgress(100, "Busca concluída!");
                            Qt.callLater(function () {
                                DialogHelpers.hideProgress(page.searchProgressDialog);
                                page.searchProgressDialog = null;

                                Qt.callLater(function () {
                                    if (page.myIssuesModel && page.myIssuesModel.issues && page.myIssuesModel.issues.length > 0) {
                                        var firstIssue = page.myIssuesModel.issues[0];
                                        if (firstIssue && firstIssue.key && page.issueList) {
                                            page.issueList.selectIssue(firstIssue.key);
                                        }
                                    }
                                });
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

        // Iniciar busca
        if (page.controller) {
            page.controller.searchIssues(query || "");
        } else {
            page.myIssuesModel.refreshIssues(query || "");
        }
    }

    // Criar controller
    Component.onCompleted: {
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
                    page.progressDialog = DialogHelpers.showProgress(page, "../components/dialogs/ProgressDialog.qml");
                });

                page.controller.updateCompleted.connect(function (issueKey) {
                    page.isProcessing = false;
                    DialogHelpers.hideProgress(page.progressDialog);
                    page.progressDialog = null;
                    DialogHelpers.showSuccess(page, "../components/dialogs/SuccessDialog.qml", issueKey, "", true);
                    if (page.issueSearchForm) {
                        var query = page.issueSearchForm.getQuery();
                        page.refreshIssues(query);
                    }
                });

                page.controller.updateFailed.connect(function (errorMessage) {
                    page.isProcessing = false;
                    DialogHelpers.hideProgress(page.progressDialog);
                    page.progressDialog = null;
                    DialogHelpers.showError(page, "../components/dialogs/ErrorDialog.qml", errorMessage);
                });

                page.controller.issueSelected.connect(function (issueKey, issueData) {
                    if (issueKey) {
                        page.selectedIssueKey = issueKey;
                        page.loadIssueDetails(issueKey);
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
                width: leftScrollView.width
                // Garante altura mínima da viewport para o ColumnLayout dar espaço ao IssueList (fillHeight)
                implicitHeight: Math.max(leftScrollView.height, leftColumnLayout.implicitHeight)

                ColumnLayout {
                    id: leftColumnLayout
                    anchors.fill: parent
                    anchors.leftMargin: 20
                    anchors.rightMargin: 20
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

                    Controls.Label {
                        text: qsTr("Issues atribuídas a você")
                        font.bold: true
                        Layout.fillWidth: true
                    }

                    // Lista de issues usando componente reutilizável
                    Item {
                        id: issueListContainer
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        IssueList {
                            id: issueList
                            anchors.fill: parent
                            enabled: !page.isProcessing
                            model: page.myIssuesModel ? page.myIssuesModel.issues : []
                            isLoading: page.myIssuesModel ? page.myIssuesModel.isLoading : false
                            selectedIssueKey: page.selectedIssueKey
                            timerModel: page.timerModel
                            timerService: page.timerService

                            onIssueSelected: function (issueKey, issueData) {
                                page.selectedIssueKey = issueKey;
                                page.loadIssueDetails(issueKey);
                            }
                        }
                    }
                }
            }
        }

        // Coluna Direita (60% - Detail)
        MyIssuesDetailPane {
            id: detailPane
            issueModel: page.issueModel
            selectedIssueKey: page.selectedIssueKey
            isProcessing: page.isProcessing
            isDetailsLoading: page.isDetailsLoading
            jiraService: page.jiraService
            sharedEpicKey: page.sharedEpicKey
            sharedEpicSummary: page.sharedEpicSummary

            onEpicSelected: function (key, summary) {
                page.epicSelected(key, summary);
            }
        }
    }

    // Conectar signals do jiraService
    Connections {
        target: page.jiraService

        function onProgressUpdated(percentage, message) {
            if (page.progressDialog) {
                page.progressDialog.updateProgress(percentage, message);
            }
        }
    }

    // Conectar signals do myIssuesModel para fechar diálogo de busca
    Connections {
        target: page.myIssuesModel

        function onErrorOccurred(errorMessage) {
            DialogHelpers.hideProgress(page.searchProgressDialog);
            page.searchProgressDialog = null;
            DialogHelpers.showError(page, "../components/dialogs/ErrorDialog.qml", errorMessage);
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
        if (!page.selectedIssueKey || page.selectedIssueKey === "") {
            DialogHelpers.showError(page, "../components/dialogs/ErrorDialog.qml", "Por favor, selecione uma task para atualizar");
            return;
        }

        if (!page.controller) {
            DialogHelpers.showError(page, "../components/dialogs/ErrorDialog.qml", "Controller não disponível");
            return;
        }

        var fieldData = page.detailPane.getFieldData();
        var worklogData = page.detailPane.getWorklogData();
        var epicKey = page.detailPane.getEpicKey();
        page.controller.updateIssue(page.selectedIssueKey, fieldData, worklogData, epicKey, page.originalStatus);
    }

    function resetFields() {
        page.detailPane.resetFields();
        page.originalStatus = "";
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
                page.originalStatus = String(details.status || "");
                MyIssuesPageLogic.applyIssueDetailsToForm(details, page.detailPane);
            } finally {
                page.isDetailsLoading = false;
            }
        }
    }
}
