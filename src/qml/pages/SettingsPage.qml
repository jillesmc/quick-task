/**
 * SettingsPage.qml
 *
 * Página de configuração de conexão Jira
 * Permite configurar conexão Jira (server, login, token) e GitHub (token, username) via arquivos de configuração.
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

    // Recebidos do Main (passados explicitamente)
    property var settingsModel: null
    property var jiraService: null
    property var myIssuesModel: null
    property var googleAuthService: null
    property bool isSaving: false
    property bool isValid: connectionBlock ? connectionBlock.valid : false

    // Entrada por voz: context property (pode ser null se dependências não instaladas)
    property var _ctxVoiceInputService: (typeof voiceInputService !== "undefined" ? voiceInputService : null) // qmllint disable unqualified
    property bool voiceInputAvailable: _ctxVoiceInputService ? _ctxVoiceInputService.isAvailable() : false

    // Função pública para integração com Main.qml (botão global no header)
    function saveSettingsFromToolbar() {
        if (page.settingsModel && page.isValid && !page.isSaving) {
            page.isSaving = true;
            successMessage.visible = false;
            errorMessage.visible = false;
            statusMessage.text = qsTr("Salvando configurações...");
            statusMessage.visible = true;
            page.settingsModel.save();
        }
    }

    Component.onCompleted: {
        // Blocks load their own initial values from settingsModel
    }

    // Conectar sinais do modelo (só quando o modelo existir)
    Connections {
        target: page.settingsModel
        enabled: page.settingsModel !== null && page.settingsModel !== undefined

        function onSaved() {
            // Não desabilitar ainda - aguardar accountId
            // O botão só será habilitado quando accountId for buscado ou houver erro
            statusMessage.text = qsTr("Configuração salva. Buscando accountId...");
            statusMessage.visible = true;
            statusMessage.color = Kirigami.Theme.textColor;
        }

        function onErrorOccurred(message) {
            page.isSaving = false;
            errorMessage.text = message;
            errorMessage.visible = true;
            successMessage.visible = false;
            statusMessage.visible = false;
        }

        function onAccountIdFetched(accountId) {
            page.isSaving = false;
            statusMessage.text = qsTr("✓ AccountId obtido com sucesso!");
            statusMessage.color = Kirigami.Theme.positiveTextColor;
            statusMessage.visible = true;
            successMessage.visible = true;
            successMessage.text = qsTr("✓ Configuração salva e accountId obtido com sucesso!");

            if (page.jiraService) {
                page.jiraService.reloadConfiguration();
            }
            if (page.myIssuesModel) {
                page.myIssuesModel.reloadConfiguration();
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
        handle: SplitViewHandle { }

        // Coluna Esquerda: Conexões com plataformas e dados do Jira
        Controls.ScrollView {
            id: leftScrollView
            Controls.SplitView.preferredWidth: parent.width * 0.5
            Controls.SplitView.minimumWidth: 400
            Controls.SplitView.fillHeight: true
            clip: true
            contentWidth: availableWidth

            Item {
                width: leftScrollView.availableWidth
                implicitHeight: leftColumn.implicitHeight + 2 * Kirigami.Units.largeSpacing

                ColumnLayout {
                    id: leftColumn
                    anchors.fill: parent
                    anchors.leftMargin: Kirigami.Units.largeSpacing
                    anchors.rightMargin: Kirigami.Units.largeSpacing
                    anchors.topMargin: Kirigami.Units.largeSpacing
                    anchors.bottomMargin: Kirigami.Units.largeSpacing
                    spacing: Kirigami.Units.largeSpacing

                    ConnectionSettingsBlock {
                        id: connectionBlock
                        Layout.fillWidth: true
                        settingsModel: page.settingsModel
                    }

                    GitHubSettingsBlock {
                        Layout.fillWidth: true
                        settingsModel: page.settingsModel
                    }

                    GoogleOAuthSettingsBlock {
                        Layout.fillWidth: true
                        settingsModel: page.settingsModel
                        googleAuthService: page.googleAuthService
                    }

                    GoogleDriveCommentsSettingsBlock {
                        Layout.fillWidth: true
                        settingsModel: page.settingsModel
                    }

                    // Metadata do Jira (projetos, issue types, campos) - Issue #25
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        // qmllint disable unqualified
                        visible: typeof jiraMetadataConfigModel !== "undefined" && jiraMetadataConfigModel !== null

                        Kirigami.Heading {
                            text: qsTr("Metadata do Jira")
                            level: 3
                            Layout.fillWidth: true
                        }
                        Controls.Label {
                            text: qsTr("Configure quais projetos, tipos de issue e campos usar na aplicação.")
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                        Controls.Button {
                            text: qsTr("Configurar projetos e campos")
                            Layout.fillWidth: true
                            enabled: jiraMetadataConfigModel && jiraMetadataConfigModel.isAvailable() // qmllint disable unqualified
                            onClicked: {
                                var comp = Qt.createComponent("../components/dialogs/JiraMetadataWizard.qml");
                                if (comp.status !== Component.Ready) {
                                    if (comp.status === Component.Error && typeof console !== "undefined")
                                        console.warn("[SettingsPage] JiraMetadataWizard load error:", comp.errorString());
                                    return;
                                }
                                var parent = (typeof page.applicationWindow !== "undefined" ? page.applicationWindow : null) || page.parent || page; // qmllint disable missing-property
                                var dlg = comp.createObject(parent, { jiraMetadataConfigModel: jiraMetadataConfigModel }); // qmllint disable unqualified
                                if (dlg) {
                                    dlg.closed.connect(function() { dlg.destroy(); });
                                    dlg.open();
                                }
                            }
                        }
                        Controls.Label {
                            visible: jiraMetadataConfigModel && !jiraMetadataConfigModel.isAvailable() // qmllint disable unqualified
                            text: qsTr("Configure a conexão Jira acima primeiro.")
                            color: Kirigami.Theme.negativeTextColor
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                    }

                    // Recarregar opções de Assets (Valor entregue, Plataformas afetadas)
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        visible: !!page.jiraService

                        Controls.Label {
                            text: qsTr("Opções de Valor entregue e Plataformas afetadas")
                            font.bold: true
                            Layout.fillWidth: true
                        }
                        Controls.Button {
                            text: qsTr("Recarregar opções de Valor entregue e Plataformas")
                            Layout.fillWidth: true
                            onClicked: {
                                if (page.jiraService) {
                                    assetsReloadStatus.visible = true;
                                    assetsReloadStatus.text = qsTr("Recarregando...");
                                    assetsReloadStatus.color = Kirigami.Theme.textColor;
                                    page.jiraService.reloadAssetsCache();
                                }
                            }
                        }
                        Controls.Label {
                            id: assetsReloadStatus
                            Layout.fillWidth: true
                            text: ""
                            color: Kirigami.Theme.textColor
                            visible: false
                            wrapMode: Text.Wrap
                        }
                    }
                    Connections {
                        target: page.jiraService
                        function onAssetsCacheLoaded(success, message) {
                            assetsReloadStatus.visible = true;
                            assetsReloadStatus.text = message;
                            assetsReloadStatus.color = success
                                ? Kirigami.Theme.positiveTextColor
                                : Kirigami.Theme.negativeTextColor;
                        }
                    }
                }
            }
        }

        // Coluna Direita: Configurações agrupadas por tema
        Controls.ScrollView {
            id: rightScrollView
            Controls.SplitView.fillWidth: true
            Controls.SplitView.minimumWidth: 400
            Controls.SplitView.fillHeight: true
            clip: true
            contentWidth: availableWidth

            Item {
                width: rightScrollView.availableWidth
                implicitHeight: rightColumn.implicitHeight + 2 * Kirigami.Units.largeSpacing

                ColumnLayout {
                    id: rightColumn
                    anchors.fill: parent
                    anchors.leftMargin: Kirigami.Units.largeSpacing
                    anchors.rightMargin: Kirigami.Units.largeSpacing
                    anchors.topMargin: Kirigami.Units.largeSpacing
                    anchors.bottomMargin: Kirigami.Units.largeSpacing
                    spacing: Kirigami.Units.largeSpacing

                    // Produtividade (Timer)
                    Kirigami.Heading {
                        text: qsTr("Produtividade")
                        level: 2
                        Layout.fillWidth: true
                        Layout.topMargin: 0
                    }
                    PomodoroSettingsBlock {
                        Layout.fillWidth: true
                        settingsModel: page.settingsModel
                    }
                    NotificationSettingsBlock {
                        Layout.fillWidth: true
                        settingsModel: page.settingsModel
                    }

                    // Workflow Jira
                    Kirigami.Heading {
                        text: qsTr("Workflow Jira")
                        level: 2
                        Layout.fillWidth: true
                        Layout.topMargin: Kirigami.Units.largeSpacing
                    }
                    StatusTransitionsSettingsBlock {
                        Layout.fillWidth: true
                        settingsModel: page.settingsModel
                    }
                    DevelopmentPanelSettingsBlock {
                        Layout.fillWidth: true
                        settingsModel: page.settingsModel
                    }

                    // Entrada
                    Kirigami.Heading {
                        text: qsTr("Entrada")
                        level: 2
                        Layout.fillWidth: true
                        Layout.topMargin: Kirigami.Units.largeSpacing
                    }
                    VoiceInputSettingsBlock {
                        Layout.fillWidth: true
                        settingsModel: page.settingsModel
                        voiceInputAvailable: page.voiceInputAvailable
                    }

                    // Timesheet
                    Kirigami.Heading {
                        text: qsTr("Timesheet")
                        level: 2
                        Layout.fillWidth: true
                        Layout.topMargin: Kirigami.Units.largeSpacing
                    }
                    TimesheetSettingsBlock {
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
                }
            }
        }
    }
}
