/**
 * Shortcuts.qml
 *
 * Atalhos globais: Ctrl+Enter (ação da aba), Esc (esconder), Ctrl+Tab, Ctrl+Shift+Tab.
 * Atalho de voz: lido das configurações (voice_input.keyboard_shortcut).
 */
import QtQuick

Item {
    id: root

    property var stack: null
    property var tabBar: null
    property var createPage: null
    property var issuesPage: null
    property var settingsPage: null
    property var pendingWorklogsPage: null
    property var settingsModel: null

    signal hideRequested()

    Shortcut {
        id: shortcutCreateOrUpdate
        sequences: [ "Ctrl+Return", "Ctrl+Enter" ]
        onActivated: {
            if (!root.stack) return;
            if (root.stack.currentIndex === 2) return;
            if (root.stack.currentIndex === 3) {
                if (root.settingsPage && root.settingsPage.saveSettingsFromToolbar) {
                    root.settingsPage.saveSettingsFromToolbar();
                }
                return;
            }
            if (root.stack.currentIndex === 0) {
                if (root.createPage && root.createPage.createIssueFromToolbar) {
                    root.createPage.createIssueFromToolbar();
                }
            } else if (root.stack.currentIndex === 1) {
                if (root.issuesPage && root.issuesPage.updateIssue) {
                    root.issuesPage.updateIssue();
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
            if (!root.stack || !root.tabBar) return;
            var currentIdx = root.stack.currentIndex;
            if (currentIdx === 3 || currentIdx === 2) {
                root.stack.currentIndex = 0;
                root.tabBar.currentIndex = 0;
            } else if (currentIdx === 0) {
                root.stack.currentIndex = 1;
                root.tabBar.currentIndex = 1;
                if (root.issuesPage && !root.issuesPage.initialSearchDone) {
                    root.issuesPage.refreshIssues("");
                    root.issuesPage.initialSearchDone = true;
                }
            } else if (currentIdx === 1) {
                root.stack.currentIndex = 0;
                root.tabBar.currentIndex = 0;
            } else {
                root.stack.currentIndex = 0;
                root.tabBar.currentIndex = 0;
            }
        }
    }

    Shortcut {
        id: shortcutVoiceInput
        sequence: (root.settingsModel && root.settingsModel.voiceInputKeyboardShortcut)
            ? root.settingsModel.voiceInputKeyboardShortcut
            : "Meta+F"
        onActivated: {
            if (root.stack && root.stack.currentIndex === 0 && root.createPage && root.createPage.openVoiceDialog) {
                root.createPage.openVoiceDialog();
            }
        }
    }

    Shortcut {
        id: shortcutSwitchTabBack
        sequence: "Ctrl+Shift+Tab"
        onActivated: {
            if (!root.stack || !root.tabBar) return;
            var currentIdx = root.stack.currentIndex;
            if (currentIdx === 3 || currentIdx === 2) {
                root.stack.currentIndex = 1;
                root.tabBar.currentIndex = 1;
                if (root.issuesPage && !root.issuesPage.initialSearchDone) {
                    root.issuesPage.refreshIssues("");
                    root.issuesPage.initialSearchDone = true;
                }
            } else if (currentIdx === 1) {
                root.stack.currentIndex = 2;
                root.tabBar.currentIndex = 2;
            } else if (currentIdx === 0) {
                root.stack.currentIndex = 2;
                root.tabBar.currentIndex = 2;
            } else {
                root.stack.currentIndex = 0;
                root.tabBar.currentIndex = 0;
            }
        }
    }
}
