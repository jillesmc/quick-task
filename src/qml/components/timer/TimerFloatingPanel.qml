/**
 * TimerFloatingPanel.qml
 * 
 * Janela flutuante separada para exibir timer ativo
 * Aparece quando timer está rodando e pode ser minimizada/maximizada
 */
import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

Window {
    id: floatingWindow

    // Context property injetada pelo Python (timer window); não pode ser qualificada estaticamente
    property var timerModel: timerModel // qmllint disable unqualified
    property var timerService: timerService // qmllint disable unqualified
    property var settingsModel: settingsModel // qmllint disable unqualified

    // Configuração da janela
    title: qsTr("Timer Ativo")
    flags: Qt.Window | Qt.WindowStaysOnTopHint | Qt.FramelessWindowHint | Qt.Tool
    color: "transparent"

    // Dimensões
    width: 320
    height: 200
    minimumWidth: 320
    minimumHeight: 200

    // Posicionamento inicial (canto superior direito)
    x: 100
    y: 100

    // Visibilidade baseada no estado do timer
    visible: floatingWindow.timerModel && (floatingWindow.timerModel.state === "running" || floatingWindow.timerModel.state === "paused")
    
    Component.onCompleted: {
        // Posicionar no canto superior direito
        try {
            if (typeof Screen !== "undefined" && Screen.desktopAvailableWidth) {
                floatingWindow.x = Screen.desktopAvailableWidth - floatingWindow.width - 20
                floatingWindow.y = 20
            } else {
                // Fallback: posicionar em coordenadas fixas
                floatingWindow.x = 100
                floatingWindow.y = 100
            }
        } catch (e) {
            console.error("TimerFloatingPanel: Erro ao posicionar janela:", e)
            floatingWindow.x = 100
            floatingWindow.y = 100
        }
    }
    
    // Formatação de tempo
    function formatTime(seconds) {
        var hours = Math.floor(seconds / 3600)
        var minutes = Math.floor((seconds % 3600) / 60)
        var secs = seconds % 60
        return String(hours).padStart(2, '0') + ":" + 
               String(minutes).padStart(2, '0') + ":" + 
               String(secs).padStart(2, '0')
    }
    
    // Propriedade para rastrear se está arrastando (para otimização)
    property bool isDragging: false
    
    // Conteúdo da janela
    Rectangle {
        id: panel
        anchors.fill: parent
        color: Kirigami.Theme.backgroundColor || "#f0f0f0"
        border.color: Kirigami.Theme.highlightColor || "#3daee9"
        border.width: 2
        radius: Kirigami.Units.smallSpacing
        
        // Desabilitar layer durante drag para melhor performance
        layer.enabled: !floatingWindow.isDragging
        
        // Conteúdo da janela
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.mediumSpacing
            spacing: Kirigami.Units.smallSpacing
            
            // Cabeçalho com botões de controle
            RowLayout {
                Layout.fillWidth: true
                
                // Área de arrastar (cabeçalho)
                // NOTA: Este código não é mais usado - o drag é gerenciado em Python (timer_floating_window.py)
                // Mantido apenas para referência. A janela atual usa TimerFloatingPanelContent.qml
                MouseArea {
                    id: dragArea
                    Layout.fillWidth: true
                    Layout.preferredHeight: 30
                    acceptedButtons: Qt.LeftButton
                    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    
                    // Variáveis de controle para drag suave
                    property int lastMouseX: 0
                    property int lastMouseY: 0
                    property int windowStartX: 0
                    property int windowStartY: 0
                    
                    onPressed: function(mouse) {
                        windowStartX = floatingWindow.x
                        windowStartY = floatingWindow.y
                        var gp = dragArea.mapToGlobal(mouse.x, mouse.y)
                        lastMouseX = gp.x
                        lastMouseY = gp.y
                        floatingWindow.isDragging = true
                    }

                    onPositionChanged: function(mouse) {
                        if (pressed) {
                            var gp = dragArea.mapToGlobal(mouse.x, mouse.y)
                            var deltaX = gp.x - lastMouseX
                            var deltaY = gp.y - lastMouseY
                            
                            // Atualiza posição relativamente
                            var newX = windowStartX + deltaX
                            var newY = windowStartY + deltaY
                            
                            // Limitar aos limites da tela
                            var maxX = 0
                            var maxY = 0
                            try {
                                if (typeof Screen !== "undefined") {
                                    maxX = Screen.desktopAvailableWidth - floatingWindow.width
                                    maxY = Screen.desktopAvailableHeight - floatingWindow.height
                                }
                            } catch (e) {
                                maxX = 2000
                                maxY = 1000
                            }
                            
                            // Atualizar posição da janela diretamente
                            floatingWindow.x = Math.max(0, Math.min(newX, maxX))
                            floatingWindow.y = Math.max(0, Math.min(newY, maxY))
                            
                            lastMouseX = gp.x
                            lastMouseY = gp.y
                        }
                    }
                    
                    onReleased: {
                        floatingWindow.isDragging = false
                    }
                    
                    // Duplo clique para minimizar ao tray
                    onDoubleClicked: {
                        floatingWindow.visible = false
                    }
                    
                    Controls.Label {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("Timer Ativo")
                        font.bold: true
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize + 1
                    }
                }
                
                Controls.ToolButton {
                    icon.name: "window-minimize"
                    onClicked: {
                        // Minimizar ao tray (esconder janela)
                        floatingWindow.visible = false
                    }
                }
            }
            
            // Issue Key
            Controls.Label {
                text: floatingWindow.timerModel ? floatingWindow.timerModel.issueKey : ""
                font.pointSize: Kirigami.Theme.defaultFont.pointSize + 1
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
            }
            
            // Tempo decorrido
            Controls.Label {
                id: timeDisplay
                text: floatingWindow.formatTime(floatingWindow.timerModel ? floatingWindow.timerModel.elapsedSeconds : 0)
                font.pointSize: Kirigami.Theme.defaultFont.pointSize + 4
                font.bold: true
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                
                // Atualizar a cada segundo
                Connections {
                    target: floatingWindow.timerModel || null
                    function onTimeUpdated() {
                        if (floatingWindow.timerModel) {
                            timeDisplay.text = floatingWindow.formatTime(floatingWindow.timerModel.elapsedSeconds)
                        }
                    }
                }
            }
            
            // Pomodoro (se habilitado)
            Controls.Label {
                id: pomodoroLabelPanel
                text: qsTr("Pomodoro %1").arg(floatingWindow.timerModel ? floatingWindow.timerModel.currentPomodoro : 0)
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                visible: floatingWindow.settingsModel && floatingWindow.settingsModel.pomodoroEnabled
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                
                // Garantir atualização quando signal for emitido
                Connections {
                    target: floatingWindow.timerModel || null
                    function onPomodoroCompleted(pomodoroNum) {
                        pomodoroLabelPanel.text = qsTr("Pomodoro %1").arg(pomodoroNum)
                    }
                }
            }
            
            // Controles
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                
                Controls.Button {
                    text: qsTr("Pausar")
                    icon.name: "media-playback-pause"
                    Layout.fillWidth: true
                    enabled: floatingWindow.timerModel && floatingWindow.timerModel.state === "running" && !floatingWindow.timerModel.isOnBreak && !floatingWindow.timerModel.isWaitingBreakDecision
                    visible: floatingWindow.timerModel && floatingWindow.timerModel.state === "running" && !floatingWindow.timerModel.isOnBreak && !floatingWindow.timerModel.isWaitingBreakDecision && !floatingWindow.timerModel.isWaitingBreakEndDecision
                    onClicked: {
                        if (floatingWindow.timerService && floatingWindow.timerModel && floatingWindow.timerModel.state === "running") {
                            floatingWindow.timerService.pause()
                        }
                    }
                }

                Controls.Button {
                    text: qsTr("Parar")
                    icon.name: "media-playback-stop"
                    Layout.fillWidth: true
                    enabled: floatingWindow.timerModel && floatingWindow.timerModel.state !== "idle"
                    onClicked: {
                        if (floatingWindow.timerService) {
                            floatingWindow.timerService.stop()
                        }
                        // Fechar janela após parar
                        floatingWindow.visible = false
                    }
                }
            }
        }
    }
    
    // Fechar janela quando timer parar (gerenciado pelo Main.qml)
}
