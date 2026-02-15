import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

// Delegate para exibir uma issue na lista de "Minhas Issues".
// Recebe key, summary, status, issueType, assignee, parentKey, priority e index via bind automático do ListView (ListModel com roles de mesmo nome).

Controls.ItemDelegate {
    id: root

    required property string key
    required property string summary
    required property string status
    required property string issueType
    required property string assignee
    required property string parentKey
    required property int index
    property string priority: ""
    property string priorityId: ""

    // Status: texto abreviado (compatível com qualquer fonte/tema)
    property string statusDisplay: {
        var s = (root.status || "").toUpperCase()
        if (!s) return "—"
        if (s.indexOf("DONE") >= 0 || s.indexOf("CLOSED") >= 0) return "Done"
        if (s.indexOf("REVIEW") >= 0 || s.indexOf("CODE REVIEW") >= 0) return "Review"
        if (s.indexOf("DEVELOPMENT") >= 0 || s.indexOf("PROGRESS") >= 0) return "Dev"
        if (s.indexOf("HOMOLOG") >= 0 || s.indexOf("TEST") >= 0) return "Homolog"
        if (s.indexOf("TO DO") >= 0 || s.indexOf("BACKLOG") >= 0) return "To Do"
        if (s.indexOf("BLOCKED") >= 0 || s.indexOf("WAITING") >= 0) return "Wait"
        return s.length > 8 ? s.substring(0, 8) + "…" : s
    }
    // Prioridade: texto abreviado (Jira Cloud usa IDs como 10000, não 1-5)
    property string priorityDisplay: {
        var p = (root.priority || "").toLowerCase()
        var id = root.priorityId
        if (p.includes("highest") || id === "1" || id === "10000") return "Máx"
        if ((p.includes("high") && !p.includes("lowest")) || id === "2" || id === "10001") return "Alta"
        if (p.includes("medium") || p.includes("médio") || id === "3" || id === "10002") return "Média"
        if ((p.includes("low") && !p.includes("lowest")) || id === "4" || id === "10003") return "Baixa"
        if (p.includes("lowest") || id === "5" || id === "10004") return "Mín"
        return p ? (p.length > 6 ? p.substring(0, 6) + "…" : p) : "Média"
    }

    property var timerModel: null
    property var timerService: null

    signal startTimerRequested(string issueKey)

    property string issueKey: root.key
    property string parentDisplay: root.parentKey

    width: ListView.view ? ListView.view.width : implicitWidth

    background: Rectangle {
        color: root.checked ? Kirigami.Theme.highlightColor : "transparent"
        opacity: root.checked ? 0.2 : 1.0
    }

    contentItem: RowLayout {
        spacing: Kirigami.Units.smallSpacing

        Controls.Label {
            text: {
                if (root.issueType && root.issueType.toLowerCase().includes("task")) {
                    return "✓"
                } else if (root.issueType && root.issueType.toLowerCase().includes("bug")) {
                    return "🐛"
                } else if (root.issueType && root.issueType.toLowerCase().includes("story")) {
                    return "📖"
                } else if (root.issueType && root.issueType.toLowerCase().includes("epic")) {
                    return "📋"
                }
                return "○"
            }
            font.pointSize: Kirigami.Theme.defaultFont.pointSize + 2
            Layout.preferredWidth: 30
            horizontalAlignment: Text.AlignLeft
        }

        Controls.Label {
            text: root.priorityDisplay
            font.pointSize: Kirigami.Theme.defaultFont.pointSize
            Layout.preferredWidth: 50
            Layout.minimumWidth: 40
            horizontalAlignment: Text.AlignLeft
            elide: Text.ElideRight
        }

        Controls.Label {
            text: root.issueKey
            font.bold: true
            Layout.preferredWidth: 110
            horizontalAlignment: Text.AlignLeft
        }

        Controls.Label {
            text: root.summary
            Layout.fillWidth: true
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignLeft
        }

        Controls.Label {
            text: root.statusDisplay
            font.pointSize: Kirigami.Theme.defaultFont.pointSize
            Layout.preferredWidth: 70
            Layout.minimumWidth: 50
            horizontalAlignment: Text.AlignLeft
            elide: Text.ElideRight
        }

        Controls.Label {
            text: root.parentDisplay
            Layout.preferredWidth: 150
            horizontalAlignment: Text.AlignLeft
            elide: Text.ElideRight
        }

        RowLayout {
            spacing: Kirigami.Units.smallSpacing
            Layout.preferredWidth: 70
            Layout.alignment: Qt.AlignLeft

            Controls.Label {
                text: "⏱"
                visible: root.timerModel && root.timerModel.issueKey === root.issueKey &&
                         (root.timerModel.state === "running" || root.timerModel.state === "paused")
                color: root.timerModel && root.timerModel.state === "running" ? "#3daee9" : "#808080"
                Layout.preferredWidth: 30
                Layout.alignment: Qt.AlignLeft
                horizontalAlignment: Text.AlignLeft
            }

            Controls.ToolButton {
                icon.name: {
                    if (root.timerModel && root.timerModel.issueKey === root.issueKey && root.timerModel.state === "running") {
                        return "media-playback-stop"
                    } else if (root.timerModel && root.timerModel.issueKey === root.issueKey && root.timerModel.state === "paused") {
                        return "media-playback-start"
                    } else if (root.timerModel && root.timerModel.isOnBreak) {
                        return "media-playback-start"
                    }
                    return "chronometer"
                }
                Layout.preferredWidth: 40
                enabled: root.timerService && root.timerModel

                onClicked: {
                    if (!root.timerModel || !root.issueKey) {
                        return
                    }
                    function doStart() {
                        root.startTimerRequested(root.issueKey)
                    }
                    if (root.timerService && root.timerModel && root.timerModel.isOnBreak) {
                        root.timerService.cancelBreak()
                        Qt.callLater(doStart)
                        return
                    }
                    if (root.timerModel.issueKey === root.issueKey && root.timerModel.state !== "idle") {
                        if (root.timerModel.state === "running" && root.timerService) {
                            root.timerService.stop()
                        }
                    } else if (root.timerModel.state !== "idle" && root.timerModel.issueKey !== root.issueKey && root.timerService) {
                        root.timerService.stop()
                        Qt.callLater(doStart)
                    } else {
                        doStart()
                    }
                }
            }
        }
    }
}
