/**
 * SummaryAndDescriptionBlock.qml
 *
 * Agrupa SummaryField, DescriptionField e botões Voice/IA (spec summary-description-ai-voice).
 * Reutilizável em criação e edição.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami
import "."

ColumnLayout {
    id: root

    property var workItemModel: null
    property string mode: "create"
    property bool enabled: true
    property var jiraService: null
    property var clipboardHelper: null
    property var voiceInputService: null
    property bool showVoiceCreateButton: true
    property bool showExpandWithAIButton: true
    property bool requestSummaryFocus: false
    property bool summaryRequired: true
    property var applicationWindow: null

    property bool _descriptionEditMode: true
    /** Espelho local de voiceInputService.isExpanding, atualizado por signal. */
    property bool _serviceExpanding: false
    readonly property bool _fieldsEnabled: root.enabled && !root._serviceExpanding

    signal openVoiceRequested()

    spacing: Kirigami.Units.largeSpacing

    onVoiceInputServiceChanged: {
        root._serviceExpanding = (root.voiceInputService && root.voiceInputService.isExpanding) || false
    }
    Component.onCompleted: {
        root._serviceExpanding = (root.voiceInputService && root.voiceInputService.isExpanding) || false
    }

    Connections {
        target: root.voiceInputService || null
        function onExpandingChanged() {
            if (root.voiceInputService)
                root._serviceExpanding = !!root.voiceInputService.isExpanding
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: Kirigami.Units.largeSpacing

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Controls.Label {
                    text: qsTr("Summary:")
                    font.bold: true
                    Layout.fillWidth: true
                }

                Controls.ToolButton {
                    visible: root.showVoiceCreateButton && root.voiceInputService !== null && root.voiceInputService.isAvailable()
                    icon.name: "audio-input-microphone"
                    text: qsTr("Criar por voz")
                    onClicked: root.openVoiceRequested()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                SummaryField {
                    id: summaryField
                    Layout.fillWidth: true
                    text: root.workItemModel ? root.workItemModel.summary || "" : ""
                    onFieldTextChanged: function (newText) {
                        if (root.workItemModel) root.workItemModel.summary = newText
                    }
                    enabled: root._fieldsEnabled
                    opacity: root._fieldsEnabled ? 1 : 0.6
                    showLabel: false
                    maximumLength: 255
                    required: root.summaryRequired
                    requestFocusOnLoad: root.requestSummaryFocus
                }

                Controls.ToolButton {
                    visible: root.showExpandWithAIButton && root.voiceInputService !== null && root.voiceInputService.isAvailable()
                    icon.name: "tools-wizard"
                    text: qsTr("Expandir com IA")
                    enabled: root._fieldsEnabled && root.workItemModel && (root.workItemModel.summary || root.workItemModel.description)
                    onClicked: {
                        if (root.voiceInputService && root.workItemModel) {
                            var forEdit = (root.mode === "edit")
                            root.voiceInputService.expandFromSummaryAndDescription(
                                root.workItemModel.summary || "",
                                root.workItemModel.description || "",
                                forEdit
                            )
                        }
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Kirigami.Units.smallSpacing

            DescriptionField {
                id: descriptionField
                Layout.fillWidth: true
                Layout.fillHeight: true
                text: root.workItemModel ? root.workItemModel.description || "" : ""
                onFieldTextChanged: function (newText) {
                    if (root.workItemModel) root.workItemModel.description = newText
                }
                enabled: root._fieldsEnabled
                opacity: root._fieldsEnabled ? 1 : 0.6
                editMode: root._descriptionEditMode
                onFieldEditModeChanged: function (editMode) {
                    root._descriptionEditMode = editMode
                }
                showEditPreviewToggle: true
                showAttachmentsButton: true
                mode: root.mode
                jiraService: root.jiraService
                clipboardHelper: root.clipboardHelper
                workItemModel: root.workItemModel
                applicationWindow: root.applicationWindow
            }
        }
    }
}
