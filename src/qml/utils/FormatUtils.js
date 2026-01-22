/**
 * FormatUtils.js
 * 
 * Utilitários de formatação reutilizáveis
 * Segue Single Responsibility Principle - apenas formatação
 * 
 * Uso em QML:
 *   .pragma library
 *   import "FormatUtils.js" as FormatUtils
 *   FormatUtils.formatDuration(90) // "1h 30m"
 */

.pragma library

/**
 * Formata duração em minutos para string legível
 * @param {number} minutes - Duração em minutos
 * @returns {string} String formatada (ex: "2h 30m", "45m", "1h")
 * 
 * @example
 * formatDuration(90)  // "1h 30m"
 * formatDuration(60)  // "1h"
 * formatDuration(45)  // "45m"
 */
function formatDuration(minutes) {
    if (minutes < 60) {
        return minutes + "m"
    }
    var hours = Math.floor(minutes / 60)
    var remainingMinutes = minutes % 60
    if (remainingMinutes === 0) {
        return hours + "h"
    } else {
        return hours + "h " + remainingMinutes + "m"
    }
}

/**
 * Formata entrada de data para formato YYYY-MM-DD
 * Remove caracteres não numéricos e adiciona hífens automaticamente
 * 
 * @param {string} input - String de entrada
 * @returns {string} String formatada (ex: "2024-01-15")
 * 
 * @example
 * formatDateInput("20240115")  // "2024-01-15"
 * formatDateInput("2024/01/15")  // "2024-01-15"
 */
function formatDateInput(input) {
    var digits = input.replace(/[^0-9]/g, '')
    if (digits.length > 8) {
        digits = digits.substring(0, 8)
    }
    var formatted = ""
    for (var i = 0; i < digits.length; i++) {
        if (i === 4 || i === 6) {
            formatted += "-"
        }
        formatted += digits[i]
    }
    return formatted
}

/**
 * Formata entrada de hora para formato HH:MM:SS
 * Remove caracteres não numéricos e adiciona dois pontos automaticamente
 * 
 * @param {string} input - String de entrada
 * @returns {string} String formatada (ex: "14:30:00")
 * 
 * @example
 * formatTimeInput("143000")  // "14:30:00"
 * formatTimeInput("14:30:00")  // "14:30:00"
 */
function formatTimeInput(input) {
    var digits = input.replace(/[^0-9]/g, '')
    if (digits.length > 6) {
        digits = digits.substring(0, 6)
    }
    var formatted = ""
    for (var i = 0; i < digits.length; i++) {
        if (i === 2 || i === 4) {
            formatted += ":"
        }
        formatted += digits[i]
    }
    return formatted
}

/**
 * Obtém data/hora atual formatada
 * 
 * @param {boolean} dateOnly - Se true, retorna apenas data
 * @param {boolean} timeOnly - Se true, retorna apenas hora
 * @returns {object} Objeto com propriedades date e time
 * 
 * @example
 * getCurrentDateTime()  // { date: "2024-01-15", time: "14:30:00" }
 * getCurrentDateTime(true, false)  // { date: "2024-01-15", time: "" }
 */
function getCurrentDateTime(dateOnly, timeOnly) {
    var now = new Date()
    var dateStr = Qt.formatDateTime(now, "yyyy-MM-dd")
    var timeStr = Qt.formatDateTime(now, "HH:mm:ss")
    
    if (dateOnly) {
        return { date: dateStr, time: "" }
    } else if (timeOnly) {
        return { date: "", time: timeStr }
    } else {
        return { date: dateStr, time: timeStr }
    }
}
