/**
 * ParentWorkItemBlock.qml
 *
 * Bloco reutilizável: label "Parent Work Item:" + ParentWorkItemSearchForm + bindings ao workItemModel.
 * Usado em CreateWorkItemPage e no painel de detalhe de MyWorkItemsPage (abas 7 e 8).
 * Expõe getParentWorkItemKey() e setParentFromDetails(parentKey, parentSummary).
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami
import "../forms"

ColumnLayout {
    id: root

    property var model: null
    property var atlassianService: null
    property string parentIssueType: "Epic"
    property bool enabled: true
    property string mode: "create"
    property string sharedParentWorkItemKey: ""
    property string sharedParentWorkItemSummary: ""
    property real preferredHeight: 250
    property real minimumHeight: 150
    property var metadataConfigModel: null

    signal parentWorkItemSelected(string key, string summary)
    signal parentWorkItemCleared

    spacing: Kirigami.Units.smallSpacing
    Layout.fillWidth: true
    Layout.preferredHeight: root.preferredHeight
    Layout.minimumHeight: root.minimumHeight

    Controls.Label {
        text: qsTr("Parent Work Item:")
        font.bold: true
        Layout.fillWidth: true
    }

    ParentWorkItemSearchForm {
        id: epicSearchForm
        Layout.fillWidth: true
        Layout.fillHeight: true
        enabled: root.enabled
        service: root.atlassianService
        metadataConfigModel: root.metadataConfigModel

        Binding {
            target: root.model
            property: "parentWorkItemKey"
            value: epicSearchForm.selectedEpicKey
            when: root.model !== null
        }
        Binding {
            target: root.model
            property: "parentWorkItemSummary"
            value: epicSearchForm.selectedEpicSummary
            when: root.model !== null
        }
        Binding {
            target: epicSearchForm
            property: "selectedEpicKey"
            value: root.model ? root.model.parentWorkItemKey : ""
            when: root.model !== null
        }
        Binding {
            target: epicSearchForm
            property: "selectedEpicSummary"
            value: root.model ? root.model.parentWorkItemSummary : ""
            when: root.model !== null
        }

        // Modo edit: sincronizar shared -> form quando preenchido e diferente do form
        Binding {
            target: epicSearchForm
            property: "selectedEpicKey"
            value: root.sharedParentWorkItemKey
            when: root.mode === "edit" && root.sharedParentWorkItemKey !== "" && root.sharedParentWorkItemKey !== epicSearchForm.selectedEpicKey
        }
        Binding {
            target: epicSearchForm
            property: "selectedEpicSummary"
            value: root.sharedParentWorkItemSummary
            when: root.mode === "edit" && root.sharedParentWorkItemSummary !== "" && root.sharedParentWorkItemSummary !== epicSearchForm.selectedEpicSummary
        }

        onEpicSelected: function (key, summary) {
            if (root.model) {
                root.model.parentWorkItemKey = key;
                root.model.parentWorkItemSummary = summary;
            }
            root.parentWorkItemSelected(key, summary);
        }

        onEpicCleared: {
            if (root.model) {
                root.model.parentWorkItemKey = "";
                root.model.parentWorkItemSummary = "";
            }
            root.parentWorkItemCleared();
        }
    }

    Item {
        Layout.fillHeight: true
        Layout.fillWidth: true
    }

    function getParentWorkItemKey() {
        return root.model ? (root.model.parentWorkItemKey || "") : "";
    }

    function setParentFromDetails(parentKey, parentSummary) {
        if (!epicSearchForm) {
            return;
        }
        var key = (parentKey || "").toString().trim();
        var summary = (parentSummary || "").toString();
        epicSearchForm.clearFilters();
        epicSearchForm.clearAll();
        if (key === "") {
            if (typeof epicSearchForm.setDefaultFiltersForNoParent === "function") {
                epicSearchForm.setDefaultFiltersForNoParent();
            }
            epicSearchForm.clearAll();
            return;
        }
        epicSearchForm.setSearchText(key);
        if (!root.atlassianService || typeof root.atlassianService.fetchParentByKey !== "function") {
            epicSearchForm.requestAutoSelect(key, summary);
            epicSearchForm.search(key);
            return;
        }
        var result = root.atlassianService.fetchParentByKey(key, root.parentIssueType);
        if (result && result.key) {
            epicSearchForm.selectEpic(result.key, result.summary || summary);
        } else {
            epicSearchForm.requestAutoSelect(key, summary);
            epicSearchForm.search(key);
        }
    }

    function clearParent() {
        if (epicSearchForm && typeof epicSearchForm.reset === "function") {
            epicSearchForm.reset();
        }
        if (root.model) {
            root.model.parentWorkItemKey = "";
            root.model.parentWorkItemSummary = "";
        }
    }
}
