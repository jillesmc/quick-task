/**
 * PomodoroBreakPrompt.qml
 * 
 * Componente de alerta quando pomodoro completa
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

Item {
    id: root
    
    property int pomodoroNum: 0
    property string breakType: ""
    property int autoContinueTimeout: 30
    property int remainingSeconds: autoContinueTimeout
    
    Timer {
        id: countdownTimer
        interval: 1000
        running: false
        repeat: true
        onTriggered: {
            if (remainingSeconds > 0) {
                remainingSeconds--
            } else {
                // Timeout - continuar automaticamente
                countdownTimer.stop()
                if (timerService) {
                    timerService.continueWithoutBreak()
                }
            }
        }
    }
    
    // Parar contador quando alerta for escondido
    Connections {
        target: timerModel || null
        function onTimeUpdated() {
            if (timerModel && !timerModel.isWaitingBreakDecision) {
                countdownTimer.stop()
            }
        }
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
                text: qsTr("Pomodoro %1 completado!").arg(pomodoroNum)
                font.pointSize: Kirigami.Theme.defaultFont.pointSize + 4
                font.bold: true
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
            }
            
            // Mensagem
            Controls.Label {
                text: qsTr("Deseja fazer uma pausa?")
                font.pointSize: Kirigami.Theme.defaultFont.pointSize + 1
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
            }
            
            // Contador regressivo
            Controls.Label {
                text: qsTr("Continuando automaticamente em %1s...").arg(remainingSeconds)
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                color: Kirigami.Theme.neutralTextColor || "#666666"
            }
            
            Item {
                Layout.fillHeight: true
            }
            
            // Botões
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.mediumSpacing
                
                Controls.Button {
                    text: qsTr("Fazer Pausa")
                    icon.name: "media-playback-pause"
                    Layout.fillWidth: true
                    Layout.preferredHeight: 50
                    onClicked: {
                        if (timerService && breakType) {
                            timerService.acceptBreak(breakType)
                        }
                    }
                }
                
                Controls.Button {
                    text: qsTr("Continuar")
                    icon.name: "media-playback-start"
                    Layout.fillWidth: true
                    Layout.preferredHeight: 50
                    onClicked: {
                        if (timerService) {
                            timerService.continueWithoutBreak()
                        }
                    }
                }
            }
        }
    }
    
    Connections {
        target: timerModel || null
        function onBreakDecisionRequested(pomodoro_num, break_type) {
            pomodoroNum = pomodoro_num
            breakType = break_type
            remainingSeconds = autoContinueTimeout
            countdownTimer.start()
        }
    }
    
    Component.onCompleted: {
        if (settingsModel && settingsModel.autoContinueTimeoutSeconds) {
            autoContinueTimeout = settingsModel.autoContinueTimeoutSeconds
            remainingSeconds = autoContinueTimeout
        }
    }
}
