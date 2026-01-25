/**
 * BreakCountdown.qml
 * 
 * Componente de contagem regressiva durante a pausa
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

Item {
    id: root
    
    function formatTime(seconds) {
        var minutes = Math.floor(seconds / 60)
        var secs = seconds % 60
        return String(minutes).padStart(2, '0') + ":" + String(secs).padStart(2, '0')
    }
    
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
                    text: timerModel && timerModel.breakType === "long" 
                        ? qsTr("Pausa Longa") 
                        : qsTr("Pausa Curta")
                    font.bold: true
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize + 1
                }
                
                Controls.ToolButton {
                    icon.name: "window-minimize"
                    onClicked: {
                        // Minimizar ao tray (esconder janela)
                        if (hideWindow && typeof hideWindow.hide === "function") {
                            hideWindow.hide()
                        }
                    }
                }
            }
            
            Item {
                Layout.fillHeight: true
            }
            
            // Contador regressivo grande
            Controls.Label {
                id: countdownDisplay
                text: formatTime(timerModel ? timerModel.breakRemainingSeconds : 0)
                font.pointSize: Kirigami.Theme.defaultFont.pointSize + 8
                font.bold: true
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                
                Connections {
                    target: timerModel || null
                    function onTimeUpdated() {
                        if (timerModel) {
                            countdownDisplay.text = formatTime(timerModel.breakRemainingSeconds)
                        }
                    }
                }
            }
            
            Item {
                Layout.fillHeight: true
            }
            
            // Botão "Continuar já"
            Controls.Button {
                text: qsTr("Continuar já")
                icon.name: "media-playback-start"
                Layout.fillWidth: true
                Layout.preferredHeight: 50
                onClicked: {
                    if (timerService && timerModel) {
                        // Cancelar pausa e iniciar timer imediatamente
                        var issueKey = timerModel.issueKey
                        timerService.cancelBreak()
                        Qt.callLater(function() {
                            if (timerService && issueKey) {
                                timerService.start(issueKey)
                            }
                        })
                    }
                }
            }
        }
    }
}
