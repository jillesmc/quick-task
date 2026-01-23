// Diálogo de erro
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Controls.Dialog {
    id: dialog
    
    title: "Erro"
    modal: true
    
    property string errorMessage: ""
    
    standardButtons: Controls.Dialog.Ok
    
    // Centralizar o diálogo
    function centerDialog() {
        if (parent && width > 0 && height > 0 && parent.width > 0 && parent.height > 0) {
            x = Math.max(0, (parent.width - width) / 2)
            y = Math.max(0, (parent.height - height) / 2)
        }
    }
    
    Component.onCompleted: {
        // Usar Timer para garantir que as dimensões estejam disponíveis
        Qt.callLater(centerDialog)
    }
    onWidthChanged: Qt.callLater(centerDialog)
    onHeightChanged: Qt.callLater(centerDialog)
    onVisibleChanged: {
        if (visible) {
            Qt.callLater(centerDialog)
        }
    }
    
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        
        Controls.Label {
            Layout.fillWidth: true
            text: dialog.errorMessage
            wrapMode: Text.Wrap
        }
    }
    
    function show(message) {
        errorMessage = message
        open()
    }
}
