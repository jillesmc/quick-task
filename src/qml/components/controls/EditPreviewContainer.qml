/**
 * EditPreviewContainer.qml
 *
 * Edit/Preview mode container for markdown content. Header with label + EditPreviewToggle,
 * body with TextArea (edit) or rendered Text (preview). Supports drop/paste for images
 * when acceptDrops, jiraService, issueKey and clipboardHelper are provided.
 * Opens AttachmentEmbedPreviewDialog before upload (edit flow) or emits signals (create flow).
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: container

    property string content: ""
    /** Emitted when content changes. Use onContentEdited (contentChanged conflicts with property). */
    signal contentEdited(string newContent)
    property string label: qsTr("Description")
    property bool showLabel: true
    property string placeholderText: ""
    property bool acceptDrops: false
    property var jiraService: null
    property string issueKey: ""
    property var applicationWindow: null
    property var clipboardHelper: null
    property bool isEditMode: true
    /** "description" | "comment" — target do embed; usado para filtrar attachmentUploaded e passar ao uploadAttachment */
    property string embedTarget: "comment"

    /** Emitido quando em modo create (sem issueKey) e usuário faz drop de arquivo. Parent cria placeholder e chama insertPlaceholderAtCursor. */
    signal fileDroppedForPlaceholder(string path, string filename)
    /** Emitido quando em modo create e usuário cola imagem (Ctrl+V). Parent trata e chama insertPlaceholderAtCursor. */
    signal pasteRequestedForPlaceholder()
    /** Insere ![filename](pending:id) na posição do cursor. Usado pelo parent após fileDroppedForPlaceholder ou pasteRequestedForPlaceholder. */
    function insertPlaceholderAtCursor(filename, placeholderId) {
        var markdown = "![" + filename + "](pending:" + placeholderId + ")"
        editTextArea.insert(editTextArea.cursorPosition, markdown)
        contentEdited(editTextArea.text)
    }
    /** Insere [filename](pending:id) na posição do cursor (link, não imagem). */
    function insertLinkPlaceholderAtCursor(filename, placeholderId) {
        var markdown = "[" + filename + "](pending:" + placeholderId + ")"
        editTextArea.insert(editTextArea.cursorPosition, markdown)
        contentEdited(editTextArea.text)
    }

    property real _savedScrollPosition: 0
    property bool _pendingAttachOnly: false
    property bool _pendingInsertAsLink: false
    property int _pendingEmbedDisplayWidth: 760

    function _openEmbedDialogEditFlow(filePath, filename) {
        if (!filePath || !container.jiraService || !container.issueKey) return
        var comp = Qt.createComponent("../dialogs/AttachmentEmbedPreviewDialog.qml")
        var win = container.applicationWindow || (container.parent && container.parent.parent ? container.parent.parent : container)
        if (comp.status !== Component.Ready) {
            if (comp.status === Component.Error) {
                console.error("EditPreviewContainer: AttachmentEmbedPreviewDialog error:", comp.errorString())
            }
            comp.statusChanged.connect(function () {
                if (comp.status === Component.Ready) {
                    _createAndOpenEmbedDialog(comp, win, filePath, filename)
                }
            })
            return
        }
        _createAndOpenEmbedDialog(comp, win, filePath, filename)
    }

    function _createAndOpenEmbedDialog(comp, parent, filePath, filename) {
        var dlg = comp.createObject(parent)
        if (!dlg) return
        dlg.filePath = filePath
        dlg.showPositionOptions = false
        dlg.defaultDisplayWidth = (container.jiraService && typeof container.jiraService.getEmbedMaxDisplayWidth === "function")
            ? container.jiraService.getEmbedMaxDisplayWidth() : 760
        dlg.applicationWindow = container.applicationWindow
        dlg.clipboardHelper = container.clipboardHelper
        dlg.embedTarget = container.embedTarget
        dlg.acceptedEmbed.connect(function (layout, position, displayWidth) {
            container._pendingAttachOnly = false
            container._pendingEmbedDisplayWidth = displayWidth > 0 ? displayWidth : 760
            container.jiraService.uploadAttachment(container.issueKey, filePath, container.embedTarget)
        })
        dlg.acceptedAttachOnly.connect(function () {
            container._pendingAttachOnly = true
            container.jiraService.uploadAttachment(container.issueKey, filePath, container.embedTarget)
        })
        dlg.rejected.connect(function () {})
        dlg.closed.connect(function () { dlg.destroy() })
        dlg.open()
    }

    spacing: Kirigami.Units.smallSpacing

    // Header: label + EditPreviewToggle
    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        Controls.Label {
            text: container.label
            font.bold: true
            Layout.fillWidth: true
            visible: container.showLabel && container.label !== ""
        }

        EditPreviewToggle {
            id: modeToggle
            isEditMode: container.isEditMode
            onModeChanged: function(editMode) {
                // Save scroll position from the view we're leaving (Flickable contentY ratio)
                // qmllint disable missing-property
                if (editMode && previewScrollView.contentItem) {
                    var pf = previewScrollView.contentItem
                    container._savedScrollPosition = (pf.contentHeight > pf.height)
                        ? pf.contentY / (pf.contentHeight - pf.height) : 0
                } else if (!editMode && editScrollView.contentItem) {
                    var ef = editScrollView.contentItem
                    container._savedScrollPosition = (ef.contentHeight > ef.height)
                        ? ef.contentY / (ef.contentHeight - ef.height) : 0
                }
                container.isEditMode = editMode
                Qt.callLater(function() {
                    if (editMode && editScrollView.contentItem) {
                        var fy = editScrollView.contentItem
                        fy.contentY = container._savedScrollPosition * Math.max(0, fy.contentHeight - fy.height)
                    } else if (!editMode && previewScrollView.contentItem) {
                        var py = previewScrollView.contentItem
                        py.contentY = container._savedScrollPosition * Math.max(0, py.contentHeight - py.height)
                    }
                    if (!editMode) container.forceActiveFocus()
                })
                // qmllint enable missing-property
            }
        }
    }

    // Body: Edit or Preview (preenche espaço disponível; mínimo 80 apenas em contextos com altura fixa)
    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        StackLayout {
            anchors.fill: parent
            currentIndex: container.isEditMode ? 0 : 1

            // Edit mode
            Item {
                id: editPane
                Layout.fillWidth: true
                Layout.fillHeight: true

                Controls.ScrollView {
                    id: editScrollView
                    anchors.fill: parent
                    clip: true
                    contentWidth: availableWidth

                    Item {
                        width: editScrollView.availableWidth
                        height: Math.max(editScrollView.availableHeight, editTextArea.implicitHeight)

                        DropArea {
                            anchors.fill: parent
                            enabled: container.acceptDrops
                            onDropped: function(drop) {
                                if (!drop.urls || drop.urls.length === 0) return
                                var extList = (container.jiraService && typeof container.jiraService.getAllowedAttachmentExtensions === "function")
                                    ? container.jiraService.getAllowedAttachmentExtensions() : []
                                var imageExtList = (container.jiraService && typeof container.jiraService.getAllowedImageExtensions === "function")
                                    ? container.jiraService.getAllowedImageExtensions() : []
                                for (var i = 0; i < drop.urls.length; i++) {
                                    var urlStr = drop.urls[i].toString()
                                    var path = urlStr.replace(/^file:\/\//, "")
                                    var filename = path.split("/").pop() || path.split("\\").pop() || "file"
                                    var ext = filename.indexOf(".") >= 0 ? filename.split(".").pop().toLowerCase() : ""
                                    if (extList.indexOf(ext) < 0) continue
                                    var pathToUse = (container.clipboardHelper && typeof container.clipboardHelper.copyFileToTemp === "function")
                                        ? container.clipboardHelper.copyFileToTemp(path) : path
                                    if (!pathToUse) pathToUse = path
                                    if (container.issueKey && container.jiraService) {
                                        if (imageExtList.indexOf(ext) >= 0) {
                                            container._openEmbedDialogEditFlow(pathToUse, filename)
                                        } else {
                                            container._pendingInsertAsLink = true
                                            container.jiraService.uploadAttachment(container.issueKey, pathToUse, container.embedTarget)
                                        }
                                    } else {
                                        container.fileDroppedForPlaceholder(path, filename)
                                    }
                                }
                            }
                        }

                        Controls.TextArea {
                            id: editTextArea
                            width: parent.width
                            wrapMode: Controls.TextArea.Wrap
                            topPadding: Kirigami.Units.smallSpacing
                            bottomPadding: Kirigami.Units.smallSpacing
                            placeholderText: container.placeholderText
                            text: container.content
                            onTextChanged: container.contentEdited(text)

                            Keys.onPressed: function(event) {
                                if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V) {
                                    if (container.acceptDrops && container.clipboardHelper) {
                                        if (container.issueKey && container.jiraService && container.clipboardHelper.hasClipboardImage()) {
                                            var tempPath = container.clipboardHelper.getClipboardImageAsTempFile()
                                            if (tempPath) {
                                                container._openEmbedDialogEditFlow(tempPath, "paste.png")
                                                event.accepted = true
                                            }
                                        } else if (!container.issueKey && container.clipboardHelper.hasClipboardImage()) {
                                            container.pasteRequestedForPlaceholder()
                                            event.accepted = true
                                        }
                                    }
                                } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_E) {
                                    container.isEditMode = true
                                    event.accepted = true
                                } else if ((event.modifiers & (Qt.ControlModifier | Qt.ShiftModifier)) === (Qt.ControlModifier | Qt.ShiftModifier) && event.key === Qt.Key_P) {
                                    container.isEditMode = false
                                    event.accepted = true
                                } else if (event.key === Qt.Key_Escape) {
                                    container.isEditMode = true
                                    event.accepted = true
                                }
                            }
                        }
                    }
                }
            }

            // Preview mode
            Rectangle {
                id: previewPane
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "transparent"
                border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
                border.width: 0.5
                radius: Kirigami.Units.smallSpacing
                focus: !container.isEditMode

                Keys.onPressed: function(event) {
                    if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_E) {
                        container.isEditMode = true
                        event.accepted = true
                    } else if ((event.modifiers & (Qt.ControlModifier | Qt.ShiftModifier)) === (Qt.ControlModifier | Qt.ShiftModifier) && event.key === Qt.Key_P) {
                        container.isEditMode = false
                        event.accepted = true
                    } else if (event.key === Qt.Key_Escape) {
                        container.isEditMode = true
                        event.accepted = true
                    }
                }

                Controls.ScrollView {
                    id: previewScrollView
                    anchors.fill: parent
                    anchors.margins: 1
                    clip: true
                    contentWidth: availableWidth

                    Item {
                        id: previewContentItem
                        width: previewScrollView.availableWidth
                        height: Math.max(previewScrollView.availableHeight, previewText.implicitHeight)

                        MouseArea {
                            id: previewHoverArea
                            anchors.fill: parent
                            cursorShape: Qt.ForbiddenCursor
                            hoverEnabled: true
                            acceptedButtons: Qt.NoButton
                        }

                        Controls.ToolTip {
                            visible: previewHoverArea.containsMouse
                            text: qsTr("Modo de visualização - clique em Edit para modificar")
                            delay: 500
                        }

                        Text {
                            id: previewText
                            width: parent.width - Kirigami.Units.largeSpacing * 2
                            x: Kirigami.Units.largeSpacing
                            topPadding: Kirigami.Units.smallSpacing
                            bottomPadding: Kirigami.Units.smallSpacing
                            textFormat: Text.RichText
                            color: "#ffffff"
                            // qmllint disable unqualified
                            text: (typeof markdownPreviewRenderer !== "undefined" && markdownPreviewRenderer)
                                ? markdownPreviewRenderer.render(container.content)
                                : container.content
                            wrapMode: Text.Wrap
                            onLinkActivated: function(link) {
                                Qt.openUrlExternally(link)
                            }
                        }
                    }
                }
            }
        }
    }

    Connections {
        target: container.jiraService || null
        function onAttachmentUploaded(uploadedIssueKey, contentUrl, filename, embedTarget) {
            if (uploadedIssueKey !== container.issueKey || !contentUrl || !filename || !editTextArea) return
            if (embedTarget !== container.embedTarget) return
            if (container._pendingAttachOnly) {
                container._pendingAttachOnly = false
                return
            }
            if (container._pendingInsertAsLink) {
                container._pendingInsertAsLink = false
                var linkMarkdown = "[" + filename + "](" + contentUrl + ")"
                editTextArea.insert(editTextArea.cursorPosition, linkMarkdown)
                container.contentEdited(editTextArea.text)
                return
            }
            var w = container._pendingEmbedDisplayWidth > 0 ? container._pendingEmbedDisplayWidth : 760
            var markdown = "![" + filename + "](" + contentUrl + "){: width=\"" + w + "\" }"
            editTextArea.insert(editTextArea.cursorPosition, markdown)
            container.contentEdited(editTextArea.text)
        }
    }

    // Forward Keys when in preview mode (Edit pane has its own Keys.onPressed)
    Keys.onPressed: function(event) {
        if (container.isEditMode) return
        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_E) {
            container.isEditMode = true
            event.accepted = true
        } else if ((event.modifiers & (Qt.ControlModifier | Qt.ShiftModifier)) === (Qt.ControlModifier | Qt.ShiftModifier) && event.key === Qt.Key_P) {
            container.isEditMode = false
            event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
            container.isEditMode = true
            event.accepted = true
        }
    }
}
