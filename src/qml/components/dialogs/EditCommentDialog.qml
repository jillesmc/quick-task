/**
 * EditCommentDialog.qml
 * Diálogo para editar o texto de um comentário (markdown). TextArea multilinha, OK/Cancelar.
 * Emite accepted(commentId, newBody) ao confirmar.
 */
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Controls.Dialog {
    id: dialog

    title: qsTr("Editar comentário")
    modal: true
    standardButtons: Controls.Dialog.NoButton

    property string commentId: ""
    property string initialBody: ""
    property string issueKey: ""
    property var jiraService: null
    property var clipboardHelper: null
    property var voiceInputService: null
    property bool voiceInputAvailable: false
    property bool improvingComment: false

    signal accepted(string commentId, string newBody)

    implicitWidth: 480
    implicitHeight: 320
    width: implicitWidth
    height: implicitHeight

    function openWith(commentIdValue, body) {
        commentId = commentIdValue || ""
        initialBody = body || ""
        commentTextArea.text = initialBody
        open()
    }

    function centerDialog() {
        if (parent && width > 0 && height > 0 && parent.width > 0 && parent.height > 0) {
            x = Math.max(0, (parent.width - width) / 2)
            y = Math.max(0, (parent.height - height) / 2)
        }
    }

    Component.onCompleted: Qt.callLater(centerDialog)
    onWidthChanged: Qt.callLater(centerDialog)
    onHeightChanged: Qt.callLater(centerDialog)

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.mediumSpacing

        Controls.ScrollView {
            id: commentScrollView
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: availableWidth

            Item {
                width: commentScrollView.availableWidth
                height: commentTextArea.implicitHeight

                DropArea {
                    anchors.fill: parent
                    onDropped: function(drop) {
                        if (!dialog.jiraService || !dialog.issueKey || !drop.urls || drop.urls.length === 0) return
                        var extList = ["png", "jpg", "jpeg", "gif", "webp"]
                        for (var i = 0; i < drop.urls.length; i++) {
                            var urlStr = drop.urls[i].toString()
                            var path = urlStr.replace(/^file:\/\//, "")
                            var filename = path.split("/").pop() || path.split("\\").pop() || "file"
                            var ext = filename.indexOf(".") >= 0 ? filename.split(".").pop().toLowerCase() : ""
                            if (extList.indexOf(ext) < 0) continue
                            dialog.jiraService.uploadAttachment(dialog.issueKey, path)
                        }
                    }
                }

                Controls.TextArea {
                    id: commentTextArea
                    width: parent.width
                    wrapMode: Controls.TextArea.Wrap
                    placeholderText: qsTr("Digite o comentário (Markdown suportado). Arraste imagens ou use Ctrl+V para colar.")

                    Keys.onPressed: function(event) {
                        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V) {
                            if (dialog.clipboardHelper && dialog.clipboardHelper.hasClipboardImage() && dialog.jiraService && dialog.issueKey) {
                                var tempPath = dialog.clipboardHelper.getClipboardImageAsTempFile()
                                if (tempPath) {
                                    dialog.jiraService.uploadAttachment(dialog.issueKey, tempPath)
                                    event.accepted = true
                                }
                            }
                        }
                    }
                }
            }
        }

        Connections {
            target: dialog.jiraService || null
            function onAttachmentUploaded(uploadedIssueKey, contentUrl, filename) {
                if (uploadedIssueKey === dialog.issueKey && contentUrl && filename) {
                    var markdown = "![" + filename + "](" + contentUrl + ")"
                    commentTextArea.insert(commentTextArea.cursorPosition, markdown)
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignRight
            spacing: Kirigami.Units.mediumSpacing

            Controls.Button {
                text: dialog.improvingComment ? qsTr("A melhorar…") : qsTr("Melhorar com IA")
                visible: dialog.voiceInputAvailable
                enabled: !dialog.improvingComment && (commentTextArea.text || "").trim() !== ""
                onClicked: {
                    if (dialog.voiceInputService && (commentTextArea.text || "").trim() !== "") {
                        dialog.improvingComment = true
                        dialog.voiceInputService.improveCommentText(commentTextArea.text)
                    }
                }
            }
            Item { Layout.fillWidth: true }
            Controls.Button {
                text: qsTr("Cancelar")
                onClicked: dialog.close()
            }
            Controls.Button {
                text: qsTr("Salvar")
                onClicked: {
                    dialog.accepted(dialog.commentId, commentTextArea.text || "")
                    dialog.close()
                }
            }
        }
    }

    Connections {
        target: dialog.voiceInputService || null
        enabled: dialog.voiceInputService !== null
        function onCommentTextImproved(text) {
            dialog.improvingComment = false
            if (text)
                commentTextArea.text = text
        }
        function onError(message) {
            dialog.improvingComment = false
        }
    }
}
