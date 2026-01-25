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
        
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.mediumSpacing
            
            // Título
            Controls.Label {
                text: timerModel && timerModel.breakType === "long" 
                    ? qsTr("Pausa Longa") 
                    : qsTr("Pausa Curta")
                font.pointSize: Kirigami.Theme.defaultFont.pointSize + 3
                font.bold: true
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
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
        }
    }
}
