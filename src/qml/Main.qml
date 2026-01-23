// Janela principal da aplicação Kirigami
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami
import "./pages"


Kirigami.ApplicationWindow {
    id: root

    width: 900
    height: 1050
    minimumWidth: 1100  // Mínimo para evitar sobreposição de colunas
    title: "Jira Quick Task"
    visible: true

    // Interceptar fechamento da janela - minimizar ao tray ao invés de fechar
    onClosing: (close) => {
        close.accepted = false  // Previne fechamento da aplicação
        root.hide()              // Esconde a janela (minimiza ao tray)
    }

    // Desabilitar drawers padrão (não usamos por enquanto)
    globalDrawer: null
    contextDrawer: null

    // Inicializar Kirigami (ajuda a reduzir warnings)
    Component.onCompleted: {
        Kirigami.Theme.inherit = true
    }

    // -----------------------------------------------------------------
    // Atalhos globais (independentes de foco)
    // -----------------------------------------------------------------
    Shortcut {
        id: shortcutCreateOrUpdate
        sequences: [ "Ctrl+Return", "Ctrl+Enter" ]
        onActivated: {
            if (tabBar.currentIndex === 0) {
                // Aba 1: Criar Issue - delega a validação e feedback ao controller
                if (createPage && createPage.createIssueFromToolbar) {
                    createPage.createIssueFromToolbar()
                }
            } else {
                if (issuesPage && issuesPage.updateIssue) {
                    issuesPage.updateIssue()
                }
            }
        }
    }

    Shortcut {
        id: shortcutCancel
        sequence: "Esc"
        onActivated: {
            // ESC sempre esconde a janela (minimiza ao tray)
            // Não chama onCancelRequested() para evitar lógica de cancelamento
            if (typeof hideWindow === "function") {
                hideWindow()
            } else {
                root.hide()
            }
        }
    }

    Shortcut {
        id: shortcutSwitchTab
        sequence: "Ctrl+Tab"
        onActivated: {
            // Alternar para a próxima aba (avançar)
            if (tabBar.currentIndex === 0) {
                tabBar.currentIndex = 1
                // Buscar issues automaticamente apenas na primeira vez
                if (issuesPage && !issuesPage.initialSearchDone) {
                    issuesPage.refreshIssues("")
                    issuesPage.initialSearchDone = true
                }
            } else {
                tabBar.currentIndex = 0
            }
        }
    }

    Shortcut {
        id: shortcutSwitchTabBack
        sequence: "Ctrl+Shift+Tab"
        onActivated: {
            // Alternar para a aba anterior (voltar)
            if (tabBar.currentIndex === 0) {
                tabBar.currentIndex = 1
                // Buscar issues automaticamente apenas na primeira vez
                if (issuesPage && !issuesPage.initialSearchDone) {
                    issuesPage.refreshIssues("")
                    issuesPage.initialSearchDone = true
                }
            } else {
                tabBar.currentIndex = 0
            }
        }
    }

    // -----------------------------------------------------------------
    // Header customizado com TabBar e botão global dinâmico
    // -----------------------------------------------------------------
    header: RowLayout {
        id: headerRow
        width: parent.width
        spacing: Kirigami.Units.smallSpacing

        // TabBar para alternar entre abas
        Controls.TabBar {
            id: tabBar
            Layout.fillWidth: true

            Controls.TabButton {
                text: "Criar Issue"
            }
            Controls.TabButton {
                text: "Minhas Issues"
                onClicked: {
                    // Buscar issues automaticamente apenas na primeira vez
                    if (issuesPage && !issuesPage.initialSearchDone) {
                        issuesPage.refreshIssues("")
                        issuesPage.initialSearchDone = true
                    }
                }
            }
        }

        // Botão global que muda dinamicamente baseado na aba ativa
        Controls.ToolButton {
            id: globalActionButton
            text: tabBar.currentIndex === 0 ? qsTr("Criar") : qsTr("Atualizar task")
            icon.name: tabBar.currentIndex === 0 ? "document-new" : "document-save"
            enabled: {
                if (tabBar.currentIndex === 0) {
                    // Aba 1: Criar Issue
                    if (!createPage)
                        return false
                    if (createPage.isProcessing !== undefined && createPage.isProcessing)
                        return false
                    // Requisito mínimo: summary preenchido.
                    if (!issueModel)
                        return false
                    var s = issueModel.summary ? issueModel.summary.trim() : ""
                    return s.length > 0
                } else {
                    // Aba 2: Atualizar task
                    if (!issuesPage) return false
                    if (issuesPage.controller === undefined || !issuesPage.controller) return false
                    if (issuesPage.selectedIssueKey === undefined || issuesPage.selectedIssueKey === "") return false
                    if (issuesPage.isProcessing !== undefined && issuesPage.isProcessing) return false
                    if (!jiraService) return false
                    if (typeof jiraService.isAvailable !== "function") return false
                    return jiraService.isAvailable()
                }
            }
            onClicked: {
                if (tabBar.currentIndex === 0) {
                    // Aba 1: Criar Issue
                    if (createPage && createPage.createIssueFromToolbar) {
                        createPage.createIssueFromToolbar()
                    }
                } else {
                    // Aba 2: Atualizar task
                    if (issuesPage && issuesPage.updateIssue) {
                        issuesPage.updateIssue()
                    }
                }
            }
        }
    }

    // Propriedade compartilhada para sincronizar epic selecionado entre abas
    property string sharedEpicKey: ""
    property string sharedEpicSummary: ""

    // -----------------------------------------------------------------
    // Conteúdo principal: abas empilhadas
    // -----------------------------------------------------------------
    StackLayout {
        id: stack
        anchors.fill: parent
        currentIndex: tabBar.currentIndex

        IssueFormPage {
            id: createPage
            sharedEpicKey: root.sharedEpicKey
            sharedEpicSummary: root.sharedEpicSummary
            onEpicSelected: function(key, summary) {
                root.sharedEpicKey = key
                root.sharedEpicSummary = summary
            }
        }

        MyIssuesPage {
            id: issuesPage
            sharedEpicKey: root.sharedEpicKey
            sharedEpicSummary: root.sharedEpicSummary
            onEpicSelected: function(key, summary) {
                root.sharedEpicKey = key
                root.sharedEpicSummary = summary
            }
        }
    }

}
