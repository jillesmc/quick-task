/**
 * IssueSearchForm.qml
 *
 * Componente reutilizável para busca de issues
 * Segue Single Responsibility Principle - apenas gerencia busca de issues
 * Segue Open/Closed Principle - pode ser estendido sem modificar
 *
 * Propriedades:
 * - enabled: controla se o formulário está habilitado
 * - placeholderText: texto do placeholder
 * - isLoading: indica se está carregando (para desabilitar durante busca)
 *
 * Signals:
 * - searchRequested(string query): emitido quando busca é solicitada
 *
 * Métodos:
 * - reset(): limpa campo de busca
 * - setQuery(string query): define query de busca
 * - getQuery(): retorna query atual
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

RowLayout {
    id: root

    property bool enabled: true
    property string placeholderText: qsTr("Buscar issues por resumo ou chave...")
    property bool isLoading: false

    signal searchRequested(string query)

    spacing: Kirigami.Units.smallSpacing

    Controls.TextField {
        id: searchField
        Layout.fillWidth: true
        placeholderText: root.placeholderText
        enabled: root.enabled && !root.isLoading

        // Acionar busca ao pressionar ENTER
        Keys.onReturnPressed: function (event) {
            event.accepted = true;
            if (root.enabled && !root.isLoading) {
                var query = searchField.text.trim();
                root.searchRequested(query);
            }
        }

        Keys.onEnterPressed: function (event) {
            event.accepted = true;
            if (root.enabled && !root.isLoading) {
                var query = searchField.text.trim();
                root.searchRequested(query);
            }
        }
    }

    Controls.Button {
        text: qsTr("Buscar")
        icon.name: "search"
        enabled: root.enabled && !root.isLoading
        onClicked: {
            var query = searchField.text.trim();
            root.searchRequested(query);
        }
    }

    /**
     * Limpa campo de busca
     */
    function reset() {
        searchField.text = "";
    }

    /**
     * Define query de busca
     * @param {string} query - Query de busca
     */
    function setQuery(query) {
        searchField.text = query || "";
    }

    /**
     * Retorna query atual
     * @returns {string} Query atual
     */
    function getQuery() {
        return searchField.text.trim();
    }
}
