/**
 * ImportTaskDialog.qml
 *
 * Diálogo para importar tarefa do Google Tasks como issue no Jira.
 * Summary e description editáveis; sem worklog.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

Controls.Dialog {
    id: root

    parent: Controls.Overlay.overlay
    anchors.centerIn: parent

    title: qsTr("Importar tarefa para Jira")
    modal: true
    closePolicy: Controls.Popup.CloseOnEscape
    standardButtons: Controls.Dialog.Cancel

    property var taskData: null
    property var jiraService: null
    property string errorText: ""
    property bool createButtonEnabled: true

    signal importSuccess(string issueKey)
    signal importError(string message)

    function openWith(task, service) {
        taskData = task || null
        jiraService = service || null
        errorText = ""
        createButtonEnabled = true
        if (taskData) {
            summaryField.text = taskData.title || ""
            descriptionField.text = taskData.notes || ""
        }
        open()
    }

    onOpened: {
        if (taskData) {
            summaryField.text = taskData.title || ""
            descriptionField.text = taskData.notes || ""
        }
    }

    ColumnLayout {
        Layout.preferredWidth: 400
        spacing: Kirigami.Units.mediumSpacing

        Controls.Label {
            text: qsTr("Summary:")
            font.bold: true
            Layout.fillWidth: true
        }
        Controls.TextField {
            id: summaryField
            Layout.fillWidth: true
            placeholderText: qsTr("Título da issue")
        }

        Controls.Label {
            text: qsTr("Description:")
            font.bold: true
            Layout.fillWidth: true
        }
        Controls.TextArea {
            id: descriptionField
            Layout.fillWidth: true
            Layout.preferredHeight: 100
            placeholderText: qsTr("Descrição da issue")
            wrapMode: Controls.TextArea.Wrap
        }

        Controls.Label {
            id: errorLabel
            Layout.fillWidth: true
            visible: root.errorText.length > 0
            text: root.errorText
            color: Kirigami.Theme.negativeTextColor
            wrapMode: Text.WordWrap
        }

        Controls.Button {
            id: createButton
            text: qsTr("Criar no Jira")
            icon.name: "document-import"
            Layout.alignment: Qt.AlignRight
            enabled: root.createButtonEnabled && (summaryField.text || "").trim().length > 0 && root.jiraService
            onClicked: {
                if (!root.jiraService) {
                    root.errorText = qsTr("Serviço Jira não disponível.")
                    return
                }
                var summary = (summaryField.text || "").trim()
                if (!summary) {
                    root.errorText = qsTr("Summary é obrigatório.")
                    return
                }
                var desc = (descriptionField.text || "").trim()
                root.createButtonEnabled = false
                root.errorText = ""
                var ok = root.jiraService.createIssueFromTask(summary, desc)
                if (!ok) {
                    root.createButtonEnabled = true
                    root.errorText = root.jiraService.getErrorMessage
                        ? root.jiraService.getErrorMessage()
                        : qsTr("Erro ao criar issue.")
                }
            }
        }
    }

    Connections {
        target: root.jiraService || null
        function onIssueCreated(issueKey, issueUrl) {
            root.importSuccess(issueKey)
            root.close()
        }
        function onErrorOccurred(message) {
            root.importError(message)
            root.errorText = message || qsTr("Erro ao criar issue.")
            root.createButtonEnabled = true
        }
    }
}
