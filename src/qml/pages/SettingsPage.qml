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

Kirigami.Page {
    id: page

    title: qsTr("Configuração de Conexão")
    
    focus: true

    property bool isSaving: false
    property bool isValid: false

    // Validar campos em tempo real
    function validateFields() {
        var urlValid = urlField.text.trim().length > 0 && 
                       (urlField.text.startsWith("http://") || urlField.text.startsWith("https://"))
        var emailValid = emailField.text.trim().length > 0 && 
                         /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(emailField.text.trim())
        var tokenValid = tokenField.text.trim().length > 0
        
        isValid = urlValid && emailValid && tokenValid
    }

    // Carregar valores atuais ao abrir
    Component.onCompleted: {
        if (settingsModel) {
            urlField.text = settingsModel.jiraBaseUrl || ""
            emailField.text = settingsModel.jiraEmail || ""
            tokenField.text = settingsModel.jiraApiToken || ""
            var accountId = settingsModel.accountId
            accountIdLabel.text = accountId && accountId.length > 0 ? accountId : qsTr("Não configurado")
        }
        validateFields()
    }

    // Conectar sinais do modelo
    Connections {
        target: settingsModel
        
        function onSaved() {
            // Não desabilitar ainda - aguardar accountId
            // O botão só será habilitado quando accountId for buscado ou houver erro
            statusMessage.text = qsTr("Configuração salva. Buscando accountId...")
            statusMessage.visible = true
            statusMessage.color = Kirigami.Theme.textColor
        }
        
        function onErrorOccurred(message) {
            isSaving = false
            saveButton.enabled = true
            errorMessage.text = message
            errorMessage.visible = true
            successMessage.visible = false
            statusMessage.visible = false
            accountIdBusyIndicator.running = false
            accountIdBusyIndicator.visible = false
            // Se o erro for relacionado ao accountId, manter o label visível
            if (message.includes("accountId") || message.includes("AccountId")) {
                accountIdLabel.text = qsTr("Erro ao buscar")
                accountIdLabel.color = Kirigami.Theme.negativeTextColor
            }
        }
        
        function onAccountIdFetched(accountId) {
            isSaving = false
            saveButton.enabled = true
            accountIdLabel.text = accountId
            accountIdLabel.color = Kirigami.Theme.positiveTextColor
            accountIdBusyIndicator.running = false
            accountIdBusyIndicator.visible = false
            statusMessage.text = qsTr("✓ AccountId obtido com sucesso!")
            statusMessage.color = Kirigami.Theme.positiveTextColor
            statusMessage.visible = true
            successMessage.visible = true
            successMessage.text = qsTr("✓ Configuração salva e accountId obtido com sucesso!")
            
            // Recarregar configurações nos outros modelos
            if (jiraService) {
                jiraService.reloadConfiguration()
            }
            if (myIssuesModel) {
                myIssuesModel.reloadConfiguration()
            }
        }
        
        function onFetchingAccountId() {
            statusMessage.text = qsTr("Buscando accountId...")
            statusMessage.color = Kirigami.Theme.textColor
            statusMessage.visible = true
            accountIdBusyIndicator.running = true
            accountIdBusyIndicator.visible = true
            accountIdLabel.text = qsTr("Buscando...")
            accountIdLabel.color = Kirigami.Theme.textColor
        }
    }

    Controls.ScrollView {
        id: scrollView
        anchors.fill: parent
        clip: true

        Kirigami.FormLayout {
            id: formLayout
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Kirigami.Units.largeSpacing

            // JIRA_BASE_URL
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
                    validateFields()
                    if (settingsModel) {
                        settingsModel.jiraBaseUrl = text.trim()
                    }
                }
            }

            // JIRA_EMAIL
            Controls.Label {
                text: qsTr("Email do Jira:")
                font.bold: true
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.mediumSpacing
            }

            Controls.TextField {
                id: emailField
                Layout.fillWidth: true
                placeholderText: qsTr("seu-email@exemplo.com")
                inputMethodHints: Qt.ImhEmailCharactersOnly
                onTextChanged: {
                    validateFields()
                    if (settingsModel) {
                        settingsModel.jiraEmail = text.trim()
                    }
                }
            }

            // JIRA_API_TOKEN
            Controls.Label {
                text: qsTr("Token de API:")
                font.bold: true
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.mediumSpacing
            }

            Controls.TextField {
                id: tokenField
                Layout.fillWidth: true
                echoMode: TextInput.Password
                placeholderText: qsTr("Digite seu token de API")
                onTextChanged: {
                    validateFields()
                    if (settingsModel) {
                        settingsModel.jiraApiToken = text
                    }
                }
            }

            // AccountId (read-only)
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.mediumSpacing
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
                
                // Indicador visual de busca em andamento
                Controls.BusyIndicator {
                    id: accountIdBusyIndicator
                    Layout.preferredWidth: 20
                    Layout.preferredHeight: 20
                    running: false
                    visible: false
                }
            }

            // Botão Salvar
            Controls.Button {
                id: saveButton
                text: isSaving ? qsTr("Salvando...") : qsTr("Salvar")
                enabled: isValid && !isSaving
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.largeSpacing
                icon.name: "document-save"
                
                onClicked: {
                    if (settingsModel) {
                        isSaving = true
                        enabled = false
                        successMessage.visible = false
                        errorMessage.visible = false
                        statusMessage.text = qsTr("Salvando configurações...")
                        statusMessage.visible = true
                        settingsModel.save()
                    }
                }
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
        }
    }
}
