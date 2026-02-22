/**
 * BlockIssueDialog.qml
 * Diálogo para bloquear uma issue: motivo obrigatório, transição para BLOCKED.
 * Ao confirmar chama jiraService.block_issue(issueKey, reason).
 */
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Controls.Dialog {
    id: dialog

    title: qsTr("Bloquear issue")
    modal: true
    closePolicy: Controls.Popup.CloseOnEscape
    standardButtons: Controls.Dialog.NoButton

    property string issueKey: ""
    property string issueSummary: ""
    property var jiraService: null

    implicitWidth: 500
    width: implicitWidth

    function openWith(key, summary) {
        issueKey = key || ""
        issueSummary = summary || ""
        reasonInput.text = ""
        open()
    }

    onOpened: {
        if (parent && parent.width > 0 && parent.height > 0 && width > 0 && height > 0) {
            x = Math.max(0, Math.round((parent.width - width) / 2))
            y = Math.max(0, Math.round((parent.height - height) / 2))
        }
    }

    ColumnLayout {
        spacing: Kirigami.Units.mediumSpacing
        width: parent.width

        Controls.Label {
            text: (dialog.issueKey || "") + (dialog.issueSummary ? ": " + dialog.issueSummary : "")
            font.bold: true
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }

        Controls.Label {
            text: qsTr("Motivo do bloqueio:")
            font.bold: true
            Layout.fillWidth: true
        }

        Controls.ScrollView {
            Layout.fillWidth: true
            Layout.preferredHeight: 120
            clip: true
            contentWidth: availableWidth

            Controls.TextArea {
                id: reasonInput
                wrapMode: TextEdit.Wrap
                placeholderText: qsTr("Ex.: Aguardando aprovação, Dependente de outra issue, Aguardando informações…")
            }
        }

        Controls.Label {
            text: qsTr("Isso transitará a issue para o estado BLOCKED.")
            color: Kirigami.Theme.textColor
            font.italic: true
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }
    }

    footer: RowLayout {
        spacing: Kirigami.Units.mediumSpacing
        Layout.alignment: Qt.AlignRight

        Item { Layout.fillWidth: true }
        Controls.Button {
            text: qsTr("Voltar")
            onClicked: dialog.close()
        }
        Controls.Button {
            text: qsTr("Confirmar bloqueio")
            enabled: (reasonInput.text || "").trim().length > 0
            highlighted: true
            onClicked: {
                if (dialog.jiraService && dialog.issueKey) {
                    dialog.jiraService.block_issue(dialog.issueKey, reasonInput.text.trim())
                }
                dialog.close()
            }
        }
    }
}
