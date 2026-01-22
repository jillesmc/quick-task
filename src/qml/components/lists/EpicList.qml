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
import QtQuick 2.12
import QtQuick.Controls 2.12 as Controls
import org.kde.kirigami 2.12 as Kirigami
import "."

Controls.Frame {
    id: root
    
    property var model: []
    property bool enabled: true
    property string selectedEpicKey: ""
    property bool isLoading: false
    clip: true   // garante que o conteúdo da lista não extrapole visualmente o frame
    
    // Flag para evitar múltiplas chamadas de paginação
    property bool _paginationRequested: false
    
    signal epicSelected(string epicKey, var epicData)
    signal loadMoreRequested()
    
    // Propriedade para salvar/restaurar posição do scroll
    property real _savedScrollPosition: 0
    
    /**
     * Limpa a seleção visual (currentIndex) sem limpar selectedEpicKey
     */
    function clearVisualSelection() {
        epicsListView.currentIndex = -1
    }
    
    /**
     * Salva a posição atual do scroll
     */
    function saveScrollPosition() {
        root._savedScrollPosition = epicsListView.contentY
    }
    
    /**
     * Restaura a posição salva do scroll
     */
    function restoreScrollPosition() {
        Qt.callLater(function() {
            epicsListView.contentY = root._savedScrollPosition
        })
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
        
        model: root.model
        
        // Detectar quando scroll chega próximo do fim para paginação
        onContentYChanged: {
            if (!root.isLoading && root.enabled && epicsListView.count > 0 && !root._paginationRequested) {
                var scrollPosition = epicsListView.contentY
                var scrollMax = epicsListView.contentHeight - epicsListView.height
                
                // Verificar se chegou próximo do fim (dentro de 100px do fim ou 80% do scroll)
                var distanceFromEnd = scrollMax - scrollPosition
                var scrollPercentage = scrollMax > 0 ? (scrollPosition / scrollMax) : 0
                
                // Quando chegar a 80% do scroll OU estiver a menos de 100px do fim
                if (scrollPercentage >= 0.8 || (distanceFromEnd <= 100 && distanceFromEnd >= 0)) {
                    root._paginationRequested = true
                    root.loadMoreRequested()
                }
            }
        }
        
        // Resetar flag quando o modelo muda (novos itens adicionados)
        // E manter currentIndex sincronizado com selectedEpicKey
        onModelChanged: {
            // Resetar flag após um pequeno delay para permitir próxima paginação
            if (root._paginationRequested) {
                Qt.callLater(function() {
                    root._paginationRequested = false
                })
            }
            
            // Manter currentIndex sincronizado com selectedEpicKey quando o modelo muda
            Qt.callLater(function() {
                if (root.selectedEpicKey !== "" && epicsListView.count > 0) {
                    // Encontrar o índice do epic selecionado após atualização do modelo
                    for (var i = 0; i < epicsListView.count; i++) {
                        var item = epicsListView.model[i]
                        if (item && item.key === root.selectedEpicKey) {
                            epicsListView.currentIndex = i
                            return
                        }
                    }
                }
                // Se não há selectedEpicKey ou não foi encontrado, garantir que currentIndex seja -1
                // Isso evita que o primeiro item apareça visualmente selecionado
                if (root.selectedEpicKey === "") {
                    epicsListView.currentIndex = -1
                }
            })
        }
        
        // Sincronizar quando selectedEpicKey muda
        Connections {
            target: root
            function onSelectedEpicKeyChanged() {
                if (root.selectedEpicKey !== "" && epicsListView.count > 0) {
                    // Encontrar o índice do epic selecionado
                    for (var i = 0; i < epicsListView.count; i++) {
                        var item = epicsListView.model[i]
                        if (item && item.key === root.selectedEpicKey) {
                            epicsListView.currentIndex = i
                            break
                        }
                    }
                } else if (root.selectedEpicKey === "") {
                    epicsListView.currentIndex = -1
                }
            }
        }
        
        delegate: EpicListItem {
            onClicked: {
                root.selectedEpicKey = epicKey
                epicsListView.currentIndex = index
                var epicData = epicsListView.model[index]
                root.epicSelected(epicKey, epicData)
            }
            checked: ListView.isCurrentItem
        }
        
        Kirigami.PlaceholderMessage {
            anchors.centerIn: parent
            visible: (!root.model || root.model.length === 0) && !root.isLoading
            text: qsTr("Nenhum épico encontrado")
            explanation: qsTr("Faça uma busca ou ajuste os filtros.")
        }
        
        Controls.BusyIndicator {
            anchors.centerIn: parent
            running: root.isLoading
            visible: running
        }
    }
    
    /**
     * Seleciona epic programaticamente
     * @param {string} epicKey - Chave do epic a selecionar
     */
    function selectEpic(epicKey) {
        if (!epicKey) {
            clearSelection()
            return
        }
        
        selectedEpicKey = epicKey
        
        // Encontrar e selecionar na lista
        for (var i = 0; i < epicsListView.count; i++) {
            var item = epicsListView.model[i]
            if (item && item.key === epicKey) {
                epicsListView.currentIndex = i
                var epicData = epicsListView.model[i]
                epicSelected(epicKey, epicData)
                return
            }
        }
    }
    
    /**
     * Limpa seleção
     */
    function clearSelection() {
        selectedEpicKey = ""
        epicsListView.currentIndex = -1
    }
}
