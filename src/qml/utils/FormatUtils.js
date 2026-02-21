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

/**
 * Calcula hora de início retroativa baseada na duração
 * @param {number} durationMinutes - Duração em minutos
 * @returns {object} Objeto com date e time calculados
 * 
 * @example
 * calculateRetroactiveStartTime(90)  // { date: "2024-01-15", time: "13:00:00" } (se agora é 14:30)
 */
function calculateRetroactiveStartTime(durationMinutes) {
    var now = new Date()
    var startTime = new Date(now.getTime() - (durationMinutes * 60 * 1000))
    return {
        date: Qt.formatDateTime(startTime, "yyyy-MM-dd"),
        time: Qt.formatDateTime(startTime, "HH:mm:ss")
    }
}

/**
 * Formata tamanho de arquivo em bytes para string legível
 * @param {number} bytes - Tamanho em bytes
 * @returns {string} String formatada (ex: "1.2 MB", "456 KB")
 */
function formatFileSize(bytes) {
    if (bytes === undefined || bytes === null || bytes < 0) return ""
    if (bytes < 1024) return bytes + " B"
    if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + " KB"
    if (bytes < 1024 * 1024 * 1024) return (bytes / (1024 * 1024)).toFixed(1) + " MB"
    return (bytes / (1024 * 1024 * 1024)).toFixed(1) + " GB"
}

/**
 * Extrai da descrição os placeholders de imagens pendentes (create flow).
 * Procura padrões ![filename](pending:id) ou [filename](pending:id).
 *
 * @param {string} descriptionText - Texto da descrição em markdown
 * @returns {Array} Lista de { placeholderId, filename } (filename pode ser vazio)
 */
function getPendingPlaceholdersFromDescription(descriptionText) {
    if (!descriptionText || typeof descriptionText !== "string") return []
    var result = []
    var re = /!?\[([^\]]*)\]\(\s*pending:\s*([a-zA-Z0-9_]+)\s*\)/g
    var m
    while ((m = re.exec(descriptionText)) !== null) {
        result.push({ placeholderId: m[2], filename: (m[1] || "").trim() || ("pending:" + m[2]) })
    }
    return result
}

/**
 * Remove da descrição o trecho da imagem pendente (create flow).
 * Remove a linha que contém ![...](pending:placeholderId) e, se existir,
 * a linha seguinte que contém apenas {: width="..." }.
 *
 * @param {string} descriptionText - Texto da descrição em markdown
 * @param {string} placeholderId - ID do placeholder (ex.: do pendingAttachments)
 * @returns {string} Novo texto sem o trecho da imagem e do attr de largura
 */
function removePendingAttachmentFromDescription(descriptionText, placeholderId) {
    if (!descriptionText || typeof descriptionText !== "string") return descriptionText || ""
    if (!placeholderId && placeholderId !== 0) return descriptionText
    var id = String(placeholderId)
    var lines = descriptionText.split("\n")
    var result = []
    var i = 0
    while (i < lines.length) {
        if (lines[i].indexOf("pending:" + id) >= 0) {
            i += 1
            if (i < lines.length && /^\s*\{:\s*width\s*=/.test(lines[i])) i += 1
            continue
        }
        result.push(lines[i])
        i += 1
    }
    return result.join("\n")
}

/**
 * Remove da descrição o trecho da imagem/ligação do anexo (edit flow).
 * Remove a linha que contém .../attachment/content/{attachmentId}... e,
 * se existir, a linha seguinte que contém apenas {: width="..." }.
 *
 * @param {string} descriptionText - Texto da descrição em markdown
 * @param {string} attachmentId - ID do anexo no Jira (ex.: "1982426")
 * @returns {string} Novo texto sem o trecho do anexo e do attr de largura
 */
function removeAttachmentFromDescription(descriptionText, attachmentId) {
    if (!descriptionText || typeof descriptionText !== "string") return descriptionText || ""
    if (!attachmentId && attachmentId !== 0) return descriptionText
    var id = String(attachmentId).replace(/[^0-9]/g, "")
    if (!id) return descriptionText
    var pattern = "/attachment/content/" + id
    var lines = descriptionText.split("\n")
    var result = []
    var i = 0
    while (i < lines.length) {
        if (lines[i].indexOf(pattern) >= 0) {
            i += 1
            if (i < lines.length && /^\s*\{:\s*width\s*=/.test(lines[i])) i += 1
            continue
        }
        result.push(lines[i])
        i += 1
    }
    return result.join("\n")
}
