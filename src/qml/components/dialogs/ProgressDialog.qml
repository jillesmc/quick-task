// Diálogo de progresso
import QtQuick 2.12
import QtQuick.Controls 2.12 as Controls
import QtQuick.Layouts 1.12
import org.kde.kirigami 2.12 as Kirigami

Controls.Dialog {
    id: dialog
    
    title: "Progresso"
    modal: true
    
    property int progressValue: 0
    property string progressMessage: "Processando..."
    
    standardButtons: Controls.Dialog.NoButton
    
    // Centralizar o diálogo
    function centerDialog() {
        if (parent && width > 0 && height > 0) {
            x = (parent.width - width) / 2
            y = (parent.height - height) / 2
        }
    }
    
    Component.onCompleted: centerDialog()
    onWidthChanged: centerDialog()
    onHeightChanged: centerDialog()
    
    // Conteúdo do diálogo
    ColumnLayout {
        width: parent ? parent.width : 400
        spacing: Kirigami.Units.largeSpacing
        
        Controls.Label {
            id: messageLabel
            text: dialog.progressMessage
            Layout.fillWidth: true
        }
        
        Controls.ProgressBar {
            id: progressBar
            Layout.fillWidth: true
            from: 0
            to: 100
            value: dialog.progressValue
        }
    }
    
    function updateProgress(percentage, message) {
        progressValue = percentage
        if (message) {
            progressMessage = message
        }
    }
    
    function closeDialog() {
        dialog.close()
    }
}
