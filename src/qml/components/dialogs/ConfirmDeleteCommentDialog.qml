/**
 * ConfirmDeleteCommentDialog.qml
 * Diálogo de confirmação antes de excluir um comentário.
 * Emite confirmed(commentId) ao clicar em Sim; ao cancelar não emite.
 */
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Controls.Dialog {
    id: dialog

    title: qsTr("Excluir comentário")
    modal: true
    closePolicy: Controls.Popup.CloseOnEscape
    standardButtons: Controls.Dialog.NoButton

    implicitWidth: 380
    width: implicitWidth

    property string commentId: ""

    signal confirmed(string commentId)

    function openWith(commentIdValue) {
        commentId = commentIdValue || "";
        open();
    }

    function centerDialog() {
        if (parent && width > 0 && height > 0 && parent.width > 0 && parent.height > 0) {
            x = Math.max(0, (parent.width - width) / 2);
            y = Math.max(0, (parent.height - height) / 2);
        }
    }

    Component.onCompleted: Qt.callLater(centerDialog)
    onWidthChanged: Qt.callLater(centerDialog)
    onHeightChanged: Qt.callLater(centerDialog)

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.mediumSpacing

        Controls.Label {
            text: qsTr("Deseja realmente excluir este comentário?")
            wrapMode: Text.Wrap
            Layout.fillWidth: true
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
                text: qsTr("Sim")
                onClicked: {
                    dialog.confirmed(dialog.commentId);
                    dialog.close();
                }
            }
        }
    }
}
