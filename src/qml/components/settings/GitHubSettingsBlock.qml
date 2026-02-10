/**
 * GitHubSettingsBlock.qml
 *
 * Bloco de configuração GitHub: token de API e username.
 * Usado na aba GitHub para listar PRs (review required) e Issues atribuídas.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

Rectangle {
    id: root

    property var settingsModel: null

    implicitHeight: contentColumn.implicitHeight + (Kirigami.Units.largeSpacing * 2)
    color: Kirigami.Theme.backgroundColor || "#f0f0f0"
    border.color: Kirigami.Theme.textColor || "#d0d0d0"
    border.width: 1
    radius: Kirigami.Units.smallSpacing

    ColumnLayout {
        id: contentColumn
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.mediumSpacing

        Kirigami.Heading {
            text: qsTr("GitHub")
            level: 3
            Layout.fillWidth: true
        }

        Controls.Label {
            text: qsTr("Token de API (opcional: use variável de ambiente GITHUB_API_TOKEN):")
            font.bold: true
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }

        Controls.TextField {
            id: tokenField
            Layout.fillWidth: true
            echoMode: TextInput.Password
            placeholderText: qsTr("Digite seu token de API do GitHub")
            onTextChanged: {
                if (root.settingsModel) {
                    root.settingsModel.githubToken = text;
                }
            }
        }

        Controls.Label {
            text: qsTr("Username do GitHub:")
            font.bold: true
            Layout.fillWidth: true
        }

        Controls.TextField {
            id: usernameField
            Layout.fillWidth: true
            placeholderText: qsTr("seu-username")
            onTextChanged: {
                if (root.settingsModel) {
                    root.settingsModel.githubUsername = text.trim();
                }
            }
        }
    }

    Component.onCompleted: {
        if (root.settingsModel) {
            tokenField.text = root.settingsModel.githubToken || "";
            usernameField.text = root.settingsModel.githubUsername || "";
        }
    }
}
