/**
 * TimerActiveBlock.qml
 *
 * Bloco exibido quando há timer ativo: issue key, tempo decorrido, Pomodoro nº,
 * botões Pausar e Parar.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

Rectangle {
    id: root

    property var timerModel: null
    property var timerService: null
    property var settingsModel: null
    property bool hasActiveTimer: timerModel && (timerModel.state === "running" || timerModel.state === "paused")

    visible: hasActiveTimer
    Layout.preferredHeight: 200
    color: Kirigami.Theme.backgroundColor || "#f0f0f0"
    border.color: Kirigami.Theme.textColor || "#d0d0d0"
    border.width: 1
    radius: Kirigami.Units.smallSpacing

    function formatTime(seconds) {
        var hours = Math.floor(seconds / 3600);
        var minutes = Math.floor((seconds % 3600) / 60);
        var secs = seconds % 60;
        return String(hours).padStart(2, '0') + ":" + String(minutes).padStart(2, '0') + ":" + String(secs).padStart(2, '0');
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.mediumSpacing
        spacing: Kirigami.Units.mediumSpacing

        Controls.Label {
            text: qsTr("Timer Ativo")
            font.bold: true
            font.pointSize: Kirigami.Theme.defaultFont.pointSize + 2
            Layout.fillWidth: true
        }

        Controls.Label {
            text: root.timerModel ? root.timerModel.issueKey : ""
            font.pointSize: Kirigami.Theme.defaultFont.pointSize + 1
            Layout.fillWidth: true
        }

        Controls.Label {
            id: timeDisplay
            text: root.formatTime(root.timerModel ? root.timerModel.elapsedSeconds : 0)
            font.pointSize: Kirigami.Theme.defaultFont.pointSize + 4
            font.bold: true
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
        }

        Controls.Label {
            id: pomodoroLabelPage
            text: qsTr("Pomodoro %1").arg(root.timerModel ? root.timerModel.currentPomodoro : 0)
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            visible: root.settingsModel && root.settingsModel.pomodoroEnabled

            Connections {
                target: root.timerModel || null
                function onPomodoroCompleted(pomodoroNum) {
                    pomodoroLabelPage.text = qsTr("Pomodoro %1").arg(pomodoroNum);
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Controls.Button {
                text: qsTr("Pausar")
                icon.name: "media-playback-pause"
                Layout.fillWidth: true
                enabled: root.timerModel && root.timerModel.state === "running" && !root.timerModel.isOnBreak && !root.timerModel.isWaitingBreakDecision
                visible: root.timerModel && root.timerModel.state === "running" && !root.timerModel.isOnBreak && !root.timerModel.isWaitingBreakDecision && !root.timerModel.isWaitingBreakEndDecision
                onClicked: {
                    if (root.timerService && root.timerModel && root.timerModel.state === "running") {
                        root.timerService.pause();
                    }
                }
            }

            Controls.Button {
                text: qsTr("Parar")
                icon.name: "media-playback-stop"
                Layout.fillWidth: true
                enabled: root.timerModel && root.timerModel.state !== "idle" && !root.timerModel.isOnBreak && !root.timerModel.isWaitingBreakEndDecision
                visible: root.timerModel && root.timerModel.state !== "idle" && !root.timerModel.isOnBreak && !root.timerModel.isWaitingBreakEndDecision
                onClicked: {
                    if (root.timerService) {
                        root.timerService.stop();
                    }
                }
            }
        }
    }
}
