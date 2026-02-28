/**
 * ParentWorkItemSearchForm.qml
 *
 * Formulário de busca e seleção de Parent Work Item (Epic ou outro tipo).
 * Usado apenas nas abas 7 e 8 (Criar Work Item / Minhas Work Items); não usa nomes nem dependências Jira.
 *
 * Propriedades:
 * - enabled: controla se o formulário está habilitado
 * - service: AtlassianService para buscar parents (obrigatório)
 * - metadataConfigModel: modelo de metadata (atlassianMetadataConfigModel) para opções de projeto
 * - selectedEpicKey: chave do parent selecionado
 * - selectedEpicSummary: resumo do parent selecionado
 *
 * Signals:
 * - epicSelected(string key, string summary): emitido quando um parent é selecionado
 * - epicSearchRequested(string query): emitido quando busca é solicitada
 * - epicCleared(): emitido quando seleção é limpa
 *
 * Métodos:
 * - reset(): limpa seleção e resultados (mas não busca)
 * - search(string query): executa busca
 * - selectEpic(string key, string summary): seleciona parent programaticamente
 * - clear(): limpa apenas seleção
 */
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami
import "../lists"

ColumnLayout {
    id: root

    property bool enabled: true
    property var service: null
    property var metadataConfigModel: null
    property string selectedEpicKey: ""
    property string selectedEpicSummary: ""
    property bool isSearching: false
    property string nextPageToken: ""
    property bool isLoadingMore: false
    property bool filterCreatedByMe: false
    property bool filterAssignedToMe: false
    property bool filterExcludeDone: true
    property var filterSelectedProjectKeys: []
    property var _availableProjects: []
    property var searchResults: epicList.model || []
    property alias epicListRef: epicList
    property alias searchFieldRef: searchField

    signal epicSelected(string key, string summary)
    signal epicSearchRequested(string query)
    signal epicCleared

    function _itemKey(it) {
        if (!it) return "";
        var k = it["key"] !== undefined ? it["key"] : it.key;
        return (k !== undefined && k !== null) ? String(k) : "";
    }
    function _itemNameOrKey(it) {
        if (!it) return "";
        var n = it["name"] !== undefined ? it["name"] : it.name;
        var k = it["key"] !== undefined ? it["key"] : it.key;
        if (n !== undefined && n !== null && String(n).length > 0) return String(n);
        if (k !== undefined && k !== null && String(k).length > 0) return String(k);
        return "";
    }

    spacing: Kirigami.Units.smallSpacing

    component ProjectFilterCheckBox : Controls.CheckBox {
        required property int index
        required property var formRoot
        readonly property var item: formRoot._availableProjects[index] || null
        Layout.fillWidth: true
        text: formRoot._itemNameOrKey(item)
        checked: formRoot.filterSelectedProjectKeys.indexOf(formRoot._itemKey(item)) >= 0
        enabled: formRoot.enabled
        onToggled: {
            var key = formRoot._itemKey(item);
            if (!key)
                return;
            var idx = formRoot.filterSelectedProjectKeys.indexOf(key);
            var next = formRoot.filterSelectedProjectKeys.slice();
            if (checked) {
                if (idx < 0)
                    next.push(key);
            } else {
                if (idx >= 0)
                    next.splice(idx, 1);
            }
            formRoot.filterSelectedProjectKeys = next;
            formRoot.saveFilters();
            if (formRoot.epicListRef && formRoot.epicListRef.model && formRoot.epicListRef.model.length > 0) {
                formRoot.epicListRef.model = [];
                var q = formRoot.searchFieldRef ? (formRoot.searchFieldRef.text ? formRoot.searchFieldRef.text.trim() : "") : "";
                formRoot.nextPageToken = "";
                formRoot.performSearch(q, false);
            }
        }
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 2
        columnSpacing: Kirigami.Units.largeSpacing
        rowSpacing: Kirigami.Units.smallSpacing

        Controls.CheckBox {
            id: filterCreatedByMeCheckbox
            text: qsTr("Criados por mim")
            checked: root.filterCreatedByMe
            enabled: root.enabled
            onToggled: {
                root.filterCreatedByMe = checked;
                root.saveFilters();
                if (epicList.model && epicList.model.length > 0) {
                    epicList.model = [];
                    var q = searchField.text ? searchField.text.trim() : "";
                    root.nextPageToken = "";
                    root.performSearch(q, false);
                }
            }
        }

        Controls.CheckBox {
            id: filterAssignedToMeCheckbox
            text: qsTr("Direcionados a mim")
            checked: root.filterAssignedToMe
            enabled: root.enabled
            onToggled: {
                root.filterAssignedToMe = checked;
                root.saveFilters();
                if (epicList.model && epicList.model.length > 0) {
                    epicList.model = [];
                    var q = searchField.text ? searchField.text.trim() : "";
                    root.nextPageToken = "";
                    root.performSearch(q, false);
                }
            }
        }

        Controls.Label {
            Layout.columnSpan: 2
            text: qsTr("Projetos:")
            font.bold: true
        }
        ColumnLayout {
            Layout.columnSpan: 2
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            visible: root._availableProjects.length > 0
            Repeater {
                model: root._availableProjects
                delegate: ProjectFilterCheckBox {
                    index: index
                    formRoot: root
                }
            }
        }
        Controls.Label {
            Layout.columnSpan: 2
            visible: root.metadataConfigModel && root._availableProjects.length === 0
            text: qsTr("Nenhum projeto configurado em Metadados")
            font.italic: true
        }

        Controls.CheckBox {
            id: filterExcludeDoneCheckbox
            text: qsTr("Excluir status category DONE")
            checked: root.filterExcludeDone
            enabled: root.enabled
            onToggled: {
                root.filterExcludeDone = checked;
                root.saveFilters();
                if (epicList.model && epicList.model.length > 0) {
                    epicList.model = [];
                    var q = searchField.text ? searchField.text.trim() : "";
                    root.nextPageToken = "";
                    root.performSearch(q, false);
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignLeft | Qt.AlignTop
        spacing: Kirigami.Units.mediumSpacing

        Controls.TextField {
            id: searchField
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignLeft | Qt.AlignTop
            placeholderText: qsTr("Buscar Parent Work Item por resumo ou chave...")
            enabled: root.enabled

            Keys.onReturnPressed: function (event) {
                event.accepted = true;
                if (root.enabled && root.service) {
                    root.search(searchField.text);
                }
            }

            Keys.onEnterPressed: function (event) {
                event.accepted = true;
                if (root.enabled && root.service) {
                    root.search(searchField.text);
                }
            }
        }

        Controls.Button {
            id: searchButton
            text: root.isSearching ? qsTr("Buscando...") : qsTr("Buscar")
            enabled: root.enabled && !root.isSearching
            onClicked: {
                if (!root.service || root.isSearching)
                    return;
                var q = searchField.text ? searchField.text.trim() : "";
                root.performSearch(q, false);
            }
        }
    }

    EpicList {
        id: epicList
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.alignment: Qt.AlignLeft | Qt.AlignTop
        enabled: root.enabled
        selectedEpicKey: root.selectedEpicKey
        isLoading: root.isSearching || root.isLoadingMore

        onEpicSelected: function (epicKey, epicData) {
            root.selectedEpicKey = epicKey;
            root.selectedEpicSummary = epicData ? epicData.summary || "" : "";
            root.epicSelected(epicKey, root.selectedEpicSummary);
        }

        onLoadMoreRequested: {
            if (root.nextPageToken && root.nextPageToken !== "" && !root.isSearching && !root.isLoadingMore && root.enabled) {
                root.isLoadingMore = true;
                var q = searchField.text ? searchField.text.trim() : "";
                root.performSearch(q, true);
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignLeft | Qt.AlignTop
        visible: root.selectedEpicKey !== ""

        Controls.Label {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignLeft | Qt.AlignTop
            text: root.selectedEpicKey ? qsTr("Parent Work Item selecionado: %1 - %2").arg(root.selectedEpicKey).arg(root.selectedEpicSummary) : ""
            elide: Text.ElideRight
        }

        Controls.Label {
            id: epicLinkLabel
            text: root.selectedEpicKey || ""
            color: Kirigami.Theme.linkColor
            visible: root.selectedEpicKey !== ""
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (root.service && root.selectedEpicKey && typeof root.service.getIssueUrl === 'function') {
                        var url = root.service.getIssueUrl(root.selectedEpicKey);
                        if (url) {
                            Qt.openUrlExternally(url);
                        }
                    }
                }
            }
        }

        Controls.Button {
            text: qsTr("Limpar")
            enabled: root.selectedEpicKey !== ""
            onClicked: {
                root.clear();
            }
        }
    }

    function performSearch(query, isPagination) {
        if (!root.service) {
            return;
        }
        if (!isPagination) {
            epicList.model = [];
            if (typeof epicList.clearVisualSelection === 'function') {
                epicList.clearVisualSelection();
            }
        }
        var nextToken = isPagination ? root.nextPageToken : "";
        var queryText = query ? query.trim() : "";
        root.service.searchEpicsAsync(queryText, root.filterCreatedByMe, root.filterAssignedToMe, false, root.filterExcludeDone, nextToken);
    }

    function search(query) {
        var q = query;
        if (!q || q.trim() === "") {
            q = searchField.text;
        }
        if (root.autoSelectKey === "") {
            root.selectedEpicKey = "";
            root.selectedEpicSummary = "";
        }
        epicList.model = [];
        root.nextPageToken = "";
        root.performSearch(q, false);
    }

    function clear() {
        selectedEpicKey = "";
        selectedEpicSummary = "";
        epicList.clearSelection();
        root.epicCleared();
    }

    function reset() {
        clear();
    }

    function selectEpic(key, summary) {
        if (!key) {
            clear();
            return;
        }
        epicList.selectEpic(key);
        var found = false;
        for (var i = 0; i < epicList.model.length; i++) {
            if (epicList.model[i] && epicList.model[i].key === key) {
                found = true;
                break;
            }
        }
        if (!found) {
            var epic = {
                key: key,
                summary: summary || ""
            };
            epicList.model = epicList.model.concat([epic]);
            epicList.selectEpic(key);
        }
        root.selectedEpicKey = key;
        root.selectedEpicSummary = summary || "";
    }

    function setSearchText(text) {
        searchField.text = text || "";
    }

    function clearFilters() {
        root.filterCreatedByMe = false;
        root.filterAssignedToMe = false;
        root.filterSelectedProjectKeys = [];
        root.filterExcludeDone = false;
    }

    function clearAll() {
        searchField.text = "";
        epicList.model = [];
        root.nextPageToken = "";
        clear();
    }

    function setDefaultFiltersForNoParent() {
        root.filterCreatedByMe = false;
        root.filterAssignedToMe = false;
        root.filterSelectedProjectKeys = [];
        root.filterExcludeDone = true;
    }

    function requestAutoSelect(key, summary) {
        autoSelectKey = key || "";
        autoSelectSummary = summary || "";
    }

    function loadFilters() {
        if (!root.service) {
            return;
        }
        var filters = root.service.getEpicFilters();
        if (filters) {
            root.filterCreatedByMe = filters.created_by_me || false;
            root.filterAssignedToMe = filters.assigned_to_me || false;
            root.filterExcludeDone = filters.exclude_done !== undefined ? filters.exclude_done : true;
            var keys = filters.selected_project_keys;
            root.filterSelectedProjectKeys = (keys && Array.isArray(keys)) ? keys.slice() : [];
        }
    }

    function saveFilters() {
        if (!root.service) {
            return;
        }
        root.service.setEpicFilters(root.filterCreatedByMe, root.filterAssignedToMe, false, root.filterExcludeDone);
        if (typeof root.service.setEpicFilterProjectKeys === "function") {
            root.service.setEpicFilterProjectKeys(root.filterSelectedProjectKeys || []);
        }
    }

    onServiceChanged: {
        if (root.service) {
            loadFilters();
        }
    }

    Component.onCompleted: {
        if (root.service) {
            loadFilters();
        }
        var hasModel = root.metadataConfigModel && typeof root.metadataConfigModel.loadConfiguration === "function";
        console.log("[ParentWorkItemSearchForm] onCompleted metadataConfigModel=" + !!root.metadataConfigModel + " loadConfiguration=" + hasModel);
        if (hasModel) {
            // Se o modelo já tiver metadata em memória (ex.: outra aba carregou), preencher já
            var listGetter = root.metadataConfigModel.getLoadedSelectedProjects;
            if (listGetter && typeof listGetter === "function") {
                var arr = root.metadataConfigModel.getLoadedSelectedProjects() || [];
                if (arr.length > 0) {
                    root._availableProjects = arr;
                    console.log("[ParentWorkItemSearchForm] onCompleted: using existing getLoadedSelectedProjects len=" + arr.length);
                }
            }
            root.metadataConfigModel.loadConfiguration();
        } else {
            console.log("[ParentWorkItemSearchForm] onCompleted: not calling loadConfiguration (model missing or no method)");
        }
    }

    Connections {
        target: root.metadataConfigModel
        function onLoadFinished(success) {
            console.log("[ParentWorkItemSearchForm] onLoadFinished success=" + success + " hasModel=" + !!root.metadataConfigModel + " getLoadedMetadata type=" + (root.metadataConfigModel ? typeof root.metadataConfigModel.getLoadedMetadata : "no model"));
            if (!success || !root.metadataConfigModel)
                return;
            try {
                var listGetter = root.metadataConfigModel.getLoadedSelectedProjects;
                var arr = (listGetter && typeof listGetter === "function") ? (root.metadataConfigModel.getLoadedSelectedProjects() || []) : [];
                root._availableProjects = arr;
                console.log("[ParentWorkItemSearchForm] onLoadFinished _availableProjects.length=" + (arr ? arr.length : 0));
            } catch (e) {
                console.log("[ParentWorkItemSearchForm] onLoadFinished error: " + (e && e.message ? e.message : String(e)));
            }
        }
    }

    Connections {
        target: root.service

        function onEpicSearchStarted() {
            root.isSearching = true;
            root.isLoadingMore = false;
        }

        function onEpicSearchCompleted(results, nextToken) {
            if (results === undefined || results === null) {
                epicList.model = [];
            } else {
                epicList.model = results;
            }
            root.nextPageToken = nextToken || "";
            root.isLoadingMore = false;

            if (root.autoSelectKey !== "" && epicList.model.length > 0) {
                for (var i = 0; i < epicList.model.length; i++) {
                    var item = epicList.model[i];
                    if (item && item.key === root.autoSelectKey) {
                        epicList.selectEpic(root.autoSelectKey);
                        root.selectedEpicKey = root.autoSelectKey;
                        root.selectedEpicSummary = root.autoSelectSummary || (item.summary || "");
                        root.epicSelected(root.autoSelectKey, root.selectedEpicSummary);
                        break;
                    }
                }
                root.autoSelectKey = "";
                root.autoSelectSummary = "";
            } else {
                Qt.callLater(function () {
                    if (epicList && typeof epicList.clearVisualSelection === 'function') {
                        epicList.clearVisualSelection();
                    }
                });
            }
            root.isSearching = false;
        }

        function onEpicSearchPageCompleted(results, nextToken) {
            if (results === undefined || results === null) {
                root.nextPageToken = "";
                root.isSearching = false;
                root.isLoadingMore = false;
                return;
            }
            if (epicList && typeof epicList.saveScrollPosition === 'function') {
                epicList.saveScrollPosition();
            }
            var currentModel = epicList.model || [];
            epicList.model = currentModel.concat(results);
            if (epicList && typeof epicList.restoreScrollPosition === 'function') {
                epicList.restoreScrollPosition();
            }
            root.nextPageToken = nextToken || "";
            root.isSearching = false;
            root.isLoadingMore = false;
        }
    }

    property string autoSelectKey: ""
    property string autoSelectSummary: ""
}
