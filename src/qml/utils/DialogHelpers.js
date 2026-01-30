/**
 * DialogHelpers.js
 *
 * Reusable helpers for showing progress, success, and error dialogs.
 * Use from QML: import "../utils/DialogHelpers.js" as DialogHelpers
 *
 * Paths for createComponent are relative to the calling QML file.
 * Note: .pragma library is not used so Qt and Component are available from the importer's context.
 */

/**
 * Show progress dialog. Caller should store return value and pass to hideProgress.
 * @param {Item} parent - Parent for the dialog (e.g. page or window)
 * @param {string} componentPath - Path to ProgressDialog.qml relative to caller QML
 * @returns {Dialog|null} Dialog instance with open(), updateProgress(percent, message)
 */
function showProgress(parent, componentPath) {
    var component = Qt.createComponent(componentPath);
    if (component.status !== Component.Ready) {
        console.error("DialogHelpers.showProgress: component not ready", component.errorString());
        return null;
    }
    var window = parent && parent.parent ? parent.parent : parent;
    var dialog = component.createObject(window);
    if (dialog) {
        dialog.open();
    }
    return dialog;
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
 */
function showSuccess(parent, componentPath, issueKey, issueUrl, isUpdate) {
    var component = Qt.createComponent(componentPath);
    if (component.status !== Component.Ready) {
        console.error("DialogHelpers.showSuccess:", component.errorString());
        return;
    }
    var window = parent && parent.parent ? parent.parent : parent;
    var dialog = component.createObject(window);
    if (dialog) {
        dialog.show(issueKey, issueUrl || "", isUpdate);
    }
}

/**
 * Show error dialog (fire-and-forget).
 * @param {Item} parent - Parent for the dialog
 * @param {string} componentPath - Path to ErrorDialog.qml
 * @param {string} message - Error message
 */
function showError(parent, componentPath, message) {
    var component = Qt.createComponent(componentPath);
    if (component.status !== Component.Ready) {
        console.error("DialogHelpers.showError:", message, component.errorString());
        return;
    }
    var window = parent && parent.parent ? parent.parent : parent;
    var dialog = component.createObject(window);
    if (dialog) {
        dialog.show(message);
    }
}
