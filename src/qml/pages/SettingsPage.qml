/**
 * SettingsPage.qml
 *
 * Página de configuração de conexão Jira
 * Permite configurar JIRA_BASE_URL, JIRA_EMAIL e JIRA_API_TOKEN
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami
import "../components/settings"
import "../components/controls"

Kirigami.Page {
    id: page

    title: qsTr("Configuração de Conexão")

    focus: true

    property var _ctxSettingsModel: settingsModel
    property var _ctxJiraService: jiraService
    property var _ctxMyIssuesModel: myIssuesModel
    property bool isSaving: false
    property bool isValid: page.connectionBlock ? page.connectionBlock.valid : false

    // Função pública para integração com Main.qml (botão global no header)
    function saveSettingsFromToolbar() {
        if (page._ctxSettingsModel && page.isValid && !page.isSaving) {
            page.isSaving = true;
            page.successMessage.visible = false;
            page.errorMessage.visible = false;
            page.statusMessage.text = qsTr("Salvando configurações...");
            page.statusMessage.visible = true;
            page._ctxSettingsModel.save();
        }
    }

    Component.onCompleted: {
        // Blocks load their own initial values from settingsModel
    }

    // Conectar sinais do modelo
    Connections {
        target: page._ctxSettingsModel

        function onSaved() {
            // Não desabilitar ainda - aguardar accountId
            // O botão só será habilitado quando accountId for buscado ou houver erro
            page.statusMessage.text = qsTr("Configuração salva. Buscando accountId...");
            page.statusMessage.visible = true;
            page.statusMessage.color = Kirigami.Theme.textColor;
        }

        function onErrorOccurred(message) {
            page.isSaving = false;
            page.errorMessage.text = message;
            page.errorMessage.visible = true;
            page.successMessage.visible = false;
            page.statusMessage.visible = false;
        }

        function onAccountIdFetched(accountId) {
            page.isSaving = false;
            page.statusMessage.text = qsTr("✓ AccountId obtido com sucesso!");
            page.statusMessage.color = Kirigami.Theme.positiveTextColor;
            page.statusMessage.visible = true;
            page.successMessage.visible = true;
            page.successMessage.text = qsTr("✓ Configuração salva e accountId obtido com sucesso!");

            if (page._ctxJiraService) {
                page._ctxJiraService.reloadConfiguration();
            }
            if (page._ctxMyIssuesModel) {
                page._ctxMyIssuesModel.reloadConfiguration();
            }
        }

        function onFetchingAccountId() {
            page.statusMessage.text = qsTr("Buscando accountId...");
            page.statusMessage.color = Kirigami.Theme.textColor;
            page.statusMessage.visible = true;
        }
    }

    Controls.SplitView {
        id: splitView
        anchors.fill: parent
        orientation: Qt.Horizontal
        handle: SplitViewHandle { }

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
                    settingsModel: page._ctxSettingsModel
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
                    settingsModel: page._ctxSettingsModel
                }

                NotificationSettingsBlock {
                    Layout.fillWidth: true
                    settingsModel: page._ctxSettingsModel
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
