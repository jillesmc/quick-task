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
    /** Objeto com .issues e .issuesChanged (ex.: myIssuesModel). Se definido, conecta a issuesChanged para forçar sync quando a lista mudar (Qt pode não detectar mudança de referência na binding). */
    property var sourceModel: null
    property bool enabled: true
    property string selectedIssueKey: ""
    property bool isLoading: false
    property var timerModel: null
    property var timerService: null
    clip: true   // garante que o conteúdo da lista não extrapole visualmente o frame

    signal issueSelected(string issueKey, var issueData)
    /** Emitido quando o utilizador pede para iniciar o timer numa issue; conectar para lógica custom (ex.: transição para IN DEVELOPMENT). */
    signal startTimerRequested(string issueKey)

    function requestStartTimer(issueKey) {
        if (issueKey && typeof issueKey === "string" && issueKey.length > 0)
            issueListRoot.startTimerRequested(issueKey)
    }

    ListModel {
        id: issueListModel
    }

    function syncIssueModel() {
        var prevSelected = issueListRoot.selectedIssueKey
        var data = (issueListRoot.sourceModel && issueListRoot.sourceModel.issues) ? issueListRoot.sourceModel.issues : issueListRoot.model
        var dataSource = (issueListRoot.sourceModel && issueListRoot.sourceModel.issues) ? "sourceModel.issues" : "model"
        console.log("[IssueList] syncIssueModel: dataSource=" + dataSource + " data.length=" + (data ? data.length : "null"))
        if (data && data.length > 0) {
            var item = data[0]
            var keys = (typeof item === "object" && item !== null) ? Object.keys(item) : []
            console.log("[IssueList] syncIssueModel: first item keys=" + JSON.stringify(keys) + " item.key=" + (item && item.key) + " item['key']=" + (item && item["key"]) + " item.summary=" + (item && (item.summary || item["summary"] || "").toString().slice(0, 30)))
        }
        issueListModel.clear()
        if (!data || !data.length) {
            if (prevSelected) issuesListView.currentIndex = -1
            return
        }
        for (var i = 0; i < data.length; i++) {
            var item = data[i]
            var it = item || {}
            var keyVal = (it.key !== undefined || it["key"] !== undefined) ? String(it.key || it["key"] || "") : ""
            issueListModel.append({
                key: keyVal,
                summary: (it.summary !== undefined || it["summary"] !== undefined) ? String(it.summary || it["summary"] || "") : "",
                status: (it.status !== undefined || it["status"] !== undefined) ? String(it.status || it["status"] || "") : "",
                issueType: (it.issueType !== undefined || it["issueType"] !== undefined) ? String(it.issueType || it["issueType"] || "") : "",
                assignee: (it.assignee !== undefined || it["assignee"] !== undefined) ? String(it.assignee || it["assignee"] || "") : "",
                parentKey: (it.parentKey !== undefined || it["parentKey"] !== undefined) ? String(it.parentKey || it["parentKey"] || "") : "",
                priority: (it.priority !== undefined || it["priority"] !== undefined) ? String(it.priority || it["priority"] || "") : "",
                priorityId: (it.priorityId !== undefined || it["priorityId"] !== undefined) ? String(it.priorityId || it["priorityId"] || "") : "",
                index: i
            })
        }
        console.log("[IssueList] syncIssueModel: issueListModel.count=" + issueListModel.count)
        if (issueListModel.count > 0) {
            var row0 = issueListModel.get(0)
            console.log("[IssueList] syncIssueModel: get(0) key=" + (row0 && row0.key) + " summary=" + (row0 && (row0.summary || "").toString().slice(0, 30)) + " priority=" + (row0 && row0.priority))
        }
        // Restaurar seleção após sync (evita reset para primeiro item)
        if (prevSelected && data && data.length > 0) {
            Qt.callLater(function() {
                for (var j = 0; j < data.length; j++) {
                    var it2 = data[j]
                    var k = (it2 && (it2.key !== undefined || it2["key"] !== undefined)) ? String(it2.key || it2["key"] || "") : ""
                    if (k === prevSelected) {
                        issuesListView.currentIndex = j
                        break
                    }
                }
            })
        }
    }

    Connections {
        target: issueListRoot
        function onModelChanged() {
            issueListRoot.syncIssueModel()
        }
    }

    Connections {
        target: issueListRoot.sourceModel || null
        function onIssuesChanged() {
            console.log("[IssueList] onIssuesChanged: sourceModel=" + (issueListRoot.sourceModel ? "set" : "null"))
            if (issueListRoot.sourceModel) issueListRoot.syncIssueModel()
        }
    }

    onSourceModelChanged: {
        console.log("[IssueList] onSourceModelChanged: sourceModel=" + (issueListRoot.sourceModel ? "set" : "null"))
        if (issueListRoot.sourceModel) issueListRoot.syncIssueModel()
    }

    onModelChanged: {
        console.log("[IssueList] onModelChanged: model.length=" + (issueListRoot.model ? issueListRoot.model.length : "null"))
    }

    Component.onCompleted: {
        issueListRoot.syncIssueModel()
    }
    
    ColumnLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.smallSpacing

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
                    horizontalAlignment: Text.AlignLeft
                }

                Controls.Label {
                    text: qsTr("Pri")
                    font.bold: true
                    Layout.preferredWidth: 50
                    horizontalAlignment: Text.AlignLeft
                }
                
                Controls.Label {
                    text: qsTr("Chave")
                    font.bold: true
                    Layout.preferredWidth: 110
                    horizontalAlignment: Text.AlignLeft
                }
                
                Controls.Label {
                    text: qsTr("Resumo")
                    font.bold: true
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignLeft
                }
                
                Controls.Label {
                    text: qsTr("Status")
                    font.bold: true
                    Layout.preferredWidth: 70
                    horizontalAlignment: Text.AlignLeft
                }
                
                Controls.Label {
                    text: qsTr("Parent")
                    font.bold: true
                    Layout.preferredWidth: 150
                    horizontalAlignment: Text.AlignLeft
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
                priority: (ListView.view && ListView.view.model && ListView.view.model.get(index) && ListView.view.model.get(index).priority !== undefined) ? String(ListView.view.model.get(index).priority) : ""
                priorityId: (ListView.view && ListView.view.model && ListView.view.model.get(index) && ListView.view.model.get(index).priorityId !== undefined) ? String(ListView.view.model.get(index).priorityId) : ""
                onStartTimerRequested: function(issueKey) {
                    issueListRoot.requestStartTimer(issueKey)
                }
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
