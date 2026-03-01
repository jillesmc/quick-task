/**
 * DescriptionField.qml
 *
 * Campo de descrição em Markdown com edição/preview, DropArea e anexos pendentes (spec §1.4).
 * Reutilizável em criação e edição; preview único com Markdown + imagens Jira.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami
import "../controls"

ColumnLayout {
    id: root

    property string text: ""
    property bool enabled: true
    property string labelText: qsTr("Description:")
    property string placeholderText: qsTr("Arraste ficheiros ou use Ctrl+V para colar imagem; imagens têm preview, outros ficheiros ficam como link.")
    property bool editMode: true
    property bool showEditPreviewToggle: true
    property bool showAttachmentsButton: true
    property string mode: "create"
    property var jiraService: null
    property var clipboardHelper: null
    property var workItemModel: null
    property var applicationWindow: null

    signal fieldTextChanged(string newText)
    signal fieldEditModeChanged(bool editMode)

    property int _placeholderCounter: 0

    function _openEmbedDialog(filePath, filename) {
        if (!filePath || !root.workItemModel)
            return;
        var comp = Qt.createComponent("../dialogs/AttachmentEmbedPreviewDialog.qml");
        var win = root.applicationWindow || root.parent || root;
        if (comp.status !== Component.Ready) {
            if (comp.status === Component.Error) {
                console.error("DescriptionField: AttachmentEmbedPreviewDialog error:", comp.errorString());
            }
            comp.statusChanged.connect(function () {
                if (comp.status === Component.Ready)
                    root._createAndOpenEmbedDialog(comp, win, filePath, filename);
            });
            return;
        }
        root._createAndOpenEmbedDialog(comp, win, filePath, filename);
    }

    function _createAndOpenEmbedDialog(comp, parent, filePath, filename) {
        var dlg = comp.createObject(parent);
        if (!dlg)
            return;
        dlg.filePath = filePath;
        dlg.showPositionOptions = true;
        dlg.defaultDisplayWidth = (root.jiraService && typeof root.jiraService.getEmbedMaxDisplayWidth === "function") ? root.jiraService.getEmbedMaxDisplayWidth() : 760;
        dlg.applicationWindow = root.applicationWindow;
        dlg.clipboardHelper = root.clipboardHelper;
        dlg.acceptedEmbed.connect(function (layout, position, displayWidth) {
            root._placeholderCounter += 1;
            var placeholderId = "p" + root._placeholderCounter;
            var list = root.workItemModel.pendingAttachments || [];
            list.push({
                path: filePath,
                filename: filename,
                placeholderId: placeholderId,
                layout: layout,
                position: position,
                displayWidth: displayWidth
            });
            root.workItemModel.pendingAttachments = list;
            var markdown = "![" + filename + "](pending:" + placeholderId + ")";
            var pos = (position === "start") ? 0 : descriptionTextArea.text.length;
            descriptionTextArea.insert(pos, markdown);
            var newText = descriptionTextArea.text;
            if (root.workItemModel)
                root.workItemModel.description = newText;
            root.fieldTextChanged(newText);
        });
        dlg.acceptedAttachOnly.connect(function () {
            var list = root.workItemModel.pendingAttachments || [];
            list.push({
                path: filePath,
                filename: filename
            });
            root.workItemModel.pendingAttachments = list;
        });
        dlg.rejected.connect(function () {});
        dlg.closed.connect(function () {
            dlg.destroy();
        });
        dlg.open();
    }

    function _addNonImageAttachment(filePath, filename) {
        if (!root.workItemModel)
            return;
        root._placeholderCounter += 1;
        var placeholderId = "p" + root._placeholderCounter;
        var list = root.workItemModel.pendingAttachments || [];
        list.push({
            path: filePath,
            filename: filename,
            placeholderId: placeholderId
        });
        root.workItemModel.pendingAttachments = list;
        var markdown = "[" + filename + "](pending:" + placeholderId + ")";
        var pos = descriptionTextArea.cursorPosition >= 0 ? descriptionTextArea.cursorPosition : descriptionTextArea.text.length;
        descriptionTextArea.insert(pos, markdown);
        var newText = descriptionTextArea.text;
        root.workItemModel.description = newText;
        root.fieldTextChanged(newText);
    }

    function _openAttachmentsPopover(button) {
        if (!button || !root.workItemModel)
            return;
        var comp = Qt.createComponent("../dialogs/DescriptionAttachmentsPopover.qml");
        if (comp.status !== Component.Ready) {
            if (comp.status === Component.Error) {
                console.error("DescriptionField: DescriptionAttachmentsPopover error:", comp.errorString());
            }
            comp.statusChanged.connect(function () {
                if (comp.status === Component.Ready)
                    root._openAttachmentsPopover(button);
            });
            return;
        }
        var popover = comp.createObject(button);
        if (!popover)
            return;
        popover.x = 0;
        popover.y = button.height + 2;
        popover.mode = root.mode;
        popover.issueModel = root.workItemModel;
        popover.closed.connect(function () {
            popover.destroy();
        });
        popover.open();
    }

    spacing: Kirigami.Units.smallSpacing

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        Controls.Label {
            text: root.labelText
            font.bold: true
            Layout.fillWidth: true
        }

        EditPreviewToggle {
            visible: root.showEditPreviewToggle
            isEditMode: root.editMode
            onModeChanged: function (editMode) {
                root.editMode = editMode;
                root.fieldEditModeChanged(editMode);
            }
        }

        Controls.ToolButton {
            id: attachmentListButton
            visible: root.showAttachmentsButton
            icon.name: "mail-attachment"
            text: qsTr("Anexos na descrição")
            display: Controls.AbstractButton.IconOnly
            onClicked: root._openAttachmentsPopover(attachmentListButton)
        }
    }

    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 120

        StackLayout {
            anchors.fill: parent
            currentIndex: root.editMode ? 0 : 1

            DropArea {
                enabled: root.enabled
                onDropped: function (drop) {
                    if (!drop.urls || drop.urls.length === 0 || !root.workItemModel)
                        return;
                    var extList = (root.jiraService && typeof root.jiraService.getAllowedAttachmentExtensions === "function") ? root.jiraService.getAllowedAttachmentExtensions() : [];
                    var imageExtList = (root.jiraService && typeof root.jiraService.getAllowedImageExtensions === "function") ? root.jiraService.getAllowedImageExtensions() : [];
                    for (var i = 0; i < drop.urls.length; i++) {
                        var urlStr = drop.urls[i].toString();
                        var path = urlStr.replace(/^file:\/\//, "");
                        var filename = path.split("/").pop() || path.split("\\").pop() || "file";
                        var ext = filename.indexOf(".") >= 0 ? filename.split(".").pop().toLowerCase() : "";
                        if (extList.indexOf(ext) < 0)
                            continue;
                        var pathToUse = (root.clipboardHelper && typeof root.clipboardHelper.copyFileToTemp === "function") ? root.clipboardHelper.copyFileToTemp(path) : path;
                        if (!pathToUse)
                            continue;
                        if (imageExtList.indexOf(ext) >= 0) {
                            root._openEmbedDialog(pathToUse, filename);
                        } else {
                            root._addNonImageAttachment(pathToUse, filename);
                        }
                    }
                }

                Controls.ScrollView {
                    id: descScroll
                    anchors.fill: parent
                    clip: true
                    contentWidth: descriptionTextArea.implicitWidth

                    Controls.TextArea {
                        id: descriptionTextArea
                        width: descScroll.width
                        wrapMode: Controls.TextArea.Wrap
                        enabled: root.enabled
                        placeholderText: root.placeholderText
                        text: root.text
                        onTextChanged: function () {
                            root.fieldTextChanged(descriptionTextArea.text);
                        }
                        Keys.onPressed: function (event) {
                            if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V) {
                                if (!root.clipboardHelper || !root.workItemModel)
                                    return;
                                if (root.clipboardHelper.hasClipboardImage()) {
                                    var tempPath = root.clipboardHelper.getClipboardImageAsTempFile();
                                    if (tempPath) {
                                        root._openEmbedDialog(tempPath, "paste.png");
                                        event.accepted = true;
                                    }
                                }
                            } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_E) {
                                root.editMode = true;
                                event.accepted = true;
                            } else if ((event.modifiers & (Qt.ControlModifier | Qt.ShiftModifier)) === (Qt.ControlModifier | Qt.ShiftModifier) && event.key === Qt.Key_P) {
                                root.editMode = false;
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Escape) {
                                root.editMode = true;
                                event.accepted = true;
                            }
                        }
                    }
                }
            }

            Rectangle {
                focus: !root.editMode
                color: "transparent"
                border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
                border.width: 0.5
                radius: Kirigami.Units.smallSpacing

                Keys.onPressed: function (event) {
                    if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_E) {
                        root.editMode = true;
                        event.accepted = true;
                    } else if ((event.modifiers & (Qt.ControlModifier | Qt.ShiftModifier)) === (Qt.ControlModifier | Qt.ShiftModifier) && event.key === Qt.Key_P) {
                        root.editMode = false;
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Escape) {
                        root.editMode = true;
                        event.accepted = true;
                    }
                }

                Controls.ScrollView {
                    id: previewScroll
                    anchors.fill: parent
                    anchors.margins: 1
                    clip: true
                    contentWidth: availableWidth

                    Item {
                        width: previewScroll.availableWidth - Kirigami.Units.largeSpacing * 2
                        height: Math.max(richPreview.implicitHeight + Kirigami.Units.largeSpacing * 2, 100)
                        x: Kirigami.Units.largeSpacing

                        RichTextWithJiraImages {
                            id: richPreview
                            width: parent.width - Kirigami.Units.largeSpacing * 2
                            sourceText: root.text || ""
                            jiraService: root.jiraService
                            y: Kirigami.Units.smallSpacing
                        }
                    }
                }
            }
        }
    }
}
