/**
 * EditCommentDialog.qml
 * Diálogo para editar o texto de um comentário (markdown). TextArea multilinha, OK/Cancelar.
 * Emite accepted(commentId, newBody) ao confirmar.
 */
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../controls"

Controls.Dialog {
    id: dialog

    title: qsTr("Editar comentário")
    modal: true
    closePolicy: Controls.Popup.CloseOnEscape
    standardButtons: Controls.Dialog.NoButton

    property string commentId: ""
    property string initialBody: ""
    property string commentText: ""
    property string issueKey: ""
    property var applicationWindow: null
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
        commentId = commentIdValue || "";
        initialBody = body || "";
        commentText = initialBody;
        open();
    }

    function centerDialog() {
        var ref = applicationWindow || parent;
        if (ref && width > 0 && height > 0 && ref.width > 0 && ref.height > 0) {
            x = Math.max(0, (ref.width - width) / 2);
            y = Math.max(0, (ref.height - height) / 2);
        }
    }

    onOpened: Qt.callLater(centerDialog)
    Component.onCompleted: Qt.callLater(centerDialog)
    onWidthChanged: Qt.callLater(centerDialog)
    onHeightChanged: Qt.callLater(centerDialog)

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.mediumSpacing

        EditPreviewContainer {
            id: commentEditPreview
            applicationWindow: dialog.applicationWindow
            content: dialog.commentText
            onContentEdited: function (newContent) {
                dialog.commentText = newContent;
            }
            label: qsTr("Comentário")
            placeholderText: qsTr("Digite o comentário (Markdown suportado). Arraste imagens ou use Ctrl+V para colar.")
            acceptDrops: true
            jiraService: dialog.jiraService
            issueKey: dialog.issueKey
            clipboardHelper: dialog.clipboardHelper
            Layout.fillWidth: true
            Layout.fillHeight: true
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignRight
            spacing: Kirigami.Units.mediumSpacing

            Controls.Button {
                text: dialog.improvingComment ? qsTr("A melhorar…") : qsTr("Melhorar com IA")
                visible: dialog.voiceInputAvailable
                enabled: !dialog.improvingComment && (dialog.commentText || "").trim() !== ""
                onClicked: {
                    if (dialog.voiceInputService && (dialog.commentText || "").trim() !== "") {
                        dialog.improvingComment = true;
                        dialog.voiceInputService.improveCommentText(dialog.commentText);
                    }
                }
            }
            Item {
                Layout.fillWidth: true
            }
            Controls.Button {
                text: qsTr("Cancelar")
                onClicked: dialog.close()
            }
            Controls.Button {
                text: qsTr("Salvar")
                onClicked: {
                    dialog.accepted(dialog.commentId, dialog.commentText || "");
                    dialog.close();
                }
            }
        }
    }

    Connections {
        target: dialog.voiceInputService || null
        enabled: dialog.voiceInputService !== null
        function onCommentTextImproved(text) {
            dialog.improvingComment = false;
            if (text)
                dialog.commentText = text;
        }
        function onError(message) {
            dialog.improvingComment = false;
        }
    }
}
