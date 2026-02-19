/**
 * EditPreviewContainer.qml
 *
 * Edit/Preview mode container for markdown content. Header with label + EditPreviewToggle,
 * body with TextArea (edit) or rendered Text (preview). Supports drop/paste for images
 * when acceptDrops, jiraService, issueKey and clipboardHelper are provided.
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
    property var clipboardHelper: null
    property bool isEditMode: true

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

    property real _savedScrollPosition: 0

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
                                var extList = ["png", "jpg", "jpeg", "gif", "webp"]
                                for (var i = 0; i < drop.urls.length; i++) {
                                    var urlStr = drop.urls[i].toString()
                                    var path = urlStr.replace(/^file:\/\//, "")
                                    var filename = path.split("/").pop() || path.split("\\").pop() || "file"
                                    var ext = filename.indexOf(".") >= 0 ? filename.split(".").pop().toLowerCase() : ""
                                    if (extList.indexOf(ext) < 0) continue
                                    if (container.issueKey && container.jiraService) {
                                        var pathToUse = (container.clipboardHelper && typeof container.clipboardHelper.copyFileToTemp === "function")
                                            ? container.clipboardHelper.copyFileToTemp(path) : path
                                        if (!pathToUse) pathToUse = path
                                        container.jiraService.uploadAttachment(container.issueKey, pathToUse)
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
                                                container.jiraService.uploadAttachment(container.issueKey, tempPath)
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
        function onAttachmentUploaded(uploadedIssueKey, contentUrl, filename) {
            if (uploadedIssueKey === container.issueKey && contentUrl && filename && editTextArea) {
                var markdown = "![" + filename + "](" + contentUrl + ")"
                editTextArea.insert(editTextArea.cursorPosition, markdown)
                container.contentEdited(editTextArea.text)
            }
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
