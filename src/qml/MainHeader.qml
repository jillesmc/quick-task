/**
 * MainHeader.qml
 *
 * Header da janela principal: TabBar (Criar Issue, Minhas Issues, Timer, Configuração)
 * e botões globais (ação principal + Iniciar Timer na aba Minhas Issues).
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

RowLayout {
    id: root

    property alias tabBar: tabBar
    property var stack: null
    property var createPage: null
    property var issuesPage: null
    property var settingsPage: null
    property var issueModel: null
    property var jiraService: null
    property var timerModel: null
    property var timerService: null

    width: parent ? parent.width : 0
    spacing: Kirigami.Units.smallSpacing

    Controls.TabBar {
        id: tabBar
        Layout.fillWidth: true
        currentIndex: stack ? stack.currentIndex : 0

        Controls.TabButton {
            text: "Criar Issue"
        }

        Controls.TabButton {
            text: "Minhas Issues"
            onClicked: {
                if (issuesPage && issuesPage.initialSearchDone === false) {
                    issuesPage.refreshIssues("");
                    issuesPage.initialSearchDone = true;
                }
            }
        }

        Controls.TabButton {
            icon.name: "chronometer"
        }

        Controls.TabButton {
            icon.name: "configure"
        }
    }

    Controls.ToolButton {
        id: globalActionButton
        text: {
            if (!stack) return "";
            if (stack.currentIndex === 2) return "";
            if (stack.currentIndex === 0) return qsTr("Criar");
            if (stack.currentIndex === 1) return qsTr("Atualizar task");
            if (stack.currentIndex === 3) {
                if (settingsPage && settingsPage.isSaving !== undefined && settingsPage.isSaving) {
                    return qsTr("Salvando...");
                }
                return qsTr("Salvar");
            }
            return "";
        }
        icon.name: {
            if (!stack) return "";
            if (stack.currentIndex === 2) return "";
            if (stack.currentIndex === 0) return "document-new";
            if (stack.currentIndex === 1) return "document-save";
            if (stack.currentIndex === 3) return "document-save";
            return "";
        }
        visible: stack && stack.currentIndex !== 2
        enabled: {
            if (!stack) return false;
            if (stack.currentIndex === 2) return false;
            if (stack.currentIndex === 0) {
                if (!createPage) return false;
                if (createPage.isProcessing !== undefined && createPage.isProcessing) return false;
                if (!issueModel) return false;
                var s = issueModel.summary ? issueModel.summary.trim() : "";
                return s.length > 0;
            }
            if (stack.currentIndex === 1) {
                if (!issuesPage) return false;
                if (!issuesPage.controller) return false;
                if (!issuesPage.selectedIssueKey) return false;
                if (issuesPage.isProcessing !== undefined && issuesPage.isProcessing) return false;
                if (!jiraService || typeof jiraService.isAvailable !== "function") return false;
                return jiraService.isAvailable();
            }
            if (stack.currentIndex === 3) {
                if (!settingsPage) return false;
                if (settingsPage.isSaving !== undefined && settingsPage.isSaving) return false;
                if (settingsPage.isValid !== undefined && !settingsPage.isValid) return false;
                return true;
            }
            return false;
        }
        onClicked: {
            if (!stack) return;
            if (stack.currentIndex === 2) return;
            if (stack.currentIndex === 0 && createPage && createPage.createIssueFromToolbar) {
                createPage.createIssueFromToolbar();
            } else if (stack.currentIndex === 1 && issuesPage && issuesPage.updateIssue) {
                issuesPage.updateIssue();
            } else if (stack.currentIndex === 3 && settingsPage && settingsPage.saveSettingsFromToolbar) {
                settingsPage.saveSettingsFromToolbar();
            }
        }
    }

    Controls.ToolButton {
        id: startTimerButton
        text: {
            if (!stack || stack.currentIndex !== 1) return "";
            if (!issuesPage) return "";
            if (timerModel && timerModel.state === "running" && timerModel.issueKey === issuesPage.selectedIssueKey) {
                return qsTr("Parar Timer");
            }
            if (timerModel && timerModel.isOnBreak) return qsTr("Cancelar Pausa e Iniciar");
            if (timerModel && timerModel.state !== "idle" && timerModel.issueKey !== issuesPage.selectedIssueKey) {
                return qsTr("Parar e Iniciar");
            }
            return qsTr("Iniciar Timer");
        }
        icon.name: {
            if (!stack || stack.currentIndex !== 1) return "";
            if (timerModel && timerModel.state === "running" && timerModel.issueKey === issuesPage.selectedIssueKey) {
                return "media-playback-stop";
            }
            if (timerModel && timerModel.isOnBreak) return "media-playback-start";
            return "chronometer";
        }
        visible: stack && stack.currentIndex === 1
        enabled: {
            if (!stack || stack.currentIndex !== 1) return false;
            if (!issuesPage || !issuesPage.selectedIssueKey) return false;
            if (issuesPage.isProcessing !== undefined && issuesPage.isProcessing) return false;
            if (!timerService || !timerModel) return false;
            return true;
        }
        onClicked: {
            if (stack && stack.currentIndex === 1 && issuesPage && issuesPage.startTimerFromToolbar) {
                issuesPage.startTimerFromToolbar();
            }
        }
    }
}
