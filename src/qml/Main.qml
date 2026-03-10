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
    onClosing: close => {
        close.accepted = false;  // Previne fechamento da aplicação
        root.hide();              // Esconde a janela (minimiza ao tray)
    }

    // Desabilitar drawers padrão (não usamos por enquanto)
    globalDrawer: null
    contextDrawer: null

    // Inicializar Kirigami (ajuda a reduzir warnings)
    Component.onCompleted: {
        // #region agent log
        if (root.appContext && root.appContext.debugLog && typeof root.appContext.debugLog.log === "function") {
            root.appContext.debugLog.log("Main.qml:onCompleted", "start");
        }
        // #endregion
        Kirigami.Theme.inherit = true;
        // Não usar root.clipboardHelper: em QML "clipboardHelper" no onCompleted
        // resolve para root.clipboardHelper (null), não para a context property.
        // As páginas recebem a context property diretamente via binding.

        // Garantir que o header receba referências ao stack e às páginas após eles existirem
        // (no ApplicationWindow o header é criado antes do conteúdo, então stack/createPage/etc.
        // podem ser undefined na declaração; reatribuir aqui para os bindings dos botões funcionarem)
        Qt.callLater(function () {
            mainHeader.stack = root.stack;
            mainHeader.createPage = createPage;
            mainHeader.issuesPage = issuesPage;
            mainHeader.createWorkItemPage = createWorkItemPage;
            mainHeader.myWorkItemsPage = myWorkItemsPage;
            mainHeader.settingsPage = settingsPage;
            mainHeader.pendingWorklogsPage = pendingWorklogsPage;
            mainHeader.timesheetPage = timesheetPage;
            mainHeader.githubPage = githubPage;
            mainHeader.googlePage = googlePage;
        });

        // Verificar se precisa configurar antes de abrir
        Qt.callLater(function () {
            // #region agent log
            if (root.appContext && root.appContext.debugLog && typeof root.appContext.debugLog.log === "function") {
                root.appContext.debugLog.log("Main.qml:callLater2", "before set tab index");
            }
            // #endregion
            if (root.stack && root.tabBar && root.appContext && root.appContext.settingsModel) {
                if (root.appContext.settingsModel.needsConfiguration || !root.appContext.settingsModel.isConfigured) {
                    root.stack.currentIndex = 6;
                    root.tabBar.currentIndex = 6;
                    if (root.appContext && root.appContext.debugLog && typeof root.appContext.debugLog.log === "function") {
                        root.appContext.debugLog.log("Main.qml:callLater2", "set index 3");
                    }
                } else {
                    // Só alterar índice se não for já 0 (evitar setar stack+tabBar em sequência que pode disparar SIGABRT no Flatpak/Kirigami)
                    if (root.tabBar.currentIndex !== 0) {
                        root.tabBar.currentIndex = 0;
                    }
                    if (root.appContext && root.appContext.debugLog && typeof root.appContext.debugLog.log === "function") {
                        root.appContext.debugLog.log("Main.qml:callLater2", "set index 0 or skip");
                    }
                }
            } else if (root.stack && root.tabBar && root.tabBar.currentIndex !== 0) {
                root.tabBar.currentIndex = 0;
            }
        });
    }

    // Objeto único injetado pelo Python via setInitialProperties; acesso qualificado (root.appContext.xxx)
    property var appContext

    // Para preview de Markdown (DescriptionField, CommentsSection, etc.): exposto no root para resolução do identificador não qualificado "markdownPreviewRenderer" em componentes filhos.
    property var markdownPreviewRenderer: root.appContext ? root.appContext.markdownPreviewRenderer : null

    property var hideWindowFn: root.appContext ? root.appContext.hideWindow : null

    // Quando true, o erro de transição (ex.: ao clicar "Iniciar Timer" no SuccessDialog) já está a ser mostrado no diálogo de criação; evita ErrorDialog/ProcessDialog duplicados
    property bool _jiraErrorShownInCreateFlow: false

    header: MainHeader {
        id: mainHeader
        createPage: createPage
        issuesPage: issuesPage
        settingsPage: settingsPage
        pendingWorklogsPage: pendingWorklogsPage
        githubPage: githubPage
        issueModel: root.appContext ? root.appContext.issueModel : null
        workItemModel: root.appContext ? root.appContext.workItemModel : null
        jiraService: root.appContext ? root.appContext.jiraService : null
        timerModel: root.appContext ? root.appContext.timerModel : null
        timerService: root.appContext ? root.appContext.timerService : null
        githubService: root.appContext ? root.appContext.githubService : null
    }

    property alias tabBar: mainHeader.tabBar
    property alias stack: stackLayout

    // Propriedade compartilhada para sincronizar epic selecionado entre abas
    property string sharedEpicKey: ""
    property string sharedEpicSummary: ""
    // Estado partilhado epic/parent para abas work item (7 e 8)
    property string sharedParentKey: ""
    property string sharedParentSummary: ""

    /** Navega para a aba MyIssues e seleciona/carrega a issue (ex.: ao iniciar timer no diálogo de criação). */
    function navigateToIssue(issueKey) {
        if (!issueKey || !issuesPage)
            return;
        tabBar.currentIndex = 1;
        issuesPage.selectedIssueKey = issueKey;
        issuesPage.loadIssueDetails(issueKey);
        if (issuesPage.issueList)
            issuesPage.issueList.selectIssue(issueKey);
    }

    /** Navega para a aba MyWorkItems (índice 8) e seleciona/carrega a issue (ex.: após criar task e clicar Iniciar Timer ou Abrir). */
    function navigateToWorkItem(issueKey) {
        if (!issueKey || !myWorkItemsPage)
            return;
        tabBar.currentIndex = 8;
        myWorkItemsPage.selectedIssueKey = issueKey;
        myWorkItemsPage.loadIssueDetails(issueKey);
        if (myWorkItemsPage.issueList)
            myWorkItemsPage.issueList.selectIssue(issueKey);
    }

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
            issueModel: root.appContext ? root.appContext.issueModel : null
            jiraService: root.appContext ? root.appContext.jiraService : null
            clipboardHelper: root.appContext ? root.appContext.clipboardHelper : null
            hideWindowFn: root.hideWindowFn
            timerService: root.appContext ? root.appContext.timerService : null
            timerModel: root.appContext ? root.appContext.timerModel : null
            voiceInputService: root.appContext ? root.appContext.voiceInputService : null
            sharedEpicKey: root.sharedEpicKey
            sharedEpicSummary: root.sharedEpicSummary
            onEpicSelected: function (key, summary) {
                root.sharedEpicKey = key;
                root.sharedEpicSummary = summary;
            }
            onIssueCreated: function (issueKey) {
                // Atualizar lista de MyIssues em background (sem mostrar diálogo de busca)
                if (issuesPage) {
                    var query = "";
                    if (issuesPage.issueSearchForm) {
                        query = issuesPage.issueSearchForm.getQuery();
                    }
                    issuesPage.refreshIssues(query, false);
                }
            }
        }

        // Índice 1: Minhas Issues
        MyIssuesPage {
            id: issuesPage
            applicationWindow: root
            issueModel: root.appContext ? root.appContext.editingIssueModel : null
            jiraService: root.appContext ? root.appContext.jiraService : null
            clipboardHelper: root.appContext ? root.appContext.clipboardHelper : null
            gitCommandHelper: root.appContext ? root.appContext.gitCommandHelper : null
            myIssuesModel: root.appContext ? root.appContext.myIssuesModel : null
            timerService: root.appContext ? root.appContext.timerService : null
            voiceInputService: root.appContext ? root.appContext.voiceInputService : null
            timerModel: root.appContext ? root.appContext.timerModel : null
            worklogSyncService: root.appContext ? root.appContext.worklogSyncService : null
            githubService: root.appContext ? root.appContext.githubService : null
            hideWindowFn: root.hideWindowFn
            sharedEpicKey: root.sharedEpicKey
            sharedEpicSummary: root.sharedEpicSummary
            onEpicSelected: function (key, summary) {
                root.sharedEpicKey = key;
                root.sharedEpicSummary = summary;
            }
        }

        // Índice 2: Google (Calendar + Tasks unificados)
        GooglePage {
            id: googlePage
            googleCalendarService: root.appContext ? root.appContext.googleCalendarService : null
            googleTasksService: root.appContext ? root.appContext.googleTasksService : null
            googleDriveCommentsService: root.appContext ? root.appContext.googleDriveCommentsService : null
            googleAuthService: root.appContext ? root.appContext.googleAuthService : null
            jiraService: root.appContext ? root.appContext.jiraService : null
            issueModel: root.appContext ? root.appContext.issueModel : null
            tabBar: root.tabBar
        }

        // Índice 3: GitHub (PRs review required, Issues atribuídas)
        GitHubPage {
            id: githubPage
            githubService: root.appContext ? root.appContext.githubService : null
            issueModel: root.appContext ? root.appContext.issueModel : null
            tabBar: root.tabBar
        }

        // Índice 4: Worklogs Pendentes
        PendingWorklogsPage {
            id: pendingWorklogsPage
            worklogSyncService: root.appContext ? root.appContext.worklogSyncService : null
            jiraService: root.appContext ? root.appContext.jiraService : null
        }

        // Índice 5: Timesheet
        TimesheetPage {
            id: timesheetPage
            timesheetViewModel: root.appContext ? root.appContext.timesheetViewModel : null
        }

        // Índice 6: Configuração
        SettingsPage {
            id: settingsPage
            settingsModel: root.appContext ? root.appContext.settingsModel : null
            jiraService: root.appContext ? root.appContext.jiraService : null
            myIssuesModel: root.appContext ? root.appContext.myIssuesModel : null
            googleAuthService: root.appContext ? root.appContext.googleAuthService : null
            jiraMetadataConfigModel: root.appContext ? root.appContext.jiraMetadataConfigModel : null
            voiceInputService: root.appContext ? root.appContext.voiceInputService : null
        }

        // Índice 7: Criar work item (cópia de Criar Issue, modelos isolados)
        CreateWorkItemPage {
            id: createWorkItemPage
            applicationWindow: root
            workItemModel: root.appContext ? root.appContext.workItemModel : null
            jiraService: root.appContext ? root.appContext.atlassianService : null
            clipboardHelper: root.appContext ? root.appContext.clipboardHelper : null
            hideWindowFn: root.hideWindowFn
            timerService: root.appContext ? root.appContext.timerService : null
            timerModel: root.appContext ? root.appContext.timerModel : null
            sharedEpicKey: root.sharedParentKey
            sharedEpicSummary: root.sharedParentSummary
            voiceInputServiceOverride: root.appContext ? root.appContext.voiceTranscriptionService : null
            atlassianMetadataConfigModel: root.appContext ? root.appContext.atlassianMetadataConfigModel : null
            onEpicSelected: function (key, summary) {
                root.sharedParentKey = key;
                root.sharedParentSummary = summary;
            }
            onIssueCreated: function (issueKey) {
                if (myWorkItemsPage) {
                    var query = "";
                    if (myWorkItemsPage.issueSearchForm) {
                        query = myWorkItemsPage.issueSearchForm.getQuery();
                    }
                    myWorkItemsPage.refreshIssues(query, false);
                }
            }
        }

        // Índice 8: Minhas work items (cópia de Minhas Issues, modelos isolados)
        MyWorkItemsPage {
            id: myWorkItemsPage
            applicationWindow: root
            workItemModel: root.appContext ? root.appContext.editingWorkItemModel : null
            jiraService: root.appContext ? root.appContext.atlassianService : null
            clipboardHelper: root.appContext ? root.appContext.clipboardHelper : null
            gitCommandHelper: root.appContext ? root.appContext.gitCommandHelper : null
            myIssuesModel: root.appContext ? root.appContext.myWorkItemsModel : null
            timerService: root.appContext ? root.appContext.timerService : null
            timerModel: root.appContext ? root.appContext.timerModel : null
            worklogSyncService: root.appContext ? root.appContext.worklogSyncService : null
            githubService: root.appContext ? root.appContext.githubService : null
            hideWindowFn: root.hideWindowFn
            sharedEpicKey: root.sharedParentKey
            sharedEpicSummary: root.sharedParentSummary
            voiceInputServiceOverride: root.appContext ? root.appContext.voiceTranscriptionService : null
            atlassianMetadataConfigModel: root.appContext ? root.appContext.atlassianMetadataConfigModel : null
            onEpicSelected: function (key, summary) {
                root.sharedParentKey = key;
                root.sharedParentSummary = summary;
            }
        }
    }

    Connections {
        target: root.tabBar
        function onCurrentIndexChanged() {
            root.stack.currentIndex = root.tabBar.currentIndex;
            if (root.tabBar.currentIndex === 1 && issuesPage) {
                if (!issuesPage.hasCachedData) {
                    var query = issuesPage.issueSearchForm ? issuesPage.issueSearchForm.getQuery() : "";
                    issuesPage.refreshIssues(query);
                }
            }
            if (root.tabBar.currentIndex === 8 && myWorkItemsPage) {
                if (!myWorkItemsPage.hasCachedData) {
                    var query8 = myWorkItemsPage.issueSearchForm ? myWorkItemsPage.issueSearchForm.getQuery() : "";
                    myWorkItemsPage.refreshIssues(query8);
                }
            }
            if (root.tabBar.currentIndex === 2 && googlePage) {
                if (!googlePage.hasCachedData) {
                    googlePage.reload();
                }
            }
            if (root.tabBar.currentIndex === 3 && githubPage) {
                if (!githubPage.hasCachedData) {
                    githubPage.reload();
                }
            }
            if (root.tabBar.currentIndex === 4 && pendingWorklogsPage) {
                pendingWorklogsPage.reloadWorklogs();
            }
            if (root.tabBar.currentIndex === 5 && timesheetPage && timesheetPage.timesheetViewModel) {
                if (!timesheetPage.timesheetViewModel.hasCachedData) {
                    timesheetPage.timesheetViewModel.loadInitial();
                }
            }
        }
    }

    Shortcuts {
        id: shortcuts
        stack: root.stack
        tabBar: root.tabBar
        createPage: createPage
        issuesPage: issuesPage
        createWorkItemPage: createWorkItemPage // qmllint disable missing-property
        myWorkItemsPage: myWorkItemsPage // qmllint disable missing-property
        settingsPage: settingsPage
        pendingWorklogsPage: pendingWorklogsPage
        timesheetPage: timesheetPage
        githubPage: githubPage
        settingsModel: root.appContext ? root.appContext.settingsModel : null
        googleTabEnabled: !!(root.appContext && root.appContext.googleAuthService)
        onHideRequested: {
            if (root.appContext && root.appContext.hideWindow && typeof root.appContext.hideWindow === "function")
                root.appContext.hideWindow();
            else
                root.hide();
        }
    }

    // Painel flutuante do timer agora é gerenciado pelo Python (app.py)
    // A janela é criada/destruída automaticamente baseado no estado do timer
    // Não precisa mais criar aqui - removido para evitar conflitos

}
