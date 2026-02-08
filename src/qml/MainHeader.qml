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
    property var pendingWorklogsPage: null
    property var issueModel: null
    property var jiraService: null
    property var timerModel: null
    property var timerService: null

    property int currentTabIndex: stack ? stack.currentIndex : -1

    width: parent ? parent.width : 0
    spacing: Kirigami.Units.smallSpacing

    Controls.TabBar {
        id: tabBar
        Layout.fillWidth: true
        currentIndex: root.currentTabIndex >= 0 ? root.currentTabIndex : 0

        Controls.TabButton {
            text: "Criar Issue"
        }

        Controls.TabButton {
            text: "Minhas Issues"
            // Busca ao abrir a aba é feita em Main.qml (Connections onCurrentIndexChanged)
            // para evitar refreshIssues() duplicado e terminação do worker em execução (crash)
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
            if (root.currentTabIndex === 0) return qsTr("Criar");
            if (root.currentTabIndex === 1) return qsTr("Atualizar task");
            if (root.currentTabIndex === 3) {
                if (root.settingsPage && root.settingsPage.isSaving !== undefined && root.settingsPage.isSaving) {
                    return qsTr("Salvando...");
                }
                return qsTr("Salvar");
            }
            return "";
        }
        icon.name: {
            if (root.currentTabIndex === 0) return "document-new";
            if (root.currentTabIndex === 1) return "document-save";
            if (root.currentTabIndex === 3) return "document-save";
            return "";
        }
        visible: root.currentTabIndex >= 0 && root.currentTabIndex !== 2
        enabled: {
            if (root.currentTabIndex === 0) {
                if (!root.createPage) return false;
                if (root.createPage.isProcessing !== undefined && root.createPage.isProcessing) return false;
                if (!root.issueModel) return false;
                var s = root.issueModel.summary ? root.issueModel.summary.trim() : "";
                return s.length > 0;
            }
            if (root.currentTabIndex === 1) {
                if (!root.issuesPage) return false;
                if (!root.issuesPage.controller) return false;
                if (!root.issuesPage.selectedIssueKey) return false;
                if (root.issuesPage.isProcessing !== undefined && root.issuesPage.isProcessing) return false;
                if (!root.jiraService || typeof root.jiraService.isAvailable !== "function") return false;
                return root.jiraService.isAvailable();
            }
            if (root.currentTabIndex === 3) {
                if (!root.settingsPage) return false;
                if (root.settingsPage.isSaving !== undefined && root.settingsPage.isSaving) return false;
                if (root.settingsPage.isValid !== undefined && !root.settingsPage.isValid) return false;
                return true;
            }
            return false;
        }
        onClicked: {
            if (root.currentTabIndex === 0 && root.createPage && root.createPage.createIssueFromToolbar) {
                root.createPage.createIssueFromToolbar();
            } else if (root.currentTabIndex === 1 && root.issuesPage && root.issuesPage.updateIssue) {
                root.issuesPage.updateIssue();
            } else if (root.currentTabIndex === 3 && root.settingsPage && root.settingsPage.saveSettingsFromToolbar) {
                root.settingsPage.saveSettingsFromToolbar();
            }
        }
    }

    Controls.ToolButton {
        id: syncWorklogsButton
        text: qsTr("Sincronizar")
        icon.name: "document-send"
        visible: root.currentTabIndex === 2
        enabled: root.pendingWorklogsPage && root.pendingWorklogsPage.filteredWorklogs
                 && root.pendingWorklogsPage.filteredWorklogs.length > 0
        onClicked: {
            if (root.currentTabIndex === 2 && root.pendingWorklogsPage
                    && typeof root.pendingWorklogsPage.syncAllFromToolbar === "function") {
                root.pendingWorklogsPage.syncAllFromToolbar();
            }
        }
    }

    Controls.ToolButton {
        id: startTimerButton
        text: {
            if (root.currentTabIndex !== 1) return "";
            if (!root.issuesPage) return "";
            if (root.timerModel && root.timerModel.state === "running" && root.timerModel.issueKey === root.issuesPage.selectedIssueKey) {
                return qsTr("Parar Timer");
            }
            if (root.timerModel && root.timerModel.isOnBreak) return qsTr("Cancelar Pausa e Iniciar");
            if (root.timerModel && root.timerModel.state !== "idle" && root.timerModel.issueKey !== root.issuesPage.selectedIssueKey) {
                return qsTr("Parar e Iniciar");
            }
            return qsTr("Iniciar Timer");
        }
        icon.name: {
            if (root.currentTabIndex !== 1) return "";
            if (root.timerModel && root.timerModel.state === "running" && root.timerModel.issueKey === root.issuesPage.selectedIssueKey) {
                return "media-playback-stop";
            }
            if (root.timerModel && root.timerModel.isOnBreak) return "media-playback-start";
            return "chronometer";
        }
        visible: root.currentTabIndex === 1
        enabled: {
            if (root.currentTabIndex !== 1) return false;
            if (!root.issuesPage || !root.issuesPage.selectedIssueKey) return false;
            if (root.issuesPage.isProcessing !== undefined && root.issuesPage.isProcessing) return false;
            if (!root.timerService || !root.timerModel) return false;
            return true;
        }
        onClicked: {
            if (root.currentTabIndex === 1 && root.issuesPage && root.issuesPage.startTimerFromToolbar) {
                root.issuesPage.startTimerFromToolbar();
            }
        }
    }
}
