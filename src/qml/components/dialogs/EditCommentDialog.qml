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
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: availableWidth

            Controls.TextArea {
                id: commentTextArea
                width: parent ? parent.availableWidth : 0
                wrapMode: Controls.TextArea.Wrap
                placeholderText: qsTr("Digite o comentário (Markdown suportado)...")
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignRight
            spacing: Kirigami.Units.mediumSpacing

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
}
