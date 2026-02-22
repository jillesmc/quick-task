/**
 * CommentsSection.qml
 *
 * Ordem: (1) Novo comentário: input, drag area, botões; (2) Comentários (N), último comentário, Carregar mais, lista.
 * Input redimensionável como description (commentInputHeight + DividerBar). Carregamento inicial: só o último comentário.
 */
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami
import "../controls"

Item {
    id: commentsSectionRoot

    implicitHeight: commentsColumn.implicitHeight

    property var applicationWindow: null
    property var jiraService: null
    property var clipboardHelper: null
    property string selectedIssueKey: ""
    /** Comentário mais recente (objeto ou null). Carregado ao selecionar a issue. */
    property var lastComment: null
    /** Comentários mais antigos já carregados (ordem da API: mais antigos primeiro). */
    property var olderComments: []
    /** Total de comentários na issue (da API). -1 até receber. */
    property int commentsTotal: -1
    property bool commentsLoading: false
    property bool _latestCommentLoading: false
    /** Issue key do pedido "load more" em curso; ao receber commentsLoaded, só aplicar se for a issue atual. */
    property string _pendingCommentsIssueKey: ""
    property bool _editCommentDialogOpen: false
    property var _voiceInputService: (typeof voiceInputService !== "undefined" ? voiceInputService : null) // qmllint disable unqualified
    property bool voiceInputAvailable: _voiceInputService ? _voiceInputService.isAvailable() : false
    property bool improvingNewComment: false
    property string newCommentText: ""
    property real commentInputHeight: 200
    property bool _newCommentEditMode: true

    signal errorOccurred(string message)

    /** Exposto para o pane ancorar o overlay de resize (filho do pane) nesta barra. */
    property alias commentResizeDivider: commentInputDivider

    /** olderComments em ordem de exibição (mais novo primeiro). */
    property var displayOlderComments: []
    onOlderCommentsChanged: {
        var o = olderComments || []
        var out = []
        for (var i = o.length - 1; i >= 0; i--) out.push(o[i])
        displayOlderComments = out
    }

    /** Número exibido no título. */
    readonly property int _displayCount: commentsTotal >= 0 ? commentsTotal : ((lastComment ? 1 : 0) + (olderComments || []).length)
    readonly property bool _hasMoreComments: commentsTotal >= 0 && ((lastComment ? 1 : 0) + (olderComments || []).length) < commentsTotal

    /** accountId do usuário atual (atualizado quando jiraService existe), para comparar com autor do comentário. */
    property string _currentUserAccountId: ""
    onJiraServiceChanged: {
        if (jiraService && typeof jiraService.getAccountId === "function") {
            _currentUserAccountId = String(jiraService.getAccountId())
        } else {
            _currentUserAccountId = ""
        }
    }
    Component.onCompleted: {
        if (jiraService && typeof jiraService.getAccountId === "function") {
            _currentUserAccountId = String(jiraService.getAccountId())
        }
    }

    /** accountId do autor do lastComment (extraído no handler quando recebemos o objeto do Python). */
    property string _lastCommentAuthorAccountId: ""

    /** True se o primeiro comentário (lastComment) é do usuário atual → mostrar Editar/Excluir. */
    readonly property bool _isLastCommentByCurrentUser: _lastCommentAuthorAccountId !== "" && _currentUserAccountId !== "" && _lastCommentAuthorAccountId === _currentUserAccountId

    function _authorAccountIdFromComment(commentDict) {
        if (!commentDict) return ""
        var author = commentDict.author
        if (!author) return ""
        if (author.accountId !== undefined && author.accountId !== null) return String(author.accountId)
        if (author["accountId"] !== undefined && author["accountId"] !== null) return String(author["accountId"])
        return ""
    }

    onSelectedIssueKeyChanged: {
        lastComment = null
        _lastCommentAuthorAccountId = ""
        olderComments = []
        commentsTotal = -1
        _pendingCommentsIssueKey = ""
        if (commentsSectionRoot.selectedIssueKey && commentsSectionRoot.jiraService) {
            _latestCommentLoading = true
            commentsSectionRoot.jiraService.getLatestCommentAsync(commentsSectionRoot.selectedIssueKey)
        }
    }

    ColumnLayout {
        id: commentsColumn
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: parent.height > 0 ? parent.height : implicitHeight
        spacing: Kirigami.Units.smallSpacing

        // ---- 1) Novo comentário: seção com preferredHeight/minimumHeight como topSection no pane; área do input com fillHeight ----
        ColumnLayout {
            id: addCommentColumn
            Layout.fillWidth: true
            Layout.preferredHeight: commentsSectionRoot.commentInputHeight + _addCommentFixedHeight
            Layout.minimumHeight: 160 + _addCommentFixedHeight
            spacing: Kirigami.Units.smallSpacing

            readonly property int _addCommentFixedHeight: 94  // label + DividerBar + botões (aprox.)

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                Controls.Label {
                    text: qsTr("Adicionar comentário")
                    font.bold: true
                    Layout.fillWidth: true
                }
                EditPreviewToggle {
                    isEditMode: commentsSectionRoot._newCommentEditMode
                    onModeChanged: function(editMode) {
                        commentsSectionRoot._newCommentEditMode = editMode
                    }
                }
            }
            // Mesma estrutura da description no pane: Item com fillHeight > StackLayout > ScrollView > TextArea (sem ColumnLayout no meio).
            Item {
                id: newCommentContainer
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 160

                StackLayout {
                    anchors.fill: parent
                    currentIndex: commentsSectionRoot._newCommentEditMode ? 0 : 1

                    DropArea {
                        enabled: commentsSectionRoot.selectedIssueKey !== "" && commentsSectionRoot.jiraService
                        onDropped: function(drop) {
                            if (!commentsSectionRoot.jiraService || !commentsSectionRoot.selectedIssueKey || !drop.urls || drop.urls.length === 0) return
                            var extList = (typeof commentsSectionRoot.jiraService.getAllowedAttachmentExtensions === "function")
                                ? commentsSectionRoot.jiraService.getAllowedAttachmentExtensions() : []
                            var imageExtList = (typeof commentsSectionRoot.jiraService.getAllowedImageExtensions === "function")
                                ? commentsSectionRoot.jiraService.getAllowedImageExtensions() : []
                            for (var i = 0; i < drop.urls.length; i++) {
                                var urlStr = drop.urls[i].toString()
                                var path = urlStr.replace(/^file:\/\//, "")
                                var filename = path.split("/").pop() || path.split("\\").pop() || "file"
                                var ext = filename.indexOf(".") >= 0 ? filename.split(".").pop().toLowerCase() : ""
                                if (extList.indexOf(ext) < 0) continue
                                var pathToUse = (commentsSectionRoot.clipboardHelper && typeof commentsSectionRoot.clipboardHelper.copyFileToTemp === "function")
                                    ? commentsSectionRoot.clipboardHelper.copyFileToTemp(path) : path
                                if (!pathToUse) pathToUse = path
                                if (imageExtList.indexOf(ext) >= 0) {
                                    commentsSectionRoot._openEmbedDialogForComment(pathToUse, filename)
                                } else {
                                    commentsSectionRoot.jiraService.uploadAttachment(commentsSectionRoot.selectedIssueKey, pathToUse, "comment")
                                }
                            }
                        }

                        Controls.ScrollView {
                            anchors.fill: parent
                            clip: true
                            contentWidth: newCommentField.implicitWidth

                            Controls.TextArea {
                                id: newCommentField
                                width: newCommentContainer.width
                                wrapMode: Controls.TextArea.Wrap
                                topPadding: Kirigami.Units.smallSpacing
                                bottomPadding: Kirigami.Units.smallSpacing
                                placeholderText: qsTr("Digite seu comentário (Markdown suportado). Arraste imagens ou use Ctrl+V para colar.")
                                text: commentsSectionRoot.newCommentText
                                onTextChanged: commentsSectionRoot.newCommentText = text

                                Keys.onPressed: function(event) {
                                    if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V) {
                                        if (commentsSectionRoot.clipboardHelper && commentsSectionRoot.clipboardHelper.hasClipboardImage() && commentsSectionRoot.jiraService && commentsSectionRoot.selectedIssueKey) {
                                            var tempPath = commentsSectionRoot.clipboardHelper.getClipboardImageAsTempFile()
                                            if (tempPath) {
                                                commentsSectionRoot._openEmbedDialogForComment(tempPath, "paste.png")
                                                event.accepted = true
                                            }
                                        }
                                    } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_E) {
                                        commentsSectionRoot._newCommentEditMode = true
                                        event.accepted = true
                                    } else if ((event.modifiers & (Qt.ControlModifier | Qt.ShiftModifier)) === (Qt.ControlModifier | Qt.ShiftModifier) && event.key === Qt.Key_P) {
                                        commentsSectionRoot._newCommentEditMode = false
                                        event.accepted = true
                                    } else if (event.key === Qt.Key_Escape) {
                                        commentsSectionRoot._newCommentEditMode = true
                                        event.accepted = true
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        color: "transparent"
                        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
                        border.width: 0.5
                        radius: Kirigami.Units.smallSpacing

                        Keys.onPressed: function(event) {
                            if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_E) {
                                commentsSectionRoot._newCommentEditMode = true
                                event.accepted = true
                            } else if (event.key === Qt.Key_Escape) {
                                commentsSectionRoot._newCommentEditMode = true
                                event.accepted = true
                            }
                        }

                        Controls.ScrollView {
                            id: newCommentPreviewScroll
                            anchors.fill: parent
                            anchors.margins: 1
                            clip: true
                            contentWidth: availableWidth

                            Text {
                                width: newCommentPreviewScroll.availableWidth - Kirigami.Units.largeSpacing * 2
                                x: Kirigami.Units.largeSpacing
                                topPadding: Kirigami.Units.smallSpacing
                                bottomPadding: Kirigami.Units.smallSpacing
                                textFormat: Text.RichText
                                color: Kirigami.Theme.textColor
                                // qmllint disable unqualified
                                text: (typeof markdownPreviewRenderer !== "undefined" && markdownPreviewRenderer)
                                    ? markdownPreviewRenderer.render(commentsSectionRoot.newCommentText)
                                    : commentsSectionRoot.newCommentText
                                // qmllint enable unqualified
                                wrapMode: Text.Wrap
                                onLinkActivated: function(link) { Qt.openUrlExternally(link) }
                            }
                        }
                    }
                }
            }
            DividerBar {
                id: commentInputDivider
                Layout.fillWidth: true
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

        // ---- 2) Comentários (N): título, último comentário, Carregar mais, lista ----
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            Controls.Label {
                text: qsTr("Comentários (%1)").arg(commentsSectionRoot._displayCount)
                font.bold: true
            }
            Controls.BusyIndicator {
                running: commentsSectionRoot._latestCommentLoading
                visible: commentsSectionRoot._latestCommentLoading
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
            }
            Item { Layout.fillWidth: true }
        }

        Rectangle {
            id: lastCommentBlock
            Layout.fillWidth: true
            visible: commentsSectionRoot.lastComment != null
            color: Kirigami.Theme.alternateBackgroundColor
            border.color: Kirigami.Theme.disabledTextColor
            border.width: 1
            radius: Kirigami.Units.smallSpacing
            implicitHeight: visible ? lastCommentColumn.implicitHeight + Kirigami.Units.largeSpacing * 2 : 0

            ColumnLayout {
                id: lastCommentColumn
                anchors.fill: parent
                anchors.margins: Kirigami.Units.largeSpacing
                spacing: Kirigami.Units.smallSpacing

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    Controls.Label {
                        text: commentsSectionRoot.lastComment && commentsSectionRoot.lastComment.author ? (commentsSectionRoot.lastComment.author.displayName || "") : ""
                        font.bold: true
                    }
                    Controls.Label {
                        text: commentsSectionRoot.lastComment && commentsSectionRoot.lastComment.created ? commentsSectionRoot.formatCommentDate(commentsSectionRoot.lastComment.created) : ""
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        color: Kirigami.Theme.disabledTextColor
                    }
                    Item { Layout.fillWidth: true }
                    Row {
                        spacing: Kirigami.Units.smallSpacing
                        visible: commentsSectionRoot._isLastCommentByCurrentUser
                        Controls.Button {
                            text: qsTr("Editar")
                            flat: true
                            onClicked: commentsSectionRoot.openEditDialog(commentsSectionRoot.lastComment.id, commentsSectionRoot.lastComment.body || "")
                        }
                        Controls.Button {
                            text: qsTr("Excluir")
                            flat: true
                            onClicked: commentsSectionRoot.openDeleteDialog(commentsSectionRoot.lastComment.id)
                        }
                    }
                }
                Controls.Label {
                    text: commentsSectionRoot.lastComment ? (commentsSectionRoot.lastComment.body || "") : ""
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                    Layout.maximumHeight: 200
                    elide: Text.ElideRight
                }
            }
        }

        Controls.Button {
            id: loadMoreCommentsButton
            text: commentsSectionRoot.commentsLoading ? qsTr("Carregando…") : qsTr("Carregar mais comentários")
            enabled: !commentsSectionRoot.commentsLoading && commentsSectionRoot.selectedIssueKey !== "" && commentsSectionRoot.jiraService
            visible: commentsSectionRoot._hasMoreComments
            Layout.fillWidth: true
            onClicked: commentsSectionRoot.loadMoreComments()
        }

        Controls.ScrollView {
            Layout.fillWidth: true
            Layout.maximumHeight: 280
            Layout.minimumHeight: 0
            clip: true
            contentWidth: availableWidth
            visible: (commentsSectionRoot.displayOlderComments || []).length > 0

            ListView {
                id: olderCommentsListView
                model: commentsSectionRoot.displayOlderComments
                spacing: Kirigami.Units.smallSpacing

                delegate: Rectangle {
                    id: olderDelegate
                    width: olderCommentsListView.width
                    height: olderColumn.implicitHeight + Kirigami.Units.largeSpacing * 2
                    color: Kirigami.Theme.alternateBackgroundColor
                    border.color: Kirigami.Theme.disabledTextColor
                    border.width: 1
                    radius: Kirigami.Units.smallSpacing
                    required property var modelData

                    ColumnLayout {
                        id: olderColumn
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.largeSpacing
                        spacing: Kirigami.Units.smallSpacing
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing
                            Controls.Label {
                                text: olderDelegate.modelData.author ? (olderDelegate.modelData.author.displayName || "") : ""
                                font.bold: true
                            }
                            Controls.Label {
                                text: olderDelegate.modelData.created ? commentsSectionRoot.formatCommentDate(olderDelegate.modelData.created) : ""
                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                                color: Kirigami.Theme.disabledTextColor
                            }
                            Item { Layout.fillWidth: true }
                            Row {
                                spacing: Kirigami.Units.smallSpacing
                                visible: commentsSectionRoot.jiraService && olderDelegate.modelData.author && String(olderDelegate.modelData.author.accountId || "") === String(commentsSectionRoot.jiraService.getAccountId ? commentsSectionRoot.jiraService.getAccountId() : "")
                                Controls.Button {
                                    text: qsTr("Editar")
                                    flat: true
                                    onClicked: commentsSectionRoot.openEditDialog(olderDelegate.modelData.id, olderDelegate.modelData.body || "")
                                }
                                Controls.Button {
                                    text: qsTr("Excluir")
                                    flat: true
                                    onClicked: commentsSectionRoot.openDeleteDialog(olderDelegate.modelData.id)
                                }
                            }
                        }
                        Controls.Label {
                            text: olderDelegate.modelData.body || ""
                            wrapMode: Text.Wrap
                            Layout.fillWidth: true
                            Layout.maximumHeight: 120
                            elide: Text.ElideRight
                        }
                    }
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

    Connections {
        target: commentsSectionRoot.jiraService || null
        function onAttachmentUploaded(uploadedIssueKey, contentUrl, filename, embedTarget) {
            if (uploadedIssueKey !== commentsSectionRoot.selectedIssueKey || !contentUrl || !filename || embedTarget !== "comment") return
            if (!newCommentField) return
            var w = 760
            var markdown = "![" + filename + "](" + contentUrl + "){: width=\"" + w + "\" }"
            newCommentField.insert(newCommentField.cursorPosition, markdown)
            commentsSectionRoot.newCommentText = newCommentField.text
        }
    }

    function _openEmbedDialogForComment(filePath, filename) {
        if (!commentsSectionRoot.jiraService || !commentsSectionRoot.selectedIssueKey) return
        var comp = Qt.createComponent("../dialogs/AttachmentEmbedPreviewDialog.qml")
        var win = commentsSectionRoot.applicationWindow || commentsSectionRoot.parent || commentsSectionRoot
        if (comp.status !== Component.Ready) {
            if (comp.status === Component.Error) console.error("CommentsSection: AttachmentEmbedPreviewDialog error:", comp.errorString())
            comp.statusChanged.connect(function () {
                if (comp.status === Component.Ready) _openEmbedDialogForComment(filePath, filename)
            })
            return
        }
        var dlg = comp.createObject(win)
        if (!dlg) return
        dlg.filePath = filePath
        dlg.showPositionOptions = false
        dlg.defaultDisplayWidth = (commentsSectionRoot.jiraService && typeof commentsSectionRoot.jiraService.getEmbedMaxDisplayWidth === "function")
            ? commentsSectionRoot.jiraService.getEmbedMaxDisplayWidth() : 760
        dlg.applicationWindow = commentsSectionRoot.applicationWindow
        dlg.clipboardHelper = commentsSectionRoot.clipboardHelper
        dlg.embedTarget = "comment"
        dlg.acceptedEmbed.connect(function () {
            commentsSectionRoot.jiraService.uploadAttachment(commentsSectionRoot.selectedIssueKey, filePath, "comment")
        })
        dlg.acceptedAttachOnly.connect(function () {
            commentsSectionRoot.jiraService.uploadAttachment(commentsSectionRoot.selectedIssueKey, filePath, "comment")
        })
        dlg.rejected.connect(function () {})
        dlg.closed.connect(function () { dlg.destroy() })
        dlg.open()
    }

    function loadMoreComments() {
        if (!commentsSectionRoot.jiraService || !commentsSectionRoot.selectedIssueKey) return
        commentsSectionRoot._pendingCommentsIssueKey = commentsSectionRoot.selectedIssueKey
        commentsSectionRoot.commentsLoading = true
        commentsSectionRoot.jiraService.getCommentsAsync(
            commentsSectionRoot.selectedIssueKey,
            (commentsSectionRoot.olderComments || []).length,
            50
        )
    }

    function openEditDialog(commentId, body) {
        var comp = Qt.createComponent("../dialogs/EditCommentDialog.qml")
        if (comp.status !== Component.Ready) return
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
        if (comp.status !== Component.Ready) return
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
        function onLatestCommentLoaded(issueKey, commentDict, total) {
            commentsSectionRoot._latestCommentLoading = false
            if (issueKey !== commentsSectionRoot.selectedIssueKey) return
            if (commentsSectionRoot.jiraService && typeof commentsSectionRoot.jiraService.getAccountId === "function") {
                commentsSectionRoot._currentUserAccountId = String(commentsSectionRoot.jiraService.getAccountId())
            }
            commentsSectionRoot._lastCommentAuthorAccountId = commentsSectionRoot._authorAccountIdFromComment(commentDict)
            commentsSectionRoot.lastComment = commentDict
            commentsSectionRoot.olderComments = []
            commentsSectionRoot.commentsTotal = total >= 0 ? total : 0
        }
        function onCommentsLoaded(list, startAt, total) {
            commentsSectionRoot.commentsLoading = false
            if (commentsSectionRoot._pendingCommentsIssueKey !== commentsSectionRoot.selectedIssueKey) return
            var newList = list || []
            var lastId = (commentsSectionRoot.lastComment && commentsSectionRoot.lastComment.id) ? String(commentsSectionRoot.lastComment.id) : ""
            var older = commentsSectionRoot.olderComments || []
            for (var i = 0; i < newList.length; i++) {
                var c = newList[i]
                if (lastId !== "" && c && String(c.id) === lastId) continue
                older.push(c)
            }
            commentsSectionRoot.olderComments = older
            if (total >= 0) commentsSectionRoot.commentsTotal = total
        }
        function onCommentAdded(issueKey, commentDict) {
            if (issueKey !== commentsSectionRoot.selectedIssueKey || !commentDict) return
            commentsSectionRoot._lastCommentAuthorAccountId = commentsSectionRoot._authorAccountIdFromComment(commentDict)
            commentsSectionRoot.lastComment = commentDict
            commentsSectionRoot.commentsTotal = (commentsSectionRoot.commentsTotal >= 0 ? commentsSectionRoot.commentsTotal : 0) + 1
        }
        function onCommentUpdated(issueKey, commentId, commentDict) {
            if (issueKey !== commentsSectionRoot.selectedIssueKey || !commentDict) return
            if (commentsSectionRoot.lastComment && commentsSectionRoot.lastComment.id === commentId) {
                commentsSectionRoot._lastCommentAuthorAccountId = commentsSectionRoot._authorAccountIdFromComment(commentDict)
                commentsSectionRoot.lastComment = commentDict
                return
            }
            var o = commentsSectionRoot.olderComments || []
            var out = []
            for (var i = 0; i < o.length; i++) {
                out.push(o[i].id === commentId ? commentDict : o[i])
            }
            commentsSectionRoot.olderComments = out
        }
        function onCommentDeleted(issueKey, commentId) {
            if (issueKey !== commentsSectionRoot.selectedIssueKey) return
            if (commentsSectionRoot.lastComment && commentsSectionRoot.lastComment.id === commentId) {
                commentsSectionRoot.lastComment = null
                commentsSectionRoot._lastCommentAuthorAccountId = ""
                commentsSectionRoot.commentsTotal = Math.max(0, commentsSectionRoot.commentsTotal - 1)
                return
            }
            var out = (commentsSectionRoot.olderComments || []).filter(function (c) { return c.id !== commentId })
            commentsSectionRoot.olderComments = out
            commentsSectionRoot.commentsTotal = Math.max(0, commentsSectionRoot.commentsTotal - 1)
        }
        function onErrorOccurred(message) {
            commentsSectionRoot.commentsLoading = false
            commentsSectionRoot._latestCommentLoading = false
            commentsSectionRoot.errorOccurred(message)
        }
        function onAttachmentUploaded(issueKey, contentUrl, filename, embedTarget) {}
    }
}
