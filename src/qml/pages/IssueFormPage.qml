/**
 * IssueFormPage.qml
 * 
 * Página do formulário de criação de issue
 * Refatorado seguindo Clean Code e SOLID
 * Usa componentes reutilizáveis e controllers
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami
import "../components/forms"
import "../controllers"

Kirigami.Page {
    id: page

    title: "Preencha os dados da issue abaixo:"
    
    // Habilitar foco para capturar atalhos de teclado
    focus: true

    // Estado do processamento
    property bool isProcessing: false
    
    // Propriedades compartilhadas para sincronizar epic entre abas
    property string sharedEpicKey: ""
    property string sharedEpicSummary: ""
    
    signal epicSelected(string key, string summary)
    
    // Diálogos
    property var progressDialog: null
    property var successDialog: null
    
    // Controller para lógica de negócio
    property var controller: null
    
    // ------------------------------------------------------------------
    // Funções públicas para integração com Main.qml (botão global)
    // ------------------------------------------------------------------
    function createIssueFromToolbar() {
        // Mantém a mesma semântica original:
        // - Só cria se não estiver processando
        // - Valida antes de chamar o serviço
        if (!isProcessing && controller && controller.validate()) {
            controller.createIssue()
        }
    }

    // Função pública para cancelar (usada pelo botão global e pela tecla ESC)
    // Esconde a janela ao invés de fechar a aplicação
    function onCancelRequested() {
        if (!isProcessing) {
            if (typeof hideWindow === "function") {
                hideWindow()  // Esconde a janela (minimiza ao tray)
            }
            // Se hideWindow não estiver disponível, não fazer nada
            // (a aplicação deve estar configurada corretamente)
        }
    }

    // Atalhos de teclado locais (apenas ESC).
    // Ctrl+Enter é tratado globalmente em Main.qml via createIssueAction.
    Keys.onPressed: function(event) {
        // ESC: cancelar
        if (event.key === Qt.Key_Escape) {
            event.accepted = true
            onCancelRequested()
            return
        }
    }
    
    // Definir foco inicial no campo Summary quando a página for carregada
    Component.onCompleted: {
        summaryField.forceActiveFocus()
        
        // Inicializar worklog com data/hora atual se não estiver definido
        if (issueModel && (!issueModel.worklogInicio || issueModel.worklogInicio === "")) {
            var now = new Date()
            var dateStr = Qt.formatDateTime(now, "yyyy-MM-dd")
            var timeStr = Qt.formatDateTime(now, "HH:mm:ss")
            issueModel.worklogInicio = dateStr + " " + timeStr
        }
        
        // Criar controller
        var component = Qt.createComponent("../controllers/IssueFormController.qml")
        if (component.status === Component.Ready) {
            controller = component.createObject(page, {
                jiraService: jiraService,
                issueModel: issueModel,
                enabled: true
            })
            
            // Conectar signals do controller
            controller.createStarted.connect(function() {
                isProcessing = true
                showProgressDialog()
            })
            
            controller.createCompleted.connect(function(issueKey, issueUrl) {
                isProcessing = false
                hideProgressDialog()
                showSuccessDialog(issueKey, issueUrl)
                resetForm()
            })
            
            controller.createFailed.connect(function(errorMessage) {
                isProcessing = false
                hideProgressDialog()
                showErrorDialog(errorMessage)
            })
        }
    }
    
    // Conectar signals do jiraService para progresso
    Connections {
        target: jiraService
        
        function onProgressUpdated(percentage, message) {
            if (progressDialog) {
                progressDialog.updateProgress(percentage, message)
            }
        }
    }

    Controls.ScrollView {
        id: scrollView
        anchors.fill: parent
        clip: true
        
        ColumnLayout {
            id: formColumn
            width: scrollView.availableWidth
            anchors.margins: Kirigami.Units.largeSpacing
            anchors.leftMargin: Kirigami.Units.largeSpacing
            anchors.rightMargin: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.largeSpacing
            Layout.alignment: Qt.AlignLeft | Qt.AlignTop
        
            // Summary
            Controls.Label {
                text: "Summary:"
                font.bold: true
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignLeft | Qt.AlignTop
            }
            
            Controls.TextField {
                id: summaryField
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.mediumSpacing
                Layout.rightMargin: Kirigami.Units.mediumSpacing
                Layout.alignment: Qt.AlignLeft | Qt.AlignTop
                enabled: !isProcessing
                text: issueModel ? issueModel.summary : ""
                onTextChanged: if (issueModel) issueModel.summary = text
            }
            
            // Campos de issue usando componente reutilizável
            IssueFieldsForm {
                id: issueFieldsForm
                Layout.fillWidth: true
                enabled: !isProcessing
                tipoAtividadeValues: issueModel ? issueModel.tipoAtividadeValues : []
                statusSequence: issueModel ? issueModel.statusSequence : []
                
                // Bindings bidirecionais com issueModel
                Binding {
                    target: issueModel
                    property: "description"
                    value: issueFieldsForm.description
                    when: issueModel
                }
                
                Binding {
                    target: issueModel
                    property: "tipoAtividade"
                    value: issueFieldsForm.tipoAtividade
                    when: issueModel
                }
                
                Binding {
                    target: issueModel
                    property: "statusInicial"
                    value: issueFieldsForm.status
                    when: issueModel
                }
                
                Binding {
                    target: issueModel
                    property: "documentacaoAnexa"
                    value: issueFieldsForm.documentacaoAnexa
                    when: issueModel
                }
                
                Binding {
                    target: issueModel
                    property: "utilizacaoIA"
                    value: issueFieldsForm.utilizacaoIA
                    when: issueModel
                }
                
                // Bindings reversos (do modelo para o formulário)
                Binding {
                    target: issueFieldsForm
                    property: "description"
                    value: issueModel ? issueModel.description : ""
                    when: issueModel
                }
                
                Binding {
                    target: issueFieldsForm
                    property: "tipoAtividade"
                    value: issueModel ? issueModel.tipoAtividade : ""
                    when: issueModel
                }
                
                Binding {
                    target: issueFieldsForm
                    property: "status"
                    value: issueModel ? issueModel.statusInicial : ""
                    when: issueModel
                }
                
                Binding {
                    target: issueFieldsForm
                    property: "documentacaoAnexa"
                    value: issueModel ? issueModel.documentacaoAnexa : "Não"
                    when: issueModel
                }
                
                Binding {
                    target: issueFieldsForm
                    property: "utilizacaoIA"
                    value: issueModel ? issueModel.utilizacaoIA : "Não"
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
                                enabled: !isProcessing
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
                
                // Coluna 2: Worklog
                ColumnLayout {
                    id: worklogColumn
                    Layout.preferredWidth: 250
                    Layout.maximumWidth: 250
                    Layout.alignment: Qt.AlignLeft | Qt.AlignTop
                    spacing: Kirigami.Units.smallSpacing
                    
                    Controls.Label {
                        text: "Worklog:"
                        font.bold: true
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignLeft | Qt.AlignTop
                    }
                    
                    WorklogForm {
                        id: worklogForm
                        Layout.fillWidth: true
                        enabled: !isProcessing
                        showCheckbox: true
                        
                        // Bindings bidirecionais com issueModel
                        Binding {
                            target: issueModel
                            property: "registrarWorklog"
                            value: worklogForm.shouldRegister
                            when: issueModel
                        }
                        
                        Binding {
                            target: issueModel
                            property: "worklogInicio"
                            value: worklogForm.date && worklogForm.time ? worklogForm.date + " " + worklogForm.time : ""
                            when: issueModel && worklogForm.date && worklogForm.time
                        }
                        
                        Binding {
                            target: issueModel
                            property: "worklogDuracao"
                            value: Math.round(worklogForm.duration)
                            when: issueModel
                        }

                        // Comentário do worklog (somente criação usa via issueModel)
                        Binding {
                            target: issueModel
                            property: "worklogComment"
                            value: worklogForm.comment
                            when: issueModel
                        }
                        
                        // Binding reverso para inicializar campos
                        Component.onCompleted: {
                            if (issueModel && issueModel.worklogInicio) {
                                var parts = issueModel.worklogInicio.split(" ")
                                if (parts.length >= 2) {
                                    worklogForm.date = parts[0]
                                    worklogForm.time = parts[1]
                                }
                            }
                            if (issueModel) {
                                worklogForm.duration = issueModel.worklogDuracao || 30
                                worklogForm.comment = issueModel.worklogComment || ""
                            }
                        }
                    }
                }
            }
        
            // Epic Parent usando componente reutilizável
            EpicSearchForm {
                id: epicSearchForm
                Layout.fillWidth: true
                enabled: !isProcessing
                
                // Binding para garantir que jiraService seja sempre atualizado
                Binding {
                    target: epicSearchForm
                    property: "jiraService"
                    value: typeof jiraService !== "undefined" ? jiraService : null
                    when: typeof jiraService !== "undefined"
                }
                
                // Bindings bidirecionais com issueModel
                Binding {
                    target: issueModel
                    property: "epicParentKey"
                    value: epicSearchForm.selectedEpicKey
                    when: issueModel
                }
                
                Binding {
                    target: issueModel
                    property: "epicParentSummary"
                    value: epicSearchForm.selectedEpicSummary
                    when: issueModel
                }
                
                // Sincronizar epic selecionado com sharedEpicKey e issueModel
                onEpicSelected: function(key, summary) {
                    // Atualizar issueModel
                    if (issueModel) {
                        issueModel.epicParentKey = key
                        issueModel.epicParentSummary = summary
                    }
                    // Emitir signal para sincronizar com outras abas
                    page.epicSelected(key, summary)
                }
                
                // Limpar sharedEpicKey quando epic é limpo
                onEpicCleared: {
                    page.sharedEpicKey = ""
                    page.sharedEpicSummary = ""
                    // Limpar também no issueModel
                    if (issueModel) {
                        issueModel.epicParentKey = ""
                        issueModel.epicParentSummary = ""
                    }
                }
                
                // Sincronizar epic compartilhado da aba 2
                Binding {
                    target: epicSearchForm
                    property: "selectedEpicKey"
                    value: page.sharedEpicKey
                    when: page.sharedEpicKey !== ""
                }
                
                Binding {
                    target: epicSearchForm
                    property: "selectedEpicSummary"
                    value: page.sharedEpicSummary
                    when: page.sharedEpicSummary !== ""
                }
                
                // Binding reverso
                Binding {
                    target: epicSearchForm
                    property: "selectedEpicKey"
                    value: issueModel ? issueModel.epicParentKey : ""
                    when: issueModel
                }
                
                Binding {
                    target: epicSearchForm
                    property: "selectedEpicSummary"
                    value: issueModel ? issueModel.epicParentSummary : ""
                    when: issueModel
                }
            }
        
            // Item vazio que preenche o espaço restante
            Item {
                Layout.fillHeight: true
                Layout.fillWidth: true
            }
        }
    }
    
    // Funções auxiliares
    function resetForm() {
        // Resetar campos para valores padrão
        if (issueModel) {
            issueModel.summary = ""
            issueModel.description = ""
            
            // Tipo de atividade padrão
            var defaultTipo = "Suporte Dúvidas/Suporte uso incorreto"
            var tipoValues = issueModel.tipoAtividadeValues
            if (tipoValues.indexOf(defaultTipo) >= 0) {
                issueModel.tipoAtividade = defaultTipo
            } else if (tipoValues.length > 0) {
                issueModel.tipoAtividade = tipoValues[0]
            }
            
            // Status inicial padrão
            if (issueModel.statusSequence && issueModel.statusSequence.length > 0) {
                issueModel.statusInicial = issueModel.statusSequence[0]
            }
            
            // Valores padrão
            issueModel.documentacaoAnexa = "Não"
            issueModel.utilizacaoIA = "Não"
            
            // Limpar Epic Parent
            issueModel.epicParentKey = ""
            issueModel.epicParentSummary = ""
            if (epicSearchForm) {
                epicSearchForm.reset()
            }
            
            // Resetar worklog
            issueModel.registrarWorklog = false
            var now = new Date()
            var dateStr = Qt.formatDateTime(now, "yyyy-MM-dd")
            var timeStr = Qt.formatDateTime(now, "HH:mm:ss")
            issueModel.worklogInicio = dateStr + " " + timeStr
            issueModel.worklogDuracao = 30
            if (worklogForm) {
                worklogForm.reset()
            }
        }
        
        // Resetar componentes
        if (issueFieldsForm) {
            issueFieldsForm.reset()
        }
    }
    
    function validateForm() {
        if (controller) {
            return controller.validate()
        }
        return false
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
    
    function showSuccessDialog(issueKey, issueUrl) {
        var component = Qt.createComponent("../components/dialogs/SuccessDialog.qml")
        if (component.status === Component.Ready) {
            var window = page.parent && page.parent.parent ? page.parent.parent : page
            successDialog = component.createObject(window)
            if (successDialog) {
                successDialog.show(issueKey, issueUrl, false)  // false indica que é criação
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
}
