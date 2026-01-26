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
                        // Minimizar ao tray (esconder janela)
                        // hideWindow é um QObject com método hide() exposto via @Slot()
                        console.log("TimerFloatingPanel: Botão minimizar clicado")
                        console.log("TimerFloatingPanel: typeof hideWindow =", typeof hideWindow)
                        if (hideWindow) {
                            console.log("TimerFloatingPanel: hideWindow encontrado, verificando método hide...")
                            console.log("TimerFloatingPanel: typeof hideWindow.hide =", typeof hideWindow.hide)
                            if (typeof hideWindow.hide === "function") {
                                console.log("TimerFloatingPanel: hideWindow.hide encontrado, chamando...")
                                try {
                                    hideWindow.hide()
                                    console.log("TimerFloatingPanel: hideWindow.hide() chamado com sucesso")
                                } catch (e) {
                                    console.log("TimerFloatingPanel: ERRO ao chamar hideWindow.hide():", e)
                                    console.log("TimerFloatingPanel: Mensagem de erro:", e.toString())
                                }
                            } else {
                                console.log("TimerFloatingPanel: ERRO - hideWindow.hide não é uma função")
                            }
                        } else {
                            console.log("TimerFloatingPanel: ERRO - hideWindow não está disponível")
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
                    text: qsTr("Pausar")
                    icon.name: "media-playback-pause"
                    Layout.fillWidth: true
                    enabled: timerModel && timerModel.state === "running" && !timerModel.isOnBreak && !timerModel.isWaitingBreakDecision
                    visible: timerModel && timerModel.state === "running" && !timerModel.isOnBreak && !timerModel.isWaitingBreakDecision && !timerModel.isWaitingBreakEndDecision
                    onClicked: {
                        console.log("TimerFloatingPanel: Botão Pausar clicado")
                        if (timerService && timerModel && timerModel.state === "running") {
                            console.log("TimerFloatingPanel: Chamando pause()")
                            timerService.pause()
                        }
                    }
                }
                
                Controls.Button {
                    text: qsTr("Parar")
                    icon.name: "media-playback-stop"
                    Layout.fillWidth: true
                    enabled: timerModel && timerModel.state !== "idle" && !timerModel.isOnBreak && !timerModel.isWaitingBreakEndDecision
                    visible: timerModel && timerModel.state !== "idle" && !timerModel.isOnBreak && !timerModel.isWaitingBreakEndDecision
                    onClicked: {
                        console.log("TimerFloatingPanel: Botão Parar clicado")
                        if (timerService) {
                            console.log("TimerFloatingPanel: Chamando stop()")
                            timerService.stop()
                        }
                        // Fechar janela após parar (será gerenciado pelo Python)
                        if (hideWindow && typeof hideWindow.hide === "function") {
                            hideWindow.hide()
                        }
                    }
                }
            }
            }
        }
        
        // Alerta de pomodoro completo
        PomodoroBreakPrompt {
            id: breakPrompt
        }
        
        // Contagem regressiva da pausa
        BreakCountdown {
            id: breakCountdown
        }
        
        // Questionamento após pausa terminar
        BreakEndPrompt {
            id: breakEndPrompt
        }
    }
    
    // Determinar qual conteúdo mostrar
    states: [
        State {
            name: "normal"
            when: !timerModel || (!timerModel.isWaitingBreakDecision && !timerModel.isOnBreak && !timerModel.isWaitingBreakEndDecision)
            PropertyChanges {
                target: contentStack
                currentIndex: 0
            }
        },
        State {
            name: "breakDecision"
            when: timerModel && timerModel.isWaitingBreakDecision
            PropertyChanges {
                target: contentStack
                currentIndex: 1
            }
        },
        State {
            name: "onBreak"
            when: timerModel && timerModel.isOnBreak
            PropertyChanges {
                target: contentStack
                currentIndex: 2
            }
        },
        State {
            name: "breakEnd"
            when: timerModel && timerModel.isWaitingBreakEndDecision
            PropertyChanges {
                target: contentStack
                currentIndex: 3
            }
        }
    ]
}
