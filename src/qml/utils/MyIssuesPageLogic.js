/**
 * MyIssuesPageLogic.js
 *
 * Logic helpers for MyIssuesPage: apply issue details to the detail pane.
 * Use from QML: import "../utils/MyIssuesPageLogic.js" as MyIssuesPageLogic
 */

.pragma library

/**
 * Apply loaded issue details to the detail pane (summary, description, model, epic).
 * The pane's setDetails() encapsulates the full logic including epic parent rules.
 * @param {object} details - Issue details from Jira (key, summary, description, status, parentKey, etc.)
 * @param {MyIssuesDetailPane} detailPane - The detail pane component with setDetails(details)
 */
function applyIssueDetailsToForm(details, detailPane) {
    if (!details || !details.key || !detailPane) {
        return;
    }
    detailPane.setDetails(details);
}
