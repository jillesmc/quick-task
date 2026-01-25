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

/**
 * Valida worklog retroativo
 * 
 * @param {number} durationMinutes - Duração em minutos
 * @param {number} maxHours - Horas máximas permitidas para worklog retroativo
 * @param {string} issueCreatedDate - Data de criação da issue (formato YYYY-MM-DD) ou null
 * @param {string} calculatedStartDateTime - Data/hora de início calculada (formato YYYY-MM-DD HH:MM:SS)
 * @returns {object} Objeto com valid (boolean) e errors (array de strings)
 * 
 * @example
 * var result = validateRetroactiveWorklog(90, 24, "2024-01-15", "2024-01-15 13:00:00")
 * if (!result.valid) {
 *     console.log("Erros:", result.errors)
 * }
 */
function validateRetroactiveWorklog(durationMinutes, maxHours, issueCreatedDate, calculatedStartDateTime) {
    var errors = []
    
    // Validar que duração não excede max_hours
    var maxMinutes = maxHours * 60
    if (durationMinutes > maxMinutes) {
        errors.push("Duração excede o máximo permitido de " + maxHours + " horas")
    }
    
    // Validar que hora de início não é no futuro
    if (calculatedStartDateTime) {
        var calculatedDate = new Date(calculatedStartDateTime.replace(" ", "T"))
        var now = new Date()
        if (calculatedDate > now) {
            errors.push("Hora de início calculada não pode ser no futuro")
        }
    }
    
    // Validar que hora de início não é anterior à criação da issue
    if (issueCreatedDate && calculatedStartDateTime) {
        var issueDate = new Date(issueCreatedDate + "T00:00:00")
        var calculatedDate = new Date(calculatedStartDateTime.replace(" ", "T"))
        if (calculatedDate < issueDate) {
            errors.push("Hora de início não pode ser anterior à data de criação da issue")
        }
    }
    
    return {
        valid: errors.length === 0,
        errors: errors
    }
}
