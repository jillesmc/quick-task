/**
 * PomodoroBreakPrompt.qml
 * 
 * Componente de alerta quando pomodoro completa
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

pragma ComponentBehavior: Bound
Item {
    id: root

    property int pomodoroNum: 0
    property string breakType: ""
    property int autoContinueTimeout: 30
    property int remainingSeconds: autoContinueTimeout
    property var timerService: null
    property var timerModel: null
    property var hideWindow: null
    property var settingsModel: null

    Timer {
        id: countdownTimer
        interval: 1000
        running: false
        repeat: true
        onTriggered: {
            if (root.remainingSeconds > 0) {
                root.remainingSeconds--
            } else {
                countdownTimer.stop()
                if (root.timerService) {
                    root.timerService.continueWithoutBreak()
                }
            }
        }
    }

    Connections {
        target: root.timerModel || null
        function onTimeUpdated() {
            if (root.timerModel && !root.timerModel.isWaitingBreakDecision) {
                countdownTimer.stop()
            }
        }
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
                    text: qsTr("Timer Ativo")
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
            
            // Título
            Controls.Label {
                text: qsTr("Pomodoro %1 completado!").arg(root.pomodoroNum)
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
                text: qsTr("Continuando automaticamente em %1s...").arg(root.remainingSeconds)
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
                        if (root.timerService && root.breakType) {
                            root.timerService.acceptBreak(root.breakType)
                        }
                    }
                }

                Controls.Button {
                    text: qsTr("Continuar")
                    icon.name: "media-playback-start"
                    Layout.fillWidth: true
                    Layout.preferredHeight: 50
                    onClicked: {
                        if (root.timerService) {
                            root.timerService.continueWithoutBreak()
                        }
                    }
                }
            }
        }
    }
    
    Connections {
        target: root.timerModel || null
        function onBreakDecisionRequested(pomodoro_num, break_type) {
            root.pomodoroNum = pomodoro_num
            root.breakType = break_type
            root.remainingSeconds = root.autoContinueTimeout
            countdownTimer.start()
        }
    }

    Component.onCompleted: {
        if (root.settingsModel && root.settingsModel.autoContinueTimeoutSeconds) {
            root.autoContinueTimeout = root.settingsModel.autoContinueTimeoutSeconds
            root.remainingSeconds = root.autoContinueTimeout
        }
    }
}
