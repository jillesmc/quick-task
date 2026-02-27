/**
 * IssueFormPage.qml
 *
 * Página do formulário de criação de issue
 * Refatorado seguindo Clean Code e SOLID
 * Usa componentes reutilizáveis e controllers
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami
import "../components/forms"
import "../components/controls"
import "../utils/DialogHelpers.js" as DialogHelpers
Kirigami.Page {
    id: page

    title: "Preencha os dados da issue abaixo:"

    property var applicationWindow: null

    // Habilitar foco para capturar atalhos de teclado
    focus: true

    // Estado do processamento
    property bool isProcessing: false

    // Registrar worklog só permitido quando status inicial é IN PROGRESS ou posterior
    property bool registrarWorklogEnabled: {
        if (!issueModel || !issueModel.statusSequence) return false
        var seq = issueModel.statusSequence
        var inDevIdx = seq.indexOf("IN PROGRESS")
        if (inDevIdx < 0) return false
        var statusIdx = seq.indexOf(issueModel.statusInicial || "")
        return statusIdx >= inDevIdx
    }

    // Contador para placeholders de anexos na descrição (nova issue)
    property int _descriptionPlaceholderCounter: 0
    property bool _descriptionEditMode: true

    // Propriedades compartilhadas para sincronizar epic entre abas
    property string sharedEpicKey: ""
    property string sharedEpicSummary: ""

    signal epicSelected(string key, string summary)
    signal issueCreated(string issueKey)  // Emitido quando uma issue é criada com sucesso

    property var progressDialog: null

    // Controller para lógica de negócio
    property var controller: null

    // Recebidos do Main (passados explicitamente)
    property var issueModel: null
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

    function _openEmbedDialogCreateFlow(filePath, filename) {
        if (!filePath || !page.issueModel) return
        var comp = Qt.createComponent("../components/dialogs/AttachmentEmbedPreviewDialog.qml")
        var win = page.applicationWindow || page.parent || page
        if (comp.status !== Component.Ready) {
            if (comp.status === Component.Error) {
                console.error("IssueFormPage: AttachmentEmbedPreviewDialog error:", comp.errorString())
            }
            comp.statusChanged.connect(function () {
                if (comp.status === Component.Ready) {
                    _createAndOpenEmbedDialog(comp, win, filePath, filename)
                }
            })
            return
        }
        _createAndOpenEmbedDialog(comp, win, filePath, filename)
    }

    function _createAndOpenEmbedDialog(comp, parent, filePath, filename) {
        var dlg = comp.createObject(parent)
        if (!dlg) return
        dlg.filePath = filePath
        dlg.showPositionOptions = true
        dlg.defaultDisplayWidth = (page.jiraService && typeof page.jiraService.getEmbedMaxDisplayWidth === "function")
            ? page.jiraService.getEmbedMaxDisplayWidth() : 760
        dlg.applicationWindow = page.applicationWindow
        dlg.clipboardHelper = page.clipboardHelper
        dlg.acceptedEmbed.connect(function (layout, position, displayWidth) {
            page._descriptionPlaceholderCounter += 1
            var placeholderId = "p" + page._descriptionPlaceholderCounter
            var list = page.issueModel.pendingAttachments || []
            list.push({ path: filePath, filename: filename, placeholderId: placeholderId, layout: layout, position: position, displayWidth: displayWidth })
            page.issueModel.pendingAttachments = list
            var markdown = "![" + filename + "](pending:" + placeholderId + ")"
            var insertPos = (position === "start") ? 0 : descriptionField.text.length
            descriptionField.insert(insertPos, markdown)
            if (page.issueModel) page.issueModel.description = descriptionField.text
        })
        dlg.acceptedAttachOnly.connect(function () {
            var list = page.issueModel.pendingAttachments || []
            list.push({ path: filePath, filename: filename })
            page.issueModel.pendingAttachments = list
        })
        dlg.rejected.connect(function () {})
        dlg.closed.connect(function () { dlg.destroy() })
        dlg.open()
    }

    function _addNonImageAttachmentCreateFlow(filePath, filename) {
        if (!page.issueModel) return
        page._descriptionPlaceholderCounter += 1
        var placeholderId = "p" + page._descriptionPlaceholderCounter
        var list = page.issueModel.pendingAttachments || []
        list.push({ path: filePath, filename: filename, placeholderId: placeholderId })
        page.issueModel.pendingAttachments = list
        var markdown = "[" + filename + "](pending:" + placeholderId + ")"
        var insertPos = descriptionField.cursorPosition >= 0 ? descriptionField.cursorPosition : descriptionField.text.length
        descriptionField.insert(insertPos, markdown)
        if (page.issueModel) page.issueModel.description = descriptionField.text
    }

    function _openAttachmentsPopover(button) {
        if (!button || !page.issueModel) return
        var comp = Qt.createComponent("../components/dialogs/DescriptionAttachmentsPopover.qml")
        if (comp.status !== Component.Ready) {
            if (comp.status === Component.Error) {
                console.error("IssueFormPage: DescriptionAttachmentsPopover error:", comp.errorString())
            }
            comp.statusChanged.connect(function () {
                if (comp.status === Component.Ready) {
                    _openAttachmentsPopover(button)
                }
            })
            return
        }
        var popover = comp.createObject(button)
        if (!popover) return
        popover.x = 0
        popover.y = button.height + 2
        popover.mode = "create"
        popover.issueModel = page.issueModel
        popover.closed.connect(function () { popover.destroy() })
        popover.open()
    }

    // Definir foco inicial no campo Summary quando a página for carregada
    Component.onCompleted: {
        summaryField.forceActiveFocus();

        // Pré-carregar ProgressDialog para que createComponent em showProgress esteja em cache quando o utilizador clicar
        Qt.createComponent("../components/dialogs/ProgressDialog.qml");

        // Inicializar worklog com data/hora atual se não estiver definido
        if (page.issueModel && (!page.issueModel.worklogInicio || page.issueModel.worklogInicio === "")) {
            var now = new Date();
            var dateStr = Qt.formatDateTime(now, "yyyy-MM-dd");
            var timeStr = Qt.formatDateTime(now, "HH:mm:ss");
            page.issueModel.worklogInicio = dateStr + " " + timeStr;
        }

        // Criar controller
        var component = Qt.createComponent("../controllers/IssueFormController.qml");
        if (component.status === Component.Ready) {
            page.controller = component.createObject(page, {
                jiraService: page.jiraService,
                issueModel: page.issueModel,
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
                DialogHelpers.showError(page, "../components/dialogs/ErrorDialog.qml", errorMessage, "IssueFormPage.jiraService");
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

                        ColumnLayout {
                            Layout.fillWidth: true
                            // Layout.margins: 20
                            // Layout.bottomMargin: 10
                            spacing: Kirigami.Units.smallSpacing

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing

                                Controls.Label {
                                    text: qsTr("Summary:")
                                    font.bold: true
                                    Layout.fillWidth: true
                                }

                                Controls.ToolButton {
                                    visible: page._effectiveVoiceInputService !== null && page._effectiveVoiceInputService.isAvailable()
                                    icon.name: "audio-input-microphone"
                                    text: qsTr("Criar por voz")
                                    onClicked: {
                                        if (voiceDialogLoader.item) {
                                            voiceDialogLoader.item.open() // qmllint disable missing-property
                                        }
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing

                                Controls.TextField {
                                    id: summaryField
                                    Layout.fillWidth: true
                                    enabled: !page.isProcessing
                                    text: page.issueModel ? page.issueModel.summary : ""
                                    onTextChanged: if (page.issueModel) page.issueModel.summary = text
                                }

                                Controls.ToolButton {
                                    visible: page._effectiveVoiceInputService !== null && page._effectiveVoiceInputService.isAvailable()
                                    icon.name: "tools-wizard"
                                    text: qsTr("Expandir com IA")
                                    enabled: !page.isProcessing && page.issueModel && (page.issueModel.summary || page.issueModel.description)
                                    onClicked: {
                                        if (page._effectiveVoiceInputService && page.issueModel) {
                                            page._effectiveVoiceInputService.expandFromSummaryAndDescription(
                                                page.issueModel.summary || "",
                                                page.issueModel.description || "",
                                                false
                                            );
                                        }
                                    }
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            // Layout.margins: 20
                            // Layout.topMargin: 0
                            spacing: Kirigami.Units.smallSpacing

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing

                                Controls.Label {
                                    text: qsTr("Description:")
                                    font.bold: true
                                    Layout.fillWidth: true
                                }

                                EditPreviewToggle {
                                    isEditMode: page._descriptionEditMode
                                    onModeChanged: function(editMode) {
                                        page._descriptionEditMode = editMode
                                    }
                                }

                                Controls.ToolButton {
                                    id: attachmentListButton
                                    icon.name: "mail-attachment"
                                    text: qsTr("Anexos na descrição")
                                    display: Controls.AbstractButton.IconOnly
                                    onClicked: page._openAttachmentsPopover(attachmentListButton)
                                }
                            }

                            // DropArea como container: cliques vão para o filho (ScrollView/TextArea), drops para o DropArea.
                            Item {
                                id: descriptionContainer
                                Layout.fillWidth: true
                                Layout.fillHeight: true

                                StackLayout {
                                    anchors.fill: parent
                                    currentIndex: page._descriptionEditMode ? 0 : 1

                                    // Edit mode: estrutura original (DropArea > ScrollView > TextArea)
                                    DropArea {
                                        enabled: !page.isProcessing
                                        onDropped: function(drop) {
                                            if (!drop.urls || drop.urls.length === 0 || !page.issueModel) return
                                            var extList = (page.jiraService && typeof page.jiraService.getAllowedAttachmentExtensions === "function")
                                                ? page.jiraService.getAllowedAttachmentExtensions() : []
                                            var imageExtList = (page.jiraService && typeof page.jiraService.getAllowedImageExtensions === "function")
                                                ? page.jiraService.getAllowedImageExtensions() : []
                                            for (var i = 0; i < drop.urls.length; i++) {
                                                var urlStr = drop.urls[i].toString()
                                                var path = urlStr.replace(/^file:\/\//, "")
                                                var filename = path.split("/").pop() || path.split("\\").pop() || "file"
                                                var ext = filename.indexOf(".") >= 0 ? filename.split(".").pop().toLowerCase() : ""
                                                if (extList.indexOf(ext) < 0) continue
                                                var pathToUse = (page.clipboardHelper && typeof page.clipboardHelper.copyFileToTemp === "function")
                                                    ? page.clipboardHelper.copyFileToTemp(path) : path
                                                if (!pathToUse) continue
                                                if (imageExtList.indexOf(ext) >= 0) {
                                                    page._openEmbedDialogCreateFlow(pathToUse, filename)
                                                } else {
                                                    page._addNonImageAttachmentCreateFlow(pathToUse, filename)
                                                }
                                            }
                                        }

                                        Controls.ScrollView {
                                            id: descriptionScrollView
                                            anchors.fill: parent
                                            clip: true
                                            contentWidth: descriptionField.implicitWidth

                                            Controls.TextArea {
                                                id: descriptionField
                                                width: descriptionContainer.width
                                                wrapMode: Controls.TextArea.Wrap
                                                enabled: !page.isProcessing
                                                topPadding: Kirigami.Units.smallSpacing
                                                bottomPadding: Kirigami.Units.smallSpacing
                                                placeholderText: qsTr("Arraste ficheiros ou use Ctrl+V para colar imagem; imagens têm preview, outros ficheiros ficam como link.")
                                                text: page.issueModel ? page.issueModel.description : ""
                                                onTextChanged: if (page.issueModel) page.issueModel.description = text

                                                Keys.onPressed: function(event) {
                                                    if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V) {
                                                        if (!page.clipboardHelper || !page.issueModel) return
                                                        if (page.clipboardHelper.hasClipboardImage()) {
                                                            var tempPath = page.clipboardHelper.getClipboardImageAsTempFile()
                                                            if (tempPath) {
                                                                page._openEmbedDialogCreateFlow(tempPath, "paste.png")
                                                                event.accepted = true
                                                            }
                                                        }
                                                    } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_E) {
                                                        page._descriptionEditMode = true
                                                        event.accepted = true
                                                    } else if ((event.modifiers & (Qt.ControlModifier | Qt.ShiftModifier)) === (Qt.ControlModifier | Qt.ShiftModifier) && event.key === Qt.Key_P) {
                                                        page._descriptionEditMode = false
                                                        event.accepted = true
                                                    } else if (event.key === Qt.Key_Escape) {
                                                        page._descriptionEditMode = true
                                                        event.accepted = true
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // Preview mode
                                    Rectangle {
                                        focus: !page._descriptionEditMode
                                        color: "transparent"
                                        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
                                        border.width: 0.5
                                        radius: Kirigami.Units.smallSpacing

                                        Keys.onPressed: function(event) {
                                            if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_E) {
                                                page._descriptionEditMode = true
                                                event.accepted = true
                                            } else if ((event.modifiers & (Qt.ControlModifier | Qt.ShiftModifier)) === (Qt.ControlModifier | Qt.ShiftModifier) && event.key === Qt.Key_P) {
                                                page._descriptionEditMode = false
                                                event.accepted = true
                                            } else if (event.key === Qt.Key_Escape) {
                                                page._descriptionEditMode = true
                                                event.accepted = true
                                            }
                                        }

                                        Controls.ScrollView {
                                            id: descriptionPreviewScroll
                                            anchors.fill: parent
                                            anchors.margins: 1
                                            clip: true
                                            contentWidth: availableWidth

                                            Text {
                                                width: descriptionPreviewScroll.availableWidth - Kirigami.Units.largeSpacing * 2
                                                x: Kirigami.Units.largeSpacing
                                                topPadding: Kirigami.Units.smallSpacing
                                                bottomPadding: Kirigami.Units.smallSpacing
                                                textFormat: Text.RichText
                                                color: "#ffffff"
                                                // qmllint disable unqualified
                                                text: (typeof markdownPreviewRenderer !== "undefined" && markdownPreviewRenderer)
                                                    ? markdownPreviewRenderer.render(page.issueModel ? page.issueModel.description : "")
                                                    : (page.issueModel ? page.issueModel.description : "")
                                                wrapMode: Text.Wrap
                                                onLinkActivated: function(link) {
                                                    Qt.openUrlExternally(link)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
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
                                    target: page.issueModel
                                    property: "epicParentKey"
                                    value: epicSearchForm.selectedEpicKey
                                    when: page.issueModel
                                }

                                Binding {
                                    target: page.issueModel
                                    property: "epicParentSummary"
                                    value: epicSearchForm.selectedEpicSummary
                                    when: page.issueModel
                                }

                                onEpicSelected: function (key, summary) {
                                    if (page.issueModel) {
                                        page.issueModel.epicParentKey = key;
                                        page.issueModel.epicParentSummary = summary;
                                    }
                                    page.epicSelected(key, summary);
                                }

                                onEpicCleared: {
                                    page.sharedEpicKey = "";
                                    page.sharedEpicSummary = "";
                                    if (page.issueModel) {
                                        page.issueModel.epicParentKey = "";
                                        page.issueModel.epicParentSummary = "";
                                    }
                                }

                                // Epic no formulário de criação vem apenas do modelo de criação (issueModel),
                                // não de sharedEpicKey (que é atualizado pela aba Minhas Issues)
                                Binding {
                                    target: epicSearchForm
                                    property: "selectedEpicKey"
                                    value: page.issueModel ? page.issueModel.epicParentKey : ""
                                    when: page.issueModel
                                }

                                Binding {
                                    target: epicSearchForm
                                    property: "selectedEpicSummary"
                                    value: page.issueModel ? page.issueModel.epicParentSummary : ""
                                    when: page.issueModel
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
                            checked: page.issueModel ? page.issueModel.registrarWorklog : false
                            onCheckedChanged: {
                                if (page.issueModel) {
                                    page.issueModel.registrarWorklog = checked;
                                }
                            }
                        }
                        Binding {
                            target: page.issueModel
                            property: "registrarWorklog"
                            value: false
                            when: page.issueModel && !page.registrarWorklogEnabled
                        }

                        // WorklogForm (oculto quando checkbox não está marcado)
                        WorklogForm {
                            id: worklogForm
                            jiraService: page.jiraService
                            Layout.fillWidth: true
                            enabled: !page.isProcessing && worklogCheckbox.checked
                            visible: worklogCheckbox.checked
                            showCheckbox: false  // Não mostrar checkbox aqui, já temos acima

                            // Bindings bidirecionais com issueModel
                            Binding {
                                target: page.issueModel
                                property: "worklogInicio"
                                value: worklogForm.date && worklogForm.time ? worklogForm.date + " " + worklogForm.time : ""
                                when: page.issueModel && worklogForm.date && worklogForm.time
                            }

                            Binding {
                                target: page.issueModel
                                property: "worklogDuracao"
                                value: Math.round(worklogForm.duration)
                                when: page.issueModel
                            }

                            Binding {
                                target: page.issueModel
                                property: "worklogComment"
                                value: worklogForm.comment
                                when: page.issueModel
                            }

                            // Binding reverso: inicializar e manter sincronizado quando model muda (ex.: import do Google Calendar)
                            Component.onCompleted: {
                                if (page.issueModel && page.issueModel.worklogInicio) {
                                    var parts = page.issueModel.worklogInicio.split(" ");
                                    if (parts.length >= 2) {
                                        worklogForm.setWorklogData({
                                            date: parts[0],
                                            time: parts[1],
                                            duration: page.issueModel.worklogDuracao || 30,
                                            comment: page.issueModel.worklogComment || ""
                                        });
                                    } else {
                                        worklogForm.setWorklogData({
                                            duration: page.issueModel.worklogDuracao || 30,
                                            comment: page.issueModel.worklogComment || ""
                                        });
                                    }
                                } else if (page.issueModel) {
                                    worklogForm.setWorklogData({
                                        duration: page.issueModel.worklogDuracao || 30,
                                        comment: page.issueModel.worklogComment || ""
                                    });
                                }
                            }
                            Connections {
                                target: page.issueModel || null
                                function onWorklogInicioChanged() {
                                    if (!page.issueModel || !worklogForm) return;
                                    var inicio = page.issueModel.worklogInicio || "";
                                    if (!inicio) return;
                                    var parts = inicio.split(" ");
                                    if (parts.length >= 2) {
                                        worklogForm.setWorklogData({
                                            date: parts[0],
                                            time: parts[1],
                                            duration: page.issueModel.worklogDuracao || 30,
                                            comment: page.issueModel.worklogComment || ""
                                        });
                                    }
                                }
                                function onWorklogDuracaoChanged() {
                                    if (!page.issueModel || !worklogForm) return;
                                    worklogForm.setWorklogData({
                                        duration: page.issueModel.worklogDuracao || 30
                                    });
                                }
                            }
                        }

                        IssueMetadataFields {
                            Layout.fillWidth: true
                            issueModel: page.issueModel
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
                    DialogHelpers.showError(page, "../components/dialogs/ErrorDialog.qml", msg, "IssueFormPage.voiceOrOther");
                })
                // qmllint enable missing-property
            }
        }
    }

    // Funções auxiliares
    function resetForm() {
        // Resetar campos para valores padrão
        if (page.issueModel) {
            page.issueModel.summary = "";
            page.issueModel.description = "";

            // Tipo de atividade padrão
            var defaultTipo = "Suporte Dúvidas/Suporte uso incorreto";
            var tipoValues = page.issueModel.tipoAtividadeValues;
            if (tipoValues.indexOf(defaultTipo) >= 0) {
                page.issueModel.tipoAtividade = defaultTipo;
            } else if (tipoValues.length > 0) {
                page.issueModel.tipoAtividade = tipoValues[0];
            }

            // Status inicial padrão
            if (page.issueModel.statusSequence && page.issueModel.statusSequence.length > 0) {
                page.issueModel.statusInicial = page.issueModel.statusSequence[0];
            }

            // Prioridade padrão
            page.issueModel.prioridade = "Medium";

            // Valores padrão
            page.issueModel.documentacaoAnexa = "Não";
            page.issueModel.utilizacaoIA = "Não";

            // Resetar Valor Entregue e Plataformas afetadas
            var valorEntregueValues = page.issueModel.valorEntregueValues;
            if (valorEntregueValues && valorEntregueValues.length > 0) {
                page.issueModel.valorEntregue = valorEntregueValues[0];
            } else {
                page.issueModel.valorEntregue = "";
            }
            page.issueModel.plataformasAfetadas = [];

            // Limpar Epic Parent
            page.issueModel.epicParentKey = "";
            page.issueModel.epicParentSummary = "";
            if (epicSearchForm) {
                epicSearchForm.reset();
            }

            // Resetar worklog
            page.issueModel.registrarWorklog = false;
            var now = new Date();
            var dateStr = Qt.formatDateTime(now, "yyyy-MM-dd");
            var timeStr = Qt.formatDateTime(now, "HH:mm:ss");
            page.issueModel.worklogInicio = dateStr + " " + timeStr;
            page.issueModel.worklogDuracao = 30;
            if (worklogForm) {
                worklogForm.reset();
            }

            // Limpar anexos pendentes da descrição
            page.issueModel.pendingAttachments = [];
            page._descriptionPlaceholderCounter = 0;
        }
    }

    function validateForm() {
        if (page.controller) {
            return page.controller.validate();
        }
        return false;
    }

}
