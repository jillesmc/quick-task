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

        // Garantir que o header receba referências ao stack e às páginas após eles existirem
        // (no ApplicationWindow o header é criado antes do conteúdo, então stack/createPage/etc.
        // podem ser undefined na declaração; reatribuir aqui para os bindings dos botões funcionarem)
        Qt.callLater(function() {
            mainHeader.stack = root.stack
            mainHeader.createPage = createPage
            mainHeader.issuesPage = issuesPage
            mainHeader.settingsPage = settingsPage
            mainHeader.pendingWorklogsPage = pendingWorklogsPage
        })

        // Verificar se precisa configurar antes de abrir
        Qt.callLater(function() {
            if (root.stack && root.tabBar && root._ctxSettingsModel) {
                // Verificar se configuração está completa
                // needsConfiguration verifica se arquivos existem E se valores estão preenchidos
                if (root._ctxSettingsModel.needsConfiguration || !root._ctxSettingsModel.isConfigured) {
                    // Não está configurado - abrir na aba de Configuração (índice 3)
                    root.stack.currentIndex = 3
                    root.tabBar.currentIndex = 3
                } else {
                    // Está configurado - abrir na primeira aba (Criar Issue, índice 0)
                    root.stack.currentIndex = 0
                    root.tabBar.currentIndex = 0
                }
            } else {
                // Se settingsModel não estiver disponível, abrir na primeira aba por padrão
                if (root.stack && root.tabBar) {
                    root.stack.currentIndex = 0
                    root.tabBar.currentIndex = 0
                }
            }

            // Janela flutuante do timer agora é gerenciada pelo Python (app.py)
            // Não precisa criar aqui
        })
    }

    // Único ponto de injeção: context properties injetadas pelo Python em app.py; não podem ser qualificadas estaticamente
    property var _ctxIssueModel: issueModel // qmllint disable unqualified
    property var _ctxEditingIssueModel: editingIssueModel // qmllint disable unqualified
    property var _ctxJiraService: jiraService // qmllint disable unqualified
    property var _ctxTimerModel: timerModel // qmllint disable unqualified
    property var _ctxTimerService: timerService // qmllint disable unqualified
    property var _ctxSettingsModel: settingsModel // qmllint disable unqualified
    property var _ctxMyIssuesModel: myIssuesModel // qmllint disable unqualified
    property var _ctxWorklogSyncService: worklogSyncService // qmllint disable unqualified
    property var hideWindowFn: hideWindow // qmllint disable unqualified

    // Header customizado com TabBar e botão global dinâmico
    header: MainHeader {
        id: mainHeader
        stack: stack
        createPage: createPage
        issuesPage: issuesPage
        settingsPage: settingsPage
        pendingWorklogsPage: pendingWorklogsPage
        issueModel: root._ctxIssueModel
        jiraService: root._ctxJiraService
        timerModel: root._ctxTimerModel
        timerService: root._ctxTimerService
    }

    property alias tabBar: mainHeader.tabBar
    property alias stack: stackLayout

    // Propriedade compartilhada para sincronizar epic selecionado entre abas
    property string sharedEpicKey: ""
    property string sharedEpicSummary: ""


    // -----------------------------------------------------------------
    // Conteúdo principal: abas empilhadas
    // -----------------------------------------------------------------
    StackLayout {
        id: stackLayout
        anchors.fill: parent
        // Sincronizar com TabBar
        currentIndex: root.tabBar.currentIndex

        // Índice 0: Criar Issue
        IssueFormPage {
            id: createPage
            issueModel: root._ctxIssueModel
            jiraService: root._ctxJiraService
            hideWindowFn: root.hideWindowFn
            timerService: root._ctxTimerService
            timerModel: root._ctxTimerModel
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
            issueModel: root._ctxEditingIssueModel
            jiraService: root._ctxJiraService
            myIssuesModel: root._ctxMyIssuesModel
            timerService: root._ctxTimerService
            timerModel: root._ctxTimerModel
            hideWindowFn: root.hideWindowFn
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
            worklogSyncService: root._ctxWorklogSyncService
            jiraService: root._ctxJiraService
        }

        // Índice 3: Configuração
        SettingsPage {
            id: settingsPage
            settingsModel: root._ctxSettingsModel
            jiraService: root._ctxJiraService
            myIssuesModel: root._ctxMyIssuesModel
        }
    }

    // Sincronizar TabBar com StackLayout quando mudar de aba
    Connections {
        target: root.tabBar
        function onCurrentIndexChanged() {
            console.log("Main.qml: TabBar mudou para índice:", root.tabBar.currentIndex)
            root.stack.currentIndex = root.tabBar.currentIndex
            console.log("Main.qml: StackLayout mudou para índice:", root.stack.currentIndex)

            // Recarregar worklogs automaticamente quando a aba de worklogs for selecionada
            // Índice 2 corresponde à aba de Worklogs
            if (root.tabBar.currentIndex === 2 && pendingWorklogsPage) {
                console.log("Main.qml: Aba de worklogs selecionada, recarregando worklogs...")
                pendingWorklogsPage.reloadWorklogs()
            }
        }
    }
    
    Connections {
        target: root.stack
        function onCurrentIndexChanged() {
            console.log("Main.qml: StackLayout mudou para índice:", root.stack.currentIndex)
        }
    }

    // Atalhos globais (após stack/tabBar existirem para Ctrl+Tab funcionar)
    Shortcuts {
        id: shortcuts
        stack: root.stack
        tabBar: root.tabBar
        createPage: createPage
        issuesPage: issuesPage
        settingsPage: settingsPage
        pendingWorklogsPage: pendingWorklogsPage
        onHideRequested: {
            if (root.hideWindowFn && typeof root.hideWindowFn === "function")
                root.hideWindowFn() // qmllint disable use-proper-function
            else
                root.hide()
        }
    }
    
    // Painel flutuante do timer agora é gerenciado pelo Python (app.py)
    // A janela é criada/destruída automaticamente baseado no estado do timer
    // Não precisa mais criar aqui - removido para evitar conflitos

}
