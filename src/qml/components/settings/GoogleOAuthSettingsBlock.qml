/**
 * GoogleOAuthSettingsBlock.qml
 *
 * Bloco de configuração Google OAuth: client_id, project_id, client_secret.
 * Usado para integração com Google Calendar e Google Tasks.
 * Botão "Autorizar" dispara o fluxo OAuth (abre navegador para consentimento).
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

Rectangle {
    id: root

    property var settingsModel: null
    property var googleAuthService: null

    implicitHeight: contentColumn.implicitHeight + (Kirigami.Units.largeSpacing * 2)
    color: Kirigami.Theme.backgroundColor || "#f0f0f0"
    border.color: Kirigami.Theme.textColor || "#d0d0d0"
    border.width: 1
    radius: Kirigami.Units.smallSpacing

    ColumnLayout {
        id: contentColumn
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Heading {
            text: qsTr("Google OAuth (Calendar e Tasks)")
            level: 3
            Layout.fillWidth: true
        }

        Controls.Label {
            Layout.topMargin: Kirigami.Units.largeSpacing
            text: qsTr("Client ID:")
            font.bold: true
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }

        Controls.TextField {
            id: clientIdField
            Layout.fillWidth: true
            placeholderText: qsTr("Digite o Client ID do projeto GCP")
            onTextChanged: {
                if (root.settingsModel) {
                    root.settingsModel.googleOAuthClientId = text;
                }
            }
        }

        Controls.Label {
            text: qsTr("Project ID:")
            font.bold: true
            Layout.fillWidth: true
        }

        Controls.TextField {
            id: projectIdField
            Layout.fillWidth: true
            placeholderText: qsTr("Digite o Project ID do projeto GCP")
            onTextChanged: {
                if (root.settingsModel) {
                    root.settingsModel.googleOAuthProjectId = text.trim();
                }
            }
        }

        Controls.Label {
            text: qsTr("Client Secret:")
            font.bold: true
            Layout.fillWidth: true
        }

        Controls.TextField {
            id: clientSecretField
            Layout.fillWidth: true
            echoMode: TextInput.Password
            placeholderText: qsTr("Digite o Client Secret do projeto GCP")
            onTextChanged: {
                if (root.settingsModel) {
                    root.settingsModel.googleOAuthClientSecret = text;
                }
            }
        }

        Controls.Label {
            text: !root.googleAuthService
                ? qsTr("Carregando serviços Google...")
                : (root.googleAuthService.isAuthorized
                    ? qsTr("Autorizado (token salvo localmente)")
                    : qsTr("Não autorizado"))
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            color: root.googleAuthService && root.googleAuthService.isAuthorized
                ? Kirigami.Theme.positiveTextColor
                : Kirigami.Theme.disabledTextColor
            Layout.fillWidth: true
        }

        Controls.Button {
            text: qsTr("Autorizar")
            icon.name: "dialog-password"
            Layout.alignment: Qt.AlignRight
            enabled: root.googleAuthService
                && root.settingsModel
                && (root.settingsModel.googleOAuthClientId || "").trim().length > 0
                && (root.settingsModel.googleOAuthClientSecret || "").trim().length > 0
                && !(root.googleAuthService && root.googleAuthService.isAuthorized)
            onClicked: {
                if (!root.googleAuthService || typeof root.googleAuthService.authorize !== "function") return
                // Salvar client_id e client_secret apenas se ainda não estiverem no config (fluxo OAuth lê do arquivo)
                if (root.settingsModel && typeof root.settingsModel.saveGoogleOAuthOnly === "function") {
                    root.settingsModel.saveGoogleOAuthOnly()
                }
                root.googleAuthService.authorize()
            }
        }
    }

    Component.onCompleted: {
        if (root.settingsModel) {
            clientIdField.text = root.settingsModel.googleOAuthClientId || "";
            projectIdField.text = root.settingsModel.googleOAuthProjectId || "";
            clientSecretField.text = root.settingsModel.googleOAuthClientSecret || "";
        }
    }
}
