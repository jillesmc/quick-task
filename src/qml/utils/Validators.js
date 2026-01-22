/**
 * Validators.js
 * 
 * Validações reutilizáveis
 * Segue Single Responsibility Principle - apenas validação
 * 
 * Uso em QML:
 *   .pragma library
 *   import "Validators.js" as Validators
 *   Validators.validateIssueForm(issueModel)
 */

.pragma library

/**
 * Valida formulário de criação de issue
 * 
 * @param {object} issueModel - Modelo da issue com propriedades: summary, tipoAtividade, statusInicial
 * @returns {object} Objeto com isValid (boolean) e errors (array de strings)
 * 
 * @example
 * var result = validateIssueForm(issueModel)
 * if (!result.isValid) {
 *     console.log("Erros:", result.errors)
 * }
 */
function validateIssueForm(issueModel) {
    var errors = []
    
    if (!issueModel) {
        return { isValid: false, errors: ["Modelo de issue não disponível"] }
    }
    
    if (!issueModel.summary || issueModel.summary.trim() === "") {
        errors.push("Summary é obrigatório")
    }
    
    if (!issueModel.tipoAtividade || issueModel.tipoAtividade === "") {
        errors.push("Tipo de atividade é obrigatório")
    }
    
    if (!issueModel.statusInicial || issueModel.statusInicial === "") {
        errors.push("Status inicial é obrigatório")
    }
    
    // Description não é obrigatório
    
    return {
        isValid: errors.length === 0,
        errors: errors
    }
}

/**
 * Valida dados de worklog
 * 
 * @param {object} worklogData - Objeto com propriedades: date, time, duration
 * @param {boolean} required - Se true, valida como obrigatório
 * @returns {object} Objeto com isValid (boolean) e errors (array de strings)
 * 
 * @example
 * var result = validateWorklog({ date: "2024-01-15", time: "14:30:00", duration: 30 })
 * if (!result.isValid) {
 *     console.log("Erros:", result.errors)
 * }
 */
function validateWorklog(worklogData, required) {
    var errors = []
    
    if (!required && (!worklogData || !worklogData.shouldRegister)) {
        return { isValid: true, errors: [] }
    }
    
    if (!worklogData) {
        return { isValid: false, errors: ["Dados de worklog não disponíveis"] }
    }
    
    if (required || worklogData.shouldRegister) {
        if (!worklogData.date || worklogData.date.trim() === "") {
            errors.push("Data do worklog é obrigatória")
        } else {
            // Validar formato YYYY-MM-DD
            var dateRegex = /^\d{4}-\d{2}-\d{2}$/
            if (!dateRegex.test(worklogData.date)) {
                errors.push("Data deve estar no formato YYYY-MM-DD")
            }
        }
        
        if (!worklogData.time || worklogData.time.trim() === "") {
            errors.push("Hora do worklog é obrigatória")
        } else {
            // Validar formato HH:MM:SS ou HH:MM
            var timeRegex = /^\d{2}:\d{2}(:\d{2})?$/
            if (!timeRegex.test(worklogData.time)) {
                errors.push("Hora deve estar no formato HH:MM:SS ou HH:MM")
            }
        }
        
        if (!worklogData.duration || worklogData.duration <= 0) {
            errors.push("Duração do worklog deve ser maior que zero")
        }
    }
    
    return {
        isValid: errors.length === 0,
        errors: errors
    }
}

/**
 * Valida se uma issue key está selecionada
 * 
 * @param {string} issueKey - Chave da issue
 * @returns {object} Objeto com isValid (boolean) e error (string ou null)
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
