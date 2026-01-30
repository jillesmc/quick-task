/**
 * TimerPage.qml
 *
 * Página para gerenciar timers e worklogs locais
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami
import "../components/timer"

Kirigami.Page {
    id: page

    title: qsTr("Timer")

    focus: true

    property string selectedIssueKey: ""
    property var pendingWorklogs: []

    // Propriedade calculada que reage às mudanças de estado
    property bool hasActiveTimer: {
        if (!timerModel)
            return false;
        var state = timerModel.state;
        return state === "running" || state === "paused";
    }

    // Conectar mudanças de estado do timer
    Connections {
        id: timerModelConnections
        target: timerModel || null

        function onStateChanged() {
            if (timerModel) {
                console.log("TimerPage: Estado do timer mudou para:", timerModel.state);
                console.log("TimerPage: hasActiveTimer agora é:", hasActiveTimer);
            }
        }

        function onTimeUpdated() {
            // Tempo atualizado - o Timer já cuida da atualização visual
        }

        function onIssueKeyChanged() {
            if (timerModel) {
                console.log("TimerPage: Issue key mudou para:", timerModel.issueKey);
            }
        }
    }

    // Conectar sinais do worklog sync service
    Connections {
        id: worklogSyncConnections
        target: worklogSyncService || null

        function onSyncCompleted(count) {
            // Atualizar lista quando sincronização for concluída
            if (worklogSyncService) {
                pendingWorklogs = worklogSyncService.get_pending_worklogs();
                console.log("TimerPage: Lista atualizada após sincronização, worklogs pendentes:", pendingWorklogs.length);
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
            console.log("TimerPage: Pomodoro completado:", pomodoroNum);
            // Notificação no tray removida - a janela do timer será trazida para primeiro plano
            // com o questionamento interativo
        }

        function onBreakSuggested(breakType) {
            console.log("TimerPage: Pausa sugerida:", breakType);
        }
    }

    // Verificar disponibilidade dos serviços ao carregar
    Component.onCompleted: {
        console.log("TimerPage: ========================================");
        console.log("TimerPage: Component.onCompleted EXECUTADO!");
        console.log("TimerPage: Página Timer foi carregada");
        console.log("TimerPage: timerService disponível:", !!timerService);
        console.log("TimerPage: timerModel disponível:", !!timerModel);
        console.log("TimerPage: notificationService disponível:", !!notificationService);
        console.log("TimerPage: settingsModel disponível:", !!settingsModel);

        if (timerModel) {
            console.log("TimerPage: Estado inicial do timer:", timerModel.state);
            console.log("TimerPage: Issue key inicial:", timerModel.issueKey);
            console.log("TimerPage: Elapsed seconds inicial:", timerModel.elapsedSeconds);
        } else {
            console.error("TimerPage: timerModel NÃO está disponível!");
        }

        if (timerService) {
            console.log("TimerPage: timerService está disponível");
            console.log("TimerPage: timerService.start é função:", typeof timerService.start === "function");
        } else {
            console.error("TimerPage: timerService NÃO está disponível!");
        }
        console.log("TimerPage: ========================================");
    }

    // Conectar sinais do worklogSyncService para atualizar lista
    Connections {
        target: worklogSyncService || null

        function onSyncCompleted(count) {
            console.log("TimerPage: Sincronização concluída, %d worklogs sincronizados", count);
            // Atualizar lista de worklogs pendentes
            if (worklogSyncService) {
                pendingWorklogs = worklogSyncService.get_pending_worklogs();
                console.log("TimerPage: Lista atualizada após sincronização, worklogs pendentes:", pendingWorklogs.length);
            }
        }

        function onSessionSynced(sessionId, jiraWorklogId) {
            console.log("TimerPage: Worklog sincronizado:", sessionId, "->", jiraWorklogId);
            // Atualizar lista imediatamente quando um worklog é sincronizado
            if (worklogSyncService) {
                pendingWorklogs = worklogSyncService.get_pending_worklogs();
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
            anchors.margins: 20
            spacing: Kirigami.Units.mediumSpacing

            TimerActiveBlock {
                Layout.fillWidth: true
                timerModel: page.timerModel
                timerService: page.timerService
                settingsModel: page.settingsModel
            }

            TimerStartBlock {
                id: timerStartBlock
                Layout.fillWidth: true
                timerService: page.timerService
                timerModel: page.timerModel
                selectedIssueKey: page.selectedIssueKey
                hasActiveTimer: page.hasActiveTimer
            }

            Binding {
                target: page
                property: "selectedIssueKey"
                value: timerStartBlock.selectedIssueKey
                when: timerStartBlock
            }

            // Separador
            Kirigami.Separator {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.mediumSpacing
            }

            TimerStatsBlock {
                Layout.fillWidth: true
                timerModel: page.timerModel
            }

            // Separador
            Kirigami.Separator {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.mediumSpacing
            }

            TimerPendingWorklogsBlock {
                id: timerPendingBlock
                Layout.fillWidth: true
                pendingWorklogs: page.pendingWorklogs
                worklogSyncService: page.worklogSyncService

                onRefreshRequested: {
                    if (worklogSyncService) {
                        page.pendingWorklogs = worklogSyncService.get_pending_worklogs();
                    }
                }
            }
        }
    }
}
