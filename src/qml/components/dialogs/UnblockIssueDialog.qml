/**
 * UnblockIssueDialog.qml
 * Diálogo para desbloquear uma issue: comentário opcional, transição para IN DEVELOPMENT.
 * Ao confirmar chama jiraService.unblock_issue(issueKey, comment).
 */
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Controls.Dialog {
    id: dialog

    title: qsTr("Desbloquear issue")
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
        commentInput.text = ""
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
            text: qsTr("Desbloquear issue e retornar para IN DEVELOPMENT?")
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }

        Controls.Label {
            text: qsTr("Comentário (opcional):")
            font.bold: true
            Layout.fillWidth: true
        }

        Controls.ScrollView {
            Layout.fillWidth: true
            Layout.preferredHeight: 80
            clip: true
            contentWidth: availableWidth

            Controls.TextArea {
                id: commentInput
                wrapMode: TextEdit.Wrap
                placeholderText: qsTr("Ex.: Aprovação recebida, Issue dependente foi resolvida…")
            }
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
            text: qsTr("Confirmar desbloqueio")
            highlighted: true
            onClicked: {
                if (dialog.jiraService && dialog.issueKey) {
                    dialog.jiraService.unblock_issue(dialog.issueKey, (commentInput.text || "").trim())
                }
                dialog.close()
            }
        }
    }
}
