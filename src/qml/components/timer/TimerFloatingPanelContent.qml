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

    property var timerModel: timerModel // qmllint disable unqualified
    property var timerService: timerService // qmllint disable unqualified
    property var hideWindow: hideWindow // qmllint disable unqualified
    property var settingsModel: settingsModel // qmllint disable unqualified

    // Habilitar foco para capturar eventos de mouse/teclado
    // Necessário para que a janela seja clicável (Hipótese 1 do diagnóstico)
    focus: true
    
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
    
    // StackLayout para alternar entre diferentes conteúdos
    StackLayout {
        id: contentStack
        anchors.fill: parent
        
        // Conteúdo normal do timer
        Rectangle {
            id: normalPanel
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
                        try {
                            if (root.hideWindow) {
                                root.hideWindow.hide()
                            }
                        } catch (e) {
                            console.error("TimerFloatingPanel: Erro ao minimizar janela:", e)
                        }
                    }
                }
            }
            
            // Issue Key
            Controls.Label {
                text: root.timerModel ? root.timerModel.issueKey : ""
                font.pointSize: Kirigami.Theme.defaultFont.pointSize + 1
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
            }
            
            // Tempo decorrido
            Controls.Label {
                id: timeDisplay
                text: root.formatTime(root.timerModel ? root.timerModel.elapsedSeconds : 0)
                font.pointSize: Kirigami.Theme.defaultFont.pointSize + 4
                font.bold: true
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                
                // Atualizar a cada segundo
                Connections {
                    target: root.timerModel || null
        function onTimeUpdated() {
            if (root.timerModel) {
                timeDisplay.text = root.formatTime(root.timerModel.elapsedSeconds)
                        }
                    }
                }
            }
            
            // Pomodoro (se habilitado)
            Controls.Label {
                id: pomodoroLabel
                text: qsTr("Pomodoro %1").arg(root.timerModel ? root.timerModel.currentPomodoro : 0)
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                visible: root.settingsModel && root.settingsModel.pomodoroEnabled
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                
                // Garantir atualização quando signal for emitido
                Connections {
                    target: root.timerModel || null
                    function onPomodoroCompleted(pomodoroNum) {
                        pomodoroLabel.text = qsTr("Pomodoro %1").arg(pomodoroNum)
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
                    enabled: root.timerModel && root.timerModel.state === "running" && !root.timerModel.isOnBreak && !root.timerModel.isWaitingBreakDecision
                    visible: root.timerModel && root.timerModel.state === "running" && !root.timerModel.isOnBreak && !root.timerModel.isWaitingBreakDecision && !root.timerModel.isWaitingBreakEndDecision
                    onClicked: {
                        console.log("TimerFloatingPanel: Botão Pausar clicado")
                        if (root.timerService && root.timerModel && root.timerModel.state === "running") {
                            console.log("TimerFloatingPanel: Chamando pause()")
                            root.timerService.pause()
                        }
                    }
                }
                
                Controls.Button {
                    text: qsTr("Parar")
                    icon.name: "media-playback-stop"
                    Layout.fillWidth: true
                    enabled: root.timerModel && root.timerModel.state !== "idle" && !root.timerModel.isOnBreak && !root.timerModel.isWaitingBreakEndDecision
                    visible: root.timerModel && root.timerModel.state !== "idle" && !root.timerModel.isOnBreak && !root.timerModel.isWaitingBreakEndDecision
                    onClicked: {
                        console.log("TimerFloatingPanel: Botão Parar clicado")
                        if (root.timerService) {
                            console.log("TimerFloatingPanel: Chamando stop()")
                            root.timerService.stop()
                        }
                        // Fechar janela após parar (será gerenciado pelo Python)
                        if (root.hideWindow && typeof root.hideWindow.hide === "function") {
                            root.hideWindow.hide()
                        }
                    }
                }
            }
            }
        }
        
        // Alerta de pomodoro completo
        PomodoroBreakPrompt {
            id: breakPrompt
            timerModel: root.timerModel
            timerService: root.timerService
            hideWindow: root.hideWindow
            settingsModel: root.settingsModel
        }
        
        // Contagem regressiva da pausa
        BreakCountdown {
            id: breakCountdown
            timerModel: root.timerModel
            timerService: root.timerService
            hideWindow: root.hideWindow
        }

        // Questionamento após pausa terminar
        BreakEndPrompt {
            id: breakEndPrompt
            timerService: root.timerService
            hideWindow: root.hideWindow
        }
    }
    
    // Determinar qual conteúdo mostrar
    states: [
        State {
            name: "normal"
            when: !root.timerModel || (!root.timerModel.isWaitingBreakDecision && !root.timerModel.isOnBreak && !root.timerModel.isWaitingBreakEndDecision)
            PropertyChanges {
                contentStack.currentIndex: 0
            }
        },
        State {
            name: "breakDecision"
            when: root.timerModel && root.timerModel.isWaitingBreakDecision
            PropertyChanges {
                contentStack.currentIndex: 1
            }
        },
        State {
            name: "onBreak"
            when: root.timerModel && root.timerModel.isOnBreak
            PropertyChanges {
                contentStack.currentIndex: 2
            }
        },
        State {
            name: "breakEnd"
            when: root.timerModel && root.timerModel.isWaitingBreakEndDecision
            PropertyChanges {
                contentStack.currentIndex: 3
            }
        }
    ]
}
