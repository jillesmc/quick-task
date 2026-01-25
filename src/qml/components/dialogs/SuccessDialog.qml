// Diálogo de sucesso
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Controls.Dialog {
    id: dialog
    
    property bool isUpdate: false  // Se true, é uma atualização, senão é criação
    title: isUpdate ? "Task Atualizada" : "Issue Criada"
    modal: true
    
    property string issueKey: ""
    property string issueUrl: ""
    
    // Não usar botões padrão, vamos criar um botão customizado
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
    
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.largeSpacing
        
        Controls.Label {
            text: isUpdate ? "Task atualizada com sucesso!" : "Issue criada com sucesso!"
            Layout.fillWidth: true
        }
        
        Controls.Label {
            text: "Issue: " + dialog.issueKey
            Layout.fillWidth: true
        }
        
        Controls.Label {
            text: dialog.issueUrl
            Layout.fillWidth: true
            visible: dialog.issueUrl !== ""
            color: Kirigami.Theme.linkColor
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (dialog.issueUrl) {
                        Qt.openUrlExternally(dialog.issueUrl)
                    }
                }
            }
        }
        
        // Botão Iniciar Timer (apenas para criação, não para atualização)
        Controls.Button {
            text: qsTr("Iniciar Timer")
            icon.name: "chronometer"
            Layout.fillWidth: true
            visible: !isUpdate && issueKey !== "" && timerService && timerModel
            enabled: timerService && timerModel
            
            onClicked: {
                if (timerService && issueKey) {
                    timerService.start(issueKey)
                    dialog.close()
                }
            }
        }
        
        RowLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignRight
            spacing: Kirigami.Units.smallSpacing
            
            // Botão Cancelar/Fechar explícito quando há URL
            Controls.Button {
                text: qsTr("Cancelar")
                Layout.preferredWidth: 100
                visible: dialog.issueUrl !== ""
                onClicked: dialog.close()
            }
            
            Controls.Button {
                text: dialog.issueUrl !== "" ? qsTr("Abrir") : qsTr("OK")
                Layout.preferredWidth: 100
                onClicked: {
                    if (dialog.issueUrl) {
                        Qt.openUrlExternally(dialog.issueUrl)
                    }
                    dialog.close()
                }
            }
        }
    }
    
    function show(key, url, update) {
        issueKey = key
        issueUrl = url || ""
        isUpdate = update || false
        open()
    }
}
