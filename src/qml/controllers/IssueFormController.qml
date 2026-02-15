/**
 * IssueFormController.qml
 * 
 * Controller para lógica de negócio do formulário de criação de issue
 * Segue Single Responsibility Principle - apenas lógica de negócio
 * Segue Dependency Inversion Principle - depende de abstrações (propriedades/signals)
 * 
 * Propriedades:
 * - jiraService: serviço Jira (obrigatório)
 * - issueModel: modelo da issue (obrigatório)
 * - enabled: controla se o controller está ativo
 * 
 * Signals:
 * - createRequested(): emitido quando criação é solicitada
 * - validationChanged(bool isValid): emitido quando validação muda
 * - createStarted(): emitido quando criação inicia
 * - createCompleted(string issueKey, string issueUrl): emitido quando criação completa
 * - createFailed(string errorMessage): emitido quando criação falha
 * 
 * Métodos:
 * - validate(): valida formulário
 * - prepareCreateData(): prepara dados para criação
 * - reset(): reseta estado do controller
 * - createIssue(): inicia criação de issue
 */
import QtQuick
import "../utils/Validators.js" as Validators

Item {
    id: root
    
    property var jiraService: null
    property var issueModel: null
    property bool enabled: true
    property bool isValid: false

    // Só reportar createFailed para erros que ocorrem durante a nossa própria operação de criação
    property bool _createInProgress: false

    signal createRequested()
    signal validationChanged(bool isValid)
    signal createStarted()
    signal createCompleted(string issueKey, string issueUrl)
    signal createFailed(string errorMessage)
    
    /**
     * Valida formulário
     * @returns {boolean} true se válido
     */
    function validate() {
        if (!issueModel) {
            isValid = false
            validationChanged(false)
            return false
        }
        
        var result = Validators.validateIssueForm(issueModel)
        isValid = result.isValid
        validationChanged(result.isValid)
        return result.isValid
    }
    
    /**
     * Prepara dados para criação de issue
     * @returns {object} Objeto com dados preparados
     */
    function prepareCreateData() {
        if (!issueModel) {
            return null
        }
        
        // Preparar data/hora de worklog
        var worklogInicioStr = ""
        if (issueModel.registrarWorklog && issueModel.worklogInicio) {
            worklogInicioStr = issueModel.worklogInicio
        }
        
        // Obter Epic parent key se selecionada
        var parentEpicKey = issueModel.epicParentKey || ""
        
        return {
            summary: issueModel.summary || "",
            description: issueModel.description || "",
            tipoAtividade: issueModel.tipoAtividade || "",
            statusInicial: issueModel.statusInicial || "",
            documentacaoAnexa: issueModel.documentacaoAnexa || "Não",
            utilizacaoIA: issueModel.utilizacaoIA || "Não",
            valorEntregue: issueModel.valorEntregue || "",
            plataformasAfetadas: issueModel.plataformasAfetadas || [],
            registrarWorklog: issueModel.registrarWorklog || false,
            worklogInicio: worklogInicioStr,
            worklogDuracao: issueModel.worklogDuracao || 0,
            worklogComment: issueModel.worklogComment || "",
            parentEpicKey: parentEpicKey,
            pendingAttachments: issueModel.pendingAttachments || [],
            prioridade: issueModel.prioridade || "Medium"
        }
    }
    
    /**
     * Inicia criação de issue
     */
    function createIssue() {
        if (!enabled) {
            return
        }
        
        // Validar antes de criar
        if (!validate()) {
            createFailed("Por favor, preencha todos os campos obrigatórios")
            return
        }
        
        if (!jiraService || !jiraService.isAvailable()) {
            createFailed(jiraService ? jiraService.getErrorMessage() : "Serviço Jira não disponível")
            return
        }
        
        createRequested()
        createStarted()
        _createInProgress = true

        var data = prepareCreateData()
        if (!data) {
            _createInProgress = false
            createFailed("Erro ao preparar dados para criação")
            return
        }
        
        // Chamar serviço
        jiraService.createIssue(
            data.summary,
            data.description,
            data.tipoAtividade,
            data.statusInicial,
            data.documentacaoAnexa,
            data.utilizacaoIA,
            data.valorEntregue,
            data.plataformasAfetadas,
            data.registrarWorklog,
            data.worklogInicio,
            data.worklogDuracao,
            "", // timezone vazio - será usado o do config.json automaticamente
            data.parentEpicKey,
            data.worklogComment,
            data.pendingAttachments || [],
            data.prioridade || "Medium"
        )
    }
    
    /**
     * Reseta estado do controller
     */
    function reset() {
        isValid = false
        validationChanged(false)
    }
    
    // Conectar signals do jiraService
    Connections {
        target: root.jiraService

        function onIssueCreated(issueKey, issueUrl) {
            root._createInProgress = false
            root.createCompleted(issueKey, issueUrl)
        }

        function onErrorOccurred(errorMessage) {
            // Só reportar como createFailed se o erro ocorreu durante a nossa criação de issue
            if (!root._createInProgress) return
            root._createInProgress = false
            root.createFailed(errorMessage)
        }
    }
    
    // Validar quando issueModel muda
    Connections {
        target: root.issueModel
        
        function onSummaryChanged() {
            if (root.enabled) {
                root.validate()
            }
        }
        
        function onTipoAtividadeChanged() {
            if (root.enabled) {
                root.validate()
            }
        }
        
        function onStatusInicialChanged() {
            if (root.enabled) {
                root.validate()
            }
        }
    }
    
    Component.onCompleted: {
        if (root.enabled) {
            root.validate()
        }
    }
}
