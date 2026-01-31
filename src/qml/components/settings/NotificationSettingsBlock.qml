/**
 * NotificationSettingsBlock.qml
 *
 * Bloco de notificações: notificações desktop, som, arquivos de som.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import QtQuick.Dialogs
import org.kde.kirigami as Kirigami

Rectangle {
    id: root

    property var settingsModel: null
    implicitHeight: notificationsBlock.implicitHeight + (Kirigami.Units.largeSpacing * 2)

    color: Kirigami.Theme.backgroundColor || "#f0f0f0"
    border.color: Kirigami.Theme.textColor || "#d0d0d0"
    border.width: 1
    radius: Kirigami.Units.smallSpacing

    ColumnLayout {
        id: notificationsBlock
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.mediumSpacing

        Kirigami.Heading {
            text: qsTr("Notificações")
            level: 3
            Layout.fillWidth: true
        }

        Controls.CheckBox {
            id: notificationsEnabledCheckbox
            text: qsTr("Notificações Desktop")
            Layout.fillWidth: true
            checked: true
            enabled: root.settingsModel ? root.settingsModel.pomodoroEnabled : true
            onCheckedChanged: {
                if (root.settingsModel) {
                    root.settingsModel.notificationsEnabled = checked;
                }
            }
        }

        Controls.CheckBox {
            id: soundEnabledCheckbox
            text: qsTr("Som de Alerta")
            Layout.fillWidth: true
            checked: false
            enabled: root.settingsModel ? root.settingsModel.pomodoroEnabled : true
            onCheckedChanged: {
                if (root.settingsModel) {
                    root.settingsModel.soundEnabled = checked;
                }
                shortSoundFileField.enabled = checked && (root.settingsModel ? root.settingsModel.pomodoroEnabled : true);
                longSoundFileField.enabled = shortSoundFileField.enabled;
            }
        }

        Controls.Label {
            text: qsTr("Arquivo de som - Pausa Curta:")
            font.bold: true
            Layout.fillWidth: true
            enabled: soundEnabledCheckbox.checked
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Controls.TextField {
                id: shortSoundFileField
                Layout.fillWidth: true
                placeholderText: qsTr("short")
                enabled: soundEnabledCheckbox.checked && (root.settingsModel ? root.settingsModel.pomodoroEnabled : true)
                onTextChanged: {
                    if (root.settingsModel && text.length > 0) {
                        root.settingsModel.shortSoundFile = text;
                    }
                }
            }

            Controls.Button {
                icon.name: "folder"
                enabled: shortSoundFileField.enabled
                onClicked: shortSoundFileDialog.open()
            }
        }

        FileDialog {
            id: shortSoundFileDialog
            title: qsTr("Escolher arquivo de som - Pausa Curta")
            nameFilters: ["Arquivos de áudio (*.ogg *.mp3 *.m4r *.wav)", "Todos os arquivos (*)"]
            fileMode: FileDialog.ExistingFile
            onAccepted: {
                var urlString = selectedFile.toString();
                var filePath = urlString.replace(/^file:\/{2,3}/, "");
                filePath = decodeURIComponent(filePath);
                shortSoundFileField.text = filePath;
                if (root.settingsModel) {
                    root.settingsModel.shortSoundFile = filePath;
                }
            }
        }

        Controls.Label {
            text: qsTr("Arquivo de som - Pausa Longa:")
            font.bold: true
            Layout.fillWidth: true
            enabled: soundEnabledCheckbox.checked
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Controls.TextField {
                id: longSoundFileField
                Layout.fillWidth: true
                placeholderText: qsTr("long")
                enabled: soundEnabledCheckbox.checked && (root.settingsModel ? root.settingsModel.pomodoroEnabled : true)
                onTextChanged: {
                    if (root.settingsModel && text.length > 0) {
                        root.settingsModel.longSoundFile = text;
                    }
                }
            }

            Controls.Button {
                icon.name: "folder"
                enabled: longSoundFileField.enabled
                onClicked: longSoundFileDialog.open()
            }
        }

        FileDialog {
            id: longSoundFileDialog
            title: qsTr("Escolher arquivo de som - Pausa Longa")
            nameFilters: ["Arquivos de áudio (*.ogg *.mp3 *.m4r *.wav)", "Todos os arquivos (*)"]
            fileMode: FileDialog.ExistingFile
            onAccepted: {
                var urlString = selectedFile.toString();
                var filePath = urlString.replace(/^file:\/{2,3}/, "");
                filePath = decodeURIComponent(filePath);
                longSoundFileField.text = filePath;
                if (root.settingsModel) {
                    root.settingsModel.longSoundFile = filePath;
                }
            }
        }

        Controls.CheckBox {
            id: desktopNotificationsCheckbox
            text: qsTr("Usar Notificações do Sistema")
            Layout.fillWidth: true
            checked: true
            enabled: root.settingsModel ? root.settingsModel.pomodoroEnabled : true
            onCheckedChanged: {
                if (root.settingsModel) {
                    root.settingsModel.desktopNotifications = checked;
                }
            }
        }
    }

    Component.onCompleted: {
        if (root.settingsModel) {
            notificationsEnabledCheckbox.checked = root.settingsModel.notificationsEnabled;
            soundEnabledCheckbox.checked = root.settingsModel.soundEnabled;
            desktopNotificationsCheckbox.checked = root.settingsModel.desktopNotifications;
            shortSoundFileField.text = root.settingsModel.shortSoundFile || "short";
            longSoundFileField.text = root.settingsModel.longSoundFile || "long";
            shortSoundFileField.enabled = soundEnabledCheckbox.checked;
            longSoundFileField.enabled = soundEnabledCheckbox.checked;
        }
    }
}
