/**
 * MyWorkItemsController.qml
 *
 * Controller para lógica de negócio de "Minhas Work Items" (aba 8).
 * Independente do MyIssuesController (abas 0/1).
 *
 * Propriedades:
 * - jiraService: serviço Jira (obrigatório)
 * - myWorkItemsModel: modelo da lista de work items (obrigatório)
 * - workItemModel: modelo do work item em edição / valores padrão (opcional)
 * - enabled: controla se o controller está ativo
 *
 * Signals:
 * - updateRequested(string issueKey): emitido quando atualização é solicitada
 * - issueSelected(string issueKey, var issueData): emitido quando work item é selecionado
 * - searchRequested(string query): emitido quando busca é solicitada
 * - updateStarted(): emitido quando atualização inicia
 * - updateCompleted(string issueKey): emitido quando atualização completa
 * - updateFailed(string errorMessage): emitido quando atualização falha
 *
 * Métodos:
 * - searchIssues(string query): busca work items
 * - loadIssueDetails(string issueKey): carrega detalhes de um work item
 * - updateIssue(string issueKey, object fieldData, object worklogData, string epicKey, string originalStatus): atualiza work item
 * - getDefaultFieldValues(): valores padrão
 * - resetFields(): reseta campos
 */
import QtQuick
import "../utils/Validators.js" as Validators

Item {
    id: root

    property var jiraService: null
    property var myWorkItemsModel: null
    property var workItemModel: null
    property bool enabled: true

    signal updateRequested(string issueKey)
    signal issueSelected(string issueKey, var issueData)
    signal searchRequested(string query)
    signal updateStarted()
    signal updateCompleted(string issueKey)
    signal updateFailed(string errorMessage)

    function searchIssues(query) {
        if (!enabled || !myWorkItemsModel) {
            return
        }

        var trimmedQuery = query || ""
        root.searchRequested(trimmedQuery)
        myWorkItemsModel.refreshIssues(trimmedQuery)
    }

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
        jiraService.transitionToInProgress(
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

    function getDefaultFieldValues() {
        var defaults = {
            description: "",
            tipoAtividade: "",
            status: "",
            documentacaoAnexa: "Não",
            utilizacaoIA: "Não"
        }

        if (workItemModel) {
            if (workItemModel.tipoAtividadeValues && workItemModel.tipoAtividadeValues.length > 0) {
                defaults.tipoAtividade = workItemModel.tipoAtividadeValues[0]
            }
            if (workItemModel.statusSequence && workItemModel.statusSequence.length > 0) {
                defaults.status = workItemModel.statusSequence[0]
            }
        }

        return defaults
    }

    function resetFields() {
        return getDefaultFieldValues()
    }

    Connections {
        target: root.jiraService

        function onIssueUpdated(issueKey) {
            root.updateCompleted(issueKey)
        }

        function onErrorOccurred(errorMessage) {
            if (typeof console !== "undefined" && console.log) {
                console.log("[MyWorkItemsController] jiraService.onErrorOccurred -> emit updateFailed");
            }
            root.updateFailed(errorMessage);
        }
    }

    Connections {
        target: root.myWorkItemsModel || null

        function onErrorOccurred(errorMessage) {
            root.updateFailed(errorMessage)
        }
    }
}
