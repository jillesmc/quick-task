/**
 * MyIssuesController.qml
 * 
 * Controller para lógica de negócio de "Minhas Issues"
 * Segue Single Responsibility Principle - apenas lógica de negócio
 * Segue Dependency Inversion Principle - depende de abstrações (propriedades/signals)
 * 
 * Propriedades:
 * - jiraService: serviço Jira (obrigatório)
 * - myIssuesModel: modelo de issues (obrigatório)
 * - issueModel: modelo de issue para valores padrão (opcional)
 * - enabled: controla se o controller está ativo
 * 
 * Signals:
 * - updateRequested(string issueKey): emitido quando atualização é solicitada
 * - issueSelected(string issueKey, var issueData): emitido quando issue é selecionada
 * - searchRequested(string query): emitido quando busca é solicitada
 * - updateStarted(): emitido quando atualização inicia
 * - updateCompleted(string issueKey): emitido quando atualização completa
 * - updateFailed(string errorMessage): emitido quando atualização falha
 * 
 * Métodos:
 * - searchIssues(string query): busca issues
 * - loadIssueDetails(string issueKey): carrega detalhes de uma issue
 * - updateIssue(string issueKey, object fieldData, object worklogData, string epicKey): atualiza issue
 * - resetFields(): reseta campos para valores padrão
 */
import QtQuick
import "../utils/Validators.js" as Validators

Item {
    id: root
    
    property var jiraService: null
    property var myIssuesModel: null
    property var issueModel: null
    property bool enabled: true
    
    signal updateRequested(string issueKey)
    signal issueSelected(string issueKey, var issueData)
    signal searchRequested(string query)
    signal updateStarted()
    signal updateCompleted(string issueKey)
    signal updateFailed(string errorMessage)
    
    /**
     * Busca issues
     * @param {string} query - Query de busca
     */
    function searchIssues(query) {
        if (!enabled || !myIssuesModel) {
            return
        }
        
        var trimmedQuery = query || ""
        root.searchRequested(trimmedQuery)
        myIssuesModel.refreshIssues(trimmedQuery)
    }
    
    /**
     * Carrega detalhes de uma issue
     * @param {string} issueKey - Chave da issue
     * @returns {object} Objeto com detalhes da issue ou null
     */
    function loadIssueDetails(issueKey) {
        if (!enabled || !issueKey || !jiraService) {
            return null
        }
        
        var details = jiraService.getIssueDetails(issueKey)
        if (!details || !details.key) {
            return null
        }
        
        return {
            key: details.key,
            summary: details.summary || "",
            description: String(details.description || ""),
            tipoAtividade: String(details.tipoAtividade || ""),
            status: String(details.status || ""),
            documentacaoAnexa: String(details.documentacaoAnexa || "Não"),
            utilizacaoIA: String(details.utilizacaoIA || "Não"),
            valorEntregue: String(details.valorEntregue || ""),
            plataformasAfetadas: details.plataformasAfetadas || [],
            parentKey: String(details.parentKey || ""),
            parentSummary: String(details.parentSummary || "")
        }
    }
    
    /**
     * Atualiza issue
     * @param {string} issueKey - Chave da issue
     * @param {object} fieldData - Dados dos campos (description, tipoAtividade, status, etc)
     * @param {object} worklogData - Dados do worklog (shouldRegister, date, time, duration, comment)
     * @param {string} epicKey - Chave do Epic parent
     * @param {string} originalStatus - Status original (para comparar)
     */
    function updateIssue(issueKey, fieldData, worklogData, epicKey, originalStatus) {
        if (!enabled) {
            return
        }
        
        // Validar issue key
        var keyValidation = Validators.validateIssueKey(issueKey)
        if (!keyValidation.isValid) {
            updateFailed(keyValidation.error)
            return
        }
        
        if (!jiraService || !jiraService.isAvailable()) {
            updateFailed(jiraService ? jiraService.getErrorMessage() : "Serviço Jira não disponível")
            return
        }
        
        updateRequested(issueKey)
        updateStarted()
        
        // Preparar data/hora de worklog
        var worklogInicioStr = ""
        if (worklogData && worklogData.shouldRegister && worklogData.date && worklogData.time) {
            worklogInicioStr = worklogData.date + " " + worklogData.time
        }
        
        // Determinar se deve atualizar o status (só se for diferente do original)
        var statusToUpdate = ""
        if (fieldData && fieldData.status && fieldData.status !== originalStatus) {
            statusToUpdate = fieldData.status
        }
        
        // Chamar serviço (ordem dos parâmetros conforme jira_service.py)
        var result = jiraService.updateIssue(
            issueKey,
            fieldData ? fieldData.summary || "" : "", // summary atualizado
            fieldData ? fieldData.description || "" : "",
            fieldData ? fieldData.tipoAtividade || "" : "",
            statusToUpdate,
            fieldData ? fieldData.documentacaoAnexa || "Não" : "Não",
            fieldData ? fieldData.utilizacaoIA || "Não" : "Não",
            fieldData ? fieldData.valorEntregue || "" : "",
            fieldData ? (fieldData.plataformasAfetadas || []) : [],
            epicKey || "",
            worklogData ? worklogData.shouldRegister || false : false,
            worklogInicioStr,
            worklogData ? Math.round(worklogData.duration || 0) : 0,
            "", // timezone vazio - será usado o do config.json automaticamente
            worklogData ? worklogData.comment || "" : ""
        )
        
        if (!result) {
            // Se retornar false, pode ser que já tenha emitido erro
            // O signal onErrorOccurred será tratado pelos Connections
        }
    }
    
    /**
     * Reseta campos para valores padrão
     * @returns {object} Objeto com valores padrão
     */
    function getDefaultFieldValues() {
        var defaults = {
            description: "",
            tipoAtividade: "",
            status: "",
            documentacaoAnexa: "Não",
            utilizacaoIA: "Não"
        }
        
        if (issueModel) {
            if (issueModel.tipoAtividadeValues && issueModel.tipoAtividadeValues.length > 0) {
                defaults.tipoAtividade = issueModel.tipoAtividadeValues[0]
            }
            if (issueModel.statusSequence && issueModel.statusSequence.length > 0) {
                defaults.status = issueModel.statusSequence[0]
            }
        }
        
        return defaults
    }
    
    /**
     * Reseta campos para valores padrão (alias para getDefaultFieldValues)
     */
    function resetFields() {
        return getDefaultFieldValues()
    }
    
    // Conectar signals do jiraService
    Connections {
        target: root.jiraService
        
        function onIssueUpdated(issueKey) {
            root.updateCompleted(issueKey)
        }
        
        function onErrorOccurred(errorMessage) {
            root.updateFailed(errorMessage)
        }
    }
    
    // Conectar signals do myIssuesModel
    Connections {
        target: root.myIssuesModel
        
        function onErrorOccurred(errorMessage) {
            root.updateFailed(errorMessage)
        }
    }
}
