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
        // #region agent log
        if (typeof root._ctxDebugLog !== "undefined" && root._ctxDebugLog && typeof root._ctxDebugLog.log === "function") {
            root._ctxDebugLog.log("Main.qml:onCompleted", "start")
        }
        // #endregion
        Kirigami.Theme.inherit = true
        // Não usar root.clipboardHelper: em QML "clipboardHelper" no onCompleted
        // resolve para root.clipboardHelper (null), não para a context property.
        // As páginas recebem a context property diretamente via binding.

        // Garantir que o header receba referências ao stack e às páginas após eles existirem
        // (no ApplicationWindow o header é criado antes do conteúdo, então stack/createPage/etc.
        // podem ser undefined na declaração; reatribuir aqui para os bindings dos botões funcionarem)
        Qt.callLater(function() {
            mainHeader.stack = root.stack
            mainHeader.createPage = createPage
            mainHeader.issuesPage = issuesPage
            mainHeader.settingsPage = settingsPage
            mainHeader.pendingWorklogsPage = pendingWorklogsPage
            mainHeader.githubPage = githubPage
            mainHeader.googlePage = googlePage
        })

        // Verificar se precisa configurar antes de abrir
        Qt.callLater(function() {
            // #region agent log
            if (typeof root._ctxDebugLog !== "undefined" && root._ctxDebugLog && typeof root._ctxDebugLog.log === "function") {
                root._ctxDebugLog.log("Main.qml:callLater2", "before set tab index")
            }
            // #endregion
            if (root.stack && root.tabBar && root._ctxSettingsModel) {
                if (root._ctxSettingsModel.needsConfiguration || !root._ctxSettingsModel.isConfigured) {
                    root.stack.currentIndex = 5
                    root.tabBar.currentIndex = 5
                    if (typeof root._ctxDebugLog !== "undefined" && root._ctxDebugLog && typeof root._ctxDebugLog.log === "function") {
                        root._ctxDebugLog.log("Main.qml:callLater2", "set index 3")
                    }
                } else {
                    // Só alterar índice se não for já 0 (evitar setar stack+tabBar em sequência que pode disparar SIGABRT no Flatpak/Kirigami)
                    if (root.tabBar.currentIndex !== 0) {
                        root.tabBar.currentIndex = 0
                    }
                    if (typeof root._ctxDebugLog !== "undefined" && root._ctxDebugLog && typeof root._ctxDebugLog.log === "function") {
                        root._ctxDebugLog.log("Main.qml:callLater2", "set index 0 or skip")
                    }
                }
            } else if (root.stack && root.tabBar && root.tabBar.currentIndex !== 0) {
                root.tabBar.currentIndex = 0
            }
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
    property var _ctxGitHubService: githubService // qmllint disable unqualified
    // Google services: atribuídos via Python após load (Opção B)
    property var _ctxGoogleAuthService: null
    property var _ctxGoogleCalendarService: null
    property var _ctxGoogleTasksService: null
    property var _ctxClipboardHelper: clipboardHelper // qmllint disable unqualified
    property var hideWindowFn: hideWindow // qmllint disable unqualified
    property var _ctxDebugLog: debugLog // qmllint disable unqualified

    // Quando true, o erro de transição (ex.: ao clicar "Iniciar Timer" no SuccessDialog) já está a ser mostrado no diálogo de criação; evita ErrorDialog/ProcessDialog duplicados
    property bool _jiraErrorShownInCreateFlow: false

    header: MainHeader {
        id: mainHeader
        createPage: createPage
        issuesPage: issuesPage
        settingsPage: settingsPage
        pendingWorklogsPage: pendingWorklogsPage
        githubPage: githubPage
        issueModel: root._ctxIssueModel
        jiraService: root._ctxJiraService
        timerModel: root._ctxTimerModel
        timerService: root._ctxTimerService
        githubService: root._ctxGitHubService
    }

    property alias tabBar: mainHeader.tabBar
    property alias stack: stackLayout

    // Propriedade compartilhada para sincronizar epic selecionado entre abas
    property string sharedEpicKey: ""
    property string sharedEpicSummary: ""


    // -----------------------------------------------------------------
    // Conteúdo principal: abas empilhadas
    // Evolução opcional: um único ProcessDialog como filho da janela (dialog host)
    // que as páginas pedem para mostrar progress/success/error, em vez de cada página ter o seu.
    // -----------------------------------------------------------------
    StackLayout {
        id: stackLayout
        anchors.fill: parent
        currentIndex: root.tabBar.currentIndex

        // Índice 0: Criar Issue
        IssueFormPage {
            id: createPage
            applicationWindow: root
            issueModel: root._ctxIssueModel
            jiraService: root._ctxJiraService
            clipboardHelper: root._ctxClipboardHelper
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
                // Atualizar lista de MyIssues em background (sem mostrar diálogo de busca)
                if (issuesPage) {
                    var query = ""
                    if (issuesPage.issueSearchForm) {
                        query = issuesPage.issueSearchForm.getQuery()
                    }
                    issuesPage.refreshIssues(query, false)
                }
            }
        }

        // Índice 1: Minhas Issues
        MyIssuesPage {
            id: issuesPage
            applicationWindow: root
            issueModel: root._ctxEditingIssueModel
            jiraService: root._ctxJiraService
            clipboardHelper: root._ctxClipboardHelper
            myIssuesModel: root._ctxMyIssuesModel
            timerService: root._ctxTimerService
            timerModel: root._ctxTimerModel
            worklogSyncService: root._ctxWorklogSyncService
            githubService: root._ctxGitHubService
            hideWindowFn: root.hideWindowFn
            sharedEpicKey: root.sharedEpicKey
            sharedEpicSummary: root.sharedEpicSummary
            onEpicSelected: function(key, summary) {
                root.sharedEpicKey = key
                root.sharedEpicSummary = summary
            }
        }

        // Índice 2: Google (Calendar + Tasks unificados)
        GooglePage {
            id: googlePage
            googleCalendarService: root._ctxGoogleCalendarService
            googleTasksService: root._ctxGoogleTasksService
            googleAuthService: root._ctxGoogleAuthService
            jiraService: root._ctxJiraService
            tabBar: root.tabBar
        }

        // Índice 3: GitHub (PRs review required, Issues atribuídas)
        GitHubPage {
            id: githubPage
            githubService: root._ctxGitHubService
            issueModel: root._ctxIssueModel
            tabBar: root.tabBar
        }

        // Índice 4: Worklogs Pendentes
        PendingWorklogsPage {
            id: pendingWorklogsPage
            worklogSyncService: root._ctxWorklogSyncService
            jiraService: root._ctxJiraService
        }

        // Índice 5: Configuração
        SettingsPage {
            id: settingsPage
            settingsModel: root._ctxSettingsModel
            jiraService: root._ctxJiraService
            myIssuesModel: root._ctxMyIssuesModel
            googleAuthService: root._ctxGoogleAuthService
        }
    }

    Connections {
        target: root.tabBar
        function onCurrentIndexChanged() {
            root.stack.currentIndex = root.tabBar.currentIndex
            if (root.tabBar.currentIndex === 1 && issuesPage) {
                if (!issuesPage.initialSearchDone) {
                    issuesPage.initialSearchDone = true
                }
                var query = issuesPage.issueSearchForm ? issuesPage.issueSearchForm.getQuery() : ""
                issuesPage.refreshIssues(query)
            }
            if (root.tabBar.currentIndex === 2 && googlePage) {
                googlePage.reload()
            }
            if (root.tabBar.currentIndex === 3 && githubPage) {
                githubPage.reload()
            }
            if (root.tabBar.currentIndex === 4 && pendingWorklogsPage) {
                pendingWorklogsPage.reloadWorklogs()
            }
        }
    }

    Shortcuts {
        id: shortcuts
        stack: root.stack
        tabBar: root.tabBar
        createPage: createPage
        issuesPage: issuesPage
        settingsPage: settingsPage
        pendingWorklogsPage: pendingWorklogsPage
        githubPage: githubPage
        settingsModel: root._ctxSettingsModel
        googleTabEnabled: !!root._ctxGoogleAuthService
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
