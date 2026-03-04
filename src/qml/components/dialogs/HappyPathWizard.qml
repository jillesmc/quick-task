/**
 * HappyPathWizard.qml
 *
 * Dialog em estilo wizard para definir o caminho feliz (sequência de status até Done)
 * por par projeto/tipo de issue. Usa workflow_metadata já salvo em jira_metadata.json.
 * Persiste happy_path como nó de topo separado.
 */
pragma ComponentBehavior: Bound
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
    property int _pairIndex: 0
    property var _pairsList: []
    property var _happyPathByConfig: ({})
    property string _errorMessage: ""
    property bool _loading: false
    property bool _saving: false

    function _configKey(projectKey, issuetypeId) {
        return (projectKey || "") + "_" + (issuetypeId || "");
    }

    function _stepTitle() {
        if (_pairsList.length === 0)
            return qsTr("Caminho feliz");
        var p = _pairsList[_pairIndex];
        var label = p ? ((p.projectKey || "") + " – " + (p.issuetypeName || p.issuetypeId || "")) : "-";
        return qsTr("Caminho feliz: %1").arg(label);
    }

    function _canTransitionFromTo(workflowEntry, fromStatusId, toStatusId) {
        if (!workflowEntry || !toStatusId)
            return false;
        var transitions = workflowEntry.transitions || [];
        for (var i = 0; i < transitions.length; i++) {
            var t = transitions[i];
            var toObj = t.to;
            var toId = (toObj && (toObj.id !== undefined && toObj.id !== null)) ? String(toObj.id) : "";
            if (toId !== String(toStatusId))
                continue;
            var typ = (t.type || "").toLowerCase();
            if (typ === "global")
                return true;
            if (typ === "initial" && !fromStatusId)
                return true;
            var fromIds = t.from;
            if (fromIds && typeof fromIds.length === "number") {
                for (var fi = 0; fi < fromIds.length; fi++) {
                    if (String(fromIds[fi]) === String(fromStatusId))
                        return true;
                }
                if (fromIds.length === 0 && !fromStatusId)
                    return true;
            }
        }
        return false;
    }

    function _reachableStatusIds(workflowEntry, fromStatusId) {
        if (!workflowEntry)
            return [];
        var transitions = workflowEntry.transitions || [];
        var out = [];
        var seen = {};
        for (var i = 0; i < transitions.length; i++) {
            var t = transitions[i];
            var toObj = t.to;
            var toId = toObj && (toObj.id !== undefined && toObj.id !== null) ? String(toObj.id) : "";
            if (!toId || seen[toId])
                continue;
            var typ = (t.type || "").toLowerCase();
            if (typ === "global") {
                out.push(toId);
                seen[toId] = true;
                continue;
            }
            if (typ === "initial") {
                if (!fromStatusId) {
                    out.push(toId);
                    seen[toId] = true;
                }
                continue;
            }
            var fromIds = t.from || [];
            if (fromIds && typeof fromIds.length === "number") {
                for (var fi = 0; fi < fromIds.length; fi++) {
                    if (String(fromIds[fi]) === String(fromStatusId)) {
                        out.push(toId);
                        seen[toId] = true;
                        break;
                    }
                }
            }
        }
        return out;
    }

    function _workflowEntryForCurrentPair() {
        if (!jiraMetadataConfigModel || _pairsList.length === 0 || _pairIndex < 0 || _pairIndex >= _pairsList.length)
            return null;
        var meta = jiraMetadataConfigModel.getLoadedMetadata();
        var wm = meta.workflow_metadata;
        if (!wm)
            return null;
        var p = _pairsList[_pairIndex];
        if (!p || !wm[p.projectKey])
            return null;
        return wm[p.projectKey][p.issuetypeId] || null;
    }

    function _currentSequence() {
        var p = _pairsList[_pairIndex];
        if (!p)
            return [];
        var key = _configKey(p.projectKey, p.issuetypeId);
        var arr = _happyPathByConfig[key];
        return Array.isArray(arr) ? arr.slice() : [];
    }

    function _currentSequenceNames() {
        var entry = _workflowEntryForCurrentPair();
        var statuses = (entry && entry.statuses) ? entry.statuses : [];
        var idToName = {};
        for (var i = 0; i < statuses.length; i++) {
            var s = statuses[i];
            if (s && s.id !== undefined)
                idToName[String(s.id)] = s.name || "";
        }
        var seq = _currentSequence();
        var names = [];
        for (var j = 0; j < seq.length; j++)
            names.push(idToName[String(seq[j])] || seq[j]);
        return names;
    }

    function _choicesForNextStatus() {
        var entry = _workflowEntryForCurrentPair();
        var seq = _currentSequence();
        var lastId = seq.length > 0 ? seq[seq.length - 1] : null;
        return _reachableStatusIds(entry, lastId);
    }

    function _statusListForChoiceIds(ids) {
        var entry = _workflowEntryForCurrentPair();
        var statuses = (entry && entry.statuses) ? entry.statuses : [];
        var out = [];
        for (var i = 0; i < ids.length; i++) {
            var id = ids[i];
            for (var j = 0; j < statuses.length; j++) {
                if (String(statuses[j].id) === String(id)) {
                    out.push({
                        id: statuses[j].id,
                        name: statuses[j].name || statuses[j].id
                    });
                    break;
                }
            }
        }
        return out;
    }

    function _addStatus(statusId) {
        var p = _pairsList[_pairIndex];
        if (!p)
            return;
        var key = _configKey(p.projectKey, p.issuetypeId);
        var entry = _workflowEntryForCurrentPair();
        var seq = _currentSequence();
        var lastId = seq.length > 0 ? seq[seq.length - 1] : null;
        if (!_canTransitionFromTo(entry, lastId, statusId)) {
            _errorMessage = qsTr("Não é possível transitar para este status a partir do estado atual.");
            return;
        }
        _errorMessage = "";
        var next = {};
        for (var k in _happyPathByConfig)
            next[k] = _happyPathByConfig[k];
        if (!next[key])
            next[key] = [];
        next[key] = next[key].concat([statusId]);
        _happyPathByConfig = next;
    }

    function _removeLastStatus() {
        var p = _pairsList[_pairIndex];
        if (!p)
            return;
        var key = _configKey(p.projectKey, p.issuetypeId);
        var arr = _happyPathByConfig[key];
        if (!Array.isArray(arr) || arr.length === 0)
            return;
        _errorMessage = "";
        var next = {};
        for (var k in _happyPathByConfig)
            next[k] = _happyPathByConfig[k];
        next[key] = arr.slice(0, arr.length - 1);
        _happyPathByConfig = next;
    }

    function _buildHappyPathPayload() {
        var out = {};
        for (var key in _happyPathByConfig) {
            var arr = _happyPathByConfig[key];
            if (!Array.isArray(arr) || arr.length === 0)
                continue;
            for (var i = 0; i < _pairsList.length; i++) {
                var p = _pairsList[i];
                if (_configKey(p.projectKey, p.issuetypeId) === key) {
                    if (!out[p.projectKey])
                        out[p.projectKey] = {};
                    out[p.projectKey][p.issuetypeId] = arr.slice();
                    break;
                }
            }
        }
        return out;
    }

    function _save() {
        if (!jiraMetadataConfigModel)
            return;
        _saving = true;
        _errorMessage = "";
        var data = jiraMetadataConfigModel.getLoadedMetadata();
        if (!data || typeof data !== "object")
            data = {};
        data.happy_path = _buildHappyPathPayload();
        jiraMetadataConfigModel.saveConfiguration(data);
    }

    onOpened: {
        _errorMessage = "";
        if (!jiraMetadataConfigModel) {
            _pairsList = [];
            return;
        }
        _loading = true;
        jiraMetadataConfigModel.loadConfiguration();
    }

    Connections {
        target: root.jiraMetadataConfigModel
        enabled: !!root.jiraMetadataConfigModel

        function onLoadFinished(success) {
            root._loading = false;
            if (!success) {
                root._pairsList = [];
                return;
            }
            // Listas vindas do Python (QVariantList) podem não ser Array em QML
            function hasNonEmptyList(val) {
                return val && typeof val.length === "number" && val.length > 0;
            }
            var meta = root.jiraMetadataConfigModel.getLoadedMetadata();
            var wm = meta.workflow_metadata;
            var hp = meta.happy_path;
            var pairs = [];
            if (wm && typeof wm === "object") {
                for (var pk in wm) {
                    var byType = wm[pk];
                    if (!byType || typeof byType !== "object")
                        continue;
                    for (var it in byType) {
                        var entry = byType[it];
                        var hasTrans = hasNonEmptyList(entry && entry.transitions);
                        var hasStatus = hasNonEmptyList(entry && entry.statuses);
                        if (hasTrans || hasStatus) {
                            var itName = "";
                            var selTypes = meta.selected_issue_types;
                            var typeList = selTypes && selTypes[pk];
                            if (hasNonEmptyList(typeList)) {
                                for (var ti = 0; ti < typeList.length; ti++) {
                                    var typeItem = typeList[ti];
                                    if (typeItem && String(typeItem.id) === String(it)) {
                                        itName = typeItem.name || "";
                                        break;
                                    }
                                }
                            }
                            if (!itName)
                                itName = it;
                            pairs.push({
                                projectKey: pk,
                                issuetypeId: it,
                                issuetypeName: itName
                            });
                        }
                    }
                }
            }
            root._pairsList = pairs;
            root._pairIndex = 0;
            var byConfig = {};
            if (hp && typeof hp === "object") {
                for (var pk2 in hp) {
                    var byIt = hp[pk2];
                    if (!byIt || typeof byIt !== "object")
                        continue;
                    for (var it2 in byIt) {
                        var arr = byIt[it2];
                        if (hasNonEmptyList(arr)) {
                            var copy = [];
                            for (var ci = 0; ci < arr.length; ci++)
                                copy.push(arr[ci]);
                            byConfig[root._configKey(pk2, it2)] = copy;
                        }
                    }
                }
            }
            root._happyPathByConfig = byConfig;
        }

        function onSaveFinished(ok) {
            root._saving = false;
            if (ok)
                root.close();
        }

        function onDiscoveryError(message) {
            root._saving = false;
            root._errorMessage = message || "";
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
                Layout.fillWidth: true
                Layout.preferredHeight: 450
                currentIndex: root._pairsList.length === 0 ? 1 : 0

                ColumnLayout {
                    id: stepContent
                    spacing: Kirigami.Units.smallSpacing

                    Controls.Label {
                        text: qsTr("Defina a sequência de status do caminho feliz. Escolha o próximo status na lista; a ordem será validada pelas transições do workflow.")
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    Controls.Label {
                        text: qsTr("Sequência atual:")
                        font.bold: true
                        Layout.fillWidth: true
                    }
                    Controls.Label {
                        text: root._currentSequenceNames().join(" → ") || qsTr("(vazia)")
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    Controls.Label {
                        text: qsTr("Próximo status:")
                        font.bold: true
                        Layout.fillWidth: true
                        visible: root._statusListForChoiceIds(root._choicesForNextStatus()).length > 0
                    }
                    Controls.ScrollView {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 180
                        clip: true
                        visible: root._statusListForChoiceIds(root._choicesForNextStatus()).length > 0
                        Controls.ScrollBar.vertical: Controls.ScrollBar {}
                        ListView {
                            model: root._statusListForChoiceIds(root._choicesForNextStatus())
                            delegate: Controls.Button {
                                required property var modelData
                                width: ListView.view ? ListView.view.width - Kirigami.Units.largeSpacing * 2 : 0
                                text: modelData.name || modelData.id
                                onClicked: root._addStatus(modelData.id)
                                Accessible.name: text
                                Accessible.description: qsTr("Adiciona este status ao fim do caminho feliz.")
                            }
                        }
                    }

                    Controls.Button {
                        text: qsTr("Remover último")
                        Layout.fillWidth: true
                        enabled: root._currentSequence().length > 0
                        onClicked: root._removeLastStatus()
                        Accessible.name: text
                        Accessible.description: qsTr("Remove o último status da sequência.")
                    }

                    Item {
                        Layout.fillHeight: true
                    }
                }

                ColumnLayout {
                    id: noPairsStep
                    spacing: Kirigami.Units.smallSpacing

                    Controls.Label {
                        text: qsTr("Nenhum par projeto/tipo com workflow disponível. Salve primeiro a configuração de projetos e campos com workflow preenchido.")
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    Item {
                        Layout.fillHeight: true
                    }
                }
            }

            Controls.Label {
                text: root._errorMessage
                color: Kirigami.Theme.negativeTextColor
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                visible: root._errorMessage.length > 0
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Item {
                    Layout.fillWidth: true
                }
                Controls.Button {
                    text: qsTr("Voltar")
                    visible: root._pairIndex > 0 && root._pairsList.length > 0
                    onClicked: {
                        root._errorMessage = "";
                        root._pairIndex--;
                    }
                }
                Controls.Button {
                    text: root._pairIndex < root._pairsList.length - 1 ? qsTr("Próximo") : qsTr("Salvar")
                    visible: root._pairsList.length > 0
                    onClicked: {
                        if (root._pairIndex < root._pairsList.length - 1) {
                            root._errorMessage = "";
                            root._pairIndex++;
                        } else {
                            root._save();
                        }
                    }
                }
                Controls.Button {
                    text: qsTr("Fechar")
                    visible: root._pairsList.length === 0
                    onClicked: root.close()
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            visible: root._loading || root._saving
            z: 1
            color: Kirigami.Theme.backgroundColor
            opacity: 0.92
            ColumnLayout {
                anchors.centerIn: parent
                spacing: Kirigami.Units.largeSpacing
                Controls.BusyIndicator {
                    Layout.alignment: Qt.AlignHCenter
                    running: root._loading || root._saving
                }
                Controls.Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: root._saving ? qsTr("Salvando…") : qsTr("Carregando…")
                    color: Kirigami.Theme.textColor
                }
            }
        }
    }
}
