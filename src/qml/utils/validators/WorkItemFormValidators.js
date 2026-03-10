/**
 * WorkItemFormValidators.js
 *
 * Validações de formulário de work item (abas 7/8: Criar Work Item, Minhas Work Items).
 * Escopo: criação e edição de work item.
 */
.pragma library

/**
 * Valida formulário de criação de work item.
 *
 * @param {object} workItemModel - Modelo do work item (summary, tipoAtividade, statusInicial)
 * @returns {object} { isValid: boolean, errors: string[] }
 */
function validateWorkItemForm(workItemModel) {
    var errors = []

    if (!workItemModel) {
        return { isValid: false, errors: ["Modelo de work item não disponível"] }
    }

    if (!workItemModel.summary || workItemModel.summary.trim() === "") {
        errors.push("Summary é obrigatório")
    } else if (workItemModel.summary.length > 255) {
        errors.push("Summary deve ter no máximo 255 caracteres")
    }

    if (!workItemModel.tipoAtividade || workItemModel.tipoAtividade === "") {
        errors.push("Tipo de atividade é obrigatório")
    }

    if (!workItemModel.statusInicial || workItemModel.statusInicial === "") {
        errors.push("Status inicial é obrigatório")
    }

    return {
        isValid: errors.length === 0,
        errors: errors
    }
}

/**
 * Valida dados do formulário de edição de work item (update).
 *
 * @param {object} workItemModel - Modelo do work item com summary (e demais campos já preenchidos)
 * @returns {object} { isValid: boolean, errors: string[] }
 */
function validateWorkItemUpdate(workItemModel) {
    var errors = []
    if (!workItemModel) {
        return { isValid: false, errors: ["Modelo de work item não disponível"] }
    }
    var s = (workItemModel.summary || "").trim()
    if (s === "") {
        errors.push("Summary é obrigatório")
    } else if (s.length > 255) {
        errors.push("Summary deve ter no máximo 255 caracteres")
    }
    return {
        isValid: errors.length === 0,
        errors: errors
    }
}
