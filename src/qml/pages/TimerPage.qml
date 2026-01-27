/**
 * TimerPage.qml
 * 
 * Página para gerenciar timers e worklogs locais
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

Kirigami.Page {
    id: page

    title: qsTr("Timer")
    
    focus: true
    
    property string selectedIssueKey: ""
    property var pendingWorklogs: []
    
    // Propriedade calculada que reage às mudanças de estado
    property bool hasActiveTimer: {
        if (!timerModel) return false
        var state = timerModel.state
        return state === "running" || state === "paused"
    }
    
    // Timer para atualizar display de tempo a cada segundo
    // Nota: timeDisplay será definido depois, então não podemos referenciá-lo aqui
    Timer {
        id: updateTimer
        interval: 1000  // Atualizar a cada segundo
        running: hasActiveTimer && timerModel
        repeat: true
        onTriggered: {
            // O binding do QML já atualiza automaticamente
            // Este timer apenas força a reavaliação periódica
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
    
    // Conectar mudanças de estado do timer
    Connections {
        id: timerModelConnections
        target: timerModel || null
        
        function onStateChanged() {
            if (timerModel) {
                console.log("TimerPage: Estado do timer mudou para:", timerModel.state)
                console.log("TimerPage: hasActiveTimer agora é:", hasActiveTimer)
            }
        }
        
        function onTimeUpdated() {
            // Tempo atualizado - o Timer já cuida da atualização visual
        }
        
        function onIssueKeyChanged() {
            if (timerModel) {
                console.log("TimerPage: Issue key mudou para:", timerModel.issueKey)
            }
        }
    }

    // Conectar sinais do timer
    Connections {
        id: timerServiceConnections
        target: timerService || null
        
        function onTick(seconds) {
            // Timer atualizado - o binding do QML já atualiza o display
        }
        
        function onPomodoroCompleted(pomodoroNum) {
            console.log("TimerPage: Pomodoro completado:", pomodoroNum)
            // Notificação no tray removida - a janela do timer será trazida para primeiro plano
            // com o questionamento interativo
        }
        
        function onBreakSuggested(breakType) {
            console.log("TimerPage: Pausa sugerida:", breakType)
        }
    }
    
    // Verificar disponibilidade dos serviços ao carregar
    Component.onCompleted: {
        console.log("TimerPage: ========================================")
        console.log("TimerPage: Component.onCompleted EXECUTADO!")
        console.log("TimerPage: Página Timer foi carregada")
        console.log("TimerPage: timerService disponível:", !!timerService)
        console.log("TimerPage: timerModel disponível:", !!timerModel)
        console.log("TimerPage: notificationService disponível:", !!notificationService)
        console.log("TimerPage: settingsModel disponível:", !!settingsModel)
        
        if (timerModel) {
            console.log("TimerPage: Estado inicial do timer:", timerModel.state)
            console.log("TimerPage: Issue key inicial:", timerModel.issueKey)
            console.log("TimerPage: Elapsed seconds inicial:", timerModel.elapsedSeconds)
        } else {
            console.error("TimerPage: timerModel NÃO está disponível!")
        }
        
        if (timerService) {
            console.log("TimerPage: timerService está disponível")
            console.log("TimerPage: timerService.start é função:", typeof timerService.start === "function")
        } else {
            console.error("TimerPage: timerService NÃO está disponível!")
        }
        console.log("TimerPage: ========================================")
    }
    
    // Conectar sinais do worklogSyncService para atualizar lista
    Connections {
        target: worklogSyncService || null
        
        function onSyncCompleted(count) {
            console.log("TimerPage: Sincronização concluída, %d worklogs sincronizados", count)
            // Atualizar lista de worklogs pendentes
            if (worklogSyncService) {
                pendingWorklogs = worklogSyncService.get_pending_worklogs()
                console.log("TimerPage: Lista atualizada após sincronização, worklogs pendentes:", pendingWorklogs.length)
            }
        }
        
        function onSessionSynced(sessionId, jiraWorklogId) {
            console.log("TimerPage: Worklog sincronizado:", sessionId, "->", jiraWorklogId)
            // Atualizar lista imediatamente quando um worklog é sincronizado
            if (worklogSyncService) {
                pendingWorklogs = worklogSyncService.get_pending_worklogs()
            }
        }
    }

    Controls.ScrollView {
        id: scrollView
        anchors.fill: parent
        clip: true

        ColumnLayout {
            id: mainLayout
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.mediumSpacing

            // Seção: Timer Ativo
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 200
                color: Kirigami.Theme.backgroundColor || "#f0f0f0"
                border.color: Kirigami.Theme.separatorColor || "#d0d0d0"
                border.width: 1
                radius: Kirigami.Units.smallSpacing
                visible: hasActiveTimer

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.mediumSpacing
                    spacing: Kirigami.Units.mediumSpacing

                    Controls.Label {
                        text: qsTr("Timer Ativo")
                        font.bold: true
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize + 2
                        Layout.fillWidth: true
                    }

                    Controls.Label {
                        text: timerModel ? timerModel.issueKey : ""
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize + 1
                        Layout.fillWidth: true
                    }

                    Controls.Label {
                        id: timeDisplay
                        // Binding inicial - o Timer atualiza depois
                        text: formatTime(timerModel ? timerModel.elapsedSeconds : 0)
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize + 4
                        font.bold: true
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        
                        // Também atualizar quando o modelo emitir sinal
                        Connections {
                            enabled: timerModel !== null && timerModel !== undefined
                            target: timerModel
                            function onTimeUpdated() {
                                if (timerModel) {
                                    timeDisplay.text = formatTime(timerModel.elapsedSeconds)
                                }
                            }
                        }
                    }

                    Controls.Label {
                        id: pomodoroLabelPage
                        text: qsTr("Pomodoro %1").arg(timerModel ? timerModel.currentPomodoro : 0)
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        visible: settingsModel && settingsModel.pomodoroEnabled
                        
                        // Garantir atualização quando signal for emitido
                        Connections {
                            target: timerModel || null
                            function onPomodoroCompleted(pomodoroNum) {
                                pomodoroLabelPage.text = qsTr("Pomodoro %1").arg(pomodoroNum)
                            }
                        }
                    }

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
                                if (timerService && timerModel && timerModel.state === "running") {
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
                                timerService.stop()
                            }
                        }
                    }
                }
            }

            // Seção: Iniciar Novo Timer
            Kirigami.FormLayout {
                Layout.fillWidth: true
                visible: !hasActiveTimer

                Controls.Label {
                    text: qsTr("Iniciar Timer")
                    font.bold: true
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize + 1
                    Layout.fillWidth: true
                }

                Controls.Label {
                    text: qsTr("Issue Key:")
                    font.bold: true
                    Layout.fillWidth: true
                }

                Controls.TextField {
                    id: issueKeyField
                    Layout.fillWidth: true
                    placeholderText: qsTr("PLATFORM-123")
                    text: selectedIssueKey
                    onTextChanged: {
                        selectedIssueKey = text.trim()
                        console.log("TimerPage: issueKeyField text mudou para:", text.trim())
                        console.log("TimerPage: Botão enabled agora:", startTimerButton ? startTimerButton.enabled : "N/A")
                    }
                }

                Controls.Button {
                    id: startTimerButton
                    text: qsTr("Iniciar Timer")
                    icon.name: "media-playback-start"
                    Layout.fillWidth: true
                    enabled: issueKeyField.text.trim().length > 0 && timerService && timerModel
                    
                    Component.onCompleted: {
                        console.log("TimerPage: Botão Iniciar Timer criado")
                        console.log("TimerPage: enabled inicial:", startTimerButton.enabled)
                        console.log("TimerPage: issueKeyField.text:", issueKeyField.text)
                        console.log("TimerPage: timerService:", !!timerService)
                        console.log("TimerPage: timerModel:", !!timerModel)
                    }
                    
                    onEnabledChanged: {
                        console.log("TimerPage: Botão enabled mudou para:", startTimerButton.enabled, 
                                   "text:", issueKeyField.text.trim(), 
                                   "hasService:", !!timerService, 
                                   "hasModel:", !!timerModel)
                    }
                    
                    onPressed: {
                        console.log("TimerPage: Botão PRESSIONADO (onPressed)")
                    }
                    
                    onClicked: {
                        console.log("TimerPage: ========================================")
                        console.log("TimerPage: onClicked EXECUTADO!")
                        var issueKey = issueKeyField.text.trim()
                        console.log("TimerPage: Clicou em Iniciar Timer")
                        console.log("TimerPage: issueKey:", issueKey)
                        console.log("TimerPage: timerService disponível:", !!timerService)
                        console.log("TimerPage: timerModel disponível:", !!timerModel)
                        
                        if (!timerService) {
                            console.error("TimerPage: timerService não está disponível!")
                            return
                        }
                        
                        if (!timerModel) {
                            console.error("TimerPage: timerModel não está disponível!")
                            return
                        }
                        
                        if (issueKey.length === 0) {
                            console.error("TimerPage: issueKey está vazio!")
                            return
                        }
                        
                        console.log("TimerPage: Estado ANTES de iniciar:", timerModel.state)
                        console.log("TimerPage: Chamando timerService.start(", issueKey, ")")
                        
                        try {
                            timerService.start(issueKey)
                            console.log("TimerPage: timerService.start() chamado com sucesso")
                            
                            // Verificar estado após um pequeno delay
                            Qt.callLater(function() {
                                console.log("TimerPage: Estado APÓS iniciar:", timerModel ? timerModel.state : "null")
                                console.log("TimerPage: hasActiveTimer:", hasActiveTimer)
                                console.log("TimerPage: elapsedSeconds:", timerModel ? timerModel.elapsedSeconds : "N/A")
                                console.log("TimerPage: issueKey no modelo:", timerModel ? timerModel.issueKey : "N/A")
                            })
                        } catch (e) {
                            console.error("TimerPage: ERRO ao chamar timerService.start():", e)
                        }
                        
                        console.log("========================================")
                    }
                }
            }

            // Separador
            Kirigami.Separator {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.mediumSpacing
            }

            // Seção: Estatísticas do Dia
            Controls.Label {
                text: qsTr("Estatísticas de Hoje")
                font.bold: true
                font.pointSize: Kirigami.Theme.defaultFont.pointSize + 1
                Layout.fillWidth: true
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.mediumSpacing

                ColumnLayout {
                    Layout.fillWidth: true

                    Controls.Label {
                        text: qsTr("Tempo Total")
                        font.bold: true
                        Layout.fillWidth: true
                    }

                    Controls.Label {
                        text: formatTime(timerModel ? timerModel.totalSecondsToday : 0)
                        Layout.fillWidth: true
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true

                    Controls.Label {
                        text: qsTr("Pomodoros")
                        font.bold: true
                        Layout.fillWidth: true
                    }

                    Controls.Label {
                        text: timerModel ? timerModel.pomodorosToday : 0
                        Layout.fillWidth: true
                    }
                }
            }

            // Separador
            Kirigami.Separator {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.mediumSpacing
            }

            // Seção: Worklogs Pendentes
            Controls.Label {
                text: qsTr("Worklogs Pendentes")
                font.bold: true
                font.pointSize: Kirigami.Theme.defaultFont.pointSize + 1
                Layout.fillWidth: true
            }

            // Lista de worklogs pendentes
            Repeater {
                id: pendingWorklogsRepeater
                model: pendingWorklogs
                
                delegate: Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 80
                    color: Kirigami.Theme.backgroundColor || "#f0f0f0"
                    border.color: Kirigami.Theme.separatorColor || "#d0d0d0"
                    border.width: 1
                    radius: Kirigami.Units.smallSpacing
                    
                    property var worklogData: pendingWorklogs[index] || {}
                    
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.smallSpacing
                        spacing: Kirigami.Units.mediumSpacing
                        
                        ColumnLayout {
                            Layout.fillWidth: true
                            
                            Controls.Label {
                                text: worklogData.issue_key || ""
                                font.bold: true
                                Layout.fillWidth: true
                            }
                            
                            Controls.Label {
                                text: {
                                    var duration = worklogData.duration_seconds || 0
                                    var hours = Math.floor(duration / 3600)
                                    var minutes = Math.floor((duration % 3600) / 60)
                                    return qsTr("%1h %2m").arg(hours).arg(minutes)
                                }
                                Layout.fillWidth: true
                                color: Kirigami.Theme.disabledTextColor || "#808080"
                            }
                            
                            Controls.Label {
                                text: {
                                    if (worklogData.start_time) {
                                        var date = new Date(worklogData.start_time)
                                        return Qt.formatDateTime(date, "dd/MM/yyyy HH:mm")
                                    }
                                    return ""
                                }
                                Layout.fillWidth: true
                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                                color: Kirigami.Theme.disabledTextColor || "#808080"
                            }
                        }
                        
                        Controls.Button {
                            text: qsTr("Sincronizar")
                            icon.name: "network-upload"
                            enabled: worklogSyncService !== null && worklogSyncService !== undefined
                            onClicked: {
                                if (worklogSyncService && worklogData.id) {
                                    var sessionIds = [worklogData.id]
                                    console.log("TimerPage: Sincronizando worklog:", worklogData.id)
                                    worklogSyncService.sync_pending_worklogs(sessionIds)
                                    // Atualizar lista após um pequeno delay
                                    Qt.callLater(function() {
                                        if (worklogSyncService) {
                                            pendingWorklogs = worklogSyncService.get_pending_worklogs()
                                            console.log("TimerPage: Lista atualizada, worklogs pendentes:", pendingWorklogs.length)
                                        }
                                    })
                                }
                            }
                        }
                    }
                }
            }
            
            Controls.Label {
                text: qsTr("Nenhum worklog pendente")
                Layout.fillWidth: true
                color: Kirigami.Theme.disabledTextColor || "#808080"
                visible: !worklogSyncService || (pendingWorklogs.length === 0)
            }
            
            Controls.Button {
                text: qsTr("Atualizar Lista")
                icon.name: "view-refresh"
                Layout.fillWidth: true
                enabled: worklogSyncService !== null && worklogSyncService !== undefined
                onClicked: {
                    if (worklogSyncService) {
                        pendingWorklogs = worklogSyncService.get_pending_worklogs()
                        console.log("TimerPage: Lista de worklogs atualizada, total:", pendingWorklogs.length)
                    }
                }
            }
        }
    }
}
