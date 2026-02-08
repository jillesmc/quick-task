// Diálogo de progresso
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Controls.Dialog {
    id: dialog
    
    title: "Progresso"
    modal: true
    closePolicy: Controls.Popup.CloseOnEscape

    property int progressValue: 0
    property string progressMessage: "Processando..."
    
    standardButtons: Controls.Dialog.NoButton
    
    // Definir largura explícita para evitar binding loops
    // Não definir height para permitir que seja calculado automaticamente
    width: 400
    
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
        anchors.fill: parent
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
