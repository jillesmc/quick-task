pragma ComponentBehavior: Bound
/**
 * EpicList.qml
 *
 * Componente reutilizável para lista de epics com seleção
 * Segue Single Responsibility Principle - apenas gerencia lista e seleção
 * Segue Open/Closed Principle - pode ser estendido sem modificar
 *
 * Propriedades:
 * - model: modelo de dados (array de epics)
 * - enabled: controla se a lista está habilitada
 * - selectedEpicKey: chave do epic selecionado
 * - isLoading: indica se está carregando
 *
 * Signals:
 * - epicSelected(string epicKey, var epicData): emitido quando epic é selecionado
 * - loadMoreRequested(): emitido quando scroll chega próximo do fim (para paginação)
 *
 * Métodos:
 * - selectEpic(string epicKey): seleciona epic programaticamente
 * - clearSelection(): limpa seleção
 */
import QtQuick
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami
import "."

Controls.Frame {
    id: epicListRoot

    property var model: []
    property bool enabled: true
    property string selectedEpicKey: ""
    property bool isLoading: false
    clip: true   // garante que o conteúdo da lista não extrapole visualmente o frame

    // Flag para evitar múltiplas chamadas de paginação
    property bool _paginationRequested: false

    signal epicSelected(string epicKey, var epicData)
    signal loadMoreRequested

    // Propriedade para salvar/restaurar posição do scroll
    property real _savedScrollPosition: 0

    // ListModel com roles nomeadas para o delegate (bind automático às required properties)
    ListModel {
        id: epicListModel
    }

    /**
     * Sincroniza epicListModel a partir de epicListRoot.model (array) para o ListView com roles key, summary, status, index.
     */
    function syncEpicModel() {
        epicListModel.clear();
        if (!epicListRoot.model || !epicListRoot.model.length)
            return;
        for (var i = 0; i < epicListRoot.model.length; i++) {
            var item = epicListRoot.model[i];
            epicListModel.append({
                key: item && item.key !== undefined ? item.key : "",
                summary: item && item.summary !== undefined ? item.summary : "",
                status: item && item.status !== undefined ? item.status : "",
                index: i
            });
        }
    }

    Connections {
        target: epicListRoot
        function onModelChanged() {
            epicListRoot.syncEpicModel();
        }
    }

    Component.onCompleted: {
        epicListRoot.syncEpicModel();
    }

    /**
     * Limpa a seleção visual (currentIndex) sem limpar selectedEpicKey
     */
    function clearVisualSelection() {
        epicsListView.currentIndex = -1;
    }

    /**
     * Salva a posição atual do scroll
     */
    function saveScrollPosition() {
        epicListRoot._savedScrollPosition = epicsListView.contentY;
    }

    /**
     * Restaura a posição salva do scroll
     */
    function restoreScrollPosition() {
        Qt.callLater(function () {
            epicsListView.contentY = epicListRoot._savedScrollPosition;
        });
    }

    ListView {
        id: epicsListView
        anchors.fill: parent
        clip: true               // evita vazamento visual
        interactive: true        // scroll interno controlado pelo próprio ListView

        // Barra de rolagem vertical, exibida apenas quando necessário
        Controls.ScrollBar.vertical: Controls.ScrollBar {
            policy: Controls.ScrollBar.AsNeeded
        }

        // Highlight para mostrar seleção visual
        highlight: Rectangle {
            color: Kirigami.Theme.highlightColor
            opacity: 0.3
        }
        highlightFollowsCurrentItem: true

        model: epicListModel

        // Detectar quando scroll chega próximo do fim para paginação
        onContentYChanged: {
            if (!epicListRoot.isLoading && epicListRoot.enabled && epicsListView.count > 0 && !epicListRoot._paginationRequested) {
                var scrollPosition = epicsListView.contentY;
                var scrollMax = epicsListView.contentHeight - epicsListView.height;

                // Verificar se chegou próximo do fim (dentro de 100px do fim ou 80% do scroll)
                var distanceFromEnd = scrollMax - scrollPosition;
                var scrollPercentage = scrollMax > 0 ? (scrollPosition / scrollMax) : 0;

                // Quando chegar a 80% do scroll OU estiver a menos de 100px do fim
                if (scrollPercentage >= 0.8 || (distanceFromEnd <= 100 && distanceFromEnd >= 0)) {
                    epicListRoot._paginationRequested = true;
                    epicListRoot.loadMoreRequested();
                }
            }
        }

        // Resetar flag quando o modelo muda (novos itens adicionados)
        // E manter currentIndex sincronizado com selectedEpicKey
        onModelChanged: {
            // Resetar flag após um pequeno delay para permitir próxima paginação
            if (epicListRoot._paginationRequested) {
                Qt.callLater(function () {
                    epicListRoot._paginationRequested = false;
                });
            }
            // Manter currentIndex sincronizado com selectedEpicKey quando o modelo muda
            Qt.callLater(function () {
                if (epicListRoot.selectedEpicKey !== "" && epicListRoot.model && epicListRoot.model.length > 0) {
                    for (var i = 0; i < epicListRoot.model.length; i++) {
                        var item = epicListRoot.model[i];
                        if (item && item.key === epicListRoot.selectedEpicKey) {
                            epicsListView.currentIndex = i;
                            return;
                        }
                    }
                }
                if (epicListRoot.selectedEpicKey === "") {
                    epicsListView.currentIndex = -1;
                }
            });
        }

        // Sincronizar quando selectedEpicKey muda
        Connections {
            target: epicListRoot
            function onSelectedEpicKeyChanged() {
                if (epicListRoot.selectedEpicKey !== "" && epicListRoot.model && epicListRoot.model.length > 0) {
                    for (var i = 0; i < epicListRoot.model.length; i++) {
                        var item = epicListRoot.model[i];
                        if (item && item.key === epicListRoot.selectedEpicKey) {
                            epicsListView.currentIndex = i;
                            break;
                        }
                    }
                } else if (epicListRoot.selectedEpicKey === "") {
                    epicsListView.currentIndex = -1;
                }
            }
        }

        delegate: EpicListItem {
            id: epicDelegateItem
            onClicked: {
                epicListRoot.selectedEpicKey = epicDelegateItem.key;
                epicsListView.currentIndex = epicDelegateItem.index;
                var epicData = (epicListRoot.model && epicDelegateItem.index >= 0 && epicDelegateItem.index < epicListRoot.model.length) ? epicListRoot.model[epicDelegateItem.index] : null;
                epicListRoot.epicSelected(epicDelegateItem.key, epicData);
            }
            checked: ListView.isCurrentItem
        }

        Kirigami.PlaceholderMessage {
            anchors.centerIn: parent
            visible: (!epicListRoot.model || epicListRoot.model.length === 0) && !epicListRoot.isLoading
            text: qsTr("Nenhum épico encontrado")
            explanation: qsTr("Faça uma busca ou ajuste os filtros.")
        }

        Controls.BusyIndicator {
            anchors.centerIn: parent
            running: epicListRoot.isLoading
            visible: running
        }
    }

    /**
     * Seleciona epic programaticamente
     * @param {string} epicKey - Chave do epic a selecionar
     */
    function selectEpic(epicKey) {
        if (!epicKey) {
            clearSelection();
            return;
        }

        epicListRoot.selectedEpicKey = epicKey;
        if (!epicListRoot.model || !epicListRoot.model.length)
            return;
        for (var i = 0; i < epicListRoot.model.length; i++) {
            var item = epicListRoot.model[i];
            if (item && item.key === epicKey) {
                epicsListView.currentIndex = i;
                epicListRoot.epicSelected(epicKey, epicListRoot.model[i]);
                return;
            }
        }
    }

    /**
     * Limpa seleção
     */
    function clearSelection() {
        epicListRoot.selectedEpicKey = "";
        epicsListView.currentIndex = -1;
    }
}
