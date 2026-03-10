/**
 * WorklogValidators.js
 *
 * Validações de worklog (data, hora, duração, retroativo).
 * Escopo: registo de worklog e regras retroativas.
 */
.pragma library

/**
 * Valida dados de worklog.
 *
 * @param {object} worklogData - Objeto com date, time, duration
 * @param {boolean} required - Se true, valida como obrigatório
 * @returns {object} { isValid: boolean, errors: string[] }
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
            var dateRegex = /^\d{4}-\d{2}-\d{2}$/
            if (!dateRegex.test(worklogData.date)) {
                errors.push("Data deve estar no formato YYYY-MM-DD")
            }
        }

        if (!worklogData.time || worklogData.time.trim() === "") {
            errors.push("Hora do worklog é obrigatória")
        } else {
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
 * Valida worklog retroativo (duração, hora de início, criação da issue).
 *
 * @param {number} durationMinutes - Duração em minutos
 * @param {number} maxHours - Horas máximas permitidas
 * @param {string} issueCreatedDate - Data de criação da issue (YYYY-MM-DD) ou null
 * @param {string} calculatedStartDateTime - Data/hora de início calculada (YYYY-MM-DD HH:MM:SS)
 * @returns {object} { valid: boolean, errors: string[] }
 */
function validateRetroactiveWorklog(durationMinutes, maxHours, issueCreatedDate, calculatedStartDateTime) {
    var errors = []

    var maxMinutes = maxHours * 60
    if (durationMinutes > maxMinutes) {
        errors.push("Duração excede o máximo permitido de " + maxHours + " horas")
    }

    if (calculatedStartDateTime) {
        var calculatedDate = new Date(calculatedStartDateTime.replace(" ", "T"))
        var now = new Date()
        if (calculatedDate > now) {
            errors.push("Hora de início calculada não pode ser no futuro")
        }
    }

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
