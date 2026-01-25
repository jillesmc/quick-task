/**
 * BreakEndPrompt.qml
 * 
 * Componente de questionamento quando a pausa termina
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

Item {
    id: root
    
    Rectangle {
        anchors.fill: parent
        color: Kirigami.Theme.backgroundColor || "#f0f0f0"
        
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.mediumSpacing
            
            // Título
            Controls.Label {
                text: qsTr("Pausa terminada!")
                font.pointSize: Kirigami.Theme.defaultFont.pointSize + 4
                font.bold: true
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
            }
            
            // Mensagem
            Controls.Label {
                text: qsTr("Deseja continuar?")
                font.pointSize: Kirigami.Theme.defaultFont.pointSize + 1
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
            }
            
            Item {
                Layout.fillHeight: true
            }
            
            // Botões
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.mediumSpacing
                
                Controls.Button {
                    text: qsTr("Continuar")
                    icon.name: "media-playback-start"
                    Layout.fillWidth: true
                    Layout.preferredHeight: 50
                    onClicked: {
                        if (timerService) {
                            timerService.continueAfterBreak()
                        }
                    }
                }
                
                Controls.Button {
                    text: qsTr("Parar")
                    icon.name: "media-playback-stop"
                    Layout.fillWidth: true
                    Layout.preferredHeight: 50
                    onClicked: {
                        if (timerService) {
                            timerService.stopAfterBreak()
                        }
                    }
                }
            }
        }
    }
}
