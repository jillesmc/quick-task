/**
 * SettingsPage.qml
 *
 * Página de configuração de conexão Jira
 * Permite configurar JIRA_BASE_URL, JIRA_EMAIL e JIRA_API_TOKEN
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import QtQuick.Dialogs
import org.kde.kirigami as Kirigami
import "../components/settings"

Kirigami.Page {
    id: page

    title: qsTr("Configuração de Conexão")

    focus: true

    property bool isSaving: false
    property bool isValid: connectionBlock ? connectionBlock.valid : false

    // Função pública para integração com Main.qml (botão global no header)
    function saveSettingsFromToolbar() {
        if (settingsModel && isValid && !isSaving) {
            isSaving = true;
            successMessage.visible = false;
            errorMessage.visible = false;
            statusMessage.text = qsTr("Salvando configurações...");
            statusMessage.visible = true;
            settingsModel.save();
        }
    }

    Component.onCompleted: {
        // Blocks load their own initial values from settingsModel
    }

    // Conectar sinais do modelo
    Connections {
        target: settingsModel

        function onSaved() {
            // Não desabilitar ainda - aguardar accountId
            // O botão só será habilitado quando accountId for buscado ou houver erro
            statusMessage.text = qsTr("Configuração salva. Buscando accountId...");
            statusMessage.visible = true;
            statusMessage.color = Kirigami.Theme.textColor;
        }

        function onErrorOccurred(message) {
            isSaving = false;
            errorMessage.text = message;
            errorMessage.visible = true;
            successMessage.visible = false;
            statusMessage.visible = false;
        }

        function onAccountIdFetched(accountId) {
            isSaving = false;
            statusMessage.text = qsTr("✓ AccountId obtido com sucesso!");
            statusMessage.color = Kirigami.Theme.positiveTextColor;
            statusMessage.visible = true;
            successMessage.visible = true;
            successMessage.text = qsTr("✓ Configuração salva e accountId obtido com sucesso!");

            if (jiraService) {
                jiraService.reloadConfiguration();
            }
            if (myIssuesModel) {
                myIssuesModel.reloadConfiguration();
            }
        }

        function onFetchingAccountId() {
            statusMessage.text = qsTr("Buscando accountId...");
            statusMessage.color = Kirigami.Theme.textColor;
            statusMessage.visible = true;
        }
    }

    Controls.SplitView {
        id: splitView
        anchors.fill: parent
        orientation: Qt.Horizontal

        // Coluna Esquerda (50%): Conexão Jira
        Controls.ScrollView {
            id: leftScrollView
            Controls.SplitView.preferredWidth: parent.width * 0.5
            Controls.SplitView.minimumWidth: 400
            clip: true

            ColumnLayout {
                id: leftColumn
                width: leftScrollView.availableWidth
                anchors.margins: 20
                spacing: Kirigami.Units.largeSpacing

                ConnectionSettingsBlock {
                    id: connectionBlock
                    Layout.fillWidth: true
                    settingsModel: page.settingsModel
                }

                // Espaço flexível
                Item {
                    Layout.fillHeight: true
                }
            }
        }

        // Coluna Direita (50%): Pomodoro e Notificações
        Controls.ScrollView {
            id: rightScrollView
            Controls.SplitView.fillWidth: true
            Controls.SplitView.minimumWidth: 400
            clip: true

            ColumnLayout {
                id: rightColumn
                width: rightScrollView.availableWidth
                anchors.margins: 20
                spacing: Kirigami.Units.largeSpacing

                PomodoroSettingsBlock {
                    Layout.fillWidth: true
                    settingsModel: page.settingsModel
                }

                NotificationSettingsBlock {
                    Layout.fillWidth: true
                    settingsModel: page.settingsModel
                }

                // Mensagens de feedback
                Controls.Label {
                    id: successMessage
                    Layout.fillWidth: true
                    Layout.topMargin: Kirigami.Units.mediumSpacing
                    text: qsTr("✓ Configuração salva com sucesso!")
                    color: Kirigami.Theme.positiveTextColor
                    visible: false
                    wrapMode: Text.Wrap
                }

                Controls.Label {
                    id: errorMessage
                    Layout.fillWidth: true
                    Layout.topMargin: Kirigami.Units.mediumSpacing
                    text: ""
                    color: Kirigami.Theme.negativeTextColor
                    visible: false
                    wrapMode: Text.Wrap
                }

                Controls.Label {
                    id: statusMessage
                    Layout.fillWidth: true
                    Layout.topMargin: Kirigami.Units.mediumSpacing
                    text: ""
                    color: Kirigami.Theme.textColor
                    visible: false
                    wrapMode: Text.Wrap
                }

                // Espaço flexível
                Item {
                    Layout.fillHeight: true
                }
            }
        }
    }
}
