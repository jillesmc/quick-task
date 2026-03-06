/**
 * WorkItemDetailPane.qml
 *
 * Painel de detalhe para abas 7/8 (work items). Duplicado de MyIssuesDetailPane com conceitos
 * Atlassian/parent work item: workItemModel, atlassianService, ParentWorkItemBlock.
 * Não modificar MyIssuesDetailPane (dependência das abas 0/1).
 * Exposes getFieldData(), getWorklogData(), getEpicKey() / getParentWorkItemKey(), resetFields(), setDetails(details).
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami
import "../controls"
import "../fields"
import "../../utils/DialogHelpers.js" as DialogHelpers
import "../../utils/FormatUtils.js" as FormatUtils

Item {
    id: pane

    Controls.SplitView.fillWidth: true
    Controls.SplitView.minimumWidth: 400

    /** Referência à página (MyWorkItemsPage) para reload e diálogos. */
    property var workItemsPage: null

    property var applicationWindow: null
    property var workItemModel: null
    property string selectedIssueKey: ""
    property bool isProcessing: false

    // Registrar worklog só permitido quando status alvo é IN PROGRESS ou posterior
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
    property bool isDetailsLoading: false
    property var atlassianService: null
    property var atlassianMetadataConfigModel: null
    property var clipboardHelper: null
    property var gitCommandHelper: null
    property var voiceInputService: null
    property bool voiceInputAvailable: voiceInputService ? voiceInputService.isAvailable() : false
    property string sharedEpicKey: ""
    property string sharedEpicSummary: ""
    /** Status persistido no Jira; usado para desabilitar só status anteriores ao salvo (não ao escolhido no form). */
    property string savedStatus: ""
    /** Chave do projeto da issue (ex.: PLATFORM); preenchido em setDetails para workflow metadata. */
    property string projectKey: ""
    /** ID do tipo de issue (ex.: 10008); preenchido em setDetails para workflow metadata. */
    property string issuetypeId: ""
    /** Transições disponíveis da API (GET issue/transitions); preenchido em setDetails. Usado pelo status para habilitar apenas destinos possíveis. */
    property var availableTransitions: []

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
        if (!filePath || !pane.atlassianService || !pane.selectedIssueKey)
            return;
        var comp = Qt.createComponent("../dialogs/AttachmentEmbedPreviewDialog.qml");
        var win = pane.applicationWindow || pane.parent || pane;
        if (comp.status !== Component.Ready) {
            if (comp.status === Component.Error) {
                console.error("WorkItemDetailPane: AttachmentEmbedPreviewDialog error:", comp.errorString());
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
        dlg.defaultDisplayWidth = (pane.atlassianService && typeof pane.atlassianService.getEmbedMaxDisplayWidth === "function") ? pane.atlassianService.getEmbedMaxDisplayWidth() : 760;
        dlg.applicationWindow = pane.applicationWindow;
        dlg.clipboardHelper = pane.clipboardHelper;
        dlg.embedTarget = "description";
        dlg.acceptedEmbed.connect(function (layout, position, displayWidth) {
            pane._pendingAttachOnly = false;
            pane._pendingEmbedDisplayWidth = displayWidth > 0 ? displayWidth : 760;
            pane._pendingEmbedPosition = (position === "start" || position === "end") ? position : "end";
            pane.atlassianService.uploadAttachment(pane.selectedIssueKey, filePath, "description");
        });
        dlg.acceptedAttachOnly.connect(function () {
            pane._pendingAttachOnly = true;
            pane.atlassianService.uploadAttachment(pane.selectedIssueKey, filePath, "description");
        });
        dlg.rejected.connect(function () {});
        dlg.closed.connect(function () {
            dlg.destroy();
        });
        dlg.open();
    }

    function _uploadNonImageAndInsertLink(filePath, filename) {
        if (!pane.atlassianService || !pane.selectedIssueKey)
            return;
        pane._pendingInsertAsLink = true;
        pane.atlassianService.uploadAttachment(pane.selectedIssueKey, filePath, "description");
    }

    function _openAttachmentsPopover(button) {
        if (!button || !pane.atlassianService)
            return;
        var comp = Qt.createComponent("../dialogs/DescriptionAttachmentsPopover.qml");
        if (comp.status !== Component.Ready) {
            if (comp.status === Component.Error) {
                console.error("WorkItemDetailPane: DescriptionAttachmentsPopover error:", comp.errorString());
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
        popover.jiraService = pane.atlassianService;
        popover.onAttachmentDeleted = function (attachmentId) {
            if (!pane.workItemModel)
                return;
            pane.workItemModel.description = FormatUtils.removeAttachmentFromDescription(pane.workItemModel.description, attachmentId);
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
        if (pane.workItemModel) {
            fieldData.summary = pane.workItemModel.summary || "";
            fieldData.description = pane.workItemModel.description || "";
        }
        if (workItemModel) {
            fieldData.tipoAtividade = workItemModel.tipoAtividade || "";
            fieldData.status = workItemModel.statusInicial || "";
            fieldData.prioridade = workItemModel.prioridade || "";
            fieldData.valorEntregue = workItemModel.valorEntregue || "";
            fieldData.plataformasAfetadas = workItemModel.plataformasAfetadas || [];
            fieldData.documentacaoAnexa = workItemModel.documentacaoAnexa || "Não";
            fieldData.utilizacaoIA = workItemModel.utilizacaoIA || "Não";
        }
        return fieldData;
    }

    function getWorklogData() {
        if (registerWorklogBlockRef && typeof registerWorklogBlockRef.getWorklogData === "function") {
            return registerWorklogBlockRef.getWorklogData();
        }
        return {};
    }

    function getEpicKey() {
        return getParentWorkItemKey();
    }

    function getParentWorkItemKey() {
        return parentWorkItemBlockRef && typeof parentWorkItemBlockRef.getParentWorkItemKey === "function" ? parentWorkItemBlockRef.getParentWorkItemKey() : "";
    }

    function resetFields() {
        if (workItemModel) {
            workItemModel.summary = "";
            workItemModel.description = "";
            if (workItemModel.tipoAtividadeValues && workItemModel.tipoAtividadeValues.length > 0) {
                workItemModel.tipoAtividade = workItemModel.tipoAtividadeValues[0];
            } else {
                workItemModel.tipoAtividade = "";
            }
            if (workItemModel.statusSequence && workItemModel.statusSequence.length > 0) {
                workItemModel.statusInicial = workItemModel.statusSequence[0];
            } else {
                workItemModel.statusInicial = "";
            }
            workItemModel.documentacaoAnexa = "Não";
            workItemModel.utilizacaoIA = "Não";
            workItemModel.valorEntregue = "";
            workItemModel.plataformasAfetadas = [];
        }
        if (registerWorklogBlockRef && typeof registerWorklogBlockRef.reset === "function") {
            registerWorklogBlockRef.reset();
        }
        if (parentWorkItemBlockRef && typeof parentWorkItemBlockRef.clearParent === "function") {
            parentWorkItemBlockRef.clearParent();
        }
        pane.developmentData = null;
        pane.enrichedPrs = null;
        pane.enrichedBranches = null;
        pane.availableTransitions = [];
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
        if (workItemModel) {
            workItemModel.summary = String(details.summary || "");
            workItemModel.description = String(details.description || "");
            workItemModel.tipoAtividade = String(details.tipoAtividade || "");
            workItemModel.statusInicial = String(details.status || "");
            workItemModel.prioridade = String(details.priority || "Medium");
            workItemModel.valorEntregue = String(details.valorEntregue || "");
            workItemModel.plataformasAfetadas = details.plataformasAfetadas || [];
            workItemModel.documentacaoAnexa = String(details.documentacaoAnexa || "Não");
            workItemModel.utilizacaoIA = String(details.utilizacaoIA || "Não");
            workItemModel.registrarWorklog = false;
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
        pane.projectKey = String(details.projectKey || "");
        pane.issuetypeId = String(details.issuetypeId || "");
        pane.availableTransitions = (details.availableTransitions && typeof details.availableTransitions.length === "number") ? details.availableTransitions : [];
        if (details.parentKey) {
            var parentKey = String(details.parentKey || "");
            var parentSummary = String(details.parentSummary || "");
            if (parentWorkItemBlockRef && typeof parentWorkItemBlockRef.setParentFromDetails === "function") {
                parentWorkItemBlockRef.setParentFromDetails(parentKey, parentSummary);
            }
        } else {
            if (parentWorkItemBlockRef && typeof parentWorkItemBlockRef.setParentFromDetails === "function") {
                parentWorkItemBlockRef.setParentFromDetails("", "");
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
                            issueSummary: pane.workItemModel ? pane.workItemModel.summary : ""
                            jiraService: pane.atlassianService
                            clipboardHelper: pane.clipboardHelper
                            applicationWindow: pane.applicationWindow
                            gitCommandHelper: pane.gitCommandHelper
                            onReloadRequested: {
                                if (pane.workItemsPage && pane.selectedIssueKey && typeof pane.workItemsPage.loadIssueDetails === "function") {
                                    pane.workItemsPage.loadIssueDetails(pane.selectedIssueKey);
                                }
                            }
                        }

                        SummaryAndDescriptionBlock {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            workItemModel: pane.workItemModel
                            mode: "edit"
                            enabled: pane.selectedIssueKey !== "" && !pane.isProcessing
                            jiraService: pane.atlassianService
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

                        ParentWorkItemBlock {
                            id: parentWorkItemBlockRef
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            model: pane.workItemModel
                            atlassianService: pane.atlassianService
                            metadataConfigModel: pane.atlassianMetadataConfigModel
                            parentIssueType: "Epic"
                            enabled: pane.selectedIssueKey !== "" && !pane.isProcessing
                            mode: "edit"
                            sharedParentWorkItemKey: pane.sharedEpicKey
                            sharedParentWorkItemSummary: pane.sharedEpicSummary
                            preferredHeight: pane.epicSectionHeight
                            minimumHeight: 150

                            onParentWorkItemSelected: function (key, summary) {
                                pane.epicSelected(key, summary);
                            }
                            onParentWorkItemCleared: {
                                pane.sharedEpicKey = "";
                                pane.sharedEpicSummary = "";
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

                        RegisterWorklogBlock {
                            id: registerWorklogBlockRef
                            model: pane.workItemModel
                            enabled: pane.selectedIssueKey !== "" && !pane.isProcessing
                            registrarWorklogEnabled: pane.registrarWorklogEnabled
                            service: pane.atlassianService
                        }

                        WorkItemMetadataFields {
                            Layout.fillWidth: true
                            workItemModel: pane.workItemModel
                            enabled: pane.selectedIssueKey !== "" && !pane.isProcessing
                            restrictStatusBySequence: true
                            statusForRestriction: pane.savedStatus
                            atlassianMetadataConfigModel: pane.atlassianMetadataConfigModel
                            projectKey: pane.projectKey
                            issuetypeId: pane.issuetypeId
                            availableTransitions: pane.availableTransitions
                        }

                        CommentsSection {
                            id: commentsSection
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.minimumHeight: 200
                            applicationWindow: pane.applicationWindow
                            jiraService: pane.atlassianService
                            clipboardHelper: pane.clipboardHelper
                            voiceInputService: pane.voiceInputService
                            selectedIssueKey: pane.selectedIssueKey
                            onErrorOccurred: function (message) {
                                if (typeof console !== "undefined" && console.log) {
                                    console.log("[WorkItemDetailPane] CommentsSection.onErrorOccurred. _jiraErrorShownInProcessDialog=", (pane.workItemsPage && pane.workItemsPage._jiraErrorShownInProcessDialog) || false, "_jiraErrorShownInCreateFlow=", (pane.workItemsPage && pane.workItemsPage.applicationWindow && pane.workItemsPage.applicationWindow._jiraErrorShownInCreateFlow) || false);
                                }
                                if (pane.workItemsPage && pane.workItemsPage._jiraErrorShownInProcessDialog) {
                                    if (typeof console !== "undefined" && console.log) {
                                        console.log("[WorkItemDetailPane] CommentsSection.onErrorOccurred -> SKIP (erro já no ProcessDialog)");
                                    }
                                    return;
                                }
                                if (pane.workItemsPage && pane.workItemsPage.applicationWindow && pane.workItemsPage.applicationWindow._jiraErrorShownInCreateFlow) {
                                    if (typeof console !== "undefined" && console.log) {
                                        console.log("[WorkItemDetailPane] CommentsSection.onErrorOccurred -> SKIP (erro já no SuccessDialog/ fluxo criar issue)");
                                    }
                                    return;
                                }
                                if (typeof console !== "undefined" && console.log) {
                                    console.log("[WorkItemDetailPane] CommentsSection.onErrorOccurred -> DialogHelpers.showError (ErrorDialog com OK)");
                                }
                                DialogHelpers.showError(pane, "../components/dialogs/ErrorDialog.qml", message, "WorkItemDetailPane.CommentsSection");
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
