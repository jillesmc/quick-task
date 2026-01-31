/**
 * TimerStatsBlock.qml
 *
 * Bloco de estatísticas do dia: tempo total e número de pomodoros.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: root

    property var timerModel: null

    function formatTime(seconds) {
        var hours = Math.floor(seconds / 3600);
        var minutes = Math.floor((seconds % 3600) / 60);
        var secs = seconds % 60;
        return String(hours).padStart(2, '0') + ":" + String(minutes).padStart(2, '0') + ":" + String(secs).padStart(2, '0');
    }

    Controls.Label {
        text: qsTr("Estatísticas de Hoje")
        font.bold: true
        font.pointSize: Kirigami.Theme.defaultFont.pointSize + 1
        Layout.fillWidth: true
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.mediumSpacing

        ColumnLayout {
            Layout.fillWidth: true
            Controls.Label {
                text: qsTr("Tempo Total")
                font.bold: true
                Layout.fillWidth: true
            }
            Controls.Label {
                text: root.formatTime(root.timerModel ? root.timerModel.totalSecondsToday : 0)
                Layout.fillWidth: true
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Controls.Label {
                text: qsTr("Pomodoros")
                font.bold: true
                Layout.fillWidth: true
            }
            Controls.Label {
                text: root.timerModel ? root.timerModel.pomodorosToday : 0
                Layout.fillWidth: true
            }
        }
    }
}
