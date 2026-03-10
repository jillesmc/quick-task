/**
 * DialogHelpers.js
 *
 * Helpers for showing progress, success, and error dialogs (cria instâncias por chamada).
 * Use from QML: import "../utils/DialogHelpers.js" as DialogHelpers
 *
 * MyIssuesPage e IssueFormPage usam ProcessDialog (um diálogo por fluxo com estados)
 * para update/create; estes helpers continuam em uso para busca de issues e outros casos.
 *
 * Paths for createComponent are relative to the calling QML file.
 */

// Contador global de chamadas a showError (para diagnóstico de múltiplos ErrorDialogs)
var _showErrorCallCount = 0;
// Deduplicação: última mensagem e timestamp para ignorar chamadas duplicadas no mesmo intervalo
var _showErrorLastMessage = "";
var _showErrorLastTime = 0;
var _showErrorDedupIntervalMs = 2000;

/**
 * Show progress dialog. Caller should store return value and pass to hideProgress.
 * If the component loads asynchronously, onReady(dialog) is called when the dialog is created and opened.
 * @param {Item} parent - Parent for the dialog (e.g. page or window)
 * @param {string} componentPath - Path to ProgressDialog.qml relative to caller QML
 * @param {function} onReady - Optional callback(dialog) called when dialog is ready (use when return is null to set page.progressDialog)
 * @returns {Dialog|null} Dialog instance if created synchronously, else null (dialog will be passed to onReady when ready)
 */
function showProgress(parent, componentPath, onReady) {
    var component = Qt.createComponent(componentPath);
    var window = parent && parent.parent ? parent.parent : parent;

    function createAndOpen() {
        if (component.status !== Component.Ready) return null;
        var dialog = component.createObject(window);
        if (dialog) dialog.open();
        return dialog;
    }

    if (component.status === Component.Ready) {
        var d = createAndOpen();
        if (d && typeof onReady === "function") onReady(d);
        return d;
    }
    if (component.status === Component.Error) {
        console.error("DialogHelpers.showProgress: component error", component.errorString());
        return null;
    }
    component.statusChanged.connect(function () {
        if (component.status === Component.Ready) {
            var d = createAndOpen();
            if (d && typeof onReady === "function") onReady(d);
        } else if (component.status === Component.Error) {
            console.error("DialogHelpers.showProgress: component error (async)", component.errorString());
        }
    });
    return null;
}

/**
 * Hide and destroy progress dialog. Caller should set its reference to null.
 * @param {Dialog} dialog - Instance returned by showProgress
 */
function hideProgress(dialog) {
    if (dialog) {
        dialog.close();
        dialog.destroy();
    }
}

/**
 * Show success dialog (fire-and-forget).
 * @param {Item} parent - Parent for the dialog
 * @param {string} componentPath - Path to SuccessDialog.qml
 * @param {string} issueKey - Issue key to display
 * @param {string} issueUrl - Issue URL (can be "")
 * @param {boolean} isUpdate - true for update, false for create
 * @param {object} timerService - Optional timer service for "Iniciar Timer" button
 * @param {object} timerModel - Optional timer model for "Iniciar Timer" button
 * @param {object} jiraService - Optional Jira service (para transição automática para IN PROGRESS ao iniciar timer)
 * @param {object} applicationWindow - Optional root window (para flag _jiraErrorShownInCreateFlow, evita diálogos duplicados)
 * @param {array} workflowStatusSequence - Optional workflow status name list (jira_metadata) for transitionToInProgressIfNeeded; use from CreateWorkItemPage
 */
function showSuccess(parent, componentPath, issueKey, issueUrl, isUpdate, timerService, timerModel, jiraService, applicationWindow, workflowStatusSequence) {
    var component = Qt.createComponent(componentPath);
    var window = parent && parent.parent ? parent.parent : parent;
    function createAndShow() {
        if (component.status !== Component.Ready) return;
        var dialog = component.createObject(window);
        if (dialog) {
            if (timerService !== undefined) dialog.timerService = timerService;
            if (timerModel !== undefined) dialog.timerModel = timerModel;
            if (jiraService !== undefined) dialog.jiraService = jiraService;
            if (applicationWindow !== undefined) dialog.applicationWindow = applicationWindow;
            if (workflowStatusSequence !== undefined) dialog.workflowStatusSequence = workflowStatusSequence;
            dialog.show(issueKey, issueUrl || "", isUpdate);
        }
    }
    if (component.status === Component.Ready) {
        createAndShow();
        return;
    }
    if (component.status === Component.Error) {
        console.error("DialogHelpers.showSuccess:", component.errorString());
        return;
    }
    component.statusChanged.connect(function () {
        if (component.status === Component.Ready) createAndShow();
        else if (component.status === Component.Error) console.error("DialogHelpers.showSuccess (async):", component.errorString());
    });
}

/**
 * Show error dialog (fire-and-forget).
 * @param {Item} parent - Parent for the dialog
 * @param {string} componentPath - Path to ErrorDialog.qml
 * @param {string} message - Error message
 * @param {string} callerId - Optional identifier of the call site (e.g. "MyIssuesPage.myIssuesModel") for diagnostics
 */
function showError(parent, componentPath, message, callerId) {
    _showErrorCallCount += 1;
    var now = (typeof Date !== "undefined" && Date.now) ? Date.now() : 0;
    if (message && _showErrorLastMessage === message && (now - _showErrorLastTime) < _showErrorDedupIntervalMs) {
        return;
    }
    _showErrorLastMessage = message || "";
    _showErrorLastTime = now;

    var component = Qt.createComponent(componentPath);
    var window = parent && parent.parent ? parent.parent : parent;
    function createAndShow() {
        if (component.status !== Component.Ready) return;
        var dialog = component.createObject(window);
        if (dialog) dialog.show(message);
    }
    if (component.status === Component.Ready) {
        createAndShow();
        return;
    }
    if (component.status === Component.Error) {
        console.error("DialogHelpers.showError:", message, component.errorString());
        return;
    }
    component.statusChanged.connect(function () {
        if (component.status === Component.Ready) createAndShow();
        else if (component.status === Component.Error) console.error("DialogHelpers.showError (async):", component.errorString());
    });
}
