/**
 * Shortcuts.qml
 *
 * Atalhos globais: Alt+1..6 (abas diretas), Ctrl+Enter (ação da aba), Esc (esconder),
 * Ctrl+Tab, Ctrl+Shift+Tab (ciclo 0-3, pulando Worklog e Settings).
 * Atalho de voz: lido das configurações (voice_input.keyboard_shortcut).
 */
import QtQuick

Item {
    id: root

    property var stack: null
    property var tabBar: null
    property var createPage: null
    property var issuesPage: null
    property var createWorkItemPage: null
    property var myWorkItemsPage: null
    property var settingsPage: null
    property var pendingWorklogsPage: null
    property var timesheetPage: null
    property var githubPage: null
    property var settingsModel: null
    property bool googleTabEnabled: false

    signal hideRequested

    Shortcut {
        id: shortcutCreateOrUpdate
        sequences: ["Ctrl+Return", "Ctrl+Enter"]
        onActivated: {
            if (!root.stack)
                return;
            if (root.stack.currentIndex === 2 || root.stack.currentIndex === 3 || root.stack.currentIndex === 4 || root.stack.currentIndex === 5)
                return;
            if (root.stack.currentIndex === 6) {
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
            } else if (root.stack.currentIndex === 7) {
                if (root.createWorkItemPage && root.createWorkItemPage.createIssueFromToolbar) {
                    root.createWorkItemPage.createIssueFromToolbar();
                }
            } else if (root.stack.currentIndex === 8) {
                if (root.myWorkItemsPage && root.myWorkItemsPage.updateIssue) {
                    root.myWorkItemsPage.updateIssue();
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
        sequence: "Alt+1"
        onActivated: {
            if (root.stack && root.tabBar) {
                root.stack.currentIndex = 0;
                root.tabBar.currentIndex = 0;
            }
        }
    }
    Shortcut {
        sequence: "Alt+2"
        onActivated: {
            if (root.stack && root.tabBar) {
                root.stack.currentIndex = 1;
                root.tabBar.currentIndex = 1;
            }
        }
    }
    Shortcut {
        sequence: "Alt+3"
        onActivated: {
            if (!root.googleTabEnabled)
                return;
            if (root.stack && root.tabBar) {
                root.stack.currentIndex = 2;
                root.tabBar.currentIndex = 2;
            }
        }
    }
    Shortcut {
        sequence: "Alt+4"
        onActivated: {
            if (root.stack && root.tabBar) {
                root.stack.currentIndex = 3;
                root.tabBar.currentIndex = 3;
            }
        }
    }
    Shortcut {
        sequence: "Alt+5"
        onActivated: {
            if (root.stack && root.tabBar) {
                root.stack.currentIndex = 4;
                root.tabBar.currentIndex = 4;
            }
        }
    }
    Shortcut {
        sequence: "Alt+6"
        onActivated: {
            if (root.stack && root.tabBar) {
                root.stack.currentIndex = 5;
                root.tabBar.currentIndex = 5;
            }
        }
    }
    Shortcut {
        sequence: "Alt+7"
        onActivated: {
            if (root.stack && root.tabBar) {
                root.stack.currentIndex = 6;
                root.tabBar.currentIndex = 6;
            }
        }
    }
    Shortcut {
        sequence: "Alt+8"
        onActivated: {
            if (root.stack && root.tabBar) {
                root.stack.currentIndex = 7;
                root.tabBar.currentIndex = 7;
            }
        }
    }
    Shortcut {
        sequence: "Alt+9"
        onActivated: {
            if (root.stack && root.tabBar) {
                root.stack.currentIndex = 8;
                root.tabBar.currentIndex = 8;
            }
        }
    }

    Shortcut {
        id: shortcutSwitchTab
        sequence: "Ctrl+Tab"
        onActivated: {
            if (!root.stack || !root.tabBar)
                return;
            var contentTabs = root.googleTabEnabled ? [0, 1, 2, 3] : [0, 1, 3];
            var currentIdx = root.stack.currentIndex;
            var idx = contentTabs.indexOf(currentIdx);
            var nextIdx = (idx >= 0) ? contentTabs[(idx + 1) % contentTabs.length] : 0;
            root.stack.currentIndex = nextIdx;
            root.tabBar.currentIndex = nextIdx;
        }
    }

    Shortcut {
        id: shortcutVoiceInput
        sequence: (root.settingsModel && root.settingsModel.voiceInputKeyboardShortcut) ? root.settingsModel.voiceInputKeyboardShortcut : "Meta+F"
        onActivated: {
            if (root.stack && root.stack.currentIndex === 0 && root.createPage && root.createPage.openVoiceDialog) {
                root.createPage.openVoiceDialog();
            } else if (root.stack && root.stack.currentIndex === 7 && root.createWorkItemPage && root.createWorkItemPage.openVoiceDialog) {
                root.createWorkItemPage.openVoiceDialog();
            }
        }
    }

    Shortcut {
        id: shortcutSwitchTabBack
        sequence: "Ctrl+Shift+Tab"
        onActivated: {
            if (!root.stack || !root.tabBar)
                return;
            var contentTabs = root.googleTabEnabled ? [0, 1, 2, 3] : [0, 1, 3];
            var currentIdx = root.stack.currentIndex;
            var idx = contentTabs.indexOf(currentIdx);
            var prevIdx = (idx >= 0) ? contentTabs[(idx - 1 + contentTabs.length) % contentTabs.length] : contentTabs[contentTabs.length - 1];
            root.stack.currentIndex = prevIdx;
            root.tabBar.currentIndex = prevIdx;
        }
    }
}
