/**
 * ImportCalendarEventDialog.qml
 *
 * Diálogo para importar evento do Google Calendar como issue no Jira.
 * Summary e description editáveis; worklog carregado automaticamente (duração do evento).
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

Controls.Dialog {
    id: root

    parent: Controls.Overlay.overlay
    anchors.centerIn: parent

    title: qsTr("Importar evento para Jira")
    modal: true
    closePolicy: Controls.Popup.CloseOnEscape
    standardButtons: Controls.Dialog.Cancel

    property var eventData: null
    property var jiraService: null
    property string errorText: ""
    property bool createButtonEnabled: true

    signal importSuccess(string issueKey)
    signal importError(string message)

    /** Formata start do evento (ISO) para "YYYY-MM-DD HH:MM:SS" esperado pelo Jira. */
    function formatWorklogStart(isoStart) {
        if (!isoStart || typeof isoStart !== "string") return ""
        var s = isoStart.trim()
        if (s.indexOf("T") >= 0) {
            var parts = s.split("T")
            var datePart = parts[0] || ""
            var timePart = (parts[1] || "00:00:00").replace(/[+-]\d{2}:\d{2}$/, "").split(".")[0]
            if (timePart.length === 5) timePart += ":00"
            return datePart + " " + timePart
        }
        return s + " 00:00:00"
    }

    function openWith(event, service) {
        eventData = event || null
        jiraService = service || null
        errorText = ""
        createButtonEnabled = true
        if (eventData) {
            summaryField.text = eventData.summary || ""
            descriptionField.text = eventData.description || ""
        }
        open()
    }

    onOpened: {
        if (eventData) {
            summaryField.text = eventData.summary || ""
            descriptionField.text = eventData.description || ""
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
            text: qsTr("Worklog (automático):")
            font.bold: true
            Layout.fillWidth: true
        }
        Controls.Label {
            text: root.eventData
                ? qsTr("%1 minutos").arg(root.eventData.duration_minutes || 0)
                : ""
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            color: Kirigami.Theme.disabledTextColor
            Layout.fillWidth: true
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
                var worklogStart = root.formatWorklogStart(root.eventData ? root.eventData.start : "")
                var duration = root.eventData ? (root.eventData.duration_minutes || 0) : 0
                root.createButtonEnabled = false
                root.errorText = ""
                var ok = root.jiraService.createIssueFromCalendarEvent(
                    summary, desc, worklogStart, duration
                )
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
