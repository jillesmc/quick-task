/**
 * MyIssuesPage.qml
 * 
 * Página para listar issues do usuário e atualizar issues selecionadas
 * Refatorado seguindo Clean Code e SOLID
 * Usa componentes reutilizáveis e controllers
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import QtQuick.Controls
import org.kde.kirigami as Kirigami
import "../components/forms"
import "../components/lists"
import "../controllers"

Kirigami.Page {
    id: page

    title: qsTr("Minhas Issues")
    
    // Habilitar foco para capturar atalhos de teclado
    focus: true

    // Issue selecionada atualmente
    property string selectedIssueKey: ""
    
    // Status original da issue (para comparar antes de atualizar)
    property string originalStatus: ""
    
    // Estado do processamento
    property bool isProcessing: false
    
    // Propriedades compartilhadas para sincronizar epic entre abas
    property string sharedEpicKey: ""
    property string sharedEpicSummary: ""
    
    signal epicSelected(string key, string summary)
    // Estado de carregamento dos detalhes da issue (parte inferior)
    property bool isDetailsLoading: false
    
    // Flag para controlar busca automática inicial (apenas uma vez)
    property bool initialSearchDone: false
    
    // Diálogos
    property var progressDialog: null
    property var successDialog: null
    property var searchProgressDialog: null
    
    // Controller para lógica de negócio
    property var controller: null
    
    // Função pública para cancelar (usada pelo botão global e pela tecla ESC)
    // Esconde a janela ao invés de fechar a aplicação
    function onCancelRequested() {
        if (typeof hideWindow === "function") {
            hideWindow()  // Esconde a janela (minimiza ao tray)
        }
        // Se hideWindow não estiver disponível, não fazer nada
        // (a aplicação deve estar configurada corretamente)
    }

    // Ações da página (Kirigami 6 usa 'actions' ao invés de 'mainAction')
    actions: [
        Kirigami.Action {
            id: refreshAction
            text: qsTr("Buscar")
            icon.name: "search"
            enabled: !(myIssuesModel && myIssuesModel.isLoading)
            onTriggered: {
                if (issueSearchForm) {
                    var query = issueSearchForm.getQuery()
                    refreshIssues(query)
                }
            }
        }
    ]

    // Função pública para botão global (Main.qml)
    function refreshIssuesFromToolbar() {
        if (issueSearchForm) {
            var query = issueSearchForm.getQuery()
            refreshIssues(query)
        }
    }

    // Atalhos locais (Ctrl+Enter e ESC)
    Keys.onPressed: function(event) {
        // Ctrl+Enter: atualizar lista
        if ((event.modifiers & Qt.ControlModifier) &&
                (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
            refreshIssuesFromToolbar()
            event.accepted = true
            return
        }

        // ESC: cancelar
        if (event.key === Qt.Key_Escape) {
            onCancelRequested()
            event.accepted = true
        }
    }

    function refreshIssues(query) {
        if (!myIssuesModel) {
            return
        }
        
        // Fechar diálogo anterior se existir
        if (searchProgressDialog) {
            searchProgressDialog.close()
            searchProgressDialog.destroy()
            searchProgressDialog = null
        }
        
        // Mostrar diálogo de progresso durante a busca
        var component = Qt.createComponent("../components/dialogs/ProgressDialog.qml")
        if (component.status === Component.Ready) {
            var window = page.parent && page.parent.parent ? page.parent.parent : page
            searchProgressDialog = component.createObject(window)
            if (searchProgressDialog) {
                searchProgressDialog.open()
                searchProgressDialog.updateProgress(0, "Buscando issues...")
                
                // Conectar ao sinal de loading para atualizar e fechar progresso
                var loadingConnection = function(isLoading) {
                    if (isLoading) {
                        if (searchProgressDialog) {
                            searchProgressDialog.updateProgress(50, "Buscando issues...")
                        }
                    } else {
                        Qt.callLater(function() {
                            if (searchProgressDialog) {
                                searchProgressDialog.updateProgress(100, "Busca concluída!")
                                Qt.callLater(function() {
                                    if (searchProgressDialog) {
                                        searchProgressDialog.close()
                                        searchProgressDialog.destroy()
                                        searchProgressDialog = null
                                    }
                                    
                                    // Selecionar automaticamente a primeira issue se houver resultados
                                    Qt.callLater(function() {
                                        if (myIssuesModel && myIssuesModel.issues && myIssuesModel.issues.length > 0) {
                                            var firstIssue = myIssuesModel.issues[0]
                                            if (firstIssue && firstIssue.key) {
                                                if (issueList) {
                                                    issueList.selectIssue(firstIssue.key)
                                                }
                                            }
                                        }
                                    })
                                })
                            }
                            if (myIssuesModel) {
                                myIssuesModel.loadingChanged.disconnect(loadingConnection)
                            }
                        })
                    }
                }
                
                if (myIssuesModel) {
                    myIssuesModel.loadingChanged.connect(loadingConnection)
                }
            }
        }
        
        // Iniciar busca
        if (controller) {
            controller.searchIssues(query || "")
        } else {
            myIssuesModel.refreshIssues(query || "")
        }
    }

    // Criar controller
    Component.onCompleted: {
        var component = Qt.createComponent("../controllers/MyIssuesController.qml")
        if (component.status === Component.Ready) {
            controller = component.createObject(page, {
                jiraService: jiraService,
                myIssuesModel: myIssuesModel,
                issueModel: issueModel,
                enabled: true
            })

            if (controller) {
                controller.updateStarted.connect(function() {
                    isProcessing = true
                    showProgressDialog()
                })
                
                controller.updateCompleted.connect(function(issueKey) {
                    isProcessing = false
                    hideProgressDialog()
                    showSuccessDialog(issueKey)
                    if (issueSearchForm) {
                        var query = issueSearchForm.getQuery()
                        refreshIssues(query)
                    }
                })
                
                controller.updateFailed.connect(function(errorMessage) {
                    isProcessing = false
                    hideProgressDialog()
                    showErrorDialog(errorMessage)
                })
                
                controller.issueSelected.connect(function(issueKey, issueData) {
                    if (issueKey) {
                        page.selectedIssueKey = issueKey
                        loadIssueDetails(issueKey)
                    }
                })
            }
        }
    }

    Controls.SplitView {
        id: splitView
        anchors.fill: parent
        orientation: Qt.Vertical
        
        // Container superior: Busca e lista de issues (sem ScrollView, usando scroll interno do ListView)
        Item {
            id: topPane
            SplitView.minimumHeight: 150
            SplitView.preferredHeight: 300
            SplitView.maximumHeight: 600
            SplitView.fillWidth: true
            
            ColumnLayout {
                id: topColumnLayout
                anchors.fill: parent
                anchors.margins: Kirigami.Units.largeSpacing
                anchors.leftMargin: Kirigami.Units.largeSpacing
                anchors.rightMargin: Kirigami.Units.largeSpacing
                spacing: Kirigami.Units.largeSpacing
            
                // Busca de issues usando componente reutilizável
                IssueSearchForm {
                    id: issueSearchForm
                    Layout.fillWidth: true
                    enabled: !isProcessing
                    isLoading: myIssuesModel ? myIssuesModel.isLoading : false
                    placeholderText: qsTr("Buscar issues por resumo ou chave...")
                    
                    onSearchRequested: function(query) {
                        refreshIssues(query)
                    }
                }
                
                Controls.Label {
                    text: qsTr("Issues atribuídas a você")
                    font.bold: true
                    Layout.fillWidth: true
                }
            
                // Lista de issues usando componente reutilizável
                Item {
                    id: issueListContainer
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    
                    IssueList {
                        id: issueList
                        anchors.fill: parent
                        enabled: !isProcessing
                        model: myIssuesModel ? myIssuesModel.issues : []
                        isLoading: myIssuesModel ? myIssuesModel.isLoading : false
                        selectedIssueKey: page.selectedIssueKey
                        
                        onIssueSelected: function(issueKey, issueData) {
                            page.selectedIssueKey = issueKey
                            loadIssueDetails(issueKey)
                        }
                    }
                }
            }
        }
        
        // Container inferior: Campos de atualização
        Controls.ScrollView {
            id: bottomScrollView
            SplitView.fillHeight: true
            SplitView.fillWidth: true
            SplitView.minimumHeight: 200
            clip: true
            
            Item {
                id: bottomContent
                width: bottomScrollView.availableWidth
                // Altura acompanha o conteúdo da ColumnLayout para permitir scroll
                implicitHeight: bottomColumnLayout.implicitHeight
                
                ColumnLayout {
                    id: bottomColumnLayout
                    anchors.margins: Kirigami.Units.largeSpacing
                    anchors.leftMargin: Kirigami.Units.largeSpacing
                    anchors.rightMargin: Kirigami.Units.largeSpacing
                    anchors.fill: parent
                    spacing: Kirigami.Units.largeSpacing
                    Layout.alignment: Qt.AlignLeft | Qt.AlignTop
                
                    Kirigami.Separator {
                        Layout.fillWidth: true
                    }
                
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignLeft | Qt.AlignTop
                        
                        Kirigami.Heading {
                            text: qsTr("Atualizar Task")
                            level: 3
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignLeft | Qt.AlignTop
                        }
                        
                        // Link clicável para abrir task no browser
                        Controls.Label {
                            id: taskLinkLabel
                            text: selectedIssueKey || ""
                            color: Kirigami.Theme.linkColor
                            visible: selectedIssueKey !== ""
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (jiraService && selectedIssueKey && typeof jiraService.getIssueUrl === 'function') {
                                        var url = jiraService.getIssueUrl(selectedIssueKey)
                                        if (url) {
                                            Qt.openUrlExternally(url)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    // Botão Iniciar Timer (visível apenas quando issue está selecionada)
                    Controls.Button {
                        text: {
                            if (timerModel && timerModel.state === "running" && timerModel.issueKey === selectedIssueKey) {
                                return qsTr("Timer Ativo - Parar")
                            } else if (timerModel && timerModel.state === "paused" && timerModel.issueKey === selectedIssueKey) {
                                return qsTr("Timer Pausado - Retomar")
                            } else if (timerModel && timerModel.isOnBreak) {
                                return qsTr("Cancelar Pausa e Iniciar")
                            } else if (timerModel && timerModel.state !== "idle" && timerModel.issueKey !== selectedIssueKey) {
                                return qsTr("Parar Timer Atual e Iniciar")
                            }
                            return qsTr("Iniciar Timer")
                        }
                        icon.name: {
                            if (timerModel && timerModel.state === "running" && timerModel.issueKey === selectedIssueKey) {
                                return "media-playback-stop"
                            } else if (timerModel && timerModel.state === "paused" && timerModel.issueKey === selectedIssueKey) {
                                return "media-playback-start"
                            } else if (timerModel && timerModel.isOnBreak) {
                                return "media-playback-start"
                            }
                            return "chronometer"
                        }
                        Layout.fillWidth: true
                        enabled: selectedIssueKey !== "" && !isProcessing && timerService && timerModel
                        visible: selectedIssueKey !== ""
                        
                        onClicked: {
                            if (!timerService || !timerModel || !selectedIssueKey) {
                                return
                            }
                            
                            // Se está em pausa, cancelar pausa e iniciar timer
                            if (timerModel && timerModel.isOnBreak) {
                                timerService.cancelBreak()
                                Qt.callLater(function() {
                                    if (timerService && selectedIssueKey) {
                                        timerService.start(selectedIssueKey)
                                    }
                                })
                                return
                            }
                            
                            // Se já há timer ativo para esta issue
                            if (timerModel.issueKey === selectedIssueKey && timerModel.state !== "idle") {
                                if (timerModel.state === "running") {
                                    timerService.stop()
                                } else if (timerModel.state === "paused") {
                                    timerService.resume()
                                }
                            }
                            // Se há timer ativo para outra issue, perguntar
                            else if (timerModel.state !== "idle" && timerModel.issueKey !== selectedIssueKey) {
                                // Parar timer atual e iniciar novo
                                timerService.stop()
                                // Usar callLater para garantir que o stop termine antes de iniciar
                                Qt.callLater(function() {
                                    if (timerService && selectedIssueKey) {
                                        timerService.start(selectedIssueKey)
                                    }
                                })
                            }
                            // Iniciar novo timer
                            else {
                                timerService.start(selectedIssueKey)
                            }
                        }
                    }
                    
                    // Summary (igual à aba 1)
                    Controls.Label {
                        text: qsTr("Summary:")
                        font.bold: true
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignLeft | Qt.AlignTop
                    }
                    
                    Controls.TextField {
                        id: summaryFieldTab2
                        Layout.fillWidth: true
                        Layout.leftMargin: Kirigami.Units.mediumSpacing
                        Layout.rightMargin: Kirigami.Units.mediumSpacing
                        Layout.alignment: Qt.AlignLeft | Qt.AlignTop
                        enabled: selectedIssueKey !== "" && !isProcessing
                    }
                
                    // Campos de issue usando componente reutilizável
                    IssueFieldsForm {
                        id: issueFieldsForm
                        Layout.fillWidth: true
                        enabled: selectedIssueKey !== "" && !isProcessing
                        tipoAtividadeValues: issueModel ? issueModel.tipoAtividadeValues : []
                        statusSequence: issueModel ? issueModel.statusSequence : []
                        
                        // Bindings bidirecionais do status
                        Binding {
                            target: issueModel
                            property: "statusInicial"
                            value: issueFieldsForm.status
                            when: issueModel
                        }
                        
                        Binding {
                            target: issueFieldsForm
                            property: "status"
                            value: issueModel ? issueModel.statusInicial : ""
                            when: issueModel
                        }
                    }

                    // GridLayout para Status e Worklog em 2 colunas
                    GridLayout {
                    id: statusWorklogGrid
                    columns: 2
                    columnSpacing: Kirigami.Units.largeSpacing * 2
                    rowSpacing: Kirigami.Units.mediumSpacing
                    Layout.fillWidth: false
                    Layout.fillHeight: false
                    Layout.alignment: Qt.AlignLeft | Qt.AlignTop
                    
                    // Coluna 1: Status
                    ColumnLayout {
                        id: statusColumn
                        Layout.preferredWidth: 500
                        Layout.maximumWidth: 500
                        Layout.alignment: Qt.AlignLeft | Qt.AlignTop
                        spacing: Kirigami.Units.smallSpacing
                        
                        Controls.Label {
                            text: qsTr("Status:")
                            font.bold: true
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignLeft | Qt.AlignTop
                        }
                        
                        GridLayout {
                            id: statusGrid
                            columns: 1
                            columnSpacing: Kirigami.Units.largeSpacing * 2
                            rowSpacing: Kirigami.Units.smallSpacing
                            Layout.fillWidth: true
                            Layout.leftMargin: Kirigami.Units.mediumSpacing
                            Layout.alignment: Qt.AlignLeft | Qt.AlignTop
                            
                            Repeater {
                                model: issueModel ? issueModel.statusSequence : []
                                
                                Controls.RadioButton {
                                    text: modelData
                                    enabled: selectedIssueKey !== "" && !isProcessing
                                    checked: issueModel && issueModel.statusInicial === modelData
                                    onCheckedChanged: {
                                        if (checked && issueModel) {
                                            issueModel.statusInicial = modelData
                                            if (issueFieldsForm) {
                                                issueFieldsForm.status = modelData
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    // Coluna 2: Worklog usando componente reutilizável
                    ColumnLayout {
                        id: worklogColumn
                        Layout.preferredWidth: 250
                        Layout.maximumWidth: 250
                        Layout.alignment: Qt.AlignLeft | Qt.AlignTop
                        spacing: Kirigami.Units.smallSpacing
                        
                        Controls.Label {
                            text: qsTr("Worklog:")
                            font.bold: true
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignLeft | Qt.AlignTop
                        }
                        
                        WorklogForm {
                            id: worklogForm
                            Layout.fillWidth: true
                            enabled: selectedIssueKey !== "" && !isProcessing
                            showCheckbox: true
                        }
                    }
                }

                    // Epic Parent usando componente reutilizável
                    EpicSearchForm {
                        id: epicSearchForm
                        Layout.fillWidth: true
                        enabled: selectedIssueKey !== "" && !isProcessing
                        
                        // Binding para garantir que jiraService seja sempre atualizado
                        Binding {
                            target: epicSearchForm
                            property: "jiraService"
                            value: typeof jiraService !== "undefined" ? jiraService : null
                            when: typeof jiraService !== "undefined"
                        }
                        
                        // Carregar filtros quando jiraService estiver disponível (apenas na inicialização)
                        // NOTA: As regras ao clicar em issue têm prioridade sobre o config.json
                        Connections {
                            target: epicSearchForm
                            function onJiraServiceChanged() {
                                // Só carregar filtros se não houver issue selecionada
                                // Quando uma issue é clicada, as regras específicas são aplicadas
                                if (epicSearchForm.jiraService && !page.selectedIssueKey) {
                                    epicSearchForm.loadFilters()
                                }
                            }
                        }
                        
                        // Sincronizar epic selecionado com sharedEpicKey
                        onEpicSelected: function(key, summary) {
                            page.epicSelected(key, summary)
                        }
                        
                        // Limpar sharedEpicKey quando epic é limpo
                        onEpicCleared: {
                            page.sharedEpicKey = ""
                            page.sharedEpicSummary = ""
                        }
                        
                        // Sincronizar epic compartilhado da aba 1
                        Binding {
                            target: epicSearchForm
                            property: "selectedEpicKey"
                            value: page.sharedEpicKey
                            when: page.sharedEpicKey !== "" && page.sharedEpicKey !== epicSearchForm.selectedEpicKey
                        }
                        
                        Binding {
                            target: epicSearchForm
                            property: "selectedEpicSummary"
                            value: page.sharedEpicSummary
                            when: page.sharedEpicSummary !== "" && page.sharedEpicSummary !== epicSearchForm.selectedEpicSummary
                        }
                    }

                    // Espaço extra no final para não \"comer\" o último campo
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Kirigami.Units.largeSpacing * 2
                    }
                }
                
                // Overlay de loading sobre a parte inferior
                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(0, 0, 0, 0.4)
                    visible: isDetailsLoading
                    z: 100
                    
                    Controls.BusyIndicator {
                        anchors.centerIn: parent
                        running: isDetailsLoading
                        visible: isDetailsLoading
                    }
                }
            }
        }
    }
    
    // Conectar signals do jiraService
    Connections {
        target: jiraService
        
        function onProgressUpdated(percentage, message) {
            if (progressDialog) {
                progressDialog.updateProgress(percentage, message)
            }
        }
    }
    
    // Conectar signals do myIssuesModel para fechar diálogo de busca
    Connections {
        target: myIssuesModel
        
        function onErrorOccurred(errorMessage) {
            if (searchProgressDialog) {
                searchProgressDialog.close()
                searchProgressDialog.destroy()
                searchProgressDialog = null
            }
            showErrorDialog(errorMessage)
        }
    }
    
    // Funções auxiliares
    function loadIssueDetails(issueKey) {
        if (!issueKey || !jiraService) {
            return
        }
        // Delegar carregamento para o JiraService em modo assíncrono.
        // O overlay e o preenchimento dos campos são controlados pelos
        // sinais issueDetailsStarted / issueDetailsLoaded abaixo.
        jiraService.getIssueDetailsAsync(issueKey)
    }
    
        // Função pública para atualizar issue (chamada pelo botão global / atalho)
        function updateIssue() {
        if (!selectedIssueKey || selectedIssueKey === "") {
            showErrorDialog("Por favor, selecione uma task para atualizar")
            return
        }
        
        if (!controller) {
            showErrorDialog("Controller não disponível")
            return
        }
        
        // Obter dados dos componentes
        var fieldData = issueFieldsForm ? issueFieldsForm.getFieldData() : {}
        // Incluir summary editado na aba 2
        if (summaryFieldTab2) {
            fieldData.summary = summaryFieldTab2.text || ""
        }
        var worklogData = worklogForm ? worklogForm.getWorklogData() : {}
        var epicKey = epicSearchForm ? epicSearchForm.selectedEpicKey : ""
        
        // Atualizar via controller
        controller.updateIssue(selectedIssueKey, fieldData, worklogData, epicKey, originalStatus)
    }

    function resetFields() {
        // Resetar campos para valores padrão
        if (issueFieldsForm) {
            issueFieldsForm.reset()
        }
        if (summaryFieldTab2) {
            summaryFieldTab2.text = ""
        }
        
        if (worklogForm) {
            worklogForm.reset()
        }
        
        if (epicSearchForm) {
            epicSearchForm.reset()
        }
        
        originalStatus = ""
    }

    function showProgressDialog() {
        var component = Qt.createComponent("../components/dialogs/ProgressDialog.qml")
        if (component.status === Component.Ready) {
            var window = page.parent && page.parent.parent ? page.parent.parent : page
            progressDialog = component.createObject(window)
            if (progressDialog) {
                progressDialog.open()
            }
        } else {
            console.error("Erro ao criar ProgressDialog:", component.errorString())
        }
    }

    function hideProgressDialog() {
        if (progressDialog) {
            progressDialog.close()
            progressDialog.destroy()
            progressDialog = null
        }
    }

    function showSuccessDialog(issueKey) {
        var component = Qt.createComponent("../components/dialogs/SuccessDialog.qml")
        if (component.status === Component.Ready) {
            var window = page.parent && page.parent.parent ? page.parent.parent : page
            successDialog = component.createObject(window)
            if (successDialog) {
                var issueUrl = ""
                successDialog.show(issueKey, issueUrl, true)  // true indica que é atualização
            }
        } else {
            console.error("Erro ao criar SuccessDialog:", component.errorString())
        }
    }

    function showErrorDialog(message) {
        var component = Qt.createComponent("../components/dialogs/ErrorDialog.qml")
        if (component.status === Component.Ready) {
            var window = page.parent && page.parent.parent ? page.parent.parent : page
            var dialog = component.createObject(window)
            if (dialog) {
                dialog.show(message)
            }
        } else {
            console.error("Erro:", message)
            console.error("Erro ao criar ErrorDialog:", component.errorString())
        }
    }

    // Reagir aos sinais assíncronos de carregamento de detalhes de issue
    Connections {
        target: jiraService

        function onIssueDetailsStarted(issueKey) {
            // Sempre que iniciar o carregamento de detalhes, limpar campos
            // e exibir overlay.
            isDetailsLoading = true
            resetFields()
        }

        function onIssueDetailsLoaded(details) {
            // Garantir que o overlay seja sempre removido ao final
            // (mesmo em caso de erro ou dados vazios).
            try {
                if (!details || !details.key) {
                    return
                }

                // Preencher campos do formulário
                if (issueFieldsForm) {
                    issueFieldsForm.setFieldData({
                        description: String(details.description || ""),
                        tipoAtividade: String(details.tipoAtividade || ""),
                        status: String(details.status || ""),
                        documentacaoAnexa: String(details.documentacaoAnexa || "Não"),
                        utilizacaoIA: String(details.utilizacaoIA || "Não")
                    })
                }
                if (summaryFieldTab2) {
                    summaryFieldTab2.text = String(details.summary || "")
                }

                // Armazenar status original
                originalStatus = String(details.status || "")

                // Epic Parent - regras específicas para aba 2
                if (details.parentKey) {
                    // Issue TEM parent
                    var parentKey = String(details.parentKey || "")
                    var parentSummary = String(details.parentSummary || "")

                    if (epicSearchForm && jiraService) {
                        // 1. Limpar todos os checkboxes (todos desmarcados)
                        epicSearchForm.clearFilters()
                        
                        // 2. Limpar campo de busca e listview
                        epicSearchForm.clearAll()
                        
                        // 3. Preencher campo de busca com parent key
                        epicSearchForm.setSearchText(parentKey)
                        
                        // 4. Buscar epic exato por key
                        var epic = jiraService.searchEpicByKey(parentKey)
                        
                        if (epic && epic.key) {
                            // Epic encontrado, adicionar à lista e selecionar
                            epicSearchForm.selectEpic(epic.key, epic.summary || parentSummary)
                        } else {
                            // Epic não encontrado, buscar normalmente (vai mostrar só ele pois busca por key)
                            epicSearchForm.requestAutoSelect(parentKey, parentSummary)
                            epicSearchForm.search(parentKey)
                        }
                    }
                } else {
                    // Issue NÃO TEM parent
                    if (epicSearchForm) {
                        // 1. Configurar checkboxes padrão
                        epicSearchForm.setDefaultFiltersForNoParent()
                        
                        // 2. Limpar campo de busca, listview e seleção (sem buscar)
                        epicSearchForm.clearAll()
                    }
                }
            } finally {
                isDetailsLoading = false
            }
        }
    }
}
