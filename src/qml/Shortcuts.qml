/**
 * Shortcuts.qml
 *
 * Atalhos globais: Ctrl+Enter (ação da aba), Esc (esconder), Ctrl+Tab, Ctrl+Shift+Tab.
 */
import QtQuick
import QtQuick.Controls as Controls

Item {
    id: root

    property var stack: null
    property var tabBar: null
    property var createPage: null
    property var issuesPage: null
    property var settingsPage: null
    property var pendingWorklogsPage: null

    signal hideRequested()

    Shortcut {
        id: shortcutCreateOrUpdate
        sequences: [ "Ctrl+Return", "Ctrl+Enter" ]
        onActivated: {
            if (!stack) return;
            if (stack.currentIndex === 2) return;
            if (stack.currentIndex === 3) {
                if (settingsPage && settingsPage.saveSettingsFromToolbar) {
                    settingsPage.saveSettingsFromToolbar();
                }
                return;
            }
            if (stack.currentIndex === 0) {
                if (createPage && createPage.createIssueFromToolbar) {
                    createPage.createIssueFromToolbar();
                }
            } else if (stack.currentIndex === 1) {
                if (issuesPage && issuesPage.updateIssue) {
                    issuesPage.updateIssue();
                }
            }
        }
    }

    Shortcut {
        id: shortcutCancel
        sequence: "Esc"
        onActivated: root.hideRequested()
    }

    Shortcut {
        id: shortcutSwitchTab
        sequence: "Ctrl+Tab"
        onActivated: {
            if (!stack || !tabBar) return;
            var currentIdx = stack.currentIndex;
            if (currentIdx === 3 || currentIdx === 2) {
                stack.currentIndex = 0;
                tabBar.currentIndex = 0;
            } else if (currentIdx === 0) {
                stack.currentIndex = 1;
                tabBar.currentIndex = 1;
                if (issuesPage && !issuesPage.initialSearchDone) {
                    issuesPage.refreshIssues("");
                    issuesPage.initialSearchDone = true;
                }
            } else if (currentIdx === 1) {
                stack.currentIndex = 0;
                tabBar.currentIndex = 0;
            } else {
                stack.currentIndex = 0;
                tabBar.currentIndex = 0;
            }
        }
    }

    Shortcut {
        id: shortcutSwitchTabBack
        sequence: "Ctrl+Shift+Tab"
        onActivated: {
            if (!stack || !tabBar) return;
            var currentIdx = stack.currentIndex;
            if (currentIdx === 3 || currentIdx === 2) {
                stack.currentIndex = 1;
                tabBar.currentIndex = 1;
                if (issuesPage && !issuesPage.initialSearchDone) {
                    issuesPage.refreshIssues("");
                    issuesPage.initialSearchDone = true;
                }
            } else if (currentIdx === 1) {
                stack.currentIndex = 2;
                tabBar.currentIndex = 2;
            } else if (currentIdx === 0) {
                stack.currentIndex = 2;
                tabBar.currentIndex = 2;
            } else {
                stack.currentIndex = 0;
                tabBar.currentIndex = 0;
            }
        }
    }
}
