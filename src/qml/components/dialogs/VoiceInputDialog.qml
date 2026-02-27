/**
 * VoiceInputDialog.qml
 *
 * Diálogo para criar tarefa por voz: gravar áudio, transcrição e processar com IA.
 * O serviço de voz deve ser passado pelo pai (voiceInputService); não usa contexto global.
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
    closePolicy: Controls.Popup.CloseOnEscape
    standardButtons: Controls.Dialog.Cancel

    /** Serviço de voz injetado pelo pai (aba 0/1: voiceInputService; aba 7/8: voiceTranscriptionService). */
    property var voiceInputService: null
    /** SettingsModel (opcional); usado para esconder o botão "Enriquecer com IA" quando processamento automático está ativo. */
    property var settingsModel: null
    readonly property bool _enrichButtonVisible: !(settingsModel && settingsModel.voiceInputAutoProcessAfterStop)

    property real recordingSeconds: 0
    property bool isRecording: false
    property bool _isTranscribing: false
    property string transcriptionText: ""

    signal fieldsFilled()
    signal errorMessage(string message)

    onOpened: {
        recordingSeconds = 0
        transcriptionText = ""
        _isTranscribing = false
    }

    Connections {
        target: root.voiceInputService || null
        function onRecordingStarted() {
            root.isRecording = true
            root.recordingSeconds = 0
        }
        function onRecordingStopped() {
            root.isRecording = false
            root._isTranscribing = true
        }
        function onRecordingProgress(seconds) {
            root.recordingSeconds = seconds
        }
        function onTranscriptionReady(text) {
            root._isTranscribing = false
            root.transcriptionText = text || ""
            if (root.settingsModel && root.settingsModel.voiceInputAutoProcessAfterStop) {
                root.close()
            }
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
                    text: root._isTranscribing
                        ? qsTr("Transcrevendo o áudio...")
                        : (root.isRecording
                            ? qsTr("Gravando… (%1)").arg(Math.floor(root.recordingSeconds))
                            : qsTr("Pronto para gravar"))
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
                        if (root.voiceInputService) {
                            if (root.isRecording) {
                                root.voiceInputService.stopRecording()
                            } else {
                                root.voiceInputService.startRecording()
                            }
                        }
                    }
                }

                Controls.Button {
                    text: qsTr("Enriquecer com IA")
                    icon.name: "edit-find"
                    visible: root._enrichButtonVisible
                    enabled: root.transcriptionText.length > 0
                    onClicked: {
                        if (root.voiceInputService && root.transcriptionText.length > 0) {
                            root.voiceInputService.processTranscription(root.transcriptionText)
                        }
                    }
                }
            }
        }
    }
}
