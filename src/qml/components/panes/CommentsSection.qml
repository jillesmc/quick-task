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
import "../controls"

ColumnLayout {
    id: commentsSectionRoot

    property var applicationWindow: null
    property var jiraService: null
    property var clipboardHelper: null
    property string selectedIssueKey: ""
    property var comments: []
    property bool commentsLoading: false
    /** True após o utilizador clicar em "Carregar comentários"; mantém a secção (e o campo novo comentário) visível mesmo com 0 comentários. */
    property bool commentsRequested: false
    property bool _editCommentDialogOpen: false
    property var _voiceInputService: (typeof voiceInputService !== "undefined" ? voiceInputService : null) // qmllint disable unqualified
    property bool voiceInputAvailable: _voiceInputService ? _voiceInputService.isAvailable() : false
    property bool improvingNewComment: false
    property string newCommentText: ""
    /** Altura preferida do input de comentário (redimensionável via DividerBar) */
    property real commentInputHeight: 200

    signal errorOccurred(string message)

    /** True quando todos os comentários foram carregados (ou não há mais). */
    property bool _commentsFullyLoaded: false
    /** Comentários em ordem reversa (mais recente primeiro) para exibição. */
    property var displayComments: []

    onCommentsChanged: {
        var c = comments
        var out = []
        for (var i = c.length - 1; i >= 0; i--) out.push(c[i])
        displayComments = out
    }

    onSelectedIssueKeyChanged: {
        comments = []
        commentsRequested = false
        _commentsFullyLoaded = false
        if (commentsSectionRoot.selectedIssueKey && commentsSectionRoot.jiraService) {
            commentsSectionRoot.commentsRequested = true
            commentsSectionRoot.commentsLoading = true
            commentsSectionRoot.jiraService.getCommentsAsync(commentsSectionRoot.selectedIssueKey, 0, 50)
        }
    }

    spacing: Kirigami.Units.smallSpacing

    Controls.Label {
        text: qsTr("Comentários")
        font.bold: true
        Layout.fillWidth: true
        visible: !commentsSectionRoot.commentsRequested
    }

    // Estado: não carregado — mostrar botão até o utilizador clicar
    Controls.Button {
        id: loadCommentsButton
        text: commentsSectionRoot.commentsLoading ? qsTr("Carregando…") : qsTr("Carregar comentários")
        enabled: !commentsSectionRoot.commentsLoading && commentsSectionRoot.selectedIssueKey !== "" && commentsSectionRoot.jiraService
        visible: !commentsSectionRoot.commentsRequested
        Layout.fillWidth: true
        onClicked: commentsSectionRoot.loadComments()
    }

    Controls.BusyIndicator {
        running: commentsSectionRoot.commentsLoading
        visible: commentsSectionRoot.commentsRequested && commentsSectionRoot.commentsLoading
        Layout.alignment: Qt.AlignHCenter
    }

    // Estado: carregado — título com contagem, ListView e campo para adicionar (visível após clicar em Carregar)
    Item {
        id: commentsLoadedWrapper
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: commentsSectionRoot.commentsRequested

        ColumnLayout {
            id: commentsLoadedColumn
            anchors.fill: parent
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
                text: commentsSectionRoot._commentsFullyLoaded ? qsTr("Atualizar") : qsTr("Carregar comentários")
                enabled: !commentsSectionRoot.commentsLoading && commentsSectionRoot.jiraService && commentsSectionRoot.selectedIssueKey !== ""
                onClicked: commentsSectionRoot.loadComments()
            }
        }

        Controls.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 150
            clip: true
            contentWidth: availableWidth

            ListView {
                id: commentsListView
                model: commentsSectionRoot.displayComments
                spacing: Kirigami.Units.smallSpacing

                delegate: Rectangle {
                    id: commentDelegate
                    width: commentsListView.width
                    height: commentColumn.implicitHeight + Kirigami.Units.largeSpacing * 2
                    color: Kirigami.Theme.alternateBackgroundColor
                    border.color: Kirigami.Theme.disabledTextColor
                    border.width: 1
                    radius: Kirigami.Units.smallSpacing

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

        DividerBar {
            id: commentInputDivider
            Layout.fillWidth: true
        }

        ColumnLayout {
            id: addCommentColumn
            Layout.fillWidth: true
            Layout.preferredHeight: commentsSectionRoot.commentInputHeight
            Layout.minimumHeight: 200
            spacing: Kirigami.Units.smallSpacing

            Controls.Label {
                text: qsTr("Adicionar comentário")
                font.bold: true
            }
            EditPreviewContainer {
                id: newCommentEditPreview
                applicationWindow: commentsSectionRoot.applicationWindow
                content: commentsSectionRoot.newCommentText
                onContentEdited: function(newContent) {
                    commentsSectionRoot.newCommentText = newContent
                }
                label: qsTr("Novo comentário")
                placeholderText: qsTr("Digite seu comentário (Markdown suportado). Arraste imagens ou use Ctrl+V para colar.")
                acceptDrops: true
                jiraService: commentsSectionRoot.jiraService
                issueKey: commentsSectionRoot.selectedIssueKey
                clipboardHelper: commentsSectionRoot.clipboardHelper
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 160
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.mediumSpacing
                Controls.Button {
                    text: commentsSectionRoot.improvingNewComment ? qsTr("A melhorar…") : qsTr("Melhorar com IA")
                    visible: commentsSectionRoot.voiceInputAvailable
                    enabled: !commentsSectionRoot.improvingNewComment && (commentsSectionRoot.newCommentText || "").trim() !== ""
                    onClicked: {
                        if (commentsSectionRoot._voiceInputService && (commentsSectionRoot.newCommentText || "").trim() !== "") {
                            commentsSectionRoot.improvingNewComment = true
                            commentsSectionRoot._voiceInputService.improveCommentText(commentsSectionRoot.newCommentText)
                        }
                    }
                }
                Item { Layout.fillWidth: true }
                Controls.Button {
                    text: qsTr("Publicar")
                    enabled: commentsSectionRoot.jiraService && commentsSectionRoot.selectedIssueKey !== "" && (commentsSectionRoot.newCommentText || "").trim() !== ""
                    onClicked: {
                        if (commentsSectionRoot.jiraService && commentsSectionRoot.selectedIssueKey) {
                            commentsSectionRoot.jiraService.addComment(commentsSectionRoot.selectedIssueKey, commentsSectionRoot.newCommentText.trim())
                            commentsSectionRoot.newCommentText = ""
                        }
                    }
                }
            }
        }

        }
        Item {
            id: commentResizeOverlay
            anchors.fill: parent
            z: 10
            property int activeDivider: 0
            property real startGlobalY: 0
            property real startHeight: 0

            MouseArea {
                anchors.fill: parent
                hoverEnabled: false
                cursorShape: commentResizeOverlay.activeDivider ? Qt.SizeVerCursor : Qt.ArrowCursor
                onPressed: function (mouse) {
                    if (!commentsLoadedWrapper.visible) {
                        mouse.accepted = false
                        return
                    }
                    var margin = 8
                    var p = commentInputDivider.mapToItem(commentResizeOverlay, 0, 0)
                    if (mouse.y >= p.y - margin && mouse.y < p.y + commentInputDivider.height + margin) {
                        commentResizeOverlay.activeDivider = 1
                        commentResizeOverlay.startGlobalY = commentResizeOverlay.mapToGlobal(mouse.x, mouse.y).y
                        commentResizeOverlay.startHeight = commentsSectionRoot.commentInputHeight
                        mouse.accepted = true
                    } else {
                        mouse.accepted = false
                    }
                }
                onPositionChanged: function (mouse) {
                    if (commentResizeOverlay.activeDivider === 0) return
                    var cur = commentResizeOverlay.mapToGlobal(mouse.x, mouse.y).y
                    var delta = cur - commentResizeOverlay.startGlobalY
                    commentsSectionRoot.commentInputHeight = Math.max(200, commentResizeOverlay.startHeight + delta)
                }
                onReleased: {
                    commentResizeOverlay.activeDivider = 0
                }
            }
        }
    }

    Connections {
        target: commentsSectionRoot._voiceInputService || null
        enabled: commentsSectionRoot._voiceInputService !== null
        function onCommentTextImproved(text) {
            commentsSectionRoot.improvingNewComment = false
            if (text)
                commentsSectionRoot.newCommentText = text
        }
        function onError(message) {
            commentsSectionRoot.improvingNewComment = false
            commentsSectionRoot.errorOccurred(message)
        }
    }

    function loadComments() {
        if (!commentsSectionRoot.jiraService || !commentsSectionRoot.selectedIssueKey) {
            return
        }
        commentsSectionRoot.commentsRequested = true
        commentsSectionRoot.commentsLoading = true
        var startAt = commentsSectionRoot.comments.length
        var maxResults = 50
        commentsSectionRoot.jiraService.getCommentsAsync(
            commentsSectionRoot.selectedIssueKey,
            startAt,
            maxResults
        )
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
        dlg.applicationWindow = commentsSectionRoot.applicationWindow
        dlg.issueKey = commentsSectionRoot.selectedIssueKey
        dlg.jiraService = commentsSectionRoot.jiraService
        dlg.clipboardHelper = commentsSectionRoot.clipboardHelper
        dlg.voiceInputService = commentsSectionRoot._voiceInputService
        dlg.voiceInputAvailable = commentsSectionRoot.voiceInputAvailable
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
        function onCommentsLoaded(list, startAt) {
            commentsSectionRoot.commentsLoading = false
            var newList = list || []
            if (startAt === 0) {
                commentsSectionRoot.comments = newList
            } else {
                commentsSectionRoot.comments = commentsSectionRoot.comments.concat(newList)
            }
            commentsSectionRoot._commentsFullyLoaded = (newList.length < 50)
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
        function onAttachmentUploaded(issueKey, contentUrl, filename, embedTarget) {
            // EditPreviewContainer handles insert for new comment field; EditCommentDialog handles its own
        }
    }

}
