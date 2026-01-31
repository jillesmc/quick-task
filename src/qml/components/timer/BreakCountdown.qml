pragma ComponentBehavior: Bound
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

    property var timerModel: null
    property var timerService: null
    property var hideWindow: null

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
                    text: root.timerModel && root.timerModel.breakType === "long"
                        ? qsTr("Pausa Longa")
                        : qsTr("Pausa Curta")
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
            
            Item {
                Layout.fillHeight: true
            }
            
            // Contador regressivo grande
            Controls.Label {
                id: countdownDisplay
                text: root.formatTime(root.timerModel ? root.timerModel.breakRemainingSeconds : 0)
                font.pointSize: Kirigami.Theme.defaultFont.pointSize + 8
                font.bold: true
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                
                Connections {
                    target: root.timerModel || null
                    function onTimeUpdated() {
                        if (root.timerModel) {
                            countdownDisplay.text = root.formatTime(root.timerModel.breakRemainingSeconds)
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
                    if (root.timerService && root.timerModel) {
                        var issueKey = root.timerModel.issueKey
                        root.timerService.cancelBreak()
                        Qt.callLater(function() {
                            if (root.timerService && issueKey) {
                                root.timerService.start(issueKey)
                            }
                        })
                    }
                }
            }
        }
    }
}
