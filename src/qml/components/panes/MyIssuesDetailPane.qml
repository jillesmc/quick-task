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

Item {
    id: pane

    Controls.SplitView.fillWidth: true
    Controls.SplitView.minimumWidth: 400

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
    property string sharedEpicKey: ""
    property string sharedEpicSummary: ""

    property real topSectionHeight: 300
    property real epicSectionHeight: 250

    signal epicSelected(string key, string summary)

    function getFieldData() {
        var fieldData = {};
        if (summaryFieldTab2) {
            fieldData.summary = summaryFieldTab2.text || "";
        }
        if (descriptionFieldTab2) {
            fieldData.description = descriptionFieldTab2.text || "";
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
        if (summaryFieldTab2) {
            summaryFieldTab2.text = "";
        }
        if (descriptionFieldTab2) {
            descriptionFieldTab2.text = "";
        }
        if (issueModel) {
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
    }

    function setDetails(details) {
        if (!details || !details.key) {
            return;
        }
        if (summaryFieldTab2) {
            summaryFieldTab2.text = String(details.summary || "");
        }
        if (descriptionFieldTab2) {
            descriptionFieldTab2.text = String(details.description || "");
        }
        if (issueModel) {
            issueModel.tipoAtividade = String(details.tipoAtividade || "");
            issueModel.statusInicial = String(details.status || "");
            issueModel.valorEntregue = String(details.valorEntregue || "");
            issueModel.plataformasAfetadas = details.plataformasAfetadas || [];
            issueModel.documentacaoAnexa = String(details.documentacaoAnexa || "Não");
            issueModel.utilizacaoIA = String(details.utilizacaoIA || "Não");
            issueModel.registrarWorklog = false;
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

    // Mesma hierarquia que IssueFormPage: ScrollView > Item > ColumnLayout (margens no ColumnLayout)
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
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                spacing: 0

                ColumnLayout {
                    id: topSection
                    Layout.fillWidth: true
                    Layout.preferredHeight: pane.topSectionHeight
                    Layout.minimumHeight: 150
                    spacing: 0

                    RowLayout {
                        Layout.fillWidth: true
                        // Layout.margins: 20
                        // Layout.bottomMargin: 5

                        Kirigami.Heading {
                            text: qsTr("Atualizar Task")
                            level: 3
                            Layout.fillWidth: true
                        }

                        Controls.Label {
                            id: taskLinkLabel
                            text: pane.selectedIssueKey || ""
                            color: Kirigami.Theme.linkColor
                            visible: pane.selectedIssueKey !== ""
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (pane.jiraService && pane.selectedIssueKey && typeof pane.jiraService.getIssueUrl === 'function') {
                                        var url = pane.jiraService.getIssueUrl(pane.selectedIssueKey);
                                        if (url) {
                                            Qt.openUrlExternally(url);
                                        }
                                    }
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        // Layout.margins: 20
                        // Layout.topMargin: 0
                        // Layout.bottomMargin: 10
                        spacing: Kirigami.Units.smallSpacing

                        Controls.Label {
                            text: qsTr("Summary:")
                            font.bold: true
                            Layout.fillWidth: true
                        }

                        Controls.TextField {
                            id: summaryFieldTab2
                            Layout.fillWidth: true
                            enabled: pane.selectedIssueKey !== "" && !pane.isProcessing
                            text: pane.issueModel ? pane.issueModel.summary : ""
                            onTextChanged: if (pane.issueModel)
                                pane.issueModel.summary = text
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        // Layout.margins: 20
                        // Layout.topMargin: 0
                        spacing: Kirigami.Units.smallSpacing

                        Controls.Label {
                            text: qsTr("Description:")
                            font.bold: true
                            Layout.fillWidth: true
                        }

                        Controls.ScrollView {
                            id: descriptionScrollView
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true

                            Controls.TextArea {
                                id: descriptionFieldTab2
                                width: descriptionScrollView.availableWidth
                                wrapMode: Controls.TextArea.Wrap
                                enabled: pane.selectedIssueKey !== "" && !pane.isProcessing
                                text: pane.issueModel ? pane.issueModel.description : ""
                                onTextChanged: if (pane.issueModel)
                                    pane.issueModel.description = text
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
                    }

                    CommentsSection {
                        id: commentsSection
                        Layout.fillWidth: true
                        applicationWindow: pane.applicationWindow
                        jiraService: pane.jiraService
                        selectedIssueKey: pane.selectedIssueKey
                        onErrorOccurred: function (message) {
                            DialogHelpers.showError(pane, "../dialogs/ErrorDialog.qml", message)
                        }
                    }

                    Item {
                        Layout.fillHeight: true
                        Layout.fillWidth: true
                    }
                }
            }
        }
    }

    Item {
        id: resizeOverlay
        z: 10
        anchors.fill: parent
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
                }
            }
            onReleased: {
                resizeOverlay.activeDivider = 0;
            }
        }
    }

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
}
