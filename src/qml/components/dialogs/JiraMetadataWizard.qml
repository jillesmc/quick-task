/**
 * JiraMetadataWizard.qml
 *
 * Wizard de 3 etapas para configurar metadata do Jira (projetos, issue types, campos).
 * Issue #25 - carrega via Qt.createComponent a partir de SettingsPage.
 */
pragma ComponentBehavior: Bound
// qmllint disable unqualified
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Controls.Dialog {
    id: root

    parent: Controls.Overlay.overlay
    anchors.centerIn: parent

    modal: true
    closePolicy: Controls.Popup.CloseOnEscape
    standardButtons: Controls.Dialog.NoButton
    title: _stepTitle()

    property var jiraMetadataConfigModel: null
    property int currentStep: 0
    property var _projects: []
    property var _selectedProjects: []
    property var _issueTypes: []
    property var _selectedIssueTypes: []
    property var _fields: []
    property var _selectedFields: []
    property string _selectedProjectId: ""
    property string _selectedProjectKey: ""
    property string _selectedIssuetypeId: ""
    property string _selectedIssuetypeName: ""
    property string _errorMessage: ""
    property bool _loading: false
    property string _filterProjects: ""
    property string _filterIssueTypes: ""
    property string _filterFields: ""
    property int _currentProjectIndex: 0
    property var _issueTypesByProject: []
    property var _fieldConfigList: []
    property int _currentFieldConfigIndex: 0
    property var _fieldsByConfig: ({})
    property var _fieldsCache: ({})

    function _filteredProjects() {
        var q = (_filterProjects || "").trim().toLowerCase();
        if (!q) return _projects;
        var out = [];
        for (var i = 0; i < _projects.length; i++) {
            var p = _projects[i];
            var key = (p && (p.key || "")).toString().toLowerCase();
            var name = (p && (p.name || "")).toString().toLowerCase();
            if (key.indexOf(q) >= 0 || name.indexOf(q) >= 0) out.push(p);
        }
        return out;
    }
    function _filteredIssueTypes() {
        var q = (_filterIssueTypes || "").trim().toLowerCase();
        if (!q) return _issueTypes;
        var out = [];
        for (var i = 0; i < _issueTypes.length; i++) {
            var t = _issueTypes[i];
            var name = (t && (t.name || "")).toString().toLowerCase();
            if (name.indexOf(q) >= 0) out.push(t);
        }
        return out;
    }
    function _filteredFields() {
        var q = (_filterFields || "").trim().toLowerCase();
        if (!q) return _fields;
        var out = [];
        for (var i = 0; i < _fields.length; i++) {
            var f = _fields[i];
            var key = (f && (f.key || "")).toString().toLowerCase();
            var name = (f && (f.name || "")).toString().toLowerCase();
            if (key.indexOf(q) >= 0 || name.indexOf(q) >= 0) out.push(f);
        }
        return out;
    }

    function _stepTitle() {
        if (currentStep === 0) return qsTr("Etapa 1: Projetos");
        if (currentStep === 1) {
            var p = _selectedProjects[_currentProjectIndex];
            var projName = (p && (p.key || "") + (p && p.name ? " – " + p.name : "")) || "-";
            return qsTr("Etapa 2: Tipos de issue (%1)").arg(projName);
        }
        if (currentStep === 2 && _fieldConfigList.length > 0) {
            var c = _fieldConfigList[_currentFieldConfigIndex];
            var combo = (c && (c.projectKey || "") + " – " + (c && c.issuetypeName ? c.issuetypeName : c.issuetypeId || "")) || "-";
            return qsTr("Etapa 3: Campos (%1)").arg(combo);
        }
        return qsTr("Etapa 3: Campos");
    }

    onOpened: {
        _errorMessage = "";
        if (currentStep === 0 && jiraMetadataConfigModel && _projects.length === 0)
            _discoverProjects();
    }

    function _discoverProjects() {
        if (!jiraMetadataConfigModel) return;
        _loading = true;
        _errorMessage = "";
        jiraMetadataConfigModel.discoverProjects();
    }

    function _discoverIssueTypes() {
        if (!jiraMetadataConfigModel || !_selectedProjectId) return;
        _loading = true;
        _errorMessage = "";
        jiraMetadataConfigModel.discoverIssueTypes(_selectedProjectId);
    }

    function _discoverFields() {
        if (!jiraMetadataConfigModel || !_selectedProjectKey || !_selectedIssuetypeId) return;
        _loading = true;
        _errorMessage = "";
        jiraMetadataConfigModel.discoverFields(_selectedProjectKey, _selectedIssuetypeId);
    }

    function _configKey(projectKey, issuetypeId) {
        return (projectKey || "") + "_" + (issuetypeId || "");
    }

    function _buildSavePayload() {
        var payload = {
            "version": "2.0",
            "jira_instance": "",
            "selected_projects": [],
            "selected_issue_types": {},
            "selected_fields": {}
        };
        for (var i = 0; i < _selectedProjects.length; i++) {
            var p = _selectedProjects[i];
            payload.selected_projects.push({ "id": p.id, "key": p.key, "name": p.name, "enabled": true });
        }
        for (var i = 0; i < _issueTypesByProject.length; i++) {
            var entry = _issueTypesByProject[i];
            var pk = entry && entry.projectKey;
            if (!pk) continue;
            payload.selected_issue_types[pk] = [];
            var types = entry.selectedIssueTypes || [];
            for (var j = 0; j < types.length; j++) {
                var t = types[j];
                payload.selected_issue_types[pk].push({ "id": t.id, "name": t.name, "enabled": true });
            }
        }
        for (var idx = 0; idx < _fieldConfigList.length; idx++) {
            var c = _fieldConfigList[idx];
            if (!c || !c.projectKey || !c.issuetypeId) continue;
            var key = _configKey(c.projectKey, c.issuetypeId);
            var fields = _fieldsByConfig[key];
            if (!fields) continue;
            if (!payload.selected_fields[c.projectKey])
                payload.selected_fields[c.projectKey] = {};
            payload.selected_fields[c.projectKey][c.issuetypeId] = [];
            for (var k = 0; k < fields.length; k++) {
                var f = fields[k];
                var o = { "id": f.id, "key": f.key, "name": f.name, "enabled": true };
                if (f.field_type) o.field_type = f.field_type;
                if (f.required !== undefined) o.required = f.required;
                payload.selected_fields[c.projectKey][c.issuetypeId].push(o);
            }
        }
        return payload;
    }

    Connections {
        target: root.jiraMetadataConfigModel
        enabled: !!root.jiraMetadataConfigModel

        function onProjectsLoaded(list) {
            root._loading = false;
            root._projects = list || [];
        }
        function onIssueTypesLoaded(list) {
            root._loading = false;
            root._issueTypes = list || [];
        }
        function onFieldsLoaded(list) {
            root._loading = false;
            root._fields = list || [];
            var k = root._configKey(root._selectedProjectKey, root._selectedIssuetypeId);
            if (k && k !== "_") {
                var cache = root._fieldsCache;
                var copy = {};
                for (var key in cache) copy[key] = cache[key];
                copy[k] = list || [];
                root._fieldsCache = copy;
            }
        }
        function onDiscoveryError(message) {
            root._loading = false;
            root._errorMessage = message || "";
        }
        function onSaveFinished(ok) {
            if (ok) root.close();
        }
    }

    contentItem: Item {
        implicitWidth: 520
        implicitHeight: mainColumn.implicitHeight
        clip: true

        ColumnLayout {
            id: mainColumn
            anchors.fill: parent
            spacing: Kirigami.Units.largeSpacing

            StackLayout {
                id: stepStack
                Layout.fillWidth: true
                Layout.preferredHeight: 450
                currentIndex: root.currentStep

            // Etapa 1: Projetos
            ColumnLayout {
                id: step1
                spacing: Kirigami.Units.smallSpacing

                Controls.Button {
                    text: qsTr("Descobrir projetos")
                    Layout.fillWidth: true
                    enabled: !root._loading && !!root.jiraMetadataConfigModel
                    onClicked: root._discoverProjects()
                }
                Controls.BusyIndicator {
                    Layout.alignment: Qt.AlignHCenter
                    running: root._loading && root.currentStep === 0
                    visible: running
                }
                Controls.TextField {
                    placeholderText: qsTr("Filtrar...")
                    text: root._filterProjects
                    onTextEdited: root._filterProjects = text
                    Layout.fillWidth: true
                    visible: root._projects.length > 0
                }
                Controls.ScrollView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 350
                    clip: true
                    visible: root._projects.length > 0
                    ListView {
                        model: root._filteredProjects()
                        delegate: Controls.CheckDelegate {
                            required property var modelData
                            width: ListView.view ? (ListView.view.width - Kirigami.Units.largeSpacing * 2) : 0
                            text: (modelData && (modelData.key || modelData.name))
                                ? ((modelData.key || "") + (modelData.name ? " – " + modelData.name : "") || modelData.key || modelData.name || qsTr("(sem nome)"))
                                : qsTr("(sem nome)")
                            checked: root._selectedProjects.some(function(p) { return p.id === modelData.id; })
                            onToggled: {
                                if (checked) {
                                    if (!root._selectedProjects.some(function(p) { return p.id === modelData.id; }))
                                        root._selectedProjects.push(modelData);
                                } else {
                                    root._selectedProjects = root._selectedProjects.filter(function(p) { return p.id !== modelData.id; });
                                }
                                root._selectedProjects = root._selectedProjects.slice();
                            }
                        }
                    }
                }
            }

            // Etapa 2: Issue types
            ColumnLayout {
                id: step2
                spacing: Kirigami.Units.smallSpacing

                Controls.Label {
                    property var _p: root._selectedProjects[root._currentProjectIndex]
                    text: qsTr("Projeto: %1").arg(_p ? ((_p.key || "") + (_p.name ? " – " + _p.name : "")) || _p.key : "-")
                    Layout.fillWidth: true
                }
                Controls.Button {
                    text: qsTr("Descobrir tipos de issue")
                    Layout.fillWidth: true
                    enabled: !root._loading && root._selectedProjectId && !!root.jiraMetadataConfigModel
                    onClicked: root._discoverIssueTypes()
                }
                Controls.BusyIndicator {
                    Layout.alignment: Qt.AlignHCenter
                    running: root._loading && root.currentStep === 1
                    visible: running
                }
                Controls.TextField {
                    placeholderText: qsTr("Filtrar...")
                    text: root._filterIssueTypes
                    onTextEdited: root._filterIssueTypes = text
                    Layout.fillWidth: true
                    visible: root._issueTypes.length > 0
                }
                Controls.ScrollView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 350
                    clip: true
                    visible: root._issueTypes.length > 0
                    ListView {
                        model: root._filteredIssueTypes()
                        delegate: Controls.CheckDelegate {
                            required property var modelData
                            width: ListView.view ? (ListView.view.width - Kirigami.Units.largeSpacing * 2) : 0
                            text: modelData ? (modelData.name || "") : ""
                            checked: root._selectedIssueTypes.some(function(t) { return t.id === modelData.id; })
                            onToggled: {
                                if (checked) {
                                    if (!root._selectedIssueTypes.some(function(t) { return t.id === modelData.id; }))
                                        root._selectedIssueTypes.push(modelData);
                                } else {
                                    root._selectedIssueTypes = root._selectedIssueTypes.filter(function(t) { return t.id !== modelData.id; });
                                }
                                root._selectedIssueTypes = root._selectedIssueTypes.slice();
                            }
                        }
                    }
                }
            }

            // Etapa 3: Campos
            ColumnLayout {
                id: step3
                spacing: Kirigami.Units.smallSpacing

                Controls.Label {
                    property var _c: root._fieldConfigList.length > 0 && root._currentFieldConfigIndex < root._fieldConfigList.length ? root._fieldConfigList[root._currentFieldConfigIndex] : null
                    text: _c ? qsTr("Projeto: %1  |  Tipo: %2").arg(_c.projectKey || "-").arg(_c.issuetypeName || _c.issuetypeId || "-") : qsTr("Projeto: %1  |  Tipo: %2").arg(root._selectedProjectKey || "-").arg(root._selectedIssuetypeName || root._selectedIssuetypeId || "-")
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
                Controls.Button {
                    text: qsTr("Descobrir campos")
                    Layout.fillWidth: true
                    enabled: !root._loading && root._selectedProjectKey && root._selectedIssuetypeId && !!root.jiraMetadataConfigModel
                    onClicked: root._discoverFields()
                }
                Controls.BusyIndicator {
                    Layout.alignment: Qt.AlignHCenter
                    running: root._loading && root.currentStep === 2
                    visible: running
                }
                Controls.TextField {
                    placeholderText: qsTr("Filtrar...")
                    text: root._filterFields
                    onTextEdited: root._filterFields = text
                    Layout.fillWidth: true
                    visible: root._fields.length > 0
                }
                Controls.ScrollView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 350
                    clip: true
                    visible: root._fields.length > 0
                    ListView {
                        model: root._filteredFields()
                        delegate: Controls.CheckDelegate {
                            required property var modelData
                            width: ListView.view ? (ListView.view.width - Kirigami.Units.largeSpacing * 2) : 0
                            text: modelData ? ((modelData.name || modelData.key || "") + (modelData.required ? " *" : "")) : ""
                            checked: root._selectedFields.some(function(f) { return f.id === modelData.id; })
                            onToggled: {
                                if (checked) {
                                    if (!root._selectedFields.some(function(f) { return f.id === modelData.id; }))
                                        root._selectedFields.push(modelData);
                                } else {
                                    root._selectedFields = root._selectedFields.filter(function(f) { return f.id !== modelData.id; });
                                }
                                root._selectedFields = root._selectedFields.slice();
                            }
                        }
                    }
                }
            }
        }

        Item { id: stepContent; implicitWidth: 1; implicitHeight: 1 }

        Controls.Label {
            text: root._errorMessage
            color: Kirigami.Theme.negativeTextColor
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            visible: root._errorMessage.length > 0
        }

        RowLayout {
            id: footerRow
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Item { Layout.fillWidth: true }
            Controls.Button {
                text: qsTr("Voltar")
                visible: root.currentStep > 0
                onClicked: {
                    if (root.currentStep === 2) {
                        if (root._currentFieldConfigIndex > 0) {
                            root._currentFieldConfigIndex--;
                            var c = root._fieldConfigList[root._currentFieldConfigIndex];
                            root._selectedProjectKey = c.projectKey;
                            root._selectedProjectId = c.projectId || "";
                            root._selectedIssuetypeId = c.issuetypeId;
                            root._selectedIssuetypeName = c.issuetypeName || "";
                            var key = root._configKey(c.projectKey, c.issuetypeId);
                            root._fields = root._fieldsCache[key] || [];
                            root._selectedFields = (root._fieldsByConfig[key] || []).slice();
                        } else {
                            root.currentStep = 1;
                            root._currentProjectIndex = root._selectedProjects.length - 1;
                            var p = root._selectedProjects[root._currentProjectIndex];
                            root._selectedProjectId = p ? p.id : "";
                            root._selectedProjectKey = p ? p.key : "";
                            var lastEntry = root._issueTypesByProject[root._issueTypesByProject.length - 1];
                            root._selectedIssueTypes = (lastEntry && lastEntry.selectedIssueTypes) ? lastEntry.selectedIssueTypes.slice() : [];
                            root._issueTypes = [];
                            root._discoverIssueTypes();
                        }
                    } else if (root.currentStep === 1) {
                        if (root._currentProjectIndex > 0) {
                            root._currentProjectIndex--;
                            var p2 = root._selectedProjects[root._currentProjectIndex];
                            root._selectedProjectId = p2 ? p2.id : "";
                            root._selectedProjectKey = p2 ? p2.key : "";
                            root._selectedIssueTypes = (root._issueTypesByProject[root._currentProjectIndex] && root._issueTypesByProject[root._currentProjectIndex].selectedIssueTypes) ? root._issueTypesByProject[root._currentProjectIndex].selectedIssueTypes.slice() : [];
                            root._issueTypes = [];
                            root._discoverIssueTypes();
                        } else {
                            root.currentStep = 0;
                        }
                    }
                }
            }
            Controls.Button {
                text: (root.currentStep === 2 && root._fieldConfigList.length > 0 && root._currentFieldConfigIndex + 1 < root._fieldConfigList.length) ? qsTr("Próximo") : (root.currentStep === 2 ? qsTr("Salvar configuração") : qsTr("Próximo"))
                enabled: (root.currentStep === 0 && root._selectedProjects.length > 0) ||
                         (root.currentStep === 1 && root._selectedIssueTypes.length > 0) ||
                         (root.currentStep === 2 && root._selectedFields.length > 0)
                onClicked: {
                    if (root.currentStep === 0) {
                        if (root._selectedProjects.length > 0) {
                            root._currentProjectIndex = 0;
                            root._issueTypesByProject = [];
                            var p0 = root._selectedProjects[0];
                            root._selectedProjectId = p0.id;
                            root._selectedProjectKey = p0.key;
                            root._issueTypes = [];
                            root._selectedIssueTypes = [];
                            root._discoverIssueTypes();
                            root.currentStep = 1;
                        }
                    } else if (root.currentStep === 1) {
                        if (root._selectedIssueTypes.length > 0) {
                            var entry = {
                                projectKey: root._selectedProjectKey,
                                projectId: root._selectedProjectId,
                                projectName: (root._selectedProjects[root._currentProjectIndex] && root._selectedProjects[root._currentProjectIndex].name) || "",
                                selectedIssueTypes: root._selectedIssueTypes.slice()
                            };
                            root._issueTypesByProject = root._issueTypesByProject.concat([entry]);
                            if (root._currentProjectIndex + 1 < root._selectedProjects.length) {
                                root._currentProjectIndex++;
                                var pn = root._selectedProjects[root._currentProjectIndex];
                                root._selectedProjectId = pn.id;
                                root._selectedProjectKey = pn.key;
                                root._selectedIssueTypes = [];
                                root._discoverIssueTypes();
                            } else {
                                var list = [];
                                for (var i = 0; i < root._issueTypesByProject.length; i++) {
                                    var e = root._issueTypesByProject[i];
                                    var types = e.selectedIssueTypes || [];
                                    for (var j = 0; j < types.length; j++) {
                                        list.push({
                                            projectKey: e.projectKey,
                                            projectId: e.projectId,
                                            issuetypeId: types[j].id,
                                            issuetypeName: types[j].name || ""
                                        });
                                    }
                                }
                                root._fieldConfigList = list;
                                root._currentFieldConfigIndex = 0;
                                root._fieldsByConfig = {};
                                if (list.length > 0) {
                                    var c0 = list[0];
                                    root._selectedProjectKey = c0.projectKey;
                                    root._selectedProjectId = c0.projectId || "";
                                    root._selectedIssuetypeId = c0.issuetypeId;
                                    root._selectedIssuetypeName = c0.issuetypeName || "";
                                    var k0 = root._configKey(c0.projectKey, c0.issuetypeId);
                                    if (root._fieldsCache[k0]) {
                                        root._fields = root._fieldsCache[k0];
                                        root._selectedFields = (root._fieldsByConfig[k0] || []).slice();
                                    } else {
                                        root._fields = [];
                                        root._selectedFields = [];
                                        root._discoverFields();
                                    }
                                }
                                root.currentStep = 2;
                            }
                        }
                    } else {
                        if (root._fieldConfigList.length > 0) {
                            var keySave = root._configKey(root._selectedProjectKey, root._selectedIssuetypeId);
                            var byConfig = root._fieldsByConfig;
                            var nextConfig = {};
                            for (var k in byConfig) nextConfig[k] = byConfig[k];
                            nextConfig[keySave] = root._selectedFields.slice();
                            root._fieldsByConfig = nextConfig;
                            if (root._currentFieldConfigIndex + 1 < root._fieldConfigList.length) {
                                root._currentFieldConfigIndex++;
                                var cn = root._fieldConfigList[root._currentFieldConfigIndex];
                                root._selectedProjectKey = cn.projectKey;
                                root._selectedProjectId = cn.projectId || "";
                                root._selectedIssuetypeId = cn.issuetypeId;
                                root._selectedIssuetypeName = cn.issuetypeName || "";
                                var kn = root._configKey(cn.projectKey, cn.issuetypeId);
                                if (root._fieldsCache[kn]) {
                                    root._fields = root._fieldsCache[kn];
                                    root._selectedFields = (root._fieldsByConfig[kn] || []).slice();
                                } else {
                                    root._fields = [];
                                    root._selectedFields = [];
                                    root._discoverFields();
                                }
                            } else {
                                if (root.jiraMetadataConfigModel) {
                                    var payload = root._buildSavePayload();
                                    root.jiraMetadataConfigModel.saveConfiguration(payload);
                                }
                            }
                        } else if (root.jiraMetadataConfigModel) {
                            var payloadLegacy = root._buildSavePayload();
                            root.jiraMetadataConfigModel.saveConfiguration(payloadLegacy);
                        }
                    }
                }
            }
        }
        }
    }
}
