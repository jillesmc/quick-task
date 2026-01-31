/**
 * ConnectionSettingsBlock.qml
 *
 * Bloco de configuração de conexão Jira: URL, e-mail, token, AccountId.
 * Recebe settingsModel; expõe propriedade valid para a página.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

Rectangle {
    id: root

    property var settingsModel: null
    property bool valid: (urlField.text.trim().length > 0 && (urlField.text.startsWith("http://") || urlField.text.startsWith("https://"))) &&
                         (emailField.text.trim().length > 0 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(emailField.text.trim())) &&
                         (tokenField.text.trim().length > 0)

    implicitHeight: connectionBlock.implicitHeight + (Kirigami.Units.largeSpacing * 2)
    color: Kirigami.Theme.backgroundColor || "#f0f0f0"
    border.color: Kirigami.Theme.textColor || "#d0d0d0"
    border.width: 1
    radius: Kirigami.Units.smallSpacing

    ColumnLayout {
        id: connectionBlock
        anchors.fill: parent
        anchors.margins: 20
        spacing: Kirigami.Units.mediumSpacing

        Kirigami.Heading {
            text: qsTr("Conexão Jira")
            level: 3
            Layout.fillWidth: true
        }

        Controls.Label {
            text: qsTr("URL do Servidor Jira:")
            font.bold: true
            Layout.fillWidth: true
        }

        Controls.TextField {
            id: urlField
            Layout.fillWidth: true
            placeholderText: qsTr("https://seu-projeto.atlassian.net")
            onTextChanged: {
                if (root.settingsModel) {
                    root.settingsModel.jiraBaseUrl = text.trim();
                }
            }
        }

        Controls.Label {
            text: qsTr("Email do Jira:")
            font.bold: true
            Layout.fillWidth: true
        }

        Controls.TextField {
            id: emailField
            Layout.fillWidth: true
            placeholderText: qsTr("seu-email@exemplo.com")
            inputMethodHints: Qt.ImhEmailCharactersOnly
            onTextChanged: {
                if (root.settingsModel) {
                    root.settingsModel.jiraEmail = text.trim();
                }
            }
        }

        Controls.Label {
            text: qsTr("Token de API:")
            font.bold: true
            Layout.fillWidth: true
        }

        Controls.TextField {
            id: tokenField
            Layout.fillWidth: true
            echoMode: TextInput.Password
            placeholderText: qsTr("Digite seu token de API")
            onTextChanged: {
                if (root.settingsModel) {
                    root.settingsModel.jiraApiToken = text;
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Controls.Label {
                text: qsTr("Account ID:")
                font.bold: true
            }

            Controls.Label {
                id: accountIdLabel
                Layout.fillWidth: true
                text: qsTr("Não configurado")
                color: Kirigami.Theme.disabledTextColor
                font.bold: true
            }

            Controls.BusyIndicator {
                id: accountIdBusyIndicator
                Layout.preferredWidth: 20
                Layout.preferredHeight: 20
                running: false
                visible: false
            }
        }
    }

    Connections {
        target: root.settingsModel || null
        function onAccountIdFetched(accountId) {
            accountIdLabel.text = accountId;
            accountIdLabel.color = Kirigami.Theme.positiveTextColor;
            accountIdBusyIndicator.running = false;
            accountIdBusyIndicator.visible = false;
        }
        function onFetchingAccountId() {
            accountIdLabel.text = qsTr("Buscando...");
            accountIdLabel.color = Kirigami.Theme.textColor;
            accountIdBusyIndicator.running = true;
            accountIdBusyIndicator.visible = true;
        }
        function onErrorOccurred(message) {
            accountIdBusyIndicator.running = false;
            accountIdBusyIndicator.visible = false;
            if (message && (message.includes("accountId") || message.includes("AccountId"))) {
                accountIdLabel.text = qsTr("Erro ao buscar");
                accountIdLabel.color = Kirigami.Theme.negativeTextColor;
            }
        }
    }

    Component.onCompleted: {
        if (root.settingsModel) {
            urlField.text = root.settingsModel.jiraBaseUrl || "";
            emailField.text = root.settingsModel.jiraEmail || "";
            tokenField.text = root.settingsModel.jiraApiToken || "";
            var accountId = root.settingsModel.accountId;
            accountIdLabel.text = accountId && accountId.length > 0 ? accountId : qsTr("Não configurado");
        }
    }
}
