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
        if (!workItemModel || !workItemModel.statusSequence)
            return false;
        var seq = workItemModel.statusSequence;
        var inDevIdx = seq.indexOf("IN PROGRESS");
        if (inDevIdx < 0)
            return false;
        var statusIdx = seq.indexOf(workItemModel.statusInicial || "");
        return statusIdx >= inDevIdx;
    }

    // Propriedades compartilhadas para sincronizar epic entre abas
    property string sharedEpicKey: ""
    property string sharedEpicSummary: ""

    /** Definido ao redimensionar pelo drag nos dividers; evita sobrescrever com fórmula ao mudar availableHeight. */
    property bool _userAdjustedLeftHeights: false

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
    property var atlassianMetadataConfigModel: null
    property var voiceInputService: null
    /** Quando definido (ex.: aba work item), usa este em vez do contexto. */
    property var voiceInputServiceOverride: null
    property var _effectiveVoiceInputService: (voiceInputServiceOverride !== null && voiceInputServiceOverride !== undefined) ? voiceInputServiceOverride : voiceInputService

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
            handle: SplitViewHandle {}

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

                function updateSectionHeightsFromViewport() {
                    if (leftScrollView.availableHeight <= 200)
                        return;
                    var spacing = Kirigami.Units.largeSpacing;
                    var dividerApprox = 24;
                    var total = leftScrollView.availableHeight - 2 * dividerApprox - 2 * spacing;
                    var half = Math.max(250, total / 2);
                    leftScrollView.topSectionHeight = half;
                    leftScrollView.epicSectionHeight = half;
                }

                Item {
                    width: leftScrollView.availableWidth
                    implicitHeight: leftColumn.implicitHeight

                    Component.onCompleted: {
                        leftScrollView.updateSectionHeightsFromViewport();
                        Qt.callLater(leftScrollView.updateSectionHeightsFromViewport);
                    }

                    Connections {
                        target: leftScrollView
                        function onAvailableHeightChanged() {
                            if (leftScrollView.availableHeight > 200 && !page._userAdjustedLeftHeights) {
                                leftScrollView.updateSectionHeightsFromViewport();
                            }
                        }
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
                        }

                        DividerBar {
                            id: divider1
                            Layout.fillWidth: true
                        }

                        // Seção Parent Work Item
                        ColumnLayout {
                            id: epicSection
                            Layout.fillWidth: true
                            Layout.preferredHeight: leftScrollView.epicSectionHeight
                            Layout.minimumHeight: 250
                            spacing: Kirigami.Units.smallSpacing

                            ParentWorkItemBlock {
                                id: parentWorkItemBlock
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                model: page.workItemModel
                                atlassianService: page.jiraService
                                metadataConfigModel: page.atlassianMetadataConfigModel
                                parentIssueType: "Epic"
                                enabled: !page.isProcessing
                                mode: "create"
                                sharedParentWorkItemKey: page.sharedEpicKey
                                sharedParentWorkItemSummary: page.sharedEpicSummary
                                preferredHeight: leftScrollView.epicSectionHeight
                                minimumHeight: 250

                                onParentWorkItemSelected: function (key, summary) {
                                    page.epicSelected(key, summary);
                                }
                                onParentWorkItemCleared: {
                                    page.sharedEpicKey = "";
                                    page.sharedEpicSummary = "";
                                }
                            }
                        }

                        DividerBar {
                            id: divider2
                            Layout.fillWidth: true
                        }

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

                        RegisterWorklogBlock {
                            id: registerWorklogBlock
                            model: page.workItemModel
                            enabled: !page.isProcessing
                            registrarWorklogEnabled: page.registrarWorklogEnabled
                            service: page.jiraService
                        }

                        WorkItemMetadataFields {
                            Layout.fillWidth: true
                            workItemModel: page.workItemModel
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
                        page._userAdjustedLeftHeights = true;
                        mouse.accepted = true;
                        return;
                    }
                    var p2 = divider2.mapToItem(resizeOverlay, 0, 0);
                    if (mouse.y >= p2.y - margin && mouse.y < p2.y + divider2.height + margin) {
                        resizeOverlay.activeDivider = 2;
                        resizeOverlay.startGlobalY = resizeOverlay.mapToGlobal(mouse.x, mouse.y).y;
                        resizeOverlay.startHeight = leftScrollView.epicSectionHeight;
                        page._userAdjustedLeftHeights = true;
                        mouse.accepted = true;
                        return;
                    }
                    mouse.accepted = false;
                }
                onPositionChanged: function (mouse) {
                    if (resizeOverlay.activeDivider === 0)
                        return;
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
            onPressed: function (event) {
                event.accepted = true;
            }
            onReleased: function (event) {
                event.accepted = true;
            }
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
                item.voiceInputService = page._effectiveVoiceInputService;
                item.settingsModel = (page.applicationWindow && typeof page.applicationWindow._ctxSettingsModel !== "undefined") ? page.applicationWindow._ctxSettingsModel : null;
                // qmllint disable missing-property
                item.fieldsFilled.connect(function () {
                    item.close();
                });
                item.errorMessage.connect(function (msg) {
                    DialogHelpers.showError(page, "../components/dialogs/ErrorDialog.qml", msg, "CreateWorkItemPage.voiceOrOther");
                });
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

            // Limpar Parent Work Item
            if (parentWorkItemBlock && typeof parentWorkItemBlock.clearParent === "function") {
                parentWorkItemBlock.clearParent();
            } else {
                page.workItemModel.parentWorkItemKey = "";
                page.workItemModel.parentWorkItemSummary = "";
            }

            // Resetar worklog
            if (registerWorklogBlock) {
                registerWorklogBlock.reset();
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
