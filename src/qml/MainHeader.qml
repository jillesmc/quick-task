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
    property var createWorkItemPage: null
    property var myWorkItemsPage: null
    property var settingsPage: null
    property var pendingWorklogsPage: null
    property var timesheetPage: null
    property var githubPage: null
    property var googlePage: null
    property var issueModel: null
    property var workItemModel: null
    property var jiraService: null
    property var timerModel: null
    property var timerService: null
    property var githubService: null

    property int currentTabIndex: stack ? stack.currentIndex : -1

    width: parent ? parent.width : 0
    spacing: Kirigami.Units.smallSpacing

    Controls.TabBar {
        id: tabBar
        Layout.fillWidth: true
        currentIndex: root.currentTabIndex >= 0 ? root.currentTabIndex : 0

        // Ordem: 0 Criar, 1 Minhas Issues, 2 Google, 3 GitHub, 4 Worklog, 5 Timesheet, 6 Settings
        Controls.TabButton {
            text: qsTr("Criar Issue")
        }

        Controls.TabButton {
            text: qsTr("Minhas Issues")
        }

        Controls.TabButton {
            id: googleTabButton
            text: qsTr("Google")
            enabled: root.googlePage && root.googlePage.googleAuthService
            icon.name: (root.googlePage && root.googlePage.googleAuthService) ? "" : "process-working"
        }

        Controls.TabButton {
            text: "GitHub"
        }

        Controls.TabButton {
            icon.name: "chronometer"
        }

        Controls.TabButton {
            icon.name: "view-calendar"
            text: ""
            Controls.ToolTip.text: qsTr("Timesheet")
            Controls.ToolTip.visible: hovered
        }

        Controls.TabButton {
            icon.name: "configure"
        }

        Controls.TabButton {
            icon.name: "document-new"
            text: ""
            Controls.ToolTip.text: qsTr("Criar Issue")
            Controls.ToolTip.visible: hovered
        }

        Controls.TabButton {
            icon.name: "view-list-details"
            text: ""
            Controls.ToolTip.text: qsTr("Minhas Issues")
            Controls.ToolTip.visible: hovered
        }
    }

    Controls.ToolButton {
        id: globalActionButton
        text: {
            if (root.currentTabIndex === 0) return qsTr("Criar");
            if (root.currentTabIndex === 1) return qsTr("Atualizar task");
            if (root.currentTabIndex === 6) {
                if (root.settingsPage && root.settingsPage.isSaving !== undefined && root.settingsPage.isSaving) {
                    return qsTr("Salvando...");
                }
                return qsTr("Salvar");
            }
            if (root.currentTabIndex === 7) return qsTr("Criar");
            if (root.currentTabIndex === 8) return qsTr("Atualizar task");
            return "";
        }
        icon.name: {
            if (root.currentTabIndex === 0) return "document-new";
            if (root.currentTabIndex === 1) return "document-save";
            if (root.currentTabIndex === 6) return "document-save";
            if (root.currentTabIndex === 7) return "document-new";
            if (root.currentTabIndex === 8) return "document-save";
            return "";
        }
        visible: root.currentTabIndex >= 0 && root.currentTabIndex !== 2 && root.currentTabIndex !== 3 && root.currentTabIndex !== 4 && root.currentTabIndex !== 5
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
            if (root.currentTabIndex === 6) {
                if (!root.settingsPage) return false;
                if (root.settingsPage.isSaving !== undefined && root.settingsPage.isSaving) return false;
                if (root.settingsPage.isValid !== undefined && !root.settingsPage.isValid) return false;
                return true;
            }
            if (root.currentTabIndex === 7) {
                if (!root.createWorkItemPage) return false;
                if (root.createWorkItemPage.isProcessing !== undefined && root.createWorkItemPage.isProcessing) return false;
                if (!root.workItemModel) return false;
                var s7 = root.workItemModel.summary ? root.workItemModel.summary.trim() : "";
                return s7.length > 0;
            }
            if (root.currentTabIndex === 8) {
                if (!root.myWorkItemsPage) return false;
                if (!root.myWorkItemsPage.controller) return false;
                if (!root.myWorkItemsPage.selectedIssueKey) return false;
                if (root.myWorkItemsPage.isProcessing !== undefined && root.myWorkItemsPage.isProcessing) return false;
                if (!root.jiraService || typeof root.jiraService.isAvailable !== "function") return false;
                return root.jiraService.isAvailable();
            }
            return false;
        }
        onClicked: {
            if (root.currentTabIndex === 0 && root.createPage && root.createPage.createIssueFromToolbar) {
                root.createPage.createIssueFromToolbar();
            } else if (root.currentTabIndex === 1 && root.issuesPage && root.issuesPage.updateIssue) {
                root.issuesPage.updateIssue();
            } else if (root.currentTabIndex === 6 && root.settingsPage && root.settingsPage.saveSettingsFromToolbar) {
                root.settingsPage.saveSettingsFromToolbar();
            } else if (root.currentTabIndex === 7 && root.createWorkItemPage && root.createWorkItemPage.createIssueFromToolbar) {
                root.createWorkItemPage.createIssueFromToolbar();
            } else if (root.currentTabIndex === 8 && root.myWorkItemsPage && root.myWorkItemsPage.updateIssue) {
                root.myWorkItemsPage.updateIssue();
            }
        }
    }

    Controls.ToolButton {
        id: blockIssueButton
        text: qsTr("Bloquear")
        icon.name: "lock"
        visible: {
            var page = (root.currentTabIndex === 1) ? root.issuesPage : ((root.currentTabIndex === 8) ? root.myWorkItemsPage : null);
            return page && page.selectedIssueKey !== "" && !(page.isProcessing || false)
                && (page._quickActionStatus || "") !== "BLOCKED";
        }
        Controls.ToolTip.visible: hovered
        Controls.ToolTip.text: qsTr("Bloquear issue")
        onClicked: {
            var page = (root.currentTabIndex === 1) ? root.issuesPage : ((root.currentTabIndex === 8) ? root.myWorkItemsPage : null);
            if (page && page.detailPane && typeof page.detailPane.openBlockDialog === "function") {
                page.detailPane.openBlockDialog();
            }
        }
    }

    Controls.ToolButton {
        id: unblockIssueButton
        text: qsTr("Desbloquear")
        icon.name: "unlock"
        visible: {
            var page = (root.currentTabIndex === 1) ? root.issuesPage : ((root.currentTabIndex === 8) ? root.myWorkItemsPage : null);
            return page && page.selectedIssueKey !== "" && !(page.isProcessing || false)
                && (page._quickActionStatus || "") === "BLOCKED";
        }
        Controls.ToolTip.visible: hovered
        Controls.ToolTip.text: qsTr("Desbloquear e retornar para IN PROGRESS")
        onClicked: {
            var page = (root.currentTabIndex === 1) ? root.issuesPage : ((root.currentTabIndex === 8) ? root.myWorkItemsPage : null);
            if (page && page.detailPane && typeof page.detailPane.openUnblockDialog === "function") {
                page.detailPane.openUnblockDialog();
            }
        }
    }

    Controls.ToolButton {
        id: cancelIssueButton
        text: qsTr("Cancelar")
        icon.name: "dialog-cancel"
        visible: {
            var page = (root.currentTabIndex === 1) ? root.issuesPage : ((root.currentTabIndex === 8) ? root.myWorkItemsPage : null);
            return page && page.selectedIssueKey !== "" && !(page.isProcessing || false)
                && (page._quickActionStatus || "") !== "CANCELED"
                && (page._quickActionStatus || "") !== "DONE";
        }
        Controls.ToolTip.visible: hovered
        Controls.ToolTip.text: qsTr("Cancelar issue")
        onClicked: {
            var page = (root.currentTabIndex === 1) ? root.issuesPage : ((root.currentTabIndex === 8) ? root.myWorkItemsPage : null);
            if (page && page.detailPane && typeof page.detailPane.openCancelDialog === "function") {
                page.detailPane.openCancelDialog();
            }
        }
    }

    Controls.ToolButton {
        id: refreshGoogleButton
        text: qsTr("Atualizar")
        icon.name: "view-refresh"
        visible: root.currentTabIndex === 2
        enabled: root.googlePage && root.googlePage.googleAuthService
            && root.googlePage.googleAuthService.isAuthorized && !root.googlePage.isLoading
        onClicked: {
            if (root.currentTabIndex === 2 && root.googlePage && typeof root.googlePage.reload === "function") {
                root.googlePage.reload();
            }
        }
    }

    Controls.ToolButton {
        id: refreshGitHubButton
        text: qsTr("Atualizar")
        icon.name: "view-refresh"
        visible: root.currentTabIndex === 3
        enabled: root.githubPage && root.githubPage.githubService && root.githubPage.githubService.available && !root.githubPage.isLoadingPRs && !root.githubPage.isLoadingIssues
        onClicked: {
            if (root.currentTabIndex === 3 && root.githubPage && typeof root.githubPage.reload === "function") {
                root.githubPage.reload();
            }
        }
    }

    Controls.ToolButton {
        id: refreshTimesheetButton
        text: qsTr("Atualizar")
        icon.name: "view-refresh"
        visible: root.currentTabIndex === 5
        enabled: root.timesheetPage && root.timesheetPage.timesheetViewModel && !root.timesheetPage.timesheetViewModel.loading
        onClicked: {
            if (root.currentTabIndex === 5 && root.timesheetPage && root.timesheetPage.timesheetViewModel) {
                root.timesheetPage.timesheetViewModel.refresh()
            }
        }
    }

    Controls.ToolButton {
        id: syncWorklogsButton
        text: qsTr("Sincronizar")
        icon.name: "document-send"
        visible: root.currentTabIndex === 4
        enabled: root.pendingWorklogsPage && root.pendingWorklogsPage.filteredWorklogs
                 && root.pendingWorklogsPage.filteredWorklogs.length > 0
        onClicked: {
            if (root.currentTabIndex === 4 && root.pendingWorklogsPage
                    && typeof root.pendingWorklogsPage.syncAllFromToolbar === "function") {
                root.pendingWorklogsPage.syncAllFromToolbar();
            }
        }
    }

    Controls.ToolButton {
        id: createBranchButton
        text: qsTr("Criar branch")
        icon.name: "vcs-branch"
        visible: root.currentTabIndex === 1 || root.currentTabIndex === 8
        enabled: {
            var page = (root.currentTabIndex === 1) ? root.issuesPage : ((root.currentTabIndex === 8) ? root.myWorkItemsPage : null);
            if (!page || !page.selectedIssueKey) return false;
            if (!root.githubService || !root.githubService.available) return false;
            return true;
        }
        onClicked: {
            var page = (root.currentTabIndex === 1) ? root.issuesPage : ((root.currentTabIndex === 8) ? root.myWorkItemsPage : null);
            if (page && typeof page.openCreateBranchDialog === "function") {
                page.openCreateBranchDialog();
            }
        }
    }

    Controls.ToolButton {
        id: startTimerButton
        text: {
            var page = (root.currentTabIndex === 1) ? root.issuesPage : ((root.currentTabIndex === 8) ? root.myWorkItemsPage : null);
            if (!page) return "";
            if (root.timerModel && root.timerModel.state === "running" && root.timerModel.issueKey === page.selectedIssueKey) {
                return qsTr("Parar Timer");
            }
            if (root.timerModel && root.timerModel.isOnBreak) return qsTr("Cancelar Pausa e Iniciar");
            if (root.timerModel && root.timerModel.state !== "idle" && root.timerModel.issueKey !== page.selectedIssueKey) {
                return qsTr("Parar e Iniciar");
            }
            return qsTr("Iniciar Timer");
        }
        icon.name: {
            var page = (root.currentTabIndex === 1) ? root.issuesPage : ((root.currentTabIndex === 8) ? root.myWorkItemsPage : null);
            if (!page) return "";
            if (root.timerModel && root.timerModel.state === "running" && root.timerModel.issueKey === page.selectedIssueKey) {
                return "media-playback-stop";
            }
            if (root.timerModel && root.timerModel.isOnBreak) return "media-playback-start";
            return "chronometer";
        }
        visible: root.currentTabIndex === 1 || root.currentTabIndex === 8
        enabled: {
            var page = (root.currentTabIndex === 1) ? root.issuesPage : ((root.currentTabIndex === 8) ? root.myWorkItemsPage : null);
            if (!page || !page.selectedIssueKey) return false;
            if (page.isProcessing !== undefined && page.isProcessing) return false;
            if (!root.timerService || !root.timerModel) return false;
            return true;
        }
        onClicked: {
            var page = (root.currentTabIndex === 1) ? root.issuesPage : ((root.currentTabIndex === 8) ? root.myWorkItemsPage : null);
            if (page && page.startTimerFromToolbar) {
                page.startTimerFromToolbar();
            }
        }
    }
}
