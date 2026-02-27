/**
 * Validators.js
 *
 * Fachada de validações. Reexporta funções dos módulos especializados por escopo:
 * - validators/IssueFormValidators.js   (abas 0/1: issue)
 * - validators/WorkItemFormValidators.js (abas 7/8: work item)
 * - validators/WorklogValidators.js      (worklog)
 *
 * Uso em QML (inalterado):
 *   import "Validators.js" as Validators
 *   Validators.validateIssueForm(issueModel)
 *   Validators.validateWorkItemForm(workItemModel)
 *   Validators.validateWorklog(worklogData, required)
 */
.pragma library

.import "validators/IssueFormValidators.js" as IssueForm
.import "validators/WorkItemFormValidators.js" as WorkItemForm
.import "validators/WorklogValidators.js" as Worklog

function validateIssueForm(issueModel) {
    return IssueForm.validateIssueForm(issueModel)
}

function validateIssueUpdate(issueModel) {
    return IssueForm.validateIssueUpdate(issueModel)
}

function validateIssueKey(issueKey) {
    return IssueForm.validateIssueKey(issueKey)
}

function validateWorkItemForm(workItemModel) {
    return WorkItemForm.validateWorkItemForm(workItemModel)
}

function validateWorkItemUpdate(workItemModel) {
    return WorkItemForm.validateWorkItemUpdate(workItemModel)
}

function validateWorklog(worklogData, required) {
    return Worklog.validateWorklog(worklogData, required)
}

function validateRetroactiveWorklog(durationMinutes, maxHours, issueCreatedDate, calculatedStartDateTime) {
    return Worklog.validateRetroactiveWorklog(durationMinutes, maxHours, issueCreatedDate, calculatedStartDateTime)
}
