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
     * Chama o serviço updateIssue (uma fase). Usado pela página após decisão de fluxo ou quando não há mudança de status.
     */
    function _callUpdateIssue(issueKey, fieldData, worklogData, epicKey, originalStatus) {
        var worklogInicioStr = ""
        if (worklogData && worklogData.shouldRegister && worklogData.date && worklogData.time) {
            worklogInicioStr = worklogData.date + " " + worklogData.time
        }
        var statusToUpdate = ""
        if (fieldData && fieldData.status && fieldData.status !== originalStatus) {
            statusToUpdate = fieldData.status
        }
        jiraService.updateIssue(
            issueKey,
            fieldData ? fieldData.summary || "" : "",
            fieldData ? fieldData.description || "" : "",
            fieldData ? fieldData.tipoAtividade || "" : "",
            statusToUpdate,
            fieldData ? fieldData.prioridade || "" : "",
            fieldData ? fieldData.documentacaoAnexa || "Não" : "Não",
            fieldData ? fieldData.utilizacaoIA || "Não" : "Não",
            fieldData ? fieldData.valorEntregue || "" : "",
            fieldData ? (fieldData.plataformasAfetadas || []) : [],
            epicKey || "",
            worklogData ? worklogData.shouldRegister || false : false,
            worklogInicioStr,
            worklogData ? Math.round(worklogData.duration || 0) : 0,
            "",
            worklogData ? worklogData.comment || "" : ""
        )
    }

    /**
     * Inicia transição em duas fases: emite updateStarted e chama transitionToInDevelopment.
     * A página deve tratar reachedInDevelopment e depois transitionFromInDevelopmentToTarget.
     */
    function startTwoPhaseUpdate(issueKey, fieldData, worklogData, epicKey, originalStatus) {
        if (!enabled || !jiraService || !jiraService.isAvailable()) {
            if (jiraService) updateFailed(jiraService.getErrorMessage())
            return
        }
        var worklogInicioStr = ""
        if (worklogData && worklogData.shouldRegister && worklogData.date && worklogData.time) {
            worklogInicioStr = worklogData.date + " " + worklogData.time
        }
        updateRequested(issueKey)
        updateStarted()
        jiraService.transitionToInDevelopment(
            issueKey,
            fieldData ? fieldData.summary || "" : "",
            fieldData ? fieldData.description || "" : "",
            fieldData ? fieldData.tipoAtividade || "" : "",
            fieldData ? fieldData.status || "" : "",
            fieldData ? fieldData.prioridade || "" : "",
            fieldData ? fieldData.documentacaoAnexa || "Não" : "Não",
            fieldData ? fieldData.utilizacaoIA || "Não" : "Não",
            fieldData ? fieldData.valorEntregue || "" : "",
            fieldData ? (fieldData.plataformasAfetadas || []) : [],
            epicKey || "",
            worklogData ? worklogData.shouldRegister || false : false,
            worklogInicioStr,
            worklogData ? Math.round(worklogData.duration || 0) : 0,
            "",
            worklogData ? worklogData.comment || "" : ""
        )
    }

    /**
     * Atualiza issue (pode ser chamado diretamente quando não há mudança de status ou após diálogo/sync em fluxo de uma fase).
     * @param {string} issueKey - Chave da issue
     * @param {object} fieldData - Dados dos campos
     * @param {object} worklogData - Dados do worklog
     * @param {string} epicKey - Chave do Epic parent
     * @param {string} originalStatus - Status original (para comparar)
     */
    function updateIssue(issueKey, fieldData, worklogData, epicKey, originalStatus) {
        if (!enabled) {
            return
        }
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
        _callUpdateIssue(issueKey, fieldData, worklogData, epicKey, originalStatus)
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
            if (typeof console !== "undefined" && console.log) {
                console.log("[MyIssuesController] jiraService.onErrorOccurred -> emit updateFailed");
            }
            root.updateFailed(errorMessage);
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
