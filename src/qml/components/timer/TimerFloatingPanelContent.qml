/**
 * TimerFloatingPanelContent.qml
 * 
 * Conteúdo do painel flutuante do timer (sem Window, apenas Item)
 * A janela é gerenciada pelo Python (TimerFloatingWindow)
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

Item {
    id: root
    
    // QQuickView com SizeRootObjectToView redimensiona automaticamente
    // Não precisamos definir tamanho explícito
    
    // Formatação de tempo
    function formatTime(seconds) {
        var hours = Math.floor(seconds / 3600)
        var minutes = Math.floor((seconds % 3600) / 60)
        var secs = seconds % 60
        return String(hours).padStart(2, '0') + ":" + 
               String(minutes).padStart(2, '0') + ":" + 
               String(secs).padStart(2, '0')
    }
    
    // Conteúdo da janela
    Rectangle {
        id: panel
        anchors.fill: parent
        color: Kirigami.Theme.backgroundColor || "#f0f0f0"
        border.color: Kirigami.Theme.highlightColor || "#3daee9"
        border.width: 2
        radius: Kirigami.Units.smallSpacing
        
        // Conteúdo da janela
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.mediumSpacing
            spacing: Kirigami.Units.smallSpacing
            
            // Cabeçalho com botões de controle
            RowLayout {
                Layout.fillWidth: true
                
                // Área de título (drag é gerenciado pelo Python)
                Controls.Label {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 30
                    text: qsTr("Timer Ativo")
                    font.bold: true
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize + 1
                }
                
                Controls.ToolButton {
                    icon.name: "window-minimize"
                    onClicked: {
                        // Minimizar ao tray (esconder janela)
                        // Será gerenciado pelo Python
                        if (typeof hideWindow === "function") {
                            hideWindow()
                        }
                    }
                }
            }
            
            // Issue Key
            Controls.Label {
                text: timerModel ? timerModel.issueKey : ""
                font.pointSize: Kirigami.Theme.defaultFont.pointSize + 1
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
            }
            
            // Tempo decorrido
            Controls.Label {
                id: timeDisplay
                text: formatTime(timerModel ? timerModel.elapsedSeconds : 0)
                font.pointSize: Kirigami.Theme.defaultFont.pointSize + 4
                font.bold: true
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                
                // Atualizar a cada segundo
                Connections {
                    target: timerModel || null
                    function onTimeUpdated() {
                        if (timerModel) {
                            timeDisplay.text = formatTime(timerModel.elapsedSeconds)
                        }
                    }
                }
            }
            
            // Pomodoro (se habilitado)
            Controls.Label {
                text: qsTr("Pomodoro %1").arg(timerModel ? timerModel.currentPomodoro : 0)
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                visible: settingsModel && settingsModel.pomodoroEnabled
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }
            
            // Controles
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                
                Controls.Button {
                    text: timerModel && timerModel.state === "paused" ? qsTr("Retomar") : qsTr("Pausar")
                    icon.name: timerModel && timerModel.state === "paused" ? "media-playback-start" : "media-playback-pause"
                    Layout.fillWidth: true
                    enabled: timerModel && (timerModel.state === "running" || timerModel.state === "paused")
                    onClicked: {
                        console.log("TimerFloatingPanel: Botão Pausar/Retomar clicado, estado atual:", timerModel ? timerModel.state : "null")
                        if (timerModel && timerModel.state === "paused") {
                            if (timerService) {
                                console.log("TimerFloatingPanel: Chamando resume()")
                                timerService.resume()
                            }
                        } else if (timerModel && timerModel.state === "running") {
                            if (timerService) {
                                console.log("TimerFloatingPanel: Chamando pause()")
                                timerService.pause()
                            }
                        }
                    }
                }
                
                Controls.Button {
                    text: qsTr("Parar")
                    icon.name: "media-playback-stop"
                    Layout.fillWidth: true
                    enabled: timerModel && timerModel.state !== "idle"
                    onClicked: {
                        console.log("TimerFloatingPanel: Botão Parar clicado")
                        if (timerService) {
                            console.log("TimerFloatingPanel: Chamando stop()")
                            timerService.stop()
                        }
                        // Fechar janela após parar (será gerenciado pelo Python)
                        if (typeof hideWindow === "function") {
                            hideWindow()
                        }
                    }
                }
            }
        }
    }
}
