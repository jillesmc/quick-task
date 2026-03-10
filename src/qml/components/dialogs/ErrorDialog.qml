// Diálogo de erro
import QtQuick
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

Controls.Dialog {
    id: dialog

    title: "Erro"
    modal: true
    closePolicy: Controls.Popup.CloseOnEscape

    property string errorMessage: ""

    standardButtons: Controls.Dialog.Ok

    // Centrar no overlay da aplicação (reparentar em onCompleted se criado com outro parent)
    Component.onCompleted: {
        if (Controls.Overlay.overlay) {
            parent = Controls.Overlay.overlay;
        }
    }

    parent: Controls.Overlay.overlay
    anchors.centerIn: parent

    contentItem: Item {
        implicitWidth: 420
        implicitHeight: 300
        clip: true

        Controls.ScrollView {
            id: errorScroll
            anchors.fill: parent
            clip: true
            contentWidth: availableWidth

            Controls.Label {
                id: errorLabel
                width: errorScroll.availableWidth - Kirigami.Units.largeSpacing * 2
                text: dialog.errorMessage
                wrapMode: Text.Wrap
            }
        }
    }

    function show(message) {
        errorMessage = message;
        open();
    }
}
