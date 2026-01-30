/**
 * PendingWorklogsLogic.js
 *
 * Helpers for PendingWorklogsPage: applyFilters and loadSummaries.
 * Use from QML: import "../utils/PendingWorklogsLogic.js" as PendingWorklogsLogic
 */

.pragma library

/**
 * Filter pending worklogs by issue key and date range.
 * @param {Array} pendingWorklogs - Full list of pending worklogs
 * @param {string} filterIssueKey - Issue key filter (substring match, case-insensitive)
 * @param {string} filterDateFrom - Date from (YYYY-MM-DD)
 * @param {string} filterDateTo - Date to (YYYY-MM-DD)
 * @returns {Array} Filtered array of worklogs
 */
function applyFilters(pendingWorklogs, filterIssueKey, filterDateFrom, filterDateTo) {
    var filtered = [];
    for (var i = 0; i < pendingWorklogs.length; i++) {
        var worklog = pendingWorklogs[i];
        var matches = true;

        if (filterIssueKey && filterIssueKey.trim() !== "") {
            var issueKey = worklog.issue_key || "";
            if (issueKey.toLowerCase().indexOf(filterIssueKey.toLowerCase()) < 0) {
                matches = false;
            }
        }

        if (matches && (filterDateFrom || filterDateTo)) {
            if (worklog.start_time) {
                var worklogDate = new Date(worklog.start_time);
                var dateFrom = filterDateFrom ? new Date(filterDateFrom) : null;
                var dateTo = filterDateTo ? new Date(filterDateTo) : null;

                if (dateFrom && worklogDate < dateFrom) {
                    matches = false;
                }
                if (dateTo && worklogDate > dateTo) {
                    matches = false;
                }
            } else {
                matches = false;
            }
        }

        if (matches) {
            filtered.push(worklog);
        }
    }
    return filtered;
}

/**
 * Load issue summaries for the given issue keys (synchronous).
 * @param {Object} jiraService - Jira service with getIssueDetails(key)
 * @param {Array} issueKeys - List of issue keys
 * @returns {Object} Map of issueKey -> summary
 */
function loadSummaries(jiraService, issueKeys) {
    var summaries = {};
    if (!jiraService) {
        return summaries;
    }
    for (var j = 0; j < issueKeys.length; j++) {
        var issueKey = issueKeys[j];
        try {
            var details = jiraService.getIssueDetails(issueKey);
            if (details && details.summary) {
                summaries[issueKey] = details.summary;
            }
        } catch (e) {
            console.error("PendingWorklogsLogic.loadSummaries: Erro ao buscar summary para", issueKey, ":", e);
        }
    }
    return summaries;
}
