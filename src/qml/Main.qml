// Janela principal da aplicação Kirigami
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "./pages"
import "."


Kirigami.ApplicationWindow {
    id: root

    width: 1800
    height: 1000
    minimumWidth: 1200  // Mínimo para garantir espaço suficiente para layouts horizontais
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

    // Atalhos globais (independentes de foco)
    Shortcuts {
        id: shortcuts
        stack: stack
        tabBar: mainHeader.tabBar
        createPage: createPage
        issuesPage: issuesPage
        settingsPage: settingsPage
        pendingWorklogsPage: pendingWorklogsPage
        onHideRequested: {
            if (typeof hideWindow === "function")
                hideWindow()
            else
                root.hide()
        }
    }

    // Intermediários para evitar binding loop ao passar context properties ao header
    property var _ctxIssueModel: issueModel
    property var _ctxJiraService: jiraService
    property var _ctxTimerModel: timerModel
    property var _ctxTimerService: timerService

    // Header customizado com TabBar e botão global dinâmico
    header: MainHeader {
        id: mainHeader
        stack: stack
        createPage: createPage
        issuesPage: issuesPage
        settingsPage: settingsPage
        issueModel: root._ctxIssueModel
        jiraService: root._ctxJiraService
        timerModel: root._ctxTimerModel
        timerService: root._ctxTimerService
    }

    property alias tabBar: mainHeader.tabBar

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
            onIssueCreated: function(issueKey) {
                // Quando uma issue é criada, atualizar a lista de MyIssues
                if (issuesPage) {
                    // Obter a query atual da página de MyIssues (se houver)
                    var query = ""
                    if (issuesPage.issueSearchForm) {
                        query = issuesPage.issueSearchForm.getQuery()
                    }
                    issuesPage.refreshIssues(query)
                }
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
