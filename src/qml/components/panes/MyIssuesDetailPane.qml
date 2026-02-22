/**
 * MyIssuesDetailPane.qml
 *
 * Right column of MyIssuesPage: scrollable detail with top section (summary/description),
 * epic section, bottom section (worklog + metadata). Resizable dividers and loading overlay.
 * Exposes getFieldData(), getWorklogData(), getEpicKey(), resetFields(), setDetails(details).
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami
import "../forms"
import "../controls"
import "../../utils/DialogHelpers.js" as DialogHelpers
import "../../utils/FormatUtils.js" as FormatUtils

Item {
    id: pane

    Controls.SplitView.fillWidth: true
    Controls.SplitView.minimumWidth: 400

    /** Referência à página (MyIssuesPage) para evitar ErrorDialog duplicado quando o erro já foi mostrado no ProcessDialog (ex.: iniciar timer). */
    property var myIssuesPage: null

    property var applicationWindow: null
    property var issueModel: null
    property string selectedIssueKey: ""
    property bool isProcessing: false

    // Registrar worklog só permitido quando status alvo é IN DEVELOPMENT ou posterior
    property bool registrarWorklogEnabled: {
        if (!issueModel || !issueModel.statusSequence) return false
        var seq = issueModel.statusSequence
        var inDevIdx = seq.indexOf("IN DEVELOPMENT")
        if (inDevIdx < 0) return false
        var statusIdx = seq.indexOf(issueModel.statusInicial || "")
        return statusIdx >= inDevIdx
    }
    property bool isDetailsLoading: false
    property var jiraService: null
    property var clipboardHelper: null
    property var gitCommandHelper: null
    property var voiceInputService: null
    property bool voiceInputAvailable: voiceInputService ? voiceInputService.isAvailable() : false
    property string sharedEpicKey: ""
    property string sharedEpicSummary: ""
    /** Status persistido no Jira; usado para desabilitar só status anteriores ao salvo (não ao escolhido no form). */
    property string savedStatus: ""

    property real topSectionHeight: 300
    property real epicSectionHeight: 250
    property bool _descriptionEditMode: true
    property bool _pendingAttachOnly: false
    property bool _pendingInsertAsLink: false
    property int _pendingEmbedDisplayWidth: 760
    property string _pendingEmbedPosition: "end"
    /** Anexos da issue vindos do GET (details.attachments). */
    property var _detailsAttachments: []
    /** Anexos enviados nesta sessão (upload na descrição) até salvar/recarregar. Itens: { id, filename }. */
    property var _newAttachmentsThisSession: []
    /** IDs de anexos excluídos nesta sessão (para esconder da lista até recarregar). */
    property var _deletedAttachmentIds: []

    function _buildCurrentAttachmentsList() {
        var deleted = pane._deletedAttachmentIds || []
        var fromApi = (pane._detailsAttachments || []).filter(function (a) {
            return a && deleted.indexOf(String(a.id)) < 0
        })
        return fromApi.concat(pane._newAttachmentsThisSession || [])
    }
    readonly property var _currentAttachmentsList: pane._buildCurrentAttachmentsList()

    function _openEmbedDialogForDescription(filePath, filename) {
        if (!filePath || !pane.jiraService || !pane.selectedIssueKey) return
        var comp = Qt.createComponent("../dialogs/AttachmentEmbedPreviewDialog.qml")
        var win = pane.applicationWindow || pane.parent || pane
        if (comp.status !== Component.Ready) {
            if (comp.status === Component.Error) {
                console.error("MyIssuesDetailPane: AttachmentEmbedPreviewDialog error:", comp.errorString())
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
        dlg.defaultDisplayWidth = (pane.jiraService && typeof pane.jiraService.getEmbedMaxDisplayWidth === "function")
            ? pane.jiraService.getEmbedMaxDisplayWidth() : 760
        dlg.applicationWindow = pane.applicationWindow
        dlg.clipboardHelper = pane.clipboardHelper
        dlg.embedTarget = "description"
        dlg.acceptedEmbed.connect(function (layout, position, displayWidth) {
            pane._pendingAttachOnly = false
            pane._pendingEmbedDisplayWidth = displayWidth > 0 ? displayWidth : 760
            pane._pendingEmbedPosition = (position === "start" || position === "end") ? position : "end"
            pane.jiraService.uploadAttachment(pane.selectedIssueKey, filePath, "description")
        })
        dlg.acceptedAttachOnly.connect(function () {
            pane._pendingAttachOnly = true
            pane.jiraService.uploadAttachment(pane.selectedIssueKey, filePath, "description")
        })
        dlg.rejected.connect(function () {})
        dlg.closed.connect(function () { dlg.destroy() })
        dlg.open()
    }

    function _uploadNonImageAndInsertLink(filePath, filename) {
        if (!pane.jiraService || !pane.selectedIssueKey) return
        pane._pendingInsertAsLink = true
        pane.jiraService.uploadAttachment(pane.selectedIssueKey, filePath, "description")
    }

    function _openAttachmentsPopover(button) {
        if (!button || !pane.jiraService) return
        var comp = Qt.createComponent("../dialogs/DescriptionAttachmentsPopover.qml")
        if (comp.status !== Component.Ready) {
            if (comp.status === Component.Error) {
                console.error("MyIssuesDetailPane: DescriptionAttachmentsPopover error:", comp.errorString())
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
        popover.mode = "edit"
        popover.positionLeftOfButton = true
        popover.editModePane = pane
        popover.issueKey = pane.selectedIssueKey
        popover.jiraService = pane.jiraService
        popover.onAttachmentDeleted = function (attachmentId) {
            if (!pane.issueModel) return
            pane.issueModel.description = FormatUtils.removeAttachmentFromDescription(pane.issueModel.description, attachmentId)
            var arr = []
            for (var i = 0; i < (pane._newAttachmentsThisSession || []).length; i++) {
                if (String((pane._newAttachmentsThisSession)[i].id) !== String(attachmentId)) {
                    arr.push((pane._newAttachmentsThisSession)[i])
                }
            }
            pane._newAttachmentsThisSession = arr
            var delIds = pane._deletedAttachmentIds || []
            if (delIds.indexOf(attachmentId) < 0) delIds.push(attachmentId)
            pane._deletedAttachmentIds = delIds
        }
        popover.onAttachmentDeleteFailed = function (attId, msg) {
            if (pane.applicationWindow && typeof pane.applicationWindow.showPassiveNotification === "function") {
                pane.applicationWindow.showPassiveNotification(msg || qsTr("Erro ao excluir anexo."), 4000)
            }
        }
        popover.closed.connect(function () { popover.destroy() })
        popover.open()
    }

    function _openQuickActionDialog(componentPath) {
        if (!pane.selectedIssueKey || !pane.jiraService) return
        var comp = Qt.createComponent(componentPath)
        // Usar sempre a janela principal como parent para o diálogo aparecer ao centro
        var win = pane.applicationWindow || (pane.myIssuesPage ? pane.myIssuesPage.applicationWindow : null) || pane.parent
        if (comp.status !== Component.Ready) {
            if (comp.status === Component.Error) {
                console.error("MyIssuesDetailPane: quick action dialog error:", comp.errorString())
            }
            comp.statusChanged.connect(function () {
                if (comp.status === Component.Ready) {
                    _openQuickActionDialog(componentPath)
                }
            })
            return
        }
        var dlg = comp.createObject(win)
        if (!dlg) return
        dlg.jiraService = pane.jiraService
        dlg.issueKey = pane.selectedIssueKey
        dlg.issueSummary = (pane.issueModel && pane.issueModel.summary) ? pane.issueModel.summary : ""
        if (typeof dlg.openWith === "function") {
            dlg.openWith(dlg.issueKey, dlg.issueSummary)
        } else {
            dlg.open()
        }
        if (pane.myIssuesPage && typeof pane.myIssuesPage._quickActionInProgress !== "undefined") {
            pane.myIssuesPage._quickActionInProgress = true
        }
        dlg.closed.connect(function () {
            // Limpar flag em callLater para que, se o utilizador confirmou, issueUpdated ainda veja _lastQuickActionType; se cancelou, limpamos aqui
            if (pane.myIssuesPage) {
                Qt.callLater(function () {
                    if (pane.myIssuesPage && typeof pane.myIssuesPage._quickActionInProgress !== "undefined") {
                        pane.myIssuesPage._quickActionInProgress = false
                    }
                })
            }
            dlg.destroy()
        })
    }

    function openCancelDialog() {
        if (pane.myIssuesPage && typeof pane.myIssuesPage._lastQuickActionType !== "undefined") {
            pane.myIssuesPage._lastQuickActionType = "cancel"
        }
        _openQuickActionDialog("../dialogs/CancelIssueDialog.qml")
    }
    function openBlockDialog() {
        if (pane.myIssuesPage && typeof pane.myIssuesPage._lastQuickActionType !== "undefined") {
            pane.myIssuesPage._lastQuickActionType = "block"
        }
        _openQuickActionDialog("../dialogs/BlockIssueDialog.qml")
    }
    function openUnblockDialog() {
        if (pane.myIssuesPage && typeof pane.myIssuesPage._lastQuickActionType !== "undefined") {
            pane.myIssuesPage._lastQuickActionType = "unblock"
        }
        _openQuickActionDialog("../dialogs/UnblockIssueDialog.qml")
    }

    /** Dados de development (branches/PRs) para o painel; preenchido em setDetails. null quando feature desativada. */
    property var developmentData: null
    /** Lista enriquecida de PRs (checks, approvals) quando disponível; definida externamente ao receber developmentEnriched. */
    property var enrichedPrs: null
    /** Lista enriquecida de branches (ahead/behind do GitHub) quando github_enrichment ativo; definida ao receber developmentBranchesEnriched. */
    property var enrichedBranches: null
    /** Serviço GitHub (para criar branch no painel de Development). */
    property var githubService: null

    signal epicSelected(string key, string summary)

    function getFieldData() {
        var fieldData = {};
        if (summaryFieldTab2) {
            fieldData.summary = summaryFieldTab2.text || "";
        }
        if (pane.issueModel) {
            fieldData.description = pane.issueModel.description || "";
        }
        if (issueModel) {
            fieldData.tipoAtividade = issueModel.tipoAtividade || "";
            fieldData.status = issueModel.statusInicial || "";
            fieldData.valorEntregue = issueModel.valorEntregue || "";
            fieldData.plataformasAfetadas = issueModel.plataformasAfetadas || [];
            fieldData.documentacaoAnexa = issueModel.documentacaoAnexa || "Não";
            fieldData.utilizacaoIA = issueModel.utilizacaoIA || "Não";
        }
        return fieldData;
    }

    function getWorklogData() {
        if (worklogCheckboxTab2 && worklogCheckboxTab2.checked && worklogForm) {
            var data = worklogForm.getWorklogData();
            // Com showCheckbox: false o checkbox do form não é visível; o estado vem do painel
            data.shouldRegister = true;
            return data;
        }
        return {};
    }

    function getEpicKey() {
        return epicSearchForm ? epicSearchForm.selectedEpicKey : "";
    }

    function resetFields() {
        if (issueModel) {
            issueModel.summary = "";
            issueModel.description = "";
            if (issueModel.tipoAtividadeValues && issueModel.tipoAtividadeValues.length > 0) {
                issueModel.tipoAtividade = issueModel.tipoAtividadeValues[0];
            } else {
                issueModel.tipoAtividade = "";
            }
            if (issueModel.statusSequence && issueModel.statusSequence.length > 0) {
                issueModel.statusInicial = issueModel.statusSequence[0];
            } else {
                issueModel.statusInicial = "";
            }
            issueModel.documentacaoAnexa = "Não";
            issueModel.utilizacaoIA = "Não";
            issueModel.valorEntregue = "";
            issueModel.plataformasAfetadas = [];
            issueModel.registrarWorklog = false;
        }
        if (worklogForm) {
            worklogForm.reset();
        }
        if (epicSearchForm) {
            epicSearchForm.reset();
        }
        pane.developmentData = null;
        pane.enrichedPrs = null;
        pane.enrichedBranches = null;
        pane._newAttachmentsThisSession = [];
        pane._deletedAttachmentIds = [];
    }

    function setDetails(details) {
        if (!details || !details.key) {
            return;
        }
        pane._detailsAttachments = details.attachments || [];
        pane._newAttachmentsThisSession = [];
        pane._deletedAttachmentIds = [];
        if (issueModel) {
            issueModel.summary = String(details.summary || "");
            issueModel.description = String(details.description || "");
            issueModel.tipoAtividade = String(details.tipoAtividade || "");
            issueModel.statusInicial = String(details.status || "");
            issueModel.prioridade = String(details.priority || "Medium");
            issueModel.valorEntregue = String(details.valorEntregue || "");
            issueModel.plataformasAfetadas = details.plataformasAfetadas || [];
            issueModel.documentacaoAnexa = String(details.documentacaoAnexa || "Não");
            issueModel.utilizacaoIA = String(details.utilizacaoIA || "Não");
            issueModel.registrarWorklog = false;
        }
        if (details.hasOwnProperty("development") && details.development && typeof details.development === "object") {
            pane.developmentData = details.development;
            pane.enrichedPrs = null;
            pane.enrichedBranches = null;
            var branchesLen = details.development.branches ? details.development.branches.length : 0;
            var prsLen = details.development.pullRequests ? details.development.pullRequests.length : 0;
            console.log("[ Development ] setDetails developmentData: present branches:" + branchesLen + " prs:" + prsLen);
        } else {
            pane.developmentData = null;
            pane.enrichedPrs = null;
            console.log("[ Development ] setDetails developmentData: null");
        }
        if (details.parentKey) {
            var parentKey = String(details.parentKey || "");
            var parentSummary = String(details.parentSummary || "");
            if (epicSearchForm && jiraService) {
                epicSearchForm.clearFilters();
                epicSearchForm.clearAll();
                epicSearchForm.setSearchText(parentKey);
                var epic = jiraService.searchEpicByKey(parentKey);
                if (epic && epic.key) {
                    epicSearchForm.selectEpic(epic.key, epic.summary || parentSummary);
                } else {
                    epicSearchForm.requestAutoSelect(parentKey, parentSummary);
                    epicSearchForm.search(parentKey);
                }
            }
        } else {
            if (epicSearchForm) {
                epicSearchForm.setDefaultFiltersForNoParent();
                epicSearchForm.clearAll();
            }
        }
    }

    // Wrapper para ter ScrollView e resizeOverlay como irmãos (igual IssueFormPage: SplitView e overlay irmãos).
    Item {
        id: detailsContentWrapper
        anchors.fill: parent

    Controls.ScrollView {
        id: mainDetailsScrollView
        anchors.fill: parent
        clip: true
        contentWidth: availableWidth

        Item {
            width: mainDetailsScrollView.availableWidth
            implicitHeight: contentColumn.implicitHeight

            ColumnLayout {
                id: contentColumn
                anchors.fill: parent
                anchors.leftMargin: Kirigami.Units.largeSpacing
                anchors.rightMargin: Kirigami.Units.largeSpacing
                spacing: Kirigami.Units.largeSpacing

                ColumnLayout {
                    id: topSection
                    Layout.fillWidth: true
                    Layout.preferredHeight: pane.topSectionHeight
                    Layout.minimumHeight: 150
                    spacing: Kirigami.Units.largeSpacing

                    DevelopmentHeaderBar {
                        Layout.fillWidth: true
                        developmentData: pane.developmentData
                        enrichedPrs: pane.enrichedPrs
                        enrichedBranches: pane.enrichedBranches
                        issueKey: pane.selectedIssueKey
                        issueSummary: pane.issueModel ? pane.issueModel.summary : ""
                        jiraService: pane.jiraService
                        clipboardHelper: pane.clipboardHelper
                        applicationWindow: pane.applicationWindow
                        gitCommandHelper: pane.gitCommandHelper
                        onReloadRequested: {
                            if (pane.myIssuesPage && pane.selectedIssueKey && typeof pane.myIssuesPage.loadIssueDetails === "function") {
                                pane.myIssuesPage.loadIssueDetails(pane.selectedIssueKey)
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        // Layout.margins: 20
                        // Layout.topMargin: 0
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
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            Controls.TextField {
                                id: summaryFieldTab2
                                Layout.fillWidth: true
                                enabled: pane.selectedIssueKey !== "" && !pane.isProcessing
                                text: pane.issueModel ? pane.issueModel.summary : ""
                                onTextChanged: if (pane.issueModel)
                                    pane.issueModel.summary = text
                            }

                            Controls.ToolButton {
                                visible: pane.voiceInputAvailable && pane.selectedIssueKey !== ""
                                icon.name: "tools-wizard"
                                text: qsTr("Expandir com IA")
                                enabled: !pane.isProcessing && !(pane.voiceInputService && pane.voiceInputService.isExpanding) && (summaryFieldTab2.text || (pane.issueModel ? pane.issueModel.description : ""))
                                onClicked: {
                                    if (pane.voiceInputService && summaryFieldTab2) {
                                        pane.voiceInputService.expandFromSummaryAndDescription(
                                            summaryFieldTab2.text || "",
                                            (pane.issueModel ? pane.issueModel.description : "") || "",
                                            true
                                        );
                                    }
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
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
                                isEditMode: pane._descriptionEditMode
                                onModeChanged: function(editMode) {
                                    pane._descriptionEditMode = editMode
                                }
                            }

                            Controls.ToolButton {
                                icon.name: "mail-attachment"
                                text: qsTr("Anexos na descrição")
                                display: Controls.AbstractButton.IconOnly
                                onClicked: pane._openAttachmentsPopover(this)
                            }
                        }

                        Item {
                            id: descriptionContainerTab2
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            StackLayout {
                                anchors.fill: parent
                                currentIndex: pane._descriptionEditMode ? 0 : 1

                                // Edit mode: estrutura original (DropArea > ScrollView > TextArea)
                                DropArea {
                                    enabled: pane.selectedIssueKey !== "" && !pane.isProcessing && pane.jiraService
                                    onDropped: function(drop) {
                                        if (!pane.jiraService || !pane.selectedIssueKey || !drop.urls || drop.urls.length === 0) return
                                        var extList = (typeof pane.jiraService.getAllowedAttachmentExtensions === "function")
                                            ? pane.jiraService.getAllowedAttachmentExtensions() : []
                                        var imageExtList = (typeof pane.jiraService.getAllowedImageExtensions === "function")
                                            ? pane.jiraService.getAllowedImageExtensions() : []
                                        for (var i = 0; i < drop.urls.length; i++) {
                                            var urlStr = drop.urls[i].toString()
                                            var path = urlStr.replace(/^file:\/\//, "")
                                            var filename = path.split("/").pop() || path.split("\\").pop() || "file"
                                            var ext = filename.indexOf(".") >= 0 ? filename.split(".").pop().toLowerCase() : ""
                                            if (extList.indexOf(ext) < 0) continue
                                            var pathToUse = (pane.clipboardHelper && typeof pane.clipboardHelper.copyFileToTemp === "function")
                                                ? pane.clipboardHelper.copyFileToTemp(path) : path
                                            if (!pathToUse) pathToUse = path
                                            if (imageExtList.indexOf(ext) >= 0) {
                                                pane._openEmbedDialogForDescription(pathToUse, filename)
                                            } else {
                                                pane._uploadNonImageAndInsertLink(pathToUse, filename)
                                            }
                                        }
                                    }

                                    Controls.ScrollView {
                                        id: descriptionScrollView
                                        anchors.fill: parent
                                        clip: true
                                        contentWidth: descriptionFieldTab2.implicitWidth

                                        Controls.TextArea {
                                            id: descriptionFieldTab2
                                            width: descriptionContainerTab2.width
                                            wrapMode: Controls.TextArea.Wrap
                                            enabled: pane.selectedIssueKey !== "" && !pane.isProcessing
                                            topPadding: Kirigami.Units.smallSpacing
                                            bottomPadding: Kirigami.Units.smallSpacing
                                            placeholderText: qsTr("Arraste ficheiros ou use Ctrl+V para colar imagem; imagens têm preview, outros ficheiros ficam como link.")
                                            text: pane.issueModel ? pane.issueModel.description : ""
                                            onTextChanged: if (pane.issueModel) pane.issueModel.description = text

                                            Keys.onPressed: function(event) {
                                                if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V) {
                                                    if (!pane.clipboardHelper || !pane.jiraService || !pane.selectedIssueKey) return
                                                    if (pane.clipboardHelper.hasClipboardImage()) {
                                                        var tempPath = pane.clipboardHelper.getClipboardImageAsTempFile()
                                                        if (tempPath) {
                                                            pane._openEmbedDialogForDescription(tempPath, "paste.png")
                                                            event.accepted = true
                                                        }
                                                    }
                                                } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_E) {
                                                    pane._descriptionEditMode = true
                                                    event.accepted = true
                                                } else if ((event.modifiers & (Qt.ControlModifier | Qt.ShiftModifier)) === (Qt.ControlModifier | Qt.ShiftModifier) && event.key === Qt.Key_P) {
                                                    pane._descriptionEditMode = false
                                                    event.accepted = true
                                                } else if (event.key === Qt.Key_Escape) {
                                                    pane._descriptionEditMode = true
                                                    event.accepted = true
                                                }
                                            }
                                        }
                                    }
                                }

                                // Preview mode
                                Rectangle {
                                    focus: !pane._descriptionEditMode
                                    color: "transparent"
                                    border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
                                    border.width: 0.5
                                    radius: Kirigami.Units.smallSpacing

                                    Keys.onPressed: function(event) {
                                        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_E) {
                                            pane._descriptionEditMode = true
                                            event.accepted = true
                                        } else if ((event.modifiers & (Qt.ControlModifier | Qt.ShiftModifier)) === (Qt.ControlModifier | Qt.ShiftModifier) && event.key === Qt.Key_P) {
                                            pane._descriptionEditMode = false
                                            event.accepted = true
                                        } else if (event.key === Qt.Key_Escape) {
                                            pane._descriptionEditMode = true
                                            event.accepted = true
                                        }
                                    }

                                    Controls.ScrollView {
                                        id: descriptionPreviewScrollTab2
                                        anchors.fill: parent
                                        anchors.margins: 1
                                        clip: true
                                        contentWidth: availableWidth

                                        RichTextWithJiraImages {
                                            width: descriptionPreviewScrollTab2.availableWidth
                                            sourceText: pane.issueModel ? pane.issueModel.description : ""
                                            jiraService: pane.jiraService
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Connections {
                        target: pane.jiraService || null
                        function onAttachmentUploaded(uploadedIssueKey, contentUrl, filename, embedTarget) {
                            if (uploadedIssueKey !== pane.selectedIssueKey || !contentUrl || !filename || !descriptionFieldTab2) return
                            if (embedTarget !== "description") return
                            if (pane._pendingAttachOnly) {
                                pane._pendingAttachOnly = false
                                var match = /\/attachment\/content\/(\d+)/.exec(contentUrl || "")
                                if (match && match[1]) {
                                    var arrAttach = pane._newAttachmentsThisSession || []
                                    arrAttach.push({ id: match[1], filename: filename })
                                    pane._newAttachmentsThisSession = arrAttach
                                }
                                return
                            }
                            if (pane._pendingInsertAsLink) {
                                pane._pendingInsertAsLink = false
                                var linkMarkdown = "[" + filename + "](" + contentUrl + ")"
                                var insertPos = descriptionFieldTab2.cursorPosition >= 0 ? descriptionFieldTab2.cursorPosition : descriptionFieldTab2.text.length
                                descriptionFieldTab2.insert(insertPos, linkMarkdown)
                                if (pane.issueModel) pane.issueModel.description = descriptionFieldTab2.text
                                var matchLink = /\/attachment\/content\/(\d+)/.exec(contentUrl || "")
                                if (matchLink && matchLink[1]) {
                                    var arrLink = pane._newAttachmentsThisSession || []
                                    arrLink.push({ id: matchLink[1], filename: filename })
                                    pane._newAttachmentsThisSession = arrLink
                                }
                                return
                            }
                            var w = pane._pendingEmbedDisplayWidth > 0 ? pane._pendingEmbedDisplayWidth : 760
                            var markdown = "![" + filename + "](" + contentUrl + "){: width=\"" + w + "\" }"
                            var txt = descriptionFieldTab2.text
                            var insertPos, toInsert
                            if (pane._pendingEmbedPosition === "start") {
                                insertPos = 0
                                toInsert = markdown + (txt.length > 0 ? "\n\n" : "")
                            } else {
                                insertPos = txt.length
                                toInsert = (txt.length > 0 ? "\n\n" : "") + markdown
                            }
                            descriptionFieldTab2.insert(insertPos, toInsert)
                            if (pane.issueModel) pane.issueModel.description = descriptionFieldTab2.text
                            var match = /\/attachment\/content\/(\d+)/.exec(contentUrl || "")
                            if (match && match[1]) {
                                var arr = pane._newAttachmentsThisSession || []
                                arr.push({ id: match[1], filename: filename })
                                pane._newAttachmentsThisSession = arr
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

                ColumnLayout {
                    id: epicSection
                    Layout.fillWidth: true
                    Layout.preferredHeight: pane.epicSectionHeight
                    Layout.minimumHeight: 150
                    spacing: Kirigami.Units.smallSpacing

                    Controls.Label {
                        text: qsTr("Epic Parent:")
                        font.bold: true
                        Layout.fillWidth: true
                        // Layout.leftMargin: 20
                        // Layout.topMargin: 10
                    }

                    EpicSearchForm {
                        id: epicSearchForm
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        // Layout.margins: 20
                        // Layout.topMargin: 0
                        enabled: pane.selectedIssueKey !== "" && !pane.isProcessing

                        Binding {
                            target: epicSearchForm
                            property: "jiraService"
                            value: pane.jiraService
                            when: pane.jiraService !== null
                        }

                        onEpicSelected: function (key, summary) {
                            pane.epicSelected(key, summary);
                            if (pane.issueModel) {
                                pane.issueModel.epicParentKey = key;
                                pane.issueModel.epicParentSummary = summary;
                            }
                        }

                        onEpicCleared: {
                            pane.sharedEpicKey = "";
                            pane.sharedEpicSummary = "";
                            if (pane.issueModel) {
                                pane.issueModel.epicParentKey = "";
                                pane.issueModel.epicParentSummary = "";
                            }
                        }

                        Binding {
                            target: epicSearchForm
                            property: "selectedEpicKey"
                            value: pane.sharedEpicKey
                            when: pane.sharedEpicKey !== "" && pane.sharedEpicKey !== epicSearchForm.selectedEpicKey
                        }

                        Binding {
                            target: epicSearchForm
                            property: "selectedEpicSummary"
                            value: pane.sharedEpicSummary
                            when: pane.sharedEpicSummary !== "" && pane.sharedEpicSummary !== epicSearchForm.selectedEpicSummary
                        }

                        Binding {
                            target: epicSearchForm
                            property: "selectedEpicKey"
                            value: pane.issueModel ? pane.issueModel.epicParentKey : ""
                            when: pane.issueModel
                        }

                        Binding {
                            target: epicSearchForm
                            property: "selectedEpicSummary"
                            value: pane.issueModel ? pane.issueModel.epicParentSummary : ""
                            when: pane.issueModel
                        }

                        Binding {
                            target: pane.issueModel
                            property: "epicParentKey"
                            value: epicSearchForm.selectedEpicKey
                            when: pane.issueModel
                        }

                        Binding {
                            target: pane.issueModel
                            property: "epicParentSummary"
                            value: epicSearchForm.selectedEpicSummary
                            when: pane.issueModel
                        }
                    }

                    Item {
                        Layout.fillHeight: true
                        Layout.fillWidth: true
                    }
                }

                DividerBar {
                    id: divider2
                    Layout.fillWidth: true
                }

                ColumnLayout {
                    id: bottomColumnLayout
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 0

                    ColumnLayout {
                        Layout.fillWidth: true
                        // Layout.margins: 20
                        // Layout.topMargin: 10
                        // Layout.bottomMargin: 10
                        spacing: Kirigami.Units.smallSpacing

                        Controls.CheckBox {
                            id: worklogCheckboxTab2
                            text: qsTr("Registrar worklog")
                            Layout.fillWidth: true
                            enabled: pane.selectedIssueKey !== "" && !pane.isProcessing && pane.registrarWorklogEnabled
                            checked: pane.issueModel ? pane.issueModel.registrarWorklog : false
                            onCheckedChanged: {
                                if (pane.issueModel) {
                                    pane.issueModel.registrarWorklog = checked;
                                }
                            }
                        }
                        Binding {
                            target: pane.issueModel
                            property: "registrarWorklog"
                            value: false
                            when: pane.issueModel && !pane.registrarWorklogEnabled
                        }

                        WorklogForm {
                            id: worklogForm
                            jiraService: pane.jiraService
                            Layout.fillWidth: true
                            enabled: pane.selectedIssueKey !== "" && !pane.isProcessing && worklogCheckboxTab2.checked
                            visible: worklogCheckboxTab2.checked
                            showCheckbox: false

                            Binding {
                                target: pane.issueModel
                                property: "worklogInicio"
                                value: worklogForm.date && worklogForm.time ? worklogForm.date + " " + worklogForm.time : ""
                                when: pane.issueModel && worklogForm.date && worklogForm.time
                            }

                            Binding {
                                target: pane.issueModel
                                property: "worklogDuracao"
                                value: Math.round(worklogForm.duration)
                                when: pane.issueModel
                            }

                            Binding {
                                target: pane.issueModel
                                property: "worklogComment"
                                value: worklogForm.comment
                                when: pane.issueModel
                            }

                            Component.onCompleted: {
                                if (pane.issueModel && pane.issueModel.worklogInicio) {
                                    var parts = pane.issueModel.worklogInicio.split(" ");
                                    if (parts.length >= 2) {
                                        worklogForm.date = parts[0];
                                        worklogForm.time = parts[1];
                                    }
                                }
                                if (pane.issueModel) {
                                    worklogForm.duration = pane.issueModel.worklogDuracao || 30;
                                    worklogForm.comment = pane.issueModel.worklogComment || "";
                                }
                            }
                        }
                    }

                    IssueMetadataFields {
                        Layout.fillWidth: true
                        issueModel: pane.issueModel
                        enabled: pane.selectedIssueKey !== "" && !pane.isProcessing
                        restrictStatusBySequence: true
                        statusForRestriction: pane.savedStatus
                    }

                    CommentsSection {
                        id: commentsSection
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumHeight: 200
                        applicationWindow: pane.applicationWindow
                        jiraService: pane.jiraService
                        clipboardHelper: pane.clipboardHelper
                        selectedIssueKey: pane.selectedIssueKey
                        onErrorOccurred: function (message) {
                            if (typeof console !== "undefined" && console.log) {
                                console.log("[MyIssuesDetailPane] CommentsSection.onErrorOccurred. _jiraErrorShownInProcessDialog=", (pane.myIssuesPage && pane.myIssuesPage._jiraErrorShownInProcessDialog) || false, "_jiraErrorShownInCreateFlow=", (pane.myIssuesPage && pane.myIssuesPage.applicationWindow && pane.myIssuesPage.applicationWindow._jiraErrorShownInCreateFlow) || false);
                            }
                            if (pane.myIssuesPage && pane.myIssuesPage._jiraErrorShownInProcessDialog) {
                                if (typeof console !== "undefined" && console.log) {
                                    console.log("[MyIssuesDetailPane] CommentsSection.onErrorOccurred -> SKIP (erro já no ProcessDialog)");
                                }
                                return;
                            }
                            if (pane.myIssuesPage && pane.myIssuesPage.applicationWindow && pane.myIssuesPage.applicationWindow._jiraErrorShownInCreateFlow) {
                                if (typeof console !== "undefined" && console.log) {
                                    console.log("[MyIssuesDetailPane] CommentsSection.onErrorOccurred -> SKIP (erro já no SuccessDialog/ fluxo criar issue)");
                                }
                                return;
                            }
                            if (typeof console !== "undefined" && console.log) {
                                console.log("[MyIssuesDetailPane] CommentsSection.onErrorOccurred -> DialogHelpers.showError (ErrorDialog com OK)");
                            }
                            DialogHelpers.showError(pane, "../components/dialogs/ErrorDialog.qml", message, "MyIssuesDetailPane.CommentsSection");
                        }
                    }
                }
            }
        }
    }

    // Overlay único para redimensionar dividers (irmão do ScrollView, cobre a área, hit-test em onPressed).
    Item {
        id: resizeOverlay
        z: 10
        anchors.fill: detailsContentWrapper
        property int activeDivider: 0
        property real startGlobalY: 0
        property real startHeight: 0

        MouseArea {
            anchors.fill: parent
            hoverEnabled: false
            cursorShape: parent.activeDivider ? Qt.SizeVerCursor : Qt.ArrowCursor
            onPressed: function (mouse) {
                var margin = 8
                var p1 = divider1.mapToItem(resizeOverlay, 0, 0)
                if (mouse.y >= p1.y - margin && mouse.y < p1.y + divider1.height + margin) {
                    resizeOverlay.activeDivider = 1
                    resizeOverlay.startGlobalY = resizeOverlay.mapToGlobal(mouse.x, mouse.y).y
                    resizeOverlay.startHeight = pane.topSectionHeight
                    mouse.accepted = true
                    return
                }
                var p2 = divider2.mapToItem(resizeOverlay, 0, 0)
                if (mouse.y >= p2.y - margin && mouse.y < p2.y + divider2.height + margin) {
                    resizeOverlay.activeDivider = 2
                    resizeOverlay.startGlobalY = resizeOverlay.mapToGlobal(mouse.x, mouse.y).y
                    resizeOverlay.startHeight = pane.epicSectionHeight
                    mouse.accepted = true
                    return
                }
                var p3 = commentsSection.commentResizeDivider.mapToItem(resizeOverlay, 0, 0)
                if (mouse.y >= p3.y - margin && mouse.y < p3.y + commentsSection.commentResizeDivider.height + margin) {
                    resizeOverlay.activeDivider = 3
                    resizeOverlay.startGlobalY = resizeOverlay.mapToGlobal(mouse.x, mouse.y).y
                    resizeOverlay.startHeight = commentsSection.commentInputHeight
                    mouse.accepted = true
                    return
                }
                mouse.accepted = false
            }
            onPositionChanged: function (mouse) {
                if (resizeOverlay.activeDivider === 0) return
                var cur = resizeOverlay.mapToGlobal(mouse.x, mouse.y).y
                var delta = cur - resizeOverlay.startGlobalY
                if (resizeOverlay.activeDivider === 1) {
                    pane.topSectionHeight = Math.max(150, resizeOverlay.startHeight + delta)
                } else if (resizeOverlay.activeDivider === 2) {
                    pane.epicSectionHeight = Math.max(150, resizeOverlay.startHeight + delta)
                } else if (resizeOverlay.activeDivider === 3) {
                    commentsSection.commentInputHeight = Math.max(160, resizeOverlay.startHeight + delta)
                }
            }
            onReleased: {
                resizeOverlay.activeDivider = 0
            }
        }
    }
    } // detailsContentWrapper

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.4)
        visible: pane.isDetailsLoading
        z: 100

        Controls.BusyIndicator {
            anchors.centerIn: parent
            running: pane.isDetailsLoading
            visible: pane.isDetailsLoading
        }
    }

    // Overlay de loading durante "Expandir com IA" (bloqueia o painel)
    Item {
        anchors.fill: parent
        visible: pane.voiceInputService !== null && pane.voiceInputService.isExpanding
        z: 101

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
}
