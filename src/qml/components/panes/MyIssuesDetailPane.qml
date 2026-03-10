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
import "../fields"
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

    // Registrar worklog só permitido quando status alvo é IN PROGRESS ou posterior
    property bool registrarWorklogEnabled: {
        if (!issueModel || !issueModel.statusSequence)
            return false;
        var seq = issueModel.statusSequence;
        var inDevIdx = seq.indexOf("IN PROGRESS");
        if (inDevIdx < 0)
            return false;
        var statusIdx = seq.indexOf(issueModel.statusInicial || "");
        return statusIdx >= inDevIdx;
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
        var deleted = pane._deletedAttachmentIds || [];
        var fromApi = (pane._detailsAttachments || []).filter(function (a) {
            return a && deleted.indexOf(String(a.id)) < 0;
        });
        return fromApi.concat(pane._newAttachmentsThisSession || []);
    }
    readonly property var _currentAttachmentsList: pane._buildCurrentAttachmentsList()

    function _openEmbedDialogForDescription(filePath, filename) {
        if (!filePath || !pane.jiraService || !pane.selectedIssueKey)
            return;
        var comp = Qt.createComponent("../dialogs/AttachmentEmbedPreviewDialog.qml");
        var win = pane.applicationWindow || pane.parent || pane;
        if (comp.status !== Component.Ready) {
            if (comp.status === Component.Error) {
                console.error("MyIssuesDetailPane: AttachmentEmbedPreviewDialog error:", comp.errorString());
            }
            comp.statusChanged.connect(function () {
                if (comp.status === Component.Ready) {
                    _createAndOpenEmbedDialog(comp, win, filePath, filename);
                }
            });
            return;
        }
        _createAndOpenEmbedDialog(comp, win, filePath, filename);
    }

    function _createAndOpenEmbedDialog(comp, parent, filePath, filename) {
        var dlg = comp.createObject(parent);
        if (!dlg)
            return;
        dlg.filePath = filePath;
        dlg.showPositionOptions = true;
        dlg.defaultDisplayWidth = (pane.jiraService && typeof pane.jiraService.getEmbedMaxDisplayWidth === "function") ? pane.jiraService.getEmbedMaxDisplayWidth() : 760;
        dlg.applicationWindow = pane.applicationWindow;
        dlg.clipboardHelper = pane.clipboardHelper;
        dlg.embedTarget = "description";
        dlg.acceptedEmbed.connect(function (layout, position, displayWidth) {
            pane._pendingAttachOnly = false;
            pane._pendingEmbedDisplayWidth = displayWidth > 0 ? displayWidth : 760;
            pane._pendingEmbedPosition = (position === "start" || position === "end") ? position : "end";
            pane.jiraService.uploadAttachment(pane.selectedIssueKey, filePath, "description");
        });
        dlg.acceptedAttachOnly.connect(function () {
            pane._pendingAttachOnly = true;
            pane.jiraService.uploadAttachment(pane.selectedIssueKey, filePath, "description");
        });
        dlg.rejected.connect(function () {});
        dlg.closed.connect(function () {
            dlg.destroy();
        });
        dlg.open();
    }

    function _uploadNonImageAndInsertLink(filePath, filename) {
        if (!pane.jiraService || !pane.selectedIssueKey)
            return;
        pane._pendingInsertAsLink = true;
        pane.jiraService.uploadAttachment(pane.selectedIssueKey, filePath, "description");
    }

    function _openAttachmentsPopover(button) {
        if (!button || !pane.jiraService)
            return;
        var comp = Qt.createComponent("../dialogs/DescriptionAttachmentsPopover.qml");
        if (comp.status !== Component.Ready) {
            if (comp.status === Component.Error) {
                console.error("MyIssuesDetailPane: DescriptionAttachmentsPopover error:", comp.errorString());
            }
            comp.statusChanged.connect(function () {
                if (comp.status === Component.Ready) {
                    _openAttachmentsPopover(button);
                }
            });
            return;
        }
        var popover = comp.createObject(button);
        if (!popover)
            return;
        popover.x = 0;
        popover.y = button.height + 2;
        popover.mode = "edit";
        popover.positionLeftOfButton = true;
        popover.editModePane = pane;
        popover.issueKey = pane.selectedIssueKey;
        popover.jiraService = pane.jiraService;
        popover.onAttachmentDeleted = function (attachmentId) {
            if (!pane.issueModel)
                return;
            pane.issueModel.description = FormatUtils.removeAttachmentFromDescription(pane.issueModel.description, attachmentId);
            var arr = [];
            for (var i = 0; i < (pane._newAttachmentsThisSession || []).length; i++) {
                if (String((pane._newAttachmentsThisSession)[i].id) !== String(attachmentId)) {
                    arr.push((pane._newAttachmentsThisSession)[i]);
                }
            }
            pane._newAttachmentsThisSession = arr;
            var delIds = pane._deletedAttachmentIds || [];
            if (delIds.indexOf(attachmentId) < 0)
                delIds.push(attachmentId);
            pane._deletedAttachmentIds = delIds;
        };
        popover.onAttachmentDeleteFailed = function (attId, msg) {
            if (pane.applicationWindow && typeof pane.applicationWindow.showPassiveNotification === "function") {
                pane.applicationWindow.showPassiveNotification(msg || qsTr("Erro ao excluir anexo."), 4000);
            }
        };
        popover.closed.connect(function () {
            popover.destroy();
        });
        popover.open();
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
        if (pane.issueModel) {
            fieldData.summary = pane.issueModel.summary || "";
            fieldData.description = pane.issueModel.description || "";
        }
        if (issueModel) {
            fieldData.tipoAtividade = issueModel.tipoAtividade || "";
            fieldData.status = issueModel.statusInicial || "";
            fieldData.prioridade = issueModel.prioridade || "";
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
                                    pane.myIssuesPage.loadIssueDetails(pane.selectedIssueKey);
                                }
                            }
                        }

                        SummaryAndDescriptionBlock {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            workItemModel: pane.issueModel
                            mode: "edit"
                            enabled: pane.selectedIssueKey !== "" && !pane.isProcessing
                            jiraService: pane.jiraService
                            clipboardHelper: pane.clipboardHelper
                            voiceInputService: pane.voiceInputService
                            showVoiceCreateButton: false
                            showExpandWithAIButton: true
                            requestSummaryFocus: false
                            summaryRequired: true
                            applicationWindow: pane.applicationWindow
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
                        spacing: Kirigami.Units.largeSpacing

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.largeSpacing

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
                            voiceInputService: pane.voiceInputService
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
                    var margin = 8;
                    var p1 = divider1.mapToItem(resizeOverlay, 0, 0);
                    if (mouse.y >= p1.y - margin && mouse.y < p1.y + divider1.height + margin) {
                        resizeOverlay.activeDivider = 1;
                        resizeOverlay.startGlobalY = resizeOverlay.mapToGlobal(mouse.x, mouse.y).y;
                        resizeOverlay.startHeight = pane.topSectionHeight;
                        mouse.accepted = true;
                        return;
                    }
                    var p2 = divider2.mapToItem(resizeOverlay, 0, 0);
                    if (mouse.y >= p2.y - margin && mouse.y < p2.y + divider2.height + margin) {
                        resizeOverlay.activeDivider = 2;
                        resizeOverlay.startGlobalY = resizeOverlay.mapToGlobal(mouse.x, mouse.y).y;
                        resizeOverlay.startHeight = pane.epicSectionHeight;
                        mouse.accepted = true;
                        return;
                    }
                    var p3 = commentsSection.commentResizeDivider.mapToItem(resizeOverlay, 0, 0);
                    if (mouse.y >= p3.y - margin && mouse.y < p3.y + commentsSection.commentResizeDivider.height + margin) {
                        resizeOverlay.activeDivider = 3;
                        resizeOverlay.startGlobalY = resizeOverlay.mapToGlobal(mouse.x, mouse.y).y;
                        resizeOverlay.startHeight = commentsSection.commentInputHeight;
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
                        pane.topSectionHeight = Math.max(150, resizeOverlay.startHeight + delta);
                    } else if (resizeOverlay.activeDivider === 2) {
                        pane.epicSectionHeight = Math.max(150, resizeOverlay.startHeight + delta);
                    } else if (resizeOverlay.activeDivider === 3) {
                        commentsSection.commentInputHeight = Math.max(160, resizeOverlay.startHeight + delta);
                    }
                }
                onReleased: {
                    resizeOverlay.activeDivider = 0;
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
}
