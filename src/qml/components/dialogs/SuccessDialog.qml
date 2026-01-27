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
    
    // Definir tamanho mínimo adequado para acomodar todos os elementos com padding
    implicitWidth: 480
    implicitHeight: isUpdate ? 220 : 280
    width: implicitWidth
    height: implicitHeight
    
    property string issueKey: ""
    property string issueUrl: ""
    
    // Não usar botões padrão, vamos criar botões customizados
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
    
    // Conteúdo do diálogo com padding adequado
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing * 1.5  // Padding generoso
        spacing: Kirigami.Units.mediumSpacing
        
        // Mensagem de sucesso
        Controls.Label {
            text: isUpdate ? "Task atualizada com sucesso!" : "Issue criada com sucesso!"
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.smallSpacing
            Layout.rightMargin: Kirigami.Units.smallSpacing
            wrapMode: Text.Wrap
            font.pointSize: Kirigami.Theme.defaultFont.pointSize
        }
        
        // Issue Key
        Controls.Label {
            text: "Issue: " + dialog.issueKey
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.smallSpacing
            Layout.rightMargin: Kirigami.Units.smallSpacing
            wrapMode: Text.Wrap
            font.pointSize: Kirigami.Theme.defaultFont.pointSize
            font.bold: true
        }
        
        // URL clicável (com wrap para evitar vazamento)
        Controls.Label {
            text: dialog.issueUrl
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.smallSpacing
            Layout.rightMargin: Kirigami.Units.smallSpacing
            visible: dialog.issueUrl !== ""
            color: Kirigami.Theme.linkColor
            wrapMode: Text.Wrap
            elide: Text.ElideMiddle
            font.pointSize: Kirigami.Theme.smallFont.pointSize
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
        
        // Espaçador para empurrar botões para baixo
        Item {
            Layout.fillHeight: true
        }
        
        // Botão Iniciar Timer (apenas para criação, não para atualização)
        // Posicionado como ação primária, centralizado
        Controls.Button {
            text: qsTr("Iniciar Timer")
            icon.name: "chronometer"
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.smallSpacing
            Layout.rightMargin: Kirigami.Units.smallSpacing
            visible: !isUpdate && issueKey !== "" && timerService && timerModel
            enabled: timerService && timerModel
            
            onClicked: {
                if (timerService && issueKey) {
                    timerService.start(issueKey)
                    dialog.close()
                }
            }
        }
        
        // Botões secundários (Cancelar e Abrir) - centralizados
        RowLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter  // Centralizar horizontalmente
            Layout.topMargin: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.mediumSpacing
            
            // Botão Cancelar/Fechar
            Controls.Button {
                text: qsTr("Cancelar")
                Layout.preferredWidth: 120
                onClicked: dialog.close()
            }
            
            // Botão Abrir/OK
            Controls.Button {
                text: dialog.issueUrl !== "" ? qsTr("Abrir") : qsTr("OK")
                Layout.preferredWidth: 120
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
