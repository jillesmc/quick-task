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
        
        // Verificar se precisa configurar antes de abrir
        // (stack e tabBar são definidos depois, então usamos Qt.callLater para garantir que estejam prontos)
        Qt.callLater(function() {
            if (stack && tabBar && settingsModel) {
                // Verificar se configuração está completa
                // needsConfiguration verifica se arquivos existem E se valores estão preenchidos
                if (settingsModel.needsConfiguration || !settingsModel.isConfigured) {
                    // Não está configurado - abrir na aba de Configuração (índice 3)
                    stack.currentIndex = 3
                    tabBar.currentIndex = 3
                } else {
                    // Está configurado - abrir na primeira aba (Criar Issue, índice 0)
                    stack.currentIndex = 0
                    tabBar.currentIndex = 0
                }
            } else {
                // Se settingsModel não estiver disponível, abrir na primeira aba por padrão
                if (stack && tabBar) {
                    stack.currentIndex = 0
                    tabBar.currentIndex = 0
                }
            }
            
            // Janela flutuante do timer agora é gerenciada pelo Python (app.py)
            // Não precisa criar aqui
        })
    }

    // -----------------------------------------------------------------
    // Atalhos globais (independentes de foco)
    // -----------------------------------------------------------------
    Shortcut {
        id: shortcutCreateOrUpdate
        sequences: [ "Ctrl+Return", "Ctrl+Enter" ]
        onActivated: {
            // Não fazer nada se estiver na página de configuração (índice 3) ou worklogs (índice 2)
            if (stack.currentIndex === 3 || stack.currentIndex === 2) return
            
            if (stack.currentIndex === 0) {
                // Aba Criar Issue - delega a validação e feedback ao controller
                if (createPage && createPage.createIssueFromToolbar) {
                    createPage.createIssueFromToolbar()
                }
            } else if (stack.currentIndex === 1) {
                // Aba Minhas Issues: Atualizar task
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
            // Alternar apenas entre as abas principais (índices 0 e 1)
            // Ignorar a aba de Worklogs Pendentes (índice 2) e Configuração (índice 3)
            var currentIdx = stack.currentIndex
            
            // Se estiver na aba de Configuração (3) ou Worklogs (2), ir para Criar Issue (0)
            if (currentIdx === 3 || currentIdx === 2) {
                stack.currentIndex = 0
                tabBar.currentIndex = 0
            }
            // Se estiver em Criar Issue (0), ir para Minhas Issues (1)
            else if (currentIdx === 0) {
                stack.currentIndex = 1
                tabBar.currentIndex = 1
                // Buscar issues automaticamente apenas na primeira vez
                if (issuesPage && !issuesPage.initialSearchDone) {
                    issuesPage.refreshIssues("")
                    issuesPage.initialSearchDone = true
                }
            }
            // Se estiver em Minhas Issues (1), voltar para Criar Issue (0) (pula Worklogs)
            else if (currentIdx === 1) {
                stack.currentIndex = 0
                tabBar.currentIndex = 0
            }
            // Caso padrão: voltar para Criar Issue (0)
            else {
                stack.currentIndex = 0
                tabBar.currentIndex = 0
            }
        }
    }

    Shortcut {
        id: shortcutSwitchTabBack
        sequence: "Ctrl+Shift+Tab"
        onActivated: {
            // Alternar apenas entre as três abas principais (índices 0, 1 e 2)
            // Ignorar a aba de Configuração (índice 3)
            var currentIdx = stack.currentIndex
            
            // Se estiver na aba de Configuração (3) ou Timer (2), ir para Minhas Issues (1)
            if (currentIdx === 3 || currentIdx === 2) {
                stack.currentIndex = 1
                tabBar.currentIndex = 1
                // Buscar issues automaticamente apenas na primeira vez
                if (issuesPage && !issuesPage.initialSearchDone) {
                    issuesPage.refreshIssues("")
                    issuesPage.initialSearchDone = true
                }
            }
            // Se estiver em Minhas Issues (1), ir para Timer (2)
            else if (currentIdx === 1) {
                stack.currentIndex = 2
                tabBar.currentIndex = 2
            }
            // Se estiver em Criar Issue (0), ir para Timer (2)
            else if (currentIdx === 0) {
                stack.currentIndex = 2
                tabBar.currentIndex = 2
            }
            // Caso padrão: voltar para Criar Issue (0)
            else {
                stack.currentIndex = 0
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
            currentIndex: stack.currentIndex

            // Aba Criar Issue
            Controls.TabButton {
                text: "Criar Issue"
            }
            
            // Aba Minhas Issues
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

            // Aba Worklogs Pendentes
            Controls.TabButton {
                icon.name: "chronometer"
            }

            // Aba de Configuração (última, à direita)
            Controls.TabButton {
                icon.name: "configure"
            }
        }

        // Botão global que muda dinamicamente baseado na aba ativa
        Controls.ToolButton {
            id: globalActionButton
            text: {
                if (stack.currentIndex === 2) return ""  // Página de configuração não tem ação global
                if (stack.currentIndex === 0) return qsTr("Criar")
                if (stack.currentIndex === 1) return qsTr("Atualizar task")
                return ""
            }
            icon.name: {
                if (stack.currentIndex === 2) return ""  // Página de configuração não tem ação global
                if (stack.currentIndex === 0) return "document-new"
                if (stack.currentIndex === 1) return "document-save"
                return ""
            }
            visible: stack.currentIndex !== 3 && stack.currentIndex !== 2  // Ocultar na página de configuração e worklogs
            enabled: {
                if (stack.currentIndex === 3) return false  // Página de configuração
                if (stack.currentIndex === 2) return false  // Página de worklogs pendentes
                if (stack.currentIndex === 0) {
                    // Aba Criar Issue
                    if (!createPage)
                        return false
                    if (createPage.isProcessing !== undefined && createPage.isProcessing)
                        return false
                    // Requisito mínimo: summary preenchido.
                    if (!issueModel)
                        return false
                    var s = issueModel.summary ? issueModel.summary.trim() : ""
                    return s.length > 0
                } else if (stack.currentIndex === 1) {
                    // Aba Minhas Issues: Atualizar task
                    if (!issuesPage) return false
                    if (issuesPage.controller === undefined || !issuesPage.controller) return false
                    if (issuesPage.selectedIssueKey === undefined || issuesPage.selectedIssueKey === "") return false
                    if (issuesPage.isProcessing !== undefined && issuesPage.isProcessing) return false
                    if (!jiraService) return false
                    if (typeof jiraService.isAvailable !== "function") return false
                    return jiraService.isAvailable()
                }
                return false
            }
            onClicked: {
                if (stack.currentIndex === 3 || stack.currentIndex === 2) return  // Página de configuração ou worklogs
                if (stack.currentIndex === 0) {
                    // Aba Criar Issue
                    if (createPage && createPage.createIssueFromToolbar) {
                        createPage.createIssueFromToolbar()
                    }
                } else if (stack.currentIndex === 1) {
                    // Aba Minhas Issues: Atualizar task
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
        // Sincronizar com TabBar
        currentIndex: tabBar.currentIndex

        // Índice 0: Criar Issue
        IssueFormPage {
            id: createPage
            sharedEpicKey: root.sharedEpicKey
            sharedEpicSummary: root.sharedEpicSummary
            onEpicSelected: function(key, summary) {
                root.sharedEpicKey = key
                root.sharedEpicSummary = summary
            }
        }

        // Índice 1: Minhas Issues
        MyIssuesPage {
            id: issuesPage
            sharedEpicKey: root.sharedEpicKey
            sharedEpicSummary: root.sharedEpicSummary
            onEpicSelected: function(key, summary) {
                root.sharedEpicKey = key
                root.sharedEpicSummary = summary
            }
        }

        // Índice 2: Worklogs Pendentes
        PendingWorklogsPage {
            id: pendingWorklogsPage
        }

        // Índice 3: Configuração
        SettingsPage {
            id: settingsPage
        }
    }

    // Sincronizar TabBar com StackLayout quando mudar de aba
    Connections {
        target: tabBar
        function onCurrentIndexChanged() {
            console.log("Main.qml: TabBar mudou para índice:", tabBar.currentIndex)
            stack.currentIndex = tabBar.currentIndex
            console.log("Main.qml: StackLayout mudou para índice:", stack.currentIndex)
            
            // Recarregar worklogs automaticamente quando a aba de worklogs for selecionada
            // Índice 2 corresponde à aba de Worklogs
            if (tabBar.currentIndex === 2 && pendingWorklogsPage) {
                console.log("Main.qml: Aba de worklogs selecionada, recarregando worklogs...")
                pendingWorklogsPage.reloadWorklogs()
            }
        }
    }
    
    Connections {
        target: stack
        function onCurrentIndexChanged() {
            console.log("Main.qml: StackLayout mudou para índice:", stack.currentIndex)
        }
    }
    
    // Painel flutuante do timer agora é gerenciado pelo Python (app.py)
    // A janela é criada/destruída automaticamente baseado no estado do timer
    // Não precisa mais criar aqui - removido para evitar conflitos

}
