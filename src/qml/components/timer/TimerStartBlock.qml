/**
 * TimerStartBlock.qml
 *
 * Bloco para iniciar novo timer: campo Issue Key e botão Iniciar Timer.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: root

    property var timerService: null
    property var timerModel: null
    property string selectedIssueKey: ""
    property bool hasActiveTimer: false

    visible: !hasActiveTimer

    Controls.Label {
        text: qsTr("Iniciar Timer")
        font.bold: true
        font.pointSize: Kirigami.Theme.defaultFont.pointSize + 1
        Layout.fillWidth: true
    }

    Controls.Label {
        text: qsTr("Issue Key:")
        font.bold: true
        Layout.fillWidth: true
    }

    Controls.TextField {
        id: issueKeyField
        Layout.fillWidth: true
        placeholderText: qsTr("PLATFORM-123")
        text: root.selectedIssueKey
        onTextChanged: root.selectedIssueKey = text.trim()
    }

    Controls.Button {
        id: startTimerButton
        text: qsTr("Iniciar Timer")
        icon.name: "media-playback-start"
        Layout.fillWidth: true
        enabled: issueKeyField.text.trim().length > 0 && timerService && timerModel
        onClicked: {
            var issueKey = issueKeyField.text.trim();
            if (!timerService || !timerModel || issueKey.length === 0) return;
            timerService.start(issueKey);
        }
    }
}
