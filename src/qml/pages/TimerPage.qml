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

    // Context properties são injetadas pelo Python - não podem ser qualificadas
    property var _ctxTimerModel: timerModel // qmllint disable unqualified
    property var _ctxTimerService: timerService // qmllint disable unqualified
    property var _ctxWorklogSyncService: worklogSyncService // qmllint disable unqualified
    property var _ctxSettingsModel: settingsModel // qmllint disable unqualified
    property var _ctxNotificationService: notificationService // qmllint disable unqualified

    // Property aliases para expor propriedades aos componentes filhos
    property alias timerModel: page._ctxTimerModel
    property alias timerService: page._ctxTimerService
    property alias worklogSyncService: page._ctxWorklogSyncService
    property alias settingsModel: page._ctxSettingsModel

    // Propriedade calculada que reage às mudanças de estado
    property bool hasActiveTimer: {
        if (!page._ctxTimerModel)
            return false;
        var state = page._ctxTimerModel.state;
        return state === "running" || state === "paused";
    }

    // Conectar mudanças de estado do timer
    Connections {
        id: timerModelConnections
        target: page._ctxTimerModel || null

        function onStateChanged() {
            if (page._ctxTimerModel) {
                console.log("TimerPage: Estado do timer mudou para:", page._ctxTimerModel.state);
                console.log("TimerPage: hasActiveTimer agora é:", page.hasActiveTimer);
            }
        }

        function onTimeUpdated() {
            // Tempo atualizado - o Timer já cuida da atualização visual
        }

        function onIssueKeyChanged() {
            if (page._ctxTimerModel) {
                console.log("TimerPage: Issue key mudou para:", page._ctxTimerModel.issueKey);
            }
        }
    }

    // Conectar sinais do worklog sync service
    Connections {
        id: worklogSyncConnections
        target: page._ctxWorklogSyncService || null

        function onSyncCompleted(count) {
            // Atualizar lista quando sincronização for concluída
            if (page._ctxWorklogSyncService) {
                page.pendingWorklogs = page._ctxWorklogSyncService.get_pending_worklogs();
                console.log("TimerPage: Lista atualizada após sincronização, worklogs pendentes:", page.pendingWorklogs.length);
            }
        }
    }

    // Conectar sinais do timer
    Connections {
        id: timerServiceConnections
        target: page._ctxTimerService || null

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
        console.log("TimerPage: timerService disponível:", !!page._ctxTimerService);
        console.log("TimerPage: timerModel disponível:", !!page._ctxTimerModel);
        console.log("TimerPage: notificationService disponível:", !!page._ctxNotificationService);
        console.log("TimerPage: settingsModel disponível:", !!page._ctxSettingsModel);

        if (page._ctxTimerModel) {
            console.log("TimerPage: Estado inicial do timer:", page._ctxTimerModel.state);
            console.log("TimerPage: Issue key inicial:", page._ctxTimerModel.issueKey);
            console.log("TimerPage: Elapsed seconds inicial:", page._ctxTimerModel.elapsedSeconds);
        } else {
            console.error("TimerPage: timerModel NÃO está disponível!");
        }

        if (page._ctxTimerService) {
            console.log("TimerPage: timerService está disponível");
            console.log("TimerPage: timerService.start é função:", typeof page._ctxTimerService.start === "function");
        } else {
            console.error("TimerPage: timerService NÃO está disponível!");
        }
        console.log("TimerPage: ========================================");
    }

    // Conectar sinais do worklogSyncService para atualizar lista
    Connections {
        target: page._ctxWorklogSyncService || null

        function onSyncCompleted(count) {
            console.log("TimerPage: Sincronização concluída, %d worklogs sincronizados", count);
            // Atualizar lista de worklogs pendentes
            if (page._ctxWorklogSyncService) {
                page.pendingWorklogs = page._ctxWorklogSyncService.get_pending_worklogs();
                console.log("TimerPage: Lista atualizada após sincronização, worklogs pendentes:", page.pendingWorklogs.length);
            }
        }

        function onSessionSynced(sessionId, jiraWorklogId) {
            console.log("TimerPage: Worklog sincronizado:", sessionId, "->", jiraWorklogId);
            // Atualizar lista imediatamente quando um worklog é sincronizado
            if (page._ctxWorklogSyncService) {
                page.pendingWorklogs = page._ctxWorklogSyncService.get_pending_worklogs();
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

            TimerActiveBlock {
                Layout.fillWidth: true
                timerModel: page._ctxTimerModel
                timerService: page._ctxTimerService
                settingsModel: page._ctxSettingsModel
            }

            TimerStartBlock {
                id: timerStartBlock
                Layout.fillWidth: true
                timerService: page._ctxTimerService
                timerModel: page._ctxTimerModel
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
                timerModel: page._ctxTimerModel
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
                worklogSyncService: page._ctxWorklogSyncService

                onRefreshRequested: {
                    if (page._ctxWorklogSyncService) {
                        page.pendingWorklogs = page._ctxWorklogSyncService.get_pending_worklogs();
                    }
                }
            }
        }
    }
}
