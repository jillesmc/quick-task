/**
 * VoiceInputSettingsBlock.qml
 *
 * Bloco de configurações de entrada por voz: enabled, localai_base_url,
 * localai_whisper_model, localai_llm_model, language, max_recording_seconds,
 * keyboard_shortcut, auto_process_after_stop.
 * Todos os controles ficam desabilitados quando voiceInputAvailable é false
 * (áudio não disponível ou LocalAI no host inacessível).
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

Rectangle {
    id: root

    property var settingsModel: null
    property bool voiceInputAvailable: false

    implicitHeight: voiceBlock.implicitHeight + (Kirigami.Units.largeSpacing * 2)

    color: Kirigami.Theme.backgroundColor || "#f0f0f0"
    border.color: Kirigami.Theme.textColor || "#d0d0d0"
    border.width: 1
    radius: Kirigami.Units.smallSpacing

    ColumnLayout {
        id: voiceBlock
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.mediumSpacing

        Kirigami.Heading {
            text: qsTr("Entrada por voz")
            level: 3
            Layout.fillWidth: true
        }

        Controls.Label {
            visible: !root.voiceInputAvailable
            text: qsTr("Áudio ou LocalAI não disponível. Instale conforme docs/voice-input-setup.md e tenha o LocalAI rodando no host.")
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            color: Kirigami.Theme.neutralTextColor
        }

        Controls.CheckBox {
            id: voiceEnabledCheckbox
            text: qsTr("Habilitar entrada por voz")
            Layout.fillWidth: true
            enabled: root.voiceInputAvailable
            checked: false
            onCheckedChanged: {
                if (root.settingsModel) {
                    root.settingsModel.voiceInputEnabled = checked;
                }
                localaiBaseUrlField.enabled = checked && root.voiceInputAvailable;
                localaiWhisperField.enabled = checked && root.voiceInputAvailable;
                localaiLlmField.enabled = checked && root.voiceInputAvailable;
                taskPromptArea.enabled = checked && root.voiceInputAvailable;
                commentPromptArea.enabled = checked && root.voiceInputAvailable;
                voiceLanguageField.enabled = checked && root.voiceInputAvailable;
                maxRecordingSpinBox.enabled = checked && root.voiceInputAvailable;
                shortcutField.enabled = checked && root.voiceInputAvailable;
                autoProcessCheckbox.enabled = checked && root.voiceInputAvailable;
            }
        }

        Controls.Label {
            text: qsTr("URL base LocalAI:")
            font.bold: true
            Layout.fillWidth: true
            enabled: root.voiceInputAvailable
        }

        Controls.TextField {
            id: localaiBaseUrlField
            Layout.fillWidth: true
            enabled: root.voiceInputAvailable && voiceEnabledCheckbox.checked
            placeholderText: "http://localhost:8080"
            onTextChanged: {
                if (root.settingsModel && text.length > 0) {
                    root.settingsModel.localaiBaseUrl = text.trim();
                }
            }
        }

        Controls.Label {
            text: qsTr("Modelo Whisper (LocalAI):")
            font.bold: true
            Layout.fillWidth: true
            enabled: root.voiceInputAvailable
        }

        Controls.TextField {
            id: localaiWhisperField
            Layout.fillWidth: true
            enabled: root.voiceInputAvailable && voiceEnabledCheckbox.checked
            placeholderText: "whisper-1"
            onTextChanged: {
                if (root.settingsModel && text.length > 0) {
                    root.settingsModel.localaiWhisperModel = text.trim();
                }
            }
        }

        Controls.Label {
            text: qsTr("Modelo LLM (LocalAI):")
            font.bold: true
            Layout.fillWidth: true
            enabled: root.voiceInputAvailable
        }

        Controls.TextField {
            id: localaiLlmField
            Layout.fillWidth: true
            enabled: root.voiceInputAvailable && voiceEnabledCheckbox.checked
            placeholderText: "qwen2.5:3b"
            onTextChanged: {
                if (root.settingsModel && text.length > 0) {
                    root.settingsModel.localaiLlmModel = text.trim();
                }
            }
        }

        Controls.Label {
            text: qsTr("Pré-prompt para task (description):")
            font.bold: true
            Layout.fillWidth: true
            enabled: root.voiceInputAvailable
            wrapMode: Text.WordWrap
        }

        Controls.ScrollView {
            Layout.fillWidth: true
            Layout.preferredHeight: 80
            clip: true
            contentWidth: availableWidth
            Controls.TextArea {
                id: taskPromptArea
                wrapMode: Controls.TextArea.Wrap
                placeholderText: qsTr("Instrução de sistema para extração de task (summary, description, tipo_atividade). Define como a description deve ser estruturada.")
                enabled: root.voiceInputAvailable && voiceEnabledCheckbox.checked
                onTextChanged: {
                    if (root.settingsModel)
                        root.settingsModel.localaiTaskSystemPrompt = text;
                }
            }
        }

        Controls.Label {
            text: qsTr("Pré-prompt para melhoria de comentários:")
            font.bold: true
            Layout.fillWidth: true
            enabled: root.voiceInputAvailable
            wrapMode: Text.WordWrap
        }

        Controls.ScrollView {
            Layout.fillWidth: true
            Layout.preferredHeight: 80
            clip: true
            contentWidth: availableWidth
            Controls.TextArea {
                id: commentPromptArea
                wrapMode: Controls.TextArea.Wrap
                placeholderText: qsTr("Instrução para o modelo ao melhorar texto de comentários (apenas expandir e estruturar).")
                enabled: root.voiceInputAvailable && voiceEnabledCheckbox.checked
                onTextChanged: {
                    if (root.settingsModel)
                        root.settingsModel.localaiCommentImprovementPrompt = text;
                }
            }
        }

        Controls.Label {
            text: qsTr("Idioma (código, ex: pt):")
            font.bold: true
            Layout.fillWidth: true
            enabled: root.voiceInputAvailable
        }

        Controls.TextField {
            id: voiceLanguageField
            Layout.fillWidth: true
            enabled: root.voiceInputAvailable && voiceEnabledCheckbox.checked
            placeholderText: "pt"
            onTextChanged: {
                if (root.settingsModel && text.length > 0) {
                    root.settingsModel.voiceInputLanguage = text.trim();
                }
            }
        }

        Controls.Label {
            text: qsTr("Tempo máximo de gravação (segundos):")
            font.bold: true
            Layout.fillWidth: true
            enabled: root.voiceInputAvailable
        }

        Controls.SpinBox {
            id: maxRecordingSpinBox
            from: 30
            to: 300
            value: 120
            stepSize: 30
            enabled: root.voiceInputAvailable && voiceEnabledCheckbox.checked
            onValueChanged: {
                if (root.settingsModel) {
                    root.settingsModel.voiceInputMaxRecordingSeconds = value;
                }
            }
        }

        Controls.Label {
            text: qsTr("Atalho de teclado:")
            font.bold: true
            Layout.fillWidth: true
            enabled: root.voiceInputAvailable
        }

        Controls.TextField {
            id: shortcutField
            Layout.fillWidth: true
            enabled: root.voiceInputAvailable && voiceEnabledCheckbox.checked
            placeholderText: "Ctrl+Shift+V"
            onTextChanged: {
                if (root.settingsModel && text.length > 0) {
                    root.settingsModel.voiceInputKeyboardShortcut = text.trim();
                }
            }
        }

        Controls.CheckBox {
            id: autoProcessCheckbox
            text: qsTr("Processar automaticamente ao parar gravação")
            Layout.fillWidth: true
            enabled: root.voiceInputAvailable && voiceEnabledCheckbox.checked
            checked: false
            onCheckedChanged: {
                if (root.settingsModel) {
                    root.settingsModel.voiceInputAutoProcessAfterStop = checked;
                }
            }
        }
    }

    Component.onCompleted: {
        if (root.settingsModel) {
            voiceEnabledCheckbox.checked = root.settingsModel.voiceInputEnabled;
            localaiBaseUrlField.text = root.settingsModel.localaiBaseUrl || "http://localhost:8080";
            localaiWhisperField.text = root.settingsModel.localaiWhisperModel || "whisper-1";
            localaiLlmField.text = root.settingsModel.localaiLlmModel || "qwen2.5:3b";
            taskPromptArea.text = root.settingsModel.localaiTaskSystemPrompt || "";
            commentPromptArea.text = root.settingsModel.localaiCommentImprovementPrompt || "";
            voiceLanguageField.text = root.settingsModel.voiceInputLanguage || "pt";
            maxRecordingSpinBox.value = root.settingsModel.voiceInputMaxRecordingSeconds;
            shortcutField.text = root.settingsModel.voiceInputKeyboardShortcut || "Ctrl+Shift+V";
            autoProcessCheckbox.checked = root.settingsModel.voiceInputAutoProcessAfterStop;
        }
        localaiBaseUrlField.enabled = root.voiceInputAvailable && voiceEnabledCheckbox.checked;
        localaiWhisperField.enabled = root.voiceInputAvailable && voiceEnabledCheckbox.checked;
        localaiLlmField.enabled = root.voiceInputAvailable && voiceEnabledCheckbox.checked;
        taskPromptArea.enabled = root.voiceInputAvailable && voiceEnabledCheckbox.checked;
        commentPromptArea.enabled = root.voiceInputAvailable && voiceEnabledCheckbox.checked;
        voiceLanguageField.enabled = root.voiceInputAvailable && voiceEnabledCheckbox.checked;
        maxRecordingSpinBox.enabled = root.voiceInputAvailable && voiceEnabledCheckbox.checked;
        shortcutField.enabled = root.voiceInputAvailable && voiceEnabledCheckbox.checked;
        autoProcessCheckbox.enabled = root.voiceInputAvailable && voiceEnabledCheckbox.checked;
    }

    Connections {
        target: root.settingsModel || null
        enabled: root.settingsModel !== null
        function onVoiceInputEnabledChanged() {
            if (root.settingsModel) {
                voiceEnabledCheckbox.checked = root.settingsModel.voiceInputEnabled;
            }
        }
        function onLocalaiBaseUrlChanged() {
            if (root.settingsModel) {
                localaiBaseUrlField.text = root.settingsModel.localaiBaseUrl || "http://localhost:8080";
            }
        }
        function onLocalaiWhisperModelChanged() {
            if (root.settingsModel) {
                localaiWhisperField.text = root.settingsModel.localaiWhisperModel || "whisper-1";
            }
        }
        function onLocalaiLlmModelChanged() {
            if (root.settingsModel) {
                localaiLlmField.text = root.settingsModel.localaiLlmModel || "qwen2.5:3b";
            }
        }
        function onLocalaiTaskSystemPromptChanged() {
            if (root.settingsModel && taskPromptArea.text !== root.settingsModel.localaiTaskSystemPrompt) {
                taskPromptArea.text = root.settingsModel.localaiTaskSystemPrompt || "";
            }
        }
        function onLocalaiCommentImprovementPromptChanged() {
            if (root.settingsModel && commentPromptArea.text !== root.settingsModel.localaiCommentImprovementPrompt) {
                commentPromptArea.text = root.settingsModel.localaiCommentImprovementPrompt || "";
            }
        }
        function onVoiceInputLanguageChanged() {
            if (root.settingsModel) {
                voiceLanguageField.text = root.settingsModel.voiceInputLanguage || "pt";
            }
        }
        function onVoiceInputMaxRecordingSecondsChanged() {
            if (root.settingsModel) {
                maxRecordingSpinBox.value = root.settingsModel.voiceInputMaxRecordingSeconds;
            }
        }
        function onVoiceInputKeyboardShortcutChanged() {
            if (root.settingsModel) {
                shortcutField.text = root.settingsModel.voiceInputKeyboardShortcut || "Ctrl+Shift+V";
            }
        }
        function onVoiceInputAutoProcessAfterStopChanged() {
            if (root.settingsModel) {
                autoProcessCheckbox.checked = root.settingsModel.voiceInputAutoProcessAfterStop;
            }
        }
    }
}
