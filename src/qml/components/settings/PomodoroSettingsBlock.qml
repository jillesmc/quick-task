/**
 * PomodoroSettingsBlock.qml
 *
 * Bloco de configurações de Pomodoro: enabled, duration, short/long break,
 * pomodoros before long break, auto-continue timeout.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

Rectangle {
    id: root

    property var settingsModel: null
    implicitHeight: pomodoroBlock.implicitHeight + (Kirigami.Units.largeSpacing * 2)

    color: Kirigami.Theme.backgroundColor || "#f0f0f0"
    border.color: Kirigami.Theme.textColor || "#d0d0d0"
    border.width: 1
    radius: Kirigami.Units.smallSpacing

    ColumnLayout {
        id: pomodoroBlock
        anchors.fill: parent
        anchors.margins: 20
        spacing: Kirigami.Units.mediumSpacing

        Kirigami.Heading {
            text: qsTr("Configurações de Pomodoro")
            level: 3
            Layout.fillWidth: true
        }

        Controls.CheckBox {
            id: pomodoroEnabledCheckbox
            text: qsTr("Habilitar Pomodoro")
            Layout.fillWidth: true
            checked: true
            onCheckedChanged: {
                if (root.settingsModel) {
                    root.settingsModel.pomodoroEnabled = checked;
                }
                pomodoroDurationSpinBox.enabled = checked;
                shortBreakSpinBox.enabled = checked;
                longBreakSpinBox.enabled = checked;
                pomodorosBeforeLongBreakSpinBox.enabled = checked;
                autoContinueTimeoutSpinBox.enabled = checked;
            }
        }

        Controls.Label {
            text: qsTr("Duração do Pomodoro (minutos):")
            font.bold: true
            Layout.fillWidth: true
        }

        Controls.SpinBox {
            id: pomodoroDurationSpinBox
            from: 1
            to: 120
            value: 25
            onValueChanged: {
                if (root.settingsModel) {
                    root.settingsModel.pomodoroDurationMinutes = value;
                }
            }
        }

        Controls.Label {
            text: qsTr("Pausa Curta (minutos):")
            font.bold: true
            Layout.fillWidth: true
        }

        Controls.SpinBox {
            id: shortBreakSpinBox
            from: 1
            to: 60
            value: 5
            onValueChanged: {
                if (root.settingsModel) {
                    root.settingsModel.shortBreakMinutes = value;
                }
            }
        }

        Controls.Label {
            text: qsTr("Pausa Longa (minutos):")
            font.bold: true
            Layout.fillWidth: true
        }

        Controls.SpinBox {
            id: longBreakSpinBox
            from: 1
            to: 120
            value: 15
            onValueChanged: {
                if (root.settingsModel) {
                    root.settingsModel.longBreakMinutes = value;
                }
            }
        }

        Controls.Label {
            text: qsTr("Pomodoros antes da Pausa Longa:")
            font.bold: true
            Layout.fillWidth: true
        }

        Controls.SpinBox {
            id: pomodorosBeforeLongBreakSpinBox
            from: 1
            to: 10
            value: 4
            onValueChanged: {
                if (root.settingsModel) {
                    root.settingsModel.pomodorosBeforeLongBreak = value;
                }
            }
        }

        Controls.Label {
            text: qsTr("Timeout de Auto-continuação (segundos):")
            font.bold: true
            Layout.fillWidth: true
        }

        Controls.SpinBox {
            id: autoContinueTimeoutSpinBox
            from: 5
            to: 300
            value: 30
            stepSize: 5
            onValueChanged: {
                if (root.settingsModel) {
                    root.settingsModel.autoContinueTimeoutSeconds = value;
                }
            }
        }
    }

    Component.onCompleted: {
        if (root.settingsModel) {
            pomodoroEnabledCheckbox.checked = root.settingsModel.pomodoroEnabled;
            pomodoroDurationSpinBox.value = root.settingsModel.pomodoroDurationMinutes;
            shortBreakSpinBox.value = root.settingsModel.shortBreakMinutes;
            longBreakSpinBox.value = root.settingsModel.longBreakMinutes;
            pomodorosBeforeLongBreakSpinBox.value = root.settingsModel.pomodorosBeforeLongBreak;
            autoContinueTimeoutSpinBox.value = root.settingsModel.autoContinueTimeoutSeconds;
        }
    }
}
