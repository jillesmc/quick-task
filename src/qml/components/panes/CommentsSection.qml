/**
 * CommentsSection.qml
 *
 * Seção de comentários da issue: botão "Carregar comentários" ou lista de comentários
 * com Editar/Excluir para os próprios, e área "Adicionar comentário".
 */
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: commentsSectionRoot

    property var applicationWindow: null
    property var jiraService: null
    property var clipboardHelper: null
    property string selectedIssueKey: ""
    property var comments: []
    property bool commentsLoading: false
    property bool _editCommentDialogOpen: false

    signal errorOccurred(string message)

    onSelectedIssueKeyChanged: {
        comments = []
    }

    spacing: Kirigami.Units.smallSpacing

    Controls.Label {
        text: qsTr("Comentários")
        font.bold: true
        Layout.fillWidth: true
    }

    // Estado: não carregado — mostrar botão
    Controls.Button {
        id: loadCommentsButton
        text: commentsSectionRoot.commentsLoading ? qsTr("Carregando…") : qsTr("Carregar comentários")
        enabled: !commentsSectionRoot.commentsLoading && commentsSectionRoot.selectedIssueKey !== "" && commentsSectionRoot.jiraService
        visible: commentsSectionRoot.comments.length === 0 && !commentsSectionRoot.commentsLoading
        Layout.fillWidth: true
        onClicked: commentsSectionRoot.loadComments()
    }

    Controls.BusyIndicator {
        running: commentsSectionRoot.commentsLoading && commentsSectionRoot.comments.length === 0
        visible: running
        Layout.alignment: Qt.AlignHCenter
    }

    // Estado: carregado — título com contagem, ListView e adicionar
    ColumnLayout {
        id: commentsLoadedColumn
        Layout.fillWidth: true
        visible: commentsSectionRoot.comments.length > 0 || commentsSectionRoot.commentsLoading
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Controls.Label {
                text: qsTr("Comentários (%1)").arg(commentsSectionRoot.comments.length)
                font.bold: true
            }
            Item { Layout.fillWidth: true }
            Controls.Button {
                text: qsTr("Atualizar")
                enabled: !commentsSectionRoot.commentsLoading && commentsSectionRoot.jiraService && commentsSectionRoot.selectedIssueKey !== ""
                onClicked: commentsSectionRoot.loadComments()
            }
        }

        Controls.ScrollView {
            Layout.fillWidth: true
            Layout.preferredHeight: 220
            Layout.minimumHeight: 120
            clip: true
            contentWidth: availableWidth

            ListView {
                id: commentsListView
                model: commentsSectionRoot.comments
                spacing: Kirigami.Units.smallSpacing

                delegate: Rectangle {
                    id: commentDelegate
                    width: commentsListView.width
                    height: commentColumn.implicitHeight + Kirigami.Units.largeSpacing * 2
                    color: Kirigami.Theme.alternateBackgroundColor
                    border.color: Kirigami.Theme.disabledTextColor
                    border.width: 1
                    radius: 4

                    required property var modelData

                    ColumnLayout {
                        id: commentColumn
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.largeSpacing
                        spacing: Kirigami.Units.smallSpacing

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            Controls.Label {
                                text: commentDelegate.modelData.author ? (commentDelegate.modelData.author.displayName || "") : ""
                                font.bold: true
                            }
                            Controls.Label {
                                text: commentDelegate.modelData.created ? commentsSectionRoot.formatCommentDate(commentDelegate.modelData.created) : ""
                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                                color: Kirigami.Theme.disabledTextColor
                            }
                            Item { Layout.fillWidth: true }
                            Row {
                                spacing: Kirigami.Units.smallSpacing
                                visible: commentsSectionRoot.jiraService && (commentDelegate.modelData.author || {}).accountId === (commentsSectionRoot.jiraService.getAccountId ? commentsSectionRoot.jiraService.getAccountId() : "")

                                Controls.Button {
                                    text: qsTr("Editar")
                                    flat: true
                                    onClicked: commentsSectionRoot.openEditDialog(commentDelegate.modelData.id, commentDelegate.modelData.body || "")
                                }
                                Controls.Button {
                                    text: qsTr("Excluir")
                                    flat: true
                                    onClicked: commentsSectionRoot.openDeleteDialog(commentDelegate.modelData.id)
                                }
                            }
                        }

                        Controls.Label {
                            text: commentDelegate.modelData.body || ""
                            wrapMode: Text.Wrap
                            Layout.fillWidth: true
                            Layout.maximumHeight: 120
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Controls.Label {
                text: qsTr("Adicionar comentário")
                font.bold: true
            }
            Controls.ScrollView {
                id: newCommentScrollView
                Layout.fillWidth: true
                Layout.preferredHeight: 80
                clip: true
                contentWidth: availableWidth

                Item {
                    width: newCommentScrollView.availableWidth
                    height: newCommentField.implicitHeight

                    DropArea {
                        anchors.fill: parent
                        onDropped: function(drop) {
                            if (!commentsSectionRoot.jiraService || !commentsSectionRoot.selectedIssueKey || !drop.urls || drop.urls.length === 0) return
                            var extList = ["png", "jpg", "jpeg", "gif", "webp"]
                            for (var i = 0; i < drop.urls.length; i++) {
                                var urlStr = drop.urls[i].toString()
                                var path = urlStr.replace(/^file:\/\//, "")
                                var filename = path.split("/").pop() || path.split("\\").pop() || "file"
                                var ext = filename.indexOf(".") >= 0 ? filename.split(".").pop().toLowerCase() : ""
                                if (extList.indexOf(ext) < 0) continue
                                commentsSectionRoot.jiraService.uploadAttachment(commentsSectionRoot.selectedIssueKey, path)
                            }
                        }
                    }

                    Controls.TextArea {
                        id: newCommentField
                        width: parent.width
                        wrapMode: Controls.TextArea.Wrap
                        placeholderText: qsTr("Digite seu comentário (Markdown suportado). Arraste imagens ou use Ctrl+V para colar.")

                        Keys.onPressed: function(event) {
                            if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V) {
                                if (commentsSectionRoot.clipboardHelper && commentsSectionRoot.clipboardHelper.hasClipboardImage() && commentsSectionRoot.jiraService && commentsSectionRoot.selectedIssueKey) {
                                    var tempPath = commentsSectionRoot.clipboardHelper.getClipboardImageAsTempFile()
                                    if (tempPath) {
                                        commentsSectionRoot.jiraService.uploadAttachment(commentsSectionRoot.selectedIssueKey, tempPath)
                                        event.accepted = true
                                    }
                                }
                            }
                        }
                    }
                }
            }
            Controls.Button {
                text: qsTr("Publicar")
                enabled: commentsSectionRoot.jiraService && commentsSectionRoot.selectedIssueKey !== "" && newCommentField.text.trim() !== ""
                onClicked: {
                    if (commentsSectionRoot.jiraService && commentsSectionRoot.selectedIssueKey) {
                        commentsSectionRoot.jiraService.addComment(commentsSectionRoot.selectedIssueKey, newCommentField.text.trim())
                        newCommentField.text = ""
                    }
                }
            }
        }
    }

    function loadComments() {
        if (!commentsSectionRoot.jiraService || !commentsSectionRoot.selectedIssueKey) {
            return
        }
        commentsSectionRoot.commentsLoading = true
        commentsSectionRoot.jiraService.getCommentsAsync(commentsSectionRoot.selectedIssueKey)
    }

    function openEditDialog(commentId, body) {
        var comp = Qt.createComponent("../dialogs/EditCommentDialog.qml")
        if (comp.status !== Component.Ready) {
            return
        }
        var win = commentsSectionRoot.applicationWindow || commentsSectionRoot.parent || commentsSectionRoot
        var dlg = comp.createObject(win)
        if (!dlg) return
        commentsSectionRoot._editCommentDialogOpen = true
        dlg.issueKey = commentsSectionRoot.selectedIssueKey
        dlg.jiraService = commentsSectionRoot.jiraService
        dlg.clipboardHelper = commentsSectionRoot.clipboardHelper
        dlg.accepted.connect(function (cid, newBody) {
            if (commentsSectionRoot.jiraService && commentsSectionRoot.selectedIssueKey) {
                commentsSectionRoot.jiraService.updateComment(commentsSectionRoot.selectedIssueKey, cid, newBody)
            }
        })
        dlg.closed.connect(function () {
            commentsSectionRoot._editCommentDialogOpen = false
            dlg.destroy()
        })
        dlg.openWith(commentId, body)
        dlg.open()
    }

    function openDeleteDialog(commentId) {
        var comp = Qt.createComponent("../dialogs/ConfirmDeleteCommentDialog.qml")
        if (comp.status !== Component.Ready) {
            return
        }
        var win = commentsSectionRoot.applicationWindow || commentsSectionRoot.parent || commentsSectionRoot
        var dlg = comp.createObject(win)
        if (!dlg) return
        dlg.confirmed.connect(function (cid) {
            if (commentsSectionRoot.jiraService && commentsSectionRoot.selectedIssueKey) {
                commentsSectionRoot.jiraService.deleteComment(commentsSectionRoot.selectedIssueKey, cid)
            }
        })
        dlg.closed.connect(function () { dlg.destroy() })
        dlg.openWith(commentId)
        dlg.open()
    }

    function formatCommentDate(isoString) {
        if (!isoString) return ""
        var s = String(isoString)
        var idx = s.indexOf("T")
        if (idx >= 0) {
            var datePart = s.substring(0, idx)
            var timePart = s.substring(idx + 1, idx + 6)
            return datePart + " " + timePart
        }
        return s
    }

    Connections {
        target: commentsSectionRoot.jiraService || null
        function onCommentsLoaded(list) {
            commentsSectionRoot.commentsLoading = false
            commentsSectionRoot.comments = list || []
        }
        function onCommentAdded(issueKey, commentDict) {
            if (issueKey === commentsSectionRoot.selectedIssueKey && commentDict) {
                commentsSectionRoot.comments = commentsSectionRoot.comments.concat([commentDict])
            }
        }
        function onCommentUpdated(issueKey, commentId, commentDict) {
            if (issueKey !== commentsSectionRoot.selectedIssueKey || !commentDict) return
            var out = []
            for (var i = 0; i < commentsSectionRoot.comments.length; i++) {
                if (commentsSectionRoot.comments[i].id === commentId) {
                    out.push(commentDict)
                } else {
                    out.push(commentsSectionRoot.comments[i])
                }
            }
            commentsSectionRoot.comments = out
        }
        function onCommentDeleted(issueKey, commentId) {
            if (issueKey !== commentsSectionRoot.selectedIssueKey) return
            var out = commentsSectionRoot.comments.filter(function (c) { return c.id !== commentId })
            commentsSectionRoot.comments = out
        }
        function onErrorOccurred(message) {
            commentsSectionRoot.commentsLoading = false
            commentsSectionRoot.errorOccurred(message)
        }
        function onAttachmentUploaded(issueKey, contentUrl, filename) {
            if (issueKey === commentsSectionRoot.selectedIssueKey && contentUrl && filename && !commentsSectionRoot._editCommentDialogOpen) {
                var markdown = "![" + filename + "](" + contentUrl + ")"
                newCommentField.insert(newCommentField.cursorPosition, markdown)
            }
        }
    }

}
