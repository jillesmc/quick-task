/**
 * IssueList.qml
 * 
 * Componente reutilizável para lista de issues com seleção
 * Segue Single Responsibility Principle - apenas gerencia lista e seleção
 * Segue Open/Closed Principle - pode ser estendido sem modificar
 * 
 * Propriedades:
 * - model: modelo de dados (array de issues)
 * - enabled: controla se a lista está habilitada
 * - selectedIssueKey: chave da issue selecionada
 * - isLoading: indica se está carregando
 * 
 * Signals:
 * - issueSelected(string issueKey, var issueData): emitido quando issue é selecionada
 * 
 * Métodos:
 * - selectIssue(string issueKey): seleciona issue programaticamente
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
    property string selectedIssueKey: ""
    property bool isLoading: false
    clip: true   // garante que o conteúdo da lista não extrapole visualmente o frame
    
    signal issueSelected(string issueKey, var issueData)
    
    ListView {
        id: issuesListView
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
        
        // Manter currentIndex sincronizado com selectedIssueKey quando o modelo muda
        onModelChanged: {
            Qt.callLater(function() {
                if (root.selectedIssueKey !== "" && issuesListView.count > 0) {
                    // Encontrar o índice da issue selecionada após atualização do modelo
                    for (var i = 0; i < issuesListView.count; i++) {
                        var item = issuesListView.model[i]
                        if (item && item.key === root.selectedIssueKey) {
                            issuesListView.currentIndex = i
                            break
                        }
                    }
                }
            })
        }
        
        // Sincronizar quando selectedIssueKey muda
        Connections {
            target: root
            function onSelectedIssueKeyChanged() {
                if (root.selectedIssueKey !== "" && issuesListView.count > 0) {
                    // Encontrar o índice da issue selecionada
                    for (var i = 0; i < issuesListView.count; i++) {
                        var item = issuesListView.model[i]
                        if (item && item.key === root.selectedIssueKey) {
                            issuesListView.currentIndex = i
                            break
                        }
                    }
                } else if (root.selectedIssueKey === "") {
                    issuesListView.currentIndex = -1
                }
            }
        }
        
        delegate: IssueListItem {
            onClicked: {
                root.selectedIssueKey = issueKey
                issuesListView.currentIndex = index
                var issueData = issuesListView.model[index]
                root.issueSelected(issueKey, issueData)
            }
            checked: ListView.isCurrentItem
        }
        
        Kirigami.PlaceholderMessage {
            anchors.centerIn: parent
            visible: (!root.model || root.model.length === 0) && !root.isLoading
            text: qsTr("Nenhuma issue encontrada")
            explanation: qsTr("Verifique se você possui issues atribuídas ou ajuste os filtros.")
        }
        
        Controls.BusyIndicator {
            anchors.centerIn: parent
            running: root.isLoading
            visible: running
        }
    }
    
    /**
     * Seleciona issue programaticamente
     * @param {string} issueKey - Chave da issue a selecionar
     */
    function selectIssue(issueKey) {
        if (!issueKey) {
            clearSelection()
            return
        }
        
        selectedIssueKey = issueKey
        
        // Encontrar e selecionar na lista
        for (var i = 0; i < issuesListView.count; i++) {
            var item = issuesListView.model[i]
            if (item && item.key === issueKey) {
                issuesListView.currentIndex = i
                var issueData = issuesListView.model[i]
                issueSelected(issueKey, issueData)
                return
            }
        }
    }
    
    /**
     * Limpa seleção
     */
    function clearSelection() {
        selectedIssueKey = ""
        issuesListView.currentIndex = -1
    }
}
