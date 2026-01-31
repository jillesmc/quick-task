pragma ComponentBehavior: Bound
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
    id: issueListRoot
    
    property var model: []
    property bool enabled: true
    property string selectedIssueKey: ""
    property bool isLoading: false
    property var timerModel: null
    property var timerService: null
    clip: true   // garante que o conteúdo da lista não extrapole visualmente o frame
    
    signal issueSelected(string issueKey, var issueData)

    ListModel {
        id: issueListModel
    }

    function syncIssueModel() {
        issueListModel.clear()
        if (!issueListRoot.model || !issueListRoot.model.length) return
        for (var i = 0; i < issueListRoot.model.length; i++) {
            var item = issueListRoot.model[i]
            issueListModel.append({
                key: item && item.key !== undefined ? item.key : "",
                summary: item && item.summary !== undefined ? item.summary : "",
                status: item && item.status !== undefined ? item.status : "",
                issueType: item && item.issueType !== undefined ? item.issueType : "",
                assignee: item && item.assignee !== undefined ? item.assignee : "",
                parentKey: item && item.parentKey !== undefined ? item.parentKey : "",
                index: i
            })
        }
    }

    Connections {
        target: issueListRoot
        function onModelChanged() {
            issueListRoot.syncIssueModel()
        }
    }

    Component.onCompleted: {
        issueListRoot.syncIssueModel()
    }
    
    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        
        // Cabeçalho da lista
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 35
            color: Kirigami.Theme.backgroundColor || "#f0f0f0"
            border.color: Kirigami.Theme.textColor || "#d0d0d0"
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
            
            model: issueListModel
            
            // Manter currentIndex sincronizado com selectedIssueKey quando o modelo muda
            onModelChanged: {
                Qt.callLater(function() {
                    if (issueListRoot.selectedIssueKey !== "" && issueListRoot.model && issueListRoot.model.length > 0) {
                        for (var i = 0; i < issueListRoot.model.length; i++) {
                            var item = issueListRoot.model[i]
                            if (item && item.key === issueListRoot.selectedIssueKey) {
                                issuesListView.currentIndex = i
                                break
                            }
                        }
                    }
                })
            }

            Connections {
                target: issueListRoot
                function onSelectedIssueKeyChanged() {
                    if (issueListRoot.selectedIssueKey !== "" && issueListRoot.model && issueListRoot.model.length > 0) {
                        for (var i = 0; i < issueListRoot.model.length; i++) {
                            var item = issueListRoot.model[i]
                            if (item && item.key === issueListRoot.selectedIssueKey) {
                                issuesListView.currentIndex = i
                                break
                            }
                        }
                    } else if (issueListRoot.selectedIssueKey === "") {
                        issuesListView.currentIndex = -1
                    }
                }
            }
            
            delegate: IssueListItem {
                id: delegateItem
                timerModel: issueListRoot.timerModel
                timerService: issueListRoot.timerService
                onClicked: {
                    issueListRoot.selectedIssueKey = delegateItem.key
                    issuesListView.currentIndex = delegateItem.index
                    var issueData = (issueListRoot.model && delegateItem.index >= 0 && delegateItem.index < issueListRoot.model.length)
                        ? issueListRoot.model[delegateItem.index] : null
                    issueListRoot.issueSelected(delegateItem.key, issueData)
                }
                checked: ListView.isCurrentItem
            }
            
            Kirigami.PlaceholderMessage {
                anchors.centerIn: parent
                visible: (!issueListRoot.model || issueListRoot.model.length === 0) && !issueListRoot.isLoading
                text: qsTr("Nenhuma issue encontrada")
                explanation: qsTr("Verifique se você possui issues atribuídas ou ajuste os filtros.")
            }
            
            Controls.BusyIndicator {
                anchors.centerIn: parent
                running: issueListRoot.isLoading
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
        if (!issueListRoot.model || !issueListRoot.model.length) return
        for (var i = 0; i < issueListRoot.model.length; i++) {
            var item = issueListRoot.model[i]
            if (item && item.key === issueKey) {
                issuesListView.currentIndex = i
                issueSelected(issueKey, issueListRoot.model[i])
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
