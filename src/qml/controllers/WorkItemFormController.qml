/**
 * WorkItemFormController.qml
 *
 * Controller para lógica de negócio do formulário de criação de work item (aba 7).
 * Independente do IssueFormController (abas 0/1).
 *
 * Propriedades:
 * - jiraService: serviço Jira (obrigatório)
 * - workItemModel: modelo do work item (obrigatório)
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
 * - createIssue(): inicia criação de work item
 */
import QtQuick
import "../utils/Validators.js" as Validators

Item {
    id: root

    property var jiraService: null
    property var workItemModel: null
    property bool enabled: true
    property bool isValid: false

    property bool _createInProgress: false

    signal createRequested()
    signal validationChanged(bool isValid)
    signal createStarted()
    signal createCompleted(string issueKey, string issueUrl)
    signal createFailed(string errorMessage)

    function validate() {
        if (!workItemModel) {
            isValid = false
            validationChanged(false)
            return false
        }

        var result = Validators.validateWorkItemForm(workItemModel)
        isValid = result.isValid
        validationChanged(result.isValid)
        return result.isValid
    }

    function prepareCreateData() {
        if (!workItemModel) {
            return null
        }

        var worklogInicioStr = ""
        if (workItemModel.registrarWorklog && workItemModel.worklogInicio) {
            worklogInicioStr = workItemModel.worklogInicio
        }

        var parentEpicKey = workItemModel.epicParentKey || ""

        return {
            summary: workItemModel.summary || "",
            description: workItemModel.description || "",
            tipoAtividade: workItemModel.tipoAtividade || "",
            statusInicial: workItemModel.statusInicial || "",
            documentacaoAnexa: workItemModel.documentacaoAnexa || "Não",
            utilizacaoIA: workItemModel.utilizacaoIA || "Não",
            valorEntregue: workItemModel.valorEntregue || "",
            plataformasAfetadas: workItemModel.plataformasAfetadas || [],
            registrarWorklog: workItemModel.registrarWorklog || false,
            worklogInicio: worklogInicioStr,
            worklogDuracao: workItemModel.worklogDuracao || 0,
            worklogComment: workItemModel.worklogComment || "",
            parentEpicKey: parentEpicKey,
            pendingAttachments: workItemModel.pendingAttachments || [],
            prioridade: workItemModel.prioridade || "Medium"
        }
    }

    function createIssue() {
        if (!enabled) {
            return
        }

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
            "",
            data.parentEpicKey,
            data.worklogComment,
            data.pendingAttachments || [],
            data.prioridade || "Medium"
        )
    }

    function reset() {
        isValid = false
        validationChanged(false)
    }

    Connections {
        target: root.jiraService

        function onIssueCreated(issueKey, issueUrl) {
            root._createInProgress = false
            root.createCompleted(issueKey, issueUrl)
        }

        function onErrorOccurred(errorMessage) {
            if (!root._createInProgress) return
            root._createInProgress = false
            root.createFailed(errorMessage)
        }
    }

    Connections {
        target: root.workItemModel || null

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
