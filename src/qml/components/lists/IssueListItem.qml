import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

// Delegate para exibir uma issue na lista de "Minhas Issues".
// Recebe key, summary, status, issueType, assignee, parentKey e index via bind automático do ListView (ListModel com roles de mesmo nome).

Controls.ItemDelegate {
    id: root

    required property string key
    required property string summary
    required property string status
    required property string issueType
    required property string assignee
    required property string parentKey
    required property int index

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
            horizontalAlignment: Text.AlignHCenter
        }

        Controls.Label {
            text: root.issueKey
            font.bold: true
            Layout.preferredWidth: 110
        }

        Controls.Label {
            text: root.summary
            Layout.fillWidth: true
            elide: Text.ElideRight
        }

        Controls.Label {
            text: root.status
            Layout.preferredWidth: 120
            horizontalAlignment: Text.AlignHCenter
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

            Controls.Label {
                text: "⏱"
                visible: root.timerModel && root.timerModel.issueKey === root.issueKey &&
                         (root.timerModel.state === "running" || root.timerModel.state === "paused")
                color: root.timerModel && root.timerModel.state === "running" ? "#3daee9" : "#808080"
                Layout.preferredWidth: 30
                horizontalAlignment: Text.AlignHCenter
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
