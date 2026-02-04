/**
 * VoiceInputDialog.qml
 *
 * Diálogo para criar tarefa por voz: gravar áudio, transcrição e processar com IA.
 * Só deve ser aberto quando voiceInputService !== null && voiceInputService.isAvailable().
 */
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Controls.Dialog {
    id: root

    parent: Controls.Overlay.overlay
    anchors.centerIn: parent

    title: qsTr("Criar tarefa por voz")
    modal: true
    standardButtons: Controls.Dialog.Cancel

    property real recordingSeconds: 0
    property bool isRecording: false
    property string transcriptionText: ""
    property var _voiceSvc: (typeof voiceInputService !== "undefined" ? voiceInputService : null) // qmllint disable unqualified

    signal fieldsFilled()
    signal errorMessage(string message)

    onOpened: {
        recordingSeconds = 0
        transcriptionText = ""
    }

    Connections {
        target: root._voiceSvc || null
        function onRecordingStarted() {
            root.isRecording = true
            root.recordingSeconds = 0
        }
        function onRecordingStopped() {
            root.isRecording = false
        }
        function onRecordingProgress(seconds) {
            root.recordingSeconds = seconds
        }
        function onTranscriptionReady(text) {
            root.transcriptionText = text || ""
        }
        function onFieldsFilled() {
            root.fieldsFilled()
            root.close()
        }
        function onError(message) {
            root.errorMessage(message || "")
        }
    }

    contentItem: Item {
        implicitWidth: 480
        implicitHeight: 320

        ColumnLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.largeSpacing

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Rectangle {
                    implicitWidth: 16
                    implicitHeight: 16
                    radius: 8
                    color: root.isRecording ? "red" : Kirigami.Theme.neutralBackgroundColor
                    opacity: root.isRecording ? 1.0 : 0.5

                    SequentialAnimation on opacity {
                        running: root.isRecording
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.3; duration: 500 }
                        NumberAnimation { to: 1.0; duration: 500 }
                    }
                }

                Controls.Label {
                    text: root.isRecording
                        ? qsTr("Gravando… (%1)").arg(Math.floor(root.recordingSeconds))
                        : qsTr("Pronto para gravar")
                }
            }

            Controls.Label {
                Layout.fillWidth: true
                text: qsTr("Transcrição:")
                font.bold: true
            }

            Controls.ScrollView {
                Layout.fillWidth: true
                Layout.preferredHeight: 140
                clip: true
                contentWidth: availableWidth

                Controls.TextArea {
                    id: transcriptionArea
                    wrapMode: Controls.TextArea.Wrap
                    placeholderText: qsTr("Transcrição aparecerá aqui após gravar…")
                    text: root.transcriptionText
                    onTextChanged: function() {
                        if (root.transcriptionText !== text) {
                            root.transcriptionText = text
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Controls.Button {
                    text: root.isRecording ? qsTr("Parar") : qsTr("Gravar")
                    icon.name: root.isRecording ? "media-playback-pause" : "audio-input-microphone"
                    onClicked: {
                        if (root._voiceSvc) {
                            if (root.isRecording) {
                                root._voiceSvc.stopRecording()
                            } else {
                                root._voiceSvc.startRecording()
                            }
                        }
                    }
                }

                Controls.Button {
                    text: qsTr("Processar com IA")
                    icon.name: "edit-find"
                    enabled: root.transcriptionText.length > 0
                    onClicked: {
                        if (root._voiceSvc && root.transcriptionText.length > 0) {
                            root._voiceSvc.processTranscription(root.transcriptionText)
                        }
                    }
                }
            }
        }
    }
}
