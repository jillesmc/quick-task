pragma ComponentBehavior: Bound
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

    property var timerService: null
    property var hideWindow: null

    Rectangle {
        anchors.fill: parent
        color: Kirigami.Theme.backgroundColor || "#f0f0f0"
        border.color: Kirigami.Theme.highlightColor || "#3daee9"
        border.width: 2
        radius: Kirigami.Units.smallSpacing
        
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.mediumSpacing
            spacing: Kirigami.Units.mediumSpacing
            
            // Cabeçalho com botão minimizar
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                
                Controls.Label {
                    Layout.fillWidth: true
                    text: qsTr("Pausa terminada!")
                    font.bold: true
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize + 1
                }
                
                Controls.ToolButton {
                    icon.name: "window-minimize"
                    onClicked: {
                        if (root.hideWindow && typeof root.hideWindow.hide === "function") {
                            root.hideWindow.hide()
                        }
                    }
                }
            }
            
            // Título (mantido para layout, mas menor)
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
                        if (root.timerService) {
                            root.timerService.continueAfterBreak()
                        }
                    }
                }

                Controls.Button {
                    text: qsTr("Parar")
                    icon.name: "media-playback-stop"
                    Layout.fillWidth: true
                    Layout.preferredHeight: 50
                    onClicked: {
                        if (root.timerService) {
                            root.timerService.stopAfterBreak()
                        }
                    }
                }
            }
        }
    }
}
