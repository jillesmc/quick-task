/**
 * IssueFormValidators.js
 *
 * Validações de formulário de issue (abas 0/1: Criar Issue, Minhas Issues).
 * Escopo: criação e edição de issue.
 */
.pragma library

/**
 * Valida formulário de criação de issue.
 *
 * @param {object} issueModel - Modelo da issue (summary, tipoAtividade, statusInicial)
 * @returns {object} { isValid: boolean, errors: string[] }
 */
function validateIssueForm(issueModel) {
    var errors = []

    if (!issueModel) {
        return { isValid: false, errors: ["Modelo de issue não disponível"] }
    }

    if (!issueModel.summary || issueModel.summary.trim() === "") {
        errors.push("Summary é obrigatório")
    } else if (issueModel.summary.length > 255) {
        errors.push("Summary deve ter no máximo 255 caracteres")
    }

    if (!issueModel.tipoAtividade || issueModel.tipoAtividade === "") {
        errors.push("Tipo de atividade é obrigatório")
    }

    if (!issueModel.statusInicial || issueModel.statusInicial === "") {
        errors.push("Status inicial é obrigatório")
    }

    return {
        isValid: errors.length === 0,
        errors: errors
    }
}

/**
 * Valida dados do formulário de edição de issue (update).
 *
 * @param {object} issueModel - Modelo com summary (e demais campos já preenchidos)
 * @returns {object} { isValid: boolean, errors: string[] }
 */
function validateIssueUpdate(issueModel) {
    var errors = []
    if (!issueModel) {
        return { isValid: false, errors: ["Modelo de issue não disponível"] }
    }
    var s = (issueModel.summary || "").trim()
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

/**
 * Valida se uma issue key está selecionada (comum a issue e work item).
 *
 * @param {string} issueKey - Chave da issue
 * @returns {object} { isValid: boolean, error: string|null }
 */
function validateIssueKey(issueKey) {
    if (!issueKey || issueKey.trim() === "") {
        return {
            isValid: false,
            error: "Nenhuma issue selecionada"
        }
    }
    return {
        isValid: true,
        error: null
    }
}
