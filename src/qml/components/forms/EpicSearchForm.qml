/**
 * EpicSearchForm.qml
 *
 * Componente reutilizável para busca e seleção de Epic
 * Segue Single Responsibility Principle - apenas gerencia busca e seleção de Epic
 * Segue Open/Closed Principle - pode ser estendido sem modificar
 *
 * Propriedades:
 * - enabled: controla se o formulário está habilitado
 * - jiraService: serviço Jira para buscar Epics (obrigatório)
 * - selectedEpicKey: chave do Epic selecionado
 * - selectedEpicSummary: resumo do Epic selecionado
 *
 * Signals:
 * - epicSelected(string key, string summary): emitido quando um Epic é selecionado
 * - epicSearchRequested(string query): emitido quando busca é solicitada
 * - epicCleared(): emitido quando Epic é limpo
 *
 * Métodos:
 * - reset(): limpa seleção e resultados (mas não busca)
 * - search(string query): executa busca de Epics
 * - selectEpic(string key, string summary): seleciona Epic programaticamente
 * - clear(): limpa apenas seleção
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami
import "../lists"

ColumnLayout {
    id: root

    property bool enabled: true
    property var jiraService: null
    property string selectedEpicKey: ""
    property string selectedEpicSummary: ""
    // Indica se uma busca está em andamento (usado para feedback visual)
    property bool isSearching: false
    // Token para próxima página (paginação)
    property string nextPageToken: ""
    // Flag para evitar múltiplas chamadas de paginação simultâneas
    property bool isLoadingMore: false
    // Filtros de busca (valores padrão, serão sobrescritos por loadFilters() se houver config)
    property bool filterCreatedByMe: false
    property bool filterAssignedToMe: false
    property bool filterProjectPlatform: true
    property bool filterExcludeDone: true  // Por padrão exclui DONE, será sobrescrito por loadFilters() se houver config
    // Propriedade para compatibilidade (retorna model da lista)
    property var searchResults: epicList.model || []

    signal epicSelected(string key, string summary)
    signal epicSearchRequested(string query)
    signal epicCleared

    spacing: Kirigami.Units.smallSpacing

    // Checkboxes de filtro (2 colunas)
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

        Controls.CheckBox {
            id: filterProjectPlatformCheckbox
            text: qsTr("Projeto de Plataforma (PLATFORM)")
            checked: root.filterProjectPlatform
            enabled: root.enabled
            onToggled: {
                root.filterProjectPlatform = checked;
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
            id: filterExcludeDoneCheckbox
            text: qsTr("Excluir épicos concluídos (DONE)")
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
            placeholderText: qsTr("Buscar Epic por resumo ou chave...")
            enabled: root.enabled

            // Acionar busca ao pressionar ENTER
            Keys.onReturnPressed: function (event) {
                event.accepted = true;
                if (root.enabled && root.jiraService) {
                    // Busca em branco é válida
                    root.search(searchField.text);
                }
            }

            Keys.onEnterPressed: function (event) {
                event.accepted = true;
                if (root.enabled && root.jiraService) {
                    root.search(searchField.text);
                }
            }
        }

        Controls.Button {
            id: searchButton
            text: root.isSearching ? qsTr("Buscando...") : qsTr("Buscar")
            // Sempre habilitado (busca em branco é válida)
            enabled: root.enabled && !root.isSearching
            onClicked: {
                if (!root.jiraService || root.isSearching)
                    return;
                var q = searchField.text ? searchField.text.trim() : "";
                // Busca em branco é válida - traz tudo ou baseado nos filtros
                root.performSearch(q, false);
            }
        }
    }

    // ListView de resultados
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
            // Carregar próxima página quando scroll chegar no fim
            // Verificar se há token e se não está já carregando
            if (root.nextPageToken && root.nextPageToken !== "" && !root.isSearching && !root.isLoadingMore && root.enabled) {
                root.isLoadingMore = true;
                var q = searchField.text ? searchField.text.trim() : "";
                // Usar o nextPageToken atual para paginação
                root.performSearch(q, true);  // true = paginação
            }
        }
    }

    // Exibir Epic selecionada e botão para limpar
    RowLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignLeft | Qt.AlignTop
        visible: root.selectedEpicKey !== ""

        Controls.Label {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignLeft | Qt.AlignTop
            text: root.selectedEpicKey ? qsTr("Epic selecionada: %1 - %2").arg(root.selectedEpicKey).arg(root.selectedEpicSummary) : ""
            elide: Text.ElideRight
        }

        // Link clicável para abrir epic no browser
        Controls.Label {
            id: epicLinkLabel
            text: root.selectedEpicKey || ""
            color: Kirigami.Theme.linkColor
            visible: root.selectedEpicKey !== ""
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (root.jiraService && root.selectedEpicKey && typeof root.jiraService.getIssueUrl === 'function') {
                        var url = root.jiraService.getIssueUrl(root.selectedEpicKey);
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

    /**
     * Executa busca de Epics com filtros
     * @param {string} query - Query de busca (pode ser vazio - busca em branco é válida)
     * @param {bool} isPagination - Se true, adiciona resultados à lista existente
     */
    function performSearch(query, isPagination) {
        if (!jiraService) {
            return;
        }

        // Se não for paginação, limpar resultados anteriores e seleção visual
        if (!isPagination) {
            epicList.model = [];
            // Garantir que nenhum item fique visualmente selecionado após limpar modelo
            if (typeof epicList.clearVisualSelection === 'function') {
                epicList.clearVisualSelection();
            }
        }

        // Busca em branco é válida - traz tudo ou baseado nos filtros
        var nextToken = isPagination ? root.nextPageToken : "";
        var queryText = query ? query.trim() : "";
        jiraService.searchEpicsAsync(queryText, root.filterCreatedByMe, root.filterAssignedToMe, root.filterProjectPlatform, root.filterExcludeDone, nextToken);
    }

    /**
     * Executa busca de Epics (wrapper para compatibilidade)
     * @param {string} query - Query de busca (opcional)
     */
    function search(query) {
        var q = query;
        if (!q || q.trim() === "") {
            q = searchField.text;
        }
        // Limpar seleção antes de nova busca (exceto se for autoSelect)
        if (root.autoSelectKey === "") {
            root.selectedEpicKey = "";
            root.selectedEpicSummary = "";
        }
        // Limpar resultados anteriores antes de nova busca
        epicList.model = [];
        // Resetar paginação para nova busca
        root.nextPageToken = "";
        root.performSearch(q, false);
    }

    /**
     * Limpa apenas seleção (não limpa busca)
     */
    function clear() {
        // Limpar propriedades do EpicSearchForm primeiro
        selectedEpicKey = "";
        selectedEpicSummary = "";
        // Depois limpar seleção no EpicList (isso também limpa currentIndex)
        epicList.clearSelection();
        // Emitir signal de limpeza (isso vai limpar sharedEpicKey nas páginas)
        root.epicCleared();
    }

    /**
     * Reseta formulário (limpa seleção, mas não busca)
     */
    function reset() {
        clear();
        // Não limpar searchField.text nem searchResults
        // A busca permanece visível
    }

    /**
     * Seleciona Epic programaticamente
     * @param {string} key - Chave do Epic
     * @param {string} summary - Resumo do Epic
     */
    function selectEpic(key, summary) {
        if (!key) {
            clear();
            return;
        }

        // Buscar epic na lista atual
        epicList.selectEpic(key);

        // Se não estiver na lista, adicionar e selecionar
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

    /**
     * Preenche campo de busca com texto (útil para pré-seleção)
     * @param {string} text - Texto para preencher
     */
    function setSearchText(text) {
        searchField.text = text || "";
    }

    /**
     * Limpa os checkboxes de filtro (todos desmarcados)
     * Não aciona busca automática - apenas reseta os valores
     * Os checkboxes vão atualizar visualmente via binding checked: root.filterX
     * Não salva as configurações - o usuário pode modificar depois se quiser
     */
    function clearFilters() {
        root.filterCreatedByMe = false;
        root.filterAssignedToMe = false;
        root.filterProjectPlatform = false;  // Todos limpos quando issue tem parent
        root.filterExcludeDone = false;  // Todos limpos quando issue tem parent
        // Nota: Mudar as propriedades programaticamente não aciona onToggled dos checkboxes
        // então não vai disparar busca automática nem salvar configurações
    }

    /**
     * Limpa completamente o formulário: campo de busca, listview e seleção
     */
    function clearAll() {
        searchField.text = "";
        epicList.model = [];
        root.nextPageToken = "";
        clear();  // Limpa seleção
    }

    /**
     * Configura checkboxes padrão para aba 2 quando não há parent
     */
    function setDefaultFiltersForNoParent() {
        root.filterCreatedByMe = false;
        root.filterAssignedToMe = false;
        root.filterProjectPlatform = true;
        root.filterExcludeDone = true;
    }

    /**
     * Agenda uma seleção automática após a próxima busca de Epics.
     * Usado principalmente na aba 2 para pré-selecionar o Epic parent
     * retornado pelo Jira.
     * @param {string} key - Chave do epic a selecionar
     * @param {string} summary - Resumo do epic
     */
    function requestAutoSelect(key, summary) {
        autoSelectKey = key || "";
        autoSelectSummary = summary || "";
    }

    /**
     * Carrega filtros salvos do config
     */
    function loadFilters() {
        if (!jiraService) {
            return;
        }

        var filters = jiraService.getEpicFilters();
        if (filters) {
            root.filterCreatedByMe = filters.created_by_me || false;
            root.filterAssignedToMe = filters.assigned_to_me || false;
            root.filterProjectPlatform = filters.project_platform !== undefined ? filters.project_platform : true;
            root.filterExcludeDone = filters.exclude_done !== undefined ? filters.exclude_done : true;
        }
    }

    /**
     * Salva filtros no config
     */
    function saveFilters() {
        if (!jiraService) {
            return;
        }

        jiraService.setEpicFilters(root.filterCreatedByMe, root.filterAssignedToMe, root.filterProjectPlatform, root.filterExcludeDone);
    }

    // Carregar filtros quando jiraService estiver disponível
    onJiraServiceChanged: {
        if (jiraService) {
            loadFilters();
        }
    }

    // Carregar filtros ao inicializar (caso jiraService já esteja definido)
    Component.onCompleted: {
        if (jiraService) {
            loadFilters();
        }
    }

    // Conexões com JiraService para controlar estado visual e resultados
    Connections {
        target: root.jiraService

        function onEpicSearchStarted() {
            root.isSearching = true;
            // Resetar flag de paginação quando nova busca começar
            root.isLoadingMore = false;
        }

        function onEpicSearchCompleted(results, nextToken) {
            // results chega como QVariant; garantir array
            if (results === undefined || results === null) {
                epicList.model = [];
            } else {
                epicList.model = results;
            }

            // Atualizar nextPageToken da primeira página
            root.nextPageToken = nextToken || "";
            root.isLoadingMore = false;

            // Selecionar epic se houver autoSelectKey (apenas quando há parent na aba 2)
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
                // Se não há autoSelectKey, garantir que nenhum item fique visualmente selecionado
                // Limpar currentIndex do ListView para não mostrar highlight no primeiro item
                Qt.callLater(function () {
                    if (epicList && typeof epicList.clearVisualSelection === 'function') {
                        epicList.clearVisualSelection();
                    }
                });
            }

            root.isSearching = false;
        }

        function onEpicSearchPageCompleted(results, nextToken) {
            // Adicionar resultados da página à lista existente (paginação)
            if (results === undefined || results === null) {
                root.nextPageToken = "";
                root.isSearching = false;
                root.isLoadingMore = false;
                return;
            }

            // Salvar posição do scroll antes de adicionar novos itens
            if (epicList && typeof epicList.saveScrollPosition === 'function') {
                epicList.saveScrollPosition();
            }

            var currentModel = epicList.model || [];
            // Adicionar novos resultados ao modelo existente
            epicList.model = currentModel.concat(results);

            // Restaurar posição do scroll após atualizar o modelo
            if (epicList && typeof epicList.restoreScrollPosition === 'function') {
                epicList.restoreScrollPosition();
            }

            // Atualizar nextPageToken (importante para próxima paginação)
            root.nextPageToken = nextToken || "";

            root.isSearching = false;
            root.isLoadingMore = false;
        }
    }

    // Propriedade para compatibilidade com código existente
    property string autoSelectKey: ""
    property string autoSelectSummary: ""
}
