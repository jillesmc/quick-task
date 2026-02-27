/**
 * CreateWorkItemPage.qml
 *
 * Página do formulário de criação de work item
 * Refatorado seguindo Clean Code e SOLID
 * Usa componentes reutilizáveis e controllers
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami
import "../components/forms"
import "../components/controls"
import "../components/fields"
import "../utils/DialogHelpers.js" as DialogHelpers
Kirigami.Page {
    id: page

    title: qsTr("Preencha os dados do work item abaixo:")

    property var applicationWindow: null

    // Habilitar foco para capturar atalhos de teclado
    focus: true

    // Estado do processamento
    property bool isProcessing: false

    // Registrar worklog só permitido quando status inicial é IN PROGRESS ou posterior
    property bool registrarWorklogEnabled: {
        if (!workItemModel || !workItemModel.statusSequence) return false
        var seq = workItemModel.statusSequence
        var inDevIdx = seq.indexOf("IN PROGRESS")
        if (inDevIdx < 0) return false
        var statusIdx = seq.indexOf(workItemModel.statusInicial || "")
        return statusIdx >= inDevIdx
    }

    // Propriedades compartilhadas para sincronizar epic entre abas
    property string sharedEpicKey: ""
    property string sharedEpicSummary: ""

    signal epicSelected(string key, string summary)
    signal issueCreated(string issueKey)  // Emitido quando uma issue é criada com sucesso

    property var progressDialog: null

    // Controller para lógica de negócio
    property var controller: null

    // Recebidos do Main (passados explicitamente)
    property var workItemModel: null
    property var jiraService: null
    property var clipboardHelper: null
    property var hideWindowFn: null
    property var timerService: null
    property var timerModel: null
    property var _ctxVoiceInputService: typeof voiceInputService !== "undefined" ? voiceInputService : null // qmllint disable unqualified
    /** Quando definido (ex.: aba work item), usa este em vez do contexto. */
    property var voiceInputServiceOverride: null
    property var _effectiveVoiceInputService: (voiceInputServiceOverride !== null && voiceInputServiceOverride !== undefined) ? voiceInputServiceOverride : _ctxVoiceInputService

    // ------------------------------------------------------------------
    // Funções públicas para integração com Main.qml (botão global)
    // ------------------------------------------------------------------
    function createIssueFromToolbar() {
        // Mantém a mesma semântica original:
        // - Só cria se não estiver processando
        // - Valida antes de chamar o serviço
        if (!page.isProcessing && page.controller && page.controller.validate()) {
            page.controller.createIssue();
        }
    }

    function openVoiceDialog() {
        if (voiceDialogLoader.item && page._effectiveVoiceInputService !== null && page._effectiveVoiceInputService.isAvailable()) {
            voiceDialogLoader.item.open(); // qmllint disable missing-property
        }
    }

    // Função pública para cancelar (usada pelo botão global e pela tecla ESC)
    // Esconde a janela ao invés de fechar a aplicação
    function onCancelRequested() {
        if (!page.isProcessing) {
            if (page.hideWindowFn && typeof page.hideWindowFn === "function") {
                page.hideWindowFn(); // qmllint disable use-proper-function
            }
        }
    }

    // Atalhos de teclado locais (apenas ESC).
    // Ctrl+Enter é tratado globalmente em Main.qml via createIssueAction.
    Keys.onPressed: function (event) {
        // ESC: cancelar
        if (event.key === Qt.Key_Escape) {
            event.accepted = true;
            onCancelRequested();
            return;
        }
    }

    // Definir foco inicial no campo Summary (SummaryAndDescriptionBlock usa requestSummaryFocus: true)
    Component.onCompleted: {
        // Pré-carregar ProgressDialog para que createComponent em showProgress esteja em cache quando o utilizador clicar
        Qt.createComponent("../components/dialogs/ProgressDialog.qml");

        // Inicializar worklog com data/hora atual se não estiver definido
        if (page.workItemModel && (!page.workItemModel.worklogInicio || page.workItemModel.worklogInicio === "")) {
            var now = new Date();
            var dateStr = Qt.formatDateTime(now, "yyyy-MM-dd");
            var timeStr = Qt.formatDateTime(now, "HH:mm:ss");
            page.workItemModel.worklogInicio = dateStr + " " + timeStr;
        }

        // Criar controller
        var component = Qt.createComponent("../controllers/WorkItemFormController.qml");
        if (component.status === Component.Ready) {
            page.controller = component.createObject(page, {
                jiraService: page.jiraService,
                workItemModel: page.workItemModel,
                enabled: true
            });

            page.controller.createStarted.connect(function () {
                page.isProcessing = true;
                page.progressDialog = DialogHelpers.showProgress(page, "../components/dialogs/ProgressDialog.qml", function (dlg) {
                    page.progressDialog = dlg;
                });
            });

            page.controller.createCompleted.connect(function (issueKey, issueUrl) {
                page.isProcessing = false;
                DialogHelpers.hideProgress(page.progressDialog);
                page.progressDialog = null;
                DialogHelpers.showSuccess(page, "../components/dialogs/SuccessDialog.qml", issueKey, issueUrl || "", false, page.timerService, page.timerModel, page.jiraService, page.applicationWindow);
                page.resetForm();
                page.issueCreated(issueKey);
            });

            page.controller.createFailed.connect(function (errorMessage) {
                page.isProcessing = false;
                DialogHelpers.hideProgress(page.progressDialog);
                page.progressDialog = null;
                DialogHelpers.showError(page, "../components/dialogs/ErrorDialog.qml", errorMessage, "CreateWorkItemPage.jiraService");
            });
        }
    }

    // Conectar signals do jiraService para progresso
    Connections {
        target: page.jiraService

        function onProgressUpdated(percentage, message) {
            if (page.progressDialog) {
                page.progressDialog.updateProgress(percentage, message);
            }
        }
    }

    // Wrapper para ter splitView e overlay de resize como irmãos
    Item {
        anchors.fill: parent

        Controls.SplitView {
            id: splitView
            anchors.fill: parent
            orientation: Qt.Horizontal
            handle: SplitViewHandle { }

            // Coluna Esquerda: Summary, Description e Epic Parent (ScrollView único com dividers)
            Controls.ScrollView {
                id: leftScrollView
                Controls.SplitView.preferredWidth: parent.width * 0.6
                Controls.SplitView.minimumWidth: 400
                clip: true
                contentWidth: availableWidth

                // Propriedades para alturas das seções (redimensionáveis via dividers)
                property real topSectionHeight: 300
                property real epicSectionHeight: 300

                Item {
                    width: leftScrollView.availableWidth
                    implicitHeight: leftColumn.implicitHeight

                    Component.onCompleted: {
                        function initSectionHeights() {
                            if (leftScrollView.availableHeight > 200) {
                                var spacing = Kirigami.Units.largeSpacing
                                var dividerApprox = 24
                                var total = leftScrollView.availableHeight - 2 * dividerApprox - 2 * spacing
                                var half = Math.max(250, total / 2)
                                leftScrollView.topSectionHeight = half
                                leftScrollView.epicSectionHeight = half
                            }
                        }
                        Qt.callLater(initSectionHeights)
                        // Fallback: viewport pode não estar pronto no primeiro frame
                        Qt.callLater(function() { Qt.callLater(initSectionHeights) })
                    }

                    ColumnLayout {
                        id: leftColumn
                        anchors.fill: parent
                        anchors.leftMargin: Kirigami.Units.largeSpacing
                        anchors.rightMargin: Kirigami.Units.largeSpacing
                        spacing: Kirigami.Units.largeSpacing

                        // Seção superior: Summary e Description
                        ColumnLayout {
                            id: topSection
                            Layout.fillWidth: true
                            Layout.preferredHeight: leftScrollView.topSectionHeight
                            Layout.minimumHeight: 250
                            spacing: Kirigami.Units.largeSpacing

                            SummaryAndDescriptionBlock {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                workItemModel: page.workItemModel
                                mode: "create"
                                enabled: !page.isProcessing
                                jiraService: page.jiraService
                                clipboardHelper: page.clipboardHelper
                                voiceInputService: page._effectiveVoiceInputService
                                showVoiceCreateButton: true
                                showExpandWithAIButton: true
                                requestSummaryFocus: true
                                summaryRequired: true
                                applicationWindow: page.applicationWindow
                                onOpenVoiceRequested: page.openVoiceDialog()
                            }

                        Item {
                            Layout.fillHeight: true
                            Layout.fillWidth: true
                        }
                    }

                        DividerBar {
                            id: divider1
                            Layout.fillWidth: true
                        }

                        // Seção Epic Parent
                        ColumnLayout {
                            id: epicSection
                            Layout.fillWidth: true
                            Layout.preferredHeight: leftScrollView.epicSectionHeight
                            Layout.minimumHeight: 250
                            spacing: Kirigami.Units.smallSpacing

                            Controls.Label {
                                text: qsTr("Epic Parent:")
                                font.bold: true
                                Layout.fillWidth: true
                            }

                            EpicSearchForm {
                                id: epicSearchForm
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                enabled: !page.isProcessing

                                Binding {
                                    target: epicSearchForm
                                    property: "jiraService"
                                    value: typeof page.jiraService !== "undefined" ? page.jiraService : null
                                    when: typeof page.jiraService !== "undefined"
                                }

                                Binding {
                                    target: page.workItemModel
                                    property: "epicParentKey"
                                    value: epicSearchForm.selectedEpicKey
                                    when: page.workItemModel
                                }

                                Binding {
                                    target: page.workItemModel
                                    property: "epicParentSummary"
                                    value: epicSearchForm.selectedEpicSummary
                                    when: page.workItemModel
                                }

                                onEpicSelected: function (key, summary) {
                                    if (page.workItemModel) {
                                        page.workItemModel.epicParentKey = key;
                                        page.workItemModel.epicParentSummary = summary;
                                    }
                                    page.epicSelected(key, summary);
                                }

                                onEpicCleared: {
                                    page.sharedEpicKey = "";
                                    page.sharedEpicSummary = "";
                                    if (page.workItemModel) {
                                        page.workItemModel.epicParentKey = "";
                                        page.workItemModel.epicParentSummary = "";
                                    }
                                }

                                // Epic no formulário de criação vem apenas do modelo de criação (workItemModel),
                                // não de sharedEpicKey (que é atualizado pela aba Minhas Issues)
                                Binding {
                                    target: epicSearchForm
                                    property: "selectedEpicKey"
                                    value: page.workItemModel ? page.workItemModel.epicParentKey : ""
                                    when: page.workItemModel
                                }

                                Binding {
                                    target: epicSearchForm
                                    property: "selectedEpicSummary"
                                    value: page.workItemModel ? page.workItemModel.epicParentSummary : ""
                                    when: page.workItemModel
                                }
                            }
                        }

                        DividerBar {
                            id: divider2
                            Layout.fillWidth: true
                        }

                        // Espaço final (fillHeight para permitir redimensionamento do epicSection)
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                        }
                    }
                }
            }

            // Coluna Direita: Tipo de atividade, Valor entregue, Plataformas afetadas, Documentação anexa, Utilização de IA, Worklog
            Controls.ScrollView {
                id: rightScrollView
                Controls.SplitView.fillWidth: true
                Controls.SplitView.minimumWidth: 300
                clip: true

                Item {
                    width: rightScrollView.availableWidth
                    implicitHeight: rightColumn.implicitHeight + 2 * Kirigami.Units.largeSpacing

                    ColumnLayout {
                        id: rightColumn
                        anchors.fill: parent
                        anchors.leftMargin: Kirigami.Units.largeSpacing
                        anchors.rightMargin: Kirigami.Units.largeSpacing
                        spacing: Kirigami.Units.largeSpacing

                        // Worklog (habilitado só quando status inicial é IN PROGRESS ou posterior)
                        Controls.CheckBox {
                            id: worklogCheckbox
                            text: qsTr("Registrar worklog")
                            Layout.fillWidth: true
                            enabled: !page.isProcessing && page.registrarWorklogEnabled
                            checked: page.workItemModel ? page.workItemModel.registrarWorklog : false
                            onCheckedChanged: {
                                if (page.workItemModel) {
                                    page.workItemModel.registrarWorklog = checked;
                                }
                            }
                        }
                        Binding {
                            target: page.workItemModel
                            property: "registrarWorklog"
                            value: false
                            when: page.workItemModel && !page.registrarWorklogEnabled
                        }

                        // WorklogForm (oculto quando checkbox não está marcado)
                        WorklogForm {
                            id: worklogForm
                            jiraService: page.jiraService
                            Layout.fillWidth: true
                            enabled: !page.isProcessing && worklogCheckbox.checked
                            visible: worklogCheckbox.checked
                            showCheckbox: false  // Não mostrar checkbox aqui, já temos acima

                            // Bindings bidirecionais com workItemModel
                            Binding {
                                target: page.workItemModel
                                property: "worklogInicio"
                                value: worklogForm.date && worklogForm.time ? worklogForm.date + " " + worklogForm.time : ""
                                when: page.workItemModel && worklogForm.date && worklogForm.time
                            }

                            Binding {
                                target: page.workItemModel
                                property: "worklogDuracao"
                                value: Math.round(worklogForm.duration)
                                when: page.workItemModel
                            }

                            Binding {
                                target: page.workItemModel
                                property: "worklogComment"
                                value: worklogForm.comment
                                when: page.workItemModel
                            }

                            // Binding reverso: inicializar e manter sincronizado quando model muda (ex.: import do Google Calendar)
                            Component.onCompleted: {
                                if (page.workItemModel && page.workItemModel.worklogInicio) {
                                    var parts = page.workItemModel.worklogInicio.split(" ");
                                    if (parts.length >= 2) {
                                        worklogForm.setWorklogData({
                                            date: parts[0],
                                            time: parts[1],
                                            duration: page.workItemModel.worklogDuracao || 30,
                                            comment: page.workItemModel.worklogComment || ""
                                        });
                                    } else {
                                        worklogForm.setWorklogData({
                                            duration: page.workItemModel.worklogDuracao || 30,
                                            comment: page.workItemModel.worklogComment || ""
                                        });
                                    }
                                } else if (page.workItemModel) {
                                    worklogForm.setWorklogData({
                                        duration: page.workItemModel.worklogDuracao || 30,
                                        comment: page.workItemModel.worklogComment || ""
                                    });
                                }
                            }
                            Connections {
                                target: page.workItemModel || null
                                function onWorklogInicioChanged() {
                                    if (!page.workItemModel || !worklogForm) return;
                                    var inicio = page.workItemModel.worklogInicio || "";
                                    if (!inicio) return;
                                    var parts = inicio.split(" ");
                                    if (parts.length >= 2) {
                                        worklogForm.setWorklogData({
                                            date: parts[0],
                                            time: parts[1],
                                            duration: page.workItemModel.worklogDuracao || 30,
                                            comment: page.workItemModel.worklogComment || ""
                                        });
                                    }
                                }
                                function onWorklogDuracaoChanged() {
                                    if (!page.workItemModel || !worklogForm) return;
                                    worklogForm.setWorklogData({
                                        duration: page.workItemModel.worklogDuracao || 30
                                    });
                                }
                            }
                        }

                        IssueMetadataFields {
                            Layout.fillWidth: true
                            issueModel: page.workItemModel  // IssueMetadataFields partilha prop issueModel (abas 0/1)
                            enabled: !page.isProcessing
                            restrictStatusBySequence: false
                        }

                        // Espaço extra no final para não "comer" o último campo
                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Kirigami.Units.largeSpacing * 2
                        }
                    }
                }
            }
        }

        // Overlay para redimensionar dividers (irmão do splitView, cobre só a coluna esquerda)
        Item {
            id: resizeOverlay
            z: 10
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: leftScrollView.width
            property int activeDivider: 0
            property real startGlobalY: 0
            property real startHeight: 0

            MouseArea {
                anchors.fill: parent
                hoverEnabled: false
                cursorShape: parent.activeDivider ? Qt.SizeVerCursor : Qt.ArrowCursor
                onPressed: function (mouse) {
                    var margin = 8;
                    var p1 = divider1.mapToItem(resizeOverlay, 0, 0);
                    if (mouse.y >= p1.y - margin && mouse.y < p1.y + divider1.height + margin) {
                        resizeOverlay.activeDivider = 1;
                        resizeOverlay.startGlobalY = resizeOverlay.mapToGlobal(mouse.x, mouse.y).y;
                        resizeOverlay.startHeight = leftScrollView.topSectionHeight;
                        mouse.accepted = true;
                        return;
                    }
                    var p2 = divider2.mapToItem(resizeOverlay, 0, 0);
                    if (mouse.y >= p2.y - margin && mouse.y < p2.y + divider2.height + margin) {
                        resizeOverlay.activeDivider = 2;
                        resizeOverlay.startGlobalY = resizeOverlay.mapToGlobal(mouse.x, mouse.y).y;
                        resizeOverlay.startHeight = leftScrollView.epicSectionHeight;
                        mouse.accepted = true;
                        return;
                    }
                    mouse.accepted = false;
                }
                onPositionChanged: function (mouse) {
                    if (resizeOverlay.activeDivider === 0) return;
                    var cur = resizeOverlay.mapToGlobal(mouse.x, mouse.y).y;
                    var delta = cur - resizeOverlay.startGlobalY;
                    if (resizeOverlay.activeDivider === 1) {
                        leftScrollView.topSectionHeight = Math.max(150, resizeOverlay.startHeight + delta);
                    } else if (resizeOverlay.activeDivider === 2) {
                        leftScrollView.epicSectionHeight = Math.max(150, resizeOverlay.startHeight + delta);
                    }
                }
                onReleased: {
                    resizeOverlay.activeDivider = 0;
                }
            }
        }
    }

    // Overlay de loading durante "Expandir com IA" (bloqueia a página)
    Item {
        anchors.fill: parent
        visible: page._effectiveVoiceInputService !== null && page._effectiveVoiceInputService.isExpanding
        z: 100

        Rectangle {
            anchors.fill: parent
            color: Kirigami.Theme.backgroundColor
            opacity: 0.85
        }
        MouseArea {
            anchors.fill: parent
            onPressed: function (event) { event.accepted = true }
            onReleased: function (event) { event.accepted = true }
        }
        ColumnLayout {
            anchors.centerIn: parent
            spacing: Kirigami.Units.largeSpacing

            Controls.BusyIndicator {
                Layout.alignment: Qt.AlignHCenter
                running: parent.parent.visible
            }
            Controls.Label {
                text: qsTr("A processar com IA…")
                Layout.alignment: Qt.AlignHCenter
            }
        }
    }

    Loader {
        id: voiceDialogLoader
        active: page._effectiveVoiceInputService !== null && page._effectiveVoiceInputService.isAvailable()
        source: "../components/dialogs/VoiceInputDialog.qml"
        onLoaded: {
            if (item) {
                item.voiceInputService = page._effectiveVoiceInputService
                item.settingsModel = (page.applicationWindow && typeof page.applicationWindow._ctxSettingsModel !== "undefined") ? page.applicationWindow._ctxSettingsModel : null
                // qmllint disable missing-property
                item.fieldsFilled.connect(function() { item.close(); })
                item.errorMessage.connect(function(msg) {
                    DialogHelpers.showError(page, "../components/dialogs/ErrorDialog.qml", msg, "CreateWorkItemPage.voiceOrOther");
                })
                // qmllint enable missing-property
            }
        }
    }

    // Funções auxiliares
    function resetForm() {
        // Resetar campos para valores padrão
        if (page.workItemModel) {
            page.workItemModel.summary = "";
            page.workItemModel.description = "";

            // Tipo de atividade padrão
            var defaultTipo = "Suporte Dúvidas/Suporte uso incorreto";
            var tipoValues = page.workItemModel.tipoAtividadeValues;
            if (tipoValues.indexOf(defaultTipo) >= 0) {
                page.workItemModel.tipoAtividade = defaultTipo;
            } else if (tipoValues.length > 0) {
                page.workItemModel.tipoAtividade = tipoValues[0];
            }

            // Status inicial padrão
            if (page.workItemModel.statusSequence && page.workItemModel.statusSequence.length > 0) {
                page.workItemModel.statusInicial = page.workItemModel.statusSequence[0];
            }

            // Prioridade padrão
            page.workItemModel.prioridade = "Medium";

            // Valores padrão
            page.workItemModel.documentacaoAnexa = "Não";
            page.workItemModel.utilizacaoIA = "Não";

            // Resetar Valor Entregue e Plataformas afetadas
            var valorEntregueValues = page.workItemModel.valorEntregueValues;
            if (valorEntregueValues && valorEntregueValues.length > 0) {
                page.workItemModel.valorEntregue = valorEntregueValues[0];
            } else {
                page.workItemModel.valorEntregue = "";
            }
            page.workItemModel.plataformasAfetadas = [];

            // Limpar Epic Parent
            page.workItemModel.epicParentKey = "";
            page.workItemModel.epicParentSummary = "";
            if (epicSearchForm) {
                epicSearchForm.reset();
            }

            // Resetar worklog
            page.workItemModel.registrarWorklog = false;
            var now = new Date();
            var dateStr = Qt.formatDateTime(now, "yyyy-MM-dd");
            var timeStr = Qt.formatDateTime(now, "HH:mm:ss");
            page.workItemModel.worklogInicio = dateStr + " " + timeStr;
            page.workItemModel.worklogDuracao = 30;
            if (worklogForm) {
                worklogForm.reset();
            }

            // Limpar anexos pendentes da descrição
            page.workItemModel.pendingAttachments = [];
        }
    }

    function validateForm() {
        if (page.controller) {
            return page.controller.validate();
        }
        return false;
    }

}
