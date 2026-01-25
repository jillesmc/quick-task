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
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami
import "."

Controls.Frame {
    id: root
    
    property var model: []
    property bool enabled: true
    property string selectedIssueKey: ""
    property bool isLoading: false
    clip: true   // garante que o conteúdo da lista não extrapole visualmente o frame
    
    signal issueSelected(string issueKey, var issueData)
    
    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        
        // Cabeçalho da lista
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 35
            color: Kirigami.Theme.backgroundColor || "#f0f0f0"
            border.color: Kirigami.Theme.separatorColor || "#d0d0d0"
            border.width: 1
            
            RowLayout {
                anchors.fill: parent
                anchors.margins: Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.smallSpacing
                
                Controls.Label {
                    text: qsTr("Tipo")
                    font.bold: true
                    Layout.preferredWidth: 30
                    horizontalAlignment: Text.AlignHCenter
                }
                
                Controls.Label {
                    text: qsTr("Chave")
                    font.bold: true
                    Layout.preferredWidth: 110
                }
                
                Controls.Label {
                    text: qsTr("Resumo")
                    font.bold: true
                    Layout.fillWidth: true
                }
                
                Controls.Label {
                    text: qsTr("Status")
                    font.bold: true
                    Layout.preferredWidth: 120
                    horizontalAlignment: Text.AlignHCenter
                }
                
                Controls.Label {
                    text: qsTr("Parent")
                    font.bold: true
                    Layout.preferredWidth: 150
                }
                
                Item {
                    Layout.preferredWidth: 70
                }
            }
        }
        
        ListView {
            id: issuesListView
            Layout.fillWidth: true
            Layout.fillHeight: true
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
