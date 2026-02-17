pragma ComponentBehavior: Bound
/**
 * IssueList.qml
 *
 * Componente reutilizável para lista de issues com seleção (TableView)
 * Propriedades: model, sourceModel, enabled, selectedIssueKey, isLoading, timerModel, timerService
 * Signals: issueSelected, startTimerRequested
 * Métodos: selectIssue, clearSelection
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import Qt.labs.qmlmodels
import QtQml.Models
import org.kde.kirigami as Kirigami

Controls.Frame {
    id: issueListRoot

    property var model: []
    property var sourceModel: null
    property bool enabled: true
    property string selectedIssueKey: ""
    property bool isLoading: false
    property var timerModel: null
    property var timerService: null
    clip: true

    // Linha ativa para feedback visual instantâneo (não depende do selection model)
    property int activeRow: -1
    // Fase 2: ignorar currentRow=-1 transitório durante sync ou seleção programática
    property bool _syncing: false
    property bool _selecting: false
    signal issueSelected(string issueKey, var issueData)
    signal startTimerRequested(string issueKey)

    function requestStartTimer(issueKey) {
        if (issueKey && typeof issueKey === "string" && issueKey.length > 0)
            issueListRoot.startTimerRequested(issueKey)
    }

    // Larguras: Tipo, Pri, (priorityId oculto), Chave, Resumo, Status, Parent, Timer
    readonly property var _colWidths: [30, 50, 0, 110, 200, 70, 150, 70]

    TableModel {
        id: issueTableModel
        TableModelColumn { display: "issueType" }
        TableModelColumn { display: "priority" }
        TableModelColumn { display: "priorityId" }
        TableModelColumn { display: "key" }
        TableModelColumn { display: "summary" }
        TableModelColumn { display: "status" }
        TableModelColumn { display: "parentKey" }
        TableModelColumn { display: "timerKey" }  // col 7: key para timer (mesmo valor que key)
    }

    function syncIssueModel() {
        issueListRoot._syncing = true
        var prevSelected = issueListRoot.selectedIssueKey
        var data = (issueListRoot.sourceModel && issueListRoot.sourceModel.issues) ? issueListRoot.sourceModel.issues : issueListRoot.model
        issueTableModel.clear()
        if (!data || !data.length) {
            issueListRoot._syncing = false
            issueListRoot.activeRow = -1
            if (prevSelected && issuesTableView.selectionModel) {
                issuesTableView.selectionModel.clearCurrentIndex()
            }
            return
        }
        for (var i = 0; i < data.length; i++) {
            var it = data[i] || {}
            var keyVal = (it.key !== undefined || it["key"] !== undefined) ? String(it.key || it["key"] || "") : ""
            issueTableModel.appendRow({
                issueType: (it.issueType !== undefined || it["issueType"] !== undefined) ? String(it.issueType || it["issueType"] || "") : "",
                priority: (it.priority !== undefined || it["priority"] !== undefined) ? String(it.priority || it["priority"] || "") : "",
                priorityId: (it.priorityId !== undefined || it["priorityId"] !== undefined) ? String(it.priorityId || it["priorityId"] || "") : "",
                key: keyVal,
                summary: (it.summary !== undefined || it["summary"] !== undefined) ? String(it.summary || it["summary"] || "") : "",
                status: (it.status !== undefined || it["status"] !== undefined) ? String(it.status || it["status"] || "") : "",
                parentKey: (it.parentKey !== undefined || it["parentKey"] !== undefined) ? String(it.parentKey || it["parentKey"] || "") : "",
                timerKey: keyVal
            })
        }
        if (prevSelected && data && data.length > 0) {
            Qt.callLater(function() {
                for (var j = 0; j < data.length; j++) {
                    var it2 = data[j]
                    var k = (it2 && (it2.key !== undefined || it2["key"] !== undefined)) ? String(it2.key || it2["key"] || "") : ""
                    if (k === prevSelected) {
                        _setCurrentRow(j)
                        break
                    }
                }
                issueListRoot._syncing = false
            })
        } else if (data && data.length > 0) {
            // Carregamento inicial: selecionar primeira linha
            Qt.callLater(function() {
                _setCurrentRow(0)
                issueListRoot._syncing = false
            })
        } else {
            issueListRoot._syncing = false
        }
    }

    function _setCurrentRow(row) {
        if (!issuesTableView.selectionModel || !issueTableModel) return
        issueListRoot.activeRow = row >= 0 ? row : -1
        var idx = issueTableModel.index(row, 0)
        if (idx.valid) {
            var sm = issuesTableView.selectionModel
            sm.select(idx, ItemSelectionModel.ClearAndSelect | ItemSelectionModel.Rows)
            sm.setCurrentIndex(idx, ItemSelectionModel.Current)
        }
    }

    // Chamado pelo MouseArea do delegate ao clicar na célula. activeRow dá feedback visual
    // instantâneo; a seleção e o emit seguem.
    function _selectRowByIndex(row) {
        issueListRoot._selecting = true
        if (row < 0 || !issueTableModel || row >= issueTableModel.rowCount) return
        issueListRoot.activeRow = row
        var idx = issueTableModel.index(row, 0)
        if (!idx.valid || !issuesTableView.selectionModel) return
        var sm = issuesTableView.selectionModel
        sm.select(idx, ItemSelectionModel.ClearAndSelect | ItemSelectionModel.Rows)
        sm.setCurrentIndex(idx, ItemSelectionModel.Current)
        // Emit explícito: setCurrentIndex pode não disparar onCurrentIndexChanged imediatamente no TableView
        var rowData = issueTableModel.getRow(row)
        var k = rowData && rowData.key ? String(rowData.key) : ""
        var data = (issueListRoot.sourceModel && issueListRoot.sourceModel.issues) ? issueListRoot.sourceModel.issues : issueListRoot.model
        var issueData = (data && row >= 0 && row < data.length) ? data[row] : rowData
        issueListRoot.selectedIssueKey = k
        issueListRoot.issueSelected(k, issueData)
    }

    function _onCurrentRowChanged() {
        if (issueListRoot._syncing)
            return
        var r = issuesTableView.currentRow
        if (issueListRoot._selecting) {
            issueListRoot._selecting = false
            return
        }
        if (r < 0 || !issueTableModel || r >= issueTableModel.rowCount) {
            if (issueListRoot._syncing || issueListRoot._selecting)
                return
            issueListRoot.activeRow = -1
            if (issuesTableView.selectionModel) issuesTableView.selectionModel.clearCurrentIndex()
            if (issueListRoot.selectedIssueKey !== "") {
                issueListRoot.selectedIssueKey = ""
                issueListRoot.issueSelected("", null)
            }
            return
        }
        issueListRoot._selecting = false
        issueListRoot.activeRow = r
        var idx = issueTableModel.index(r, 0)
        if (idx.valid && issuesTableView.selectionModel) {
            issuesTableView.selectionModel.select(idx, ItemSelectionModel.ClearAndSelect | ItemSelectionModel.Rows)
        }
        var rowData = issueTableModel.getRow(r)
        var k = rowData && rowData.key ? String(rowData.key) : ""
        if (issueListRoot.selectedIssueKey !== k) {
            issueListRoot.selectedIssueKey = k
            var data = (issueListRoot.sourceModel && issueListRoot.sourceModel.issues) ? issueListRoot.sourceModel.issues : issueListRoot.model
            var issueData = (data && r >= 0 && r < data.length) ? data[r] : rowData
            issueListRoot.issueSelected(k, issueData)
        }
    }

    Connections {
        target: issueListRoot
        function onModelChanged() { issueListRoot.syncIssueModel() }
    }
    Connections {
        target: issueListRoot.sourceModel || null
        function onIssuesChanged() {
            if (issueListRoot.sourceModel) issueListRoot.syncIssueModel()
        }
    }
    onSourceModelChanged: {
        if (issueListRoot.sourceModel) issueListRoot.syncIssueModel()
    }
    Component.onCompleted: issueListRoot.syncIssueModel()

    ColumnLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.smallSpacing

        Controls.HorizontalHeaderView {
            id: headerView
            syncView: issuesTableView
            model: [qsTr("Tipo"), qsTr("Pri"), "", qsTr("Chave"), qsTr("Resumo"), qsTr("Status"), qsTr("Parent"), ""]
            delegate: Item {
                required property string modelData
                implicitWidth: headerText.implicitWidth + Kirigami.Units.smallSpacing * 2
                implicitHeight: headerText.implicitHeight + Kirigami.Units.smallSpacing * 2
                Controls.Label {
                    id: headerText
                    anchors.fill: parent
                    text: parent.modelData
                    font.bold: true
                    padding: Kirigami.Units.smallSpacing
                    horizontalAlignment: Text.AlignLeft
                }
            }
        }

        TableView {
            id: issuesTableView
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            interactive: true
            columnSpacing: 1
            rowSpacing: 1
            resizableColumns: true
            selectionModel: ItemSelectionModel { model: issueTableModel }
            selectionBehavior: TableView.SelectRows
            pointerNavigationEnabled: false  // Tratamos clique no delegate (Qt 6 não seleciona linha no tap)
            model: issueTableModel

            columnWidthProvider: function(column) {
                var explicitW = issuesTableView.explicitColumnWidth(column)
                if (explicitW >= 0)
                    return explicitW
                if (column >= 0 && column < issueListRoot._colWidths.length) {
                    var w = issueListRoot._colWidths[column]
                    return w >= 0 ? w : 100
                }
                return 100
            }
            rowHeightProvider: function(row) { return 36 }

            Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }

            Connections {
                target: issuesTableView.selectionModel
                function onCurrentIndexChanged() {
                    issueListRoot._onCurrentRowChanged()
                }
            }

            delegate: DelegateChooser {
                DelegateChoice {
                    column: 0
                    delegate: Rectangle {
                        id: tipoCell
                        implicitWidth: 30
                        implicitHeight: 36
                        color: (selected || current || row === issueListRoot.activeRow) ? Kirigami.Theme.highlightColor : "transparent"
                        opacity: (selected || current || row === issueListRoot.activeRow) ? 0.3 : 1
                        required property bool selected
                        required property bool current
                        required property int row
                        required property int column
                        required property var model
                        MouseArea {
                            anchors.fill: parent
                            onClicked: issueListRoot._selectRowByIndex(tipoCell.row)
                        }
                        Controls.Label {
                            anchors.centerIn: parent
                            text: {
                                var t = (tipoCell.model && tipoCell.model.display) ? String(tipoCell.model.display).toLowerCase() : ""
                                if (t.includes("task")) return "✓"
                                if (t.includes("bug")) return "🐛"
                                if (t.includes("story")) return "📖"
                                if (t.includes("epic")) return "📋"
                                return "○"
                            }
                            font.pointSize: Kirigami.Theme.defaultFont.pointSize + 2
                        }
                    }
                }
                DelegateChoice {
                    column: 1
                    delegate: Rectangle {
                        id: priCell
                        implicitWidth: 50
                        implicitHeight: 36
                        color: (selected || current || row === issueListRoot.activeRow) ? Kirigami.Theme.highlightColor : "transparent"
                        opacity: (selected || current || row === issueListRoot.activeRow) ? 0.3 : 1
                        required property bool selected
                        required property bool current
                        required property int row
                        required property int column
                        required property var model
                        property var _row: TableView.view && TableView.view.model && typeof TableView.view.model.getRow === "function" ? TableView.view.model.getRow(row) : {}
                        property string _priority: _row && _row.priority !== undefined ? String(_row.priority) : ""
                        property string _priorityId: _row && _row.priorityId !== undefined ? String(_row.priorityId) : ""
                        property string _priorityIcon: {
                            var p = _priority.toLowerCase()
                            var id = _priorityId
                            if (p.includes("highest") || id === "1" || id === "10000") return "flag-red"
                            if ((p.includes("high") && !p.includes("lowest")) || id === "2" || id === "10001") return "flag-yellow"
                            if (p.includes("medium") || p.includes("médio") || id === "3" || id === "10002") return "flag"
                            if ((p.includes("low") && !p.includes("lowest")) || id === "4" || id === "10003") return "flag-green"
                            if (p.includes("lowest") || id === "5" || id === "10004") return "flag-blue"
                            return ""
                        }
                        property string _priorityDisplay: {
                            var p = _priority.toLowerCase()
                            var id = _priorityId
                            if (p.includes("highest") || id === "1" || id === "10000") return "Máx"
                            if ((p.includes("high") && !p.includes("lowest")) || id === "2" || id === "10001") return "Alta"
                            if (p.includes("medium") || p.includes("médio") || id === "3" || id === "10002") return "Média"
                            if ((p.includes("low") && !p.includes("lowest")) || id === "4" || id === "10003") return "Baixa"
                            if (p.includes("lowest") || id === "5" || id === "10004") return "Mín"
                            return p ? (p.length > 6 ? p.substring(0, 6) + "…" : p) : "Média"
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: issueListRoot._selectRowByIndex(priCell.row)
                        }
                        Item {
                            anchors.fill: parent
                            Kirigami.Icon {
                                anchors.centerIn: parent
                                source: priCell._priorityIcon
                                width: Kirigami.Units.iconSizes.small
                                height: width
                                visible: priCell._priorityIcon !== ""
                            }
                            Controls.Label {
                                anchors.centerIn: parent
                                text: priCell._priorityDisplay
                                font.pointSize: Kirigami.Theme.defaultFont.pointSize
                                visible: priCell._priorityIcon === ""
                            }
                        }
                    }
                }
                DelegateChoice {
                    column: 2
                    delegate: Rectangle {
                        id: hiddenCell
                        implicitWidth: 1
                        implicitHeight: 36
                        color: (selected || current || row === issueListRoot.activeRow) ? Kirigami.Theme.highlightColor : "transparent"
                        opacity: (selected || current || row === issueListRoot.activeRow) ? 0.3 : 1
                        required property bool selected
                        required property bool current
                        required property int row
                        MouseArea {
                            anchors.fill: parent
                            onClicked: issueListRoot._selectRowByIndex(hiddenCell.row)
                        }
                    }
                }
                DelegateChoice {
                    column: 3
                    delegate: Rectangle {
                        id: chaveCell
                        implicitWidth: 110
                        implicitHeight: 36
                        color: (selected || current || row === issueListRoot.activeRow) ? Kirigami.Theme.highlightColor : "transparent"
                        opacity: (selected || current || row === issueListRoot.activeRow) ? 0.3 : 1
                        required property bool selected
                        required property bool current
                        required property int row
                        required property var model
                        MouseArea {
                            anchors.fill: parent
                            onClicked: issueListRoot._selectRowByIndex(chaveCell.row)
                        }
                        Controls.Label {
                            anchors.fill: parent
                            anchors.margins: Kirigami.Units.smallSpacing
                            text: chaveCell.model && chaveCell.model.display ? chaveCell.model.display : ""
                            font.bold: true
                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
                DelegateChoice {
                    column: 4
                    delegate: Rectangle {
                        id: resumoCell
                        implicitWidth: 200
                        implicitHeight: 36
                        color: (selected || current || row === issueListRoot.activeRow) ? Kirigami.Theme.highlightColor : "transparent"
                        opacity: (selected || current || row === issueListRoot.activeRow) ? 0.3 : 1
                        required property bool selected
                        required property bool current
                        required property int row
                        required property var model
                        MouseArea {
                            anchors.fill: parent
                            onClicked: issueListRoot._selectRowByIndex(resumoCell.row)
                        }
                        Controls.Label {
                            anchors.fill: parent
                            anchors.margins: Kirigami.Units.smallSpacing
                            text: resumoCell.model && resumoCell.model.display ? resumoCell.model.display : ""
                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
                DelegateChoice {
                    column: 5
                    delegate: Rectangle {
                        id: statusCell
                        implicitWidth: 70
                        implicitHeight: 36
                        color: (selected || current || row === issueListRoot.activeRow) ? Kirigami.Theme.highlightColor : "transparent"
                        opacity: (selected || current || row === issueListRoot.activeRow) ? 0.3 : 1
                        required property bool selected
                        required property bool current
                        required property int row
                        required property var model
                        MouseArea {
                            anchors.fill: parent
                            onClicked: issueListRoot._selectRowByIndex(statusCell.row)
                        }
                        property string _status: statusCell.model && statusCell.model.display ? String(statusCell.model.display).toUpperCase() : ""
                        property string _statusDisplay: {
                            var s = _status
                            if (!s) return "—"
                            if (s.indexOf("DONE") >= 0 || s.indexOf("CLOSED") >= 0) return "Done"
                            if (s.indexOf("REVIEW") >= 0 || s.indexOf("CODE REVIEW") >= 0) return "Review"
                            if (s.indexOf("DEVELOPMENT") >= 0 || s.indexOf("PROGRESS") >= 0) return "Dev"
                            if (s.indexOf("HOMOLOG") >= 0 || s.indexOf("TEST") >= 0) return "Homolog"
                            if (s.indexOf("TO DO") >= 0 || s.indexOf("BACKLOG") >= 0) return "To Do"
                            if (s.indexOf("BLOCKED") >= 0 || s.indexOf("WAITING") >= 0) return "Wait"
                            return s.length > 8 ? s.substring(0, 8) + "…" : s
                        }
                        Controls.Label {
                            anchors.fill: parent
                            anchors.margins: Kirigami.Units.smallSpacing
                            text: parent._statusDisplay
                            font.pointSize: Kirigami.Theme.defaultFont.pointSize
                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
                DelegateChoice {
                    column: 6
                    delegate: Rectangle {
                        id: parentCell
                        implicitWidth: 150
                        implicitHeight: 36
                        color: (selected || current || row === issueListRoot.activeRow) ? Kirigami.Theme.highlightColor : "transparent"
                        opacity: (selected || current || row === issueListRoot.activeRow) ? 0.3 : 1
                        required property bool selected
                        required property bool current
                        required property int row
                        required property var model
                        MouseArea {
                            anchors.fill: parent
                            onClicked: issueListRoot._selectRowByIndex(parentCell.row)
                        }
                        Controls.Label {
                            anchors.fill: parent
                            anchors.margins: Kirigami.Units.smallSpacing
                            text: parentCell.model && parentCell.model.display ? parentCell.model.display : ""
                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
                DelegateChoice {
                    column: 7
                    delegate: Rectangle {
                        id: timerCell
                        implicitWidth: 70
                        implicitHeight: 36
                        color: (selected || current || row === issueListRoot.activeRow) ? Kirigami.Theme.highlightColor : "transparent"
                        opacity: (selected || current || row === issueListRoot.activeRow) ? 0.3 : 1
                        required property bool selected
                        required property bool current
                        required property int row
                        required property var model
                        property string _issueKey: timerCell.model && timerCell.model.display ? timerCell.model.display : ""
                        MouseArea {
                            anchors.fill: parent
                            onClicked: issueListRoot._selectRowByIndex(timerCell.row)
                        }
                        RowLayout {
                            anchors.fill: parent
                            spacing: Kirigami.Units.smallSpacing
                            Item { Layout.preferredWidth: 4 }
                            Controls.Label {
                                text: "⏱"
                                visible: issueListRoot.timerModel && issueListRoot.timerModel.issueKey === timerCell._issueKey &&
                                         (issueListRoot.timerModel.state === "running" || issueListRoot.timerModel.state === "paused")
                                color: issueListRoot.timerModel && issueListRoot.timerModel.state === "running" ? "#3daee9" : "#808080"
                                Layout.preferredWidth: 30
                                Layout.alignment: Qt.AlignVCenter
                            }
                            Controls.ToolButton {
                                icon.name: {
                                    if (issueListRoot.timerModel && issueListRoot.timerModel.issueKey === timerCell._issueKey && issueListRoot.timerModel.state === "running")
                                        return "media-playback-stop"
                                    if (issueListRoot.timerModel && issueListRoot.timerModel.issueKey === timerCell._issueKey && issueListRoot.timerModel.state === "paused")
                                        return "media-playback-start"
                                    if (issueListRoot.timerModel && issueListRoot.timerModel.isOnBreak)
                                        return "media-playback-start"
                                    return "chronometer"
                                }
                                Layout.preferredWidth: 40
                                enabled: issueListRoot.timerService && issueListRoot.timerModel
                                onClicked: {
                                    issueListRoot._selectRowByIndex(timerCell.row)
                                    if (!issueListRoot.timerModel || !timerCell._issueKey) return
                                    function doStart() { issueListRoot.requestStartTimer(timerCell._issueKey) }
                                    if (issueListRoot.timerService && issueListRoot.timerModel && issueListRoot.timerModel.isOnBreak) {
                                        issueListRoot.timerService.cancelBreak()
                                        Qt.callLater(doStart)
                                        return
                                    }
                                    if (issueListRoot.timerModel.issueKey === timerCell._issueKey && issueListRoot.timerModel.state !== "idle") {
                                        if (issueListRoot.timerModel.state === "running" && issueListRoot.timerService)
                                            issueListRoot.timerService.stop()
                                    } else if (issueListRoot.timerModel.state !== "idle" && issueListRoot.timerModel.issueKey !== timerCell._issueKey && issueListRoot.timerService) {
                                        issueListRoot.timerService.stop()
                                        Qt.callLater(doStart)
                                    } else {
                                        doStart()
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Kirigami.PlaceholderMessage {
                anchors.centerIn: parent
                visible: issueTableModel.rowCount === 0 && !issueListRoot.isLoading
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

    function selectIssue(issueKey) {
        if (!issueKey) {
            clearSelection()
            return
        }
        if (!issueTableModel) return
        for (var i = 0; i < issueTableModel.rowCount; i++) {
            var row = issueTableModel.getRow(i)
            if (row && row.key === issueKey) {
                _setCurrentRow(i)
                var data = (issueListRoot.sourceModel && issueListRoot.sourceModel.issues) ? issueListRoot.sourceModel.issues : issueListRoot.model
                var issueData = (data && i < data.length) ? data[i] : row
                issueListRoot.selectedIssueKey = issueKey
                issueSelected(issueKey, issueData)
                return
            }
        }
    }

    function clearSelection() {
        issueListRoot.activeRow = -1
        if (issuesTableView.selectionModel) {
            issuesTableView.selectionModel.clearCurrentIndex()
            // _onCurrentRowChanged será chamado e emitirá issueSelected("", null)
        }
    }
}
