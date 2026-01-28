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

Kirigami.Page {
    id: page

    title: qsTr("Configuração de Conexão")

    focus: true

    property bool isSaving: false
    property bool isValid: false

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

    // Validar campos em tempo real
    function validateFields() {
        var urlValid = urlField.text.trim().length > 0 && (urlField.text.startsWith("http://") || urlField.text.startsWith("https://"));
        var emailValid = emailField.text.trim().length > 0 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(emailField.text.trim());
        var tokenValid = tokenField.text.trim().length > 0;

        isValid = urlValid && emailValid && tokenValid;
    }

    // Carregar valores atuais ao abrir
    Component.onCompleted: {
        if (settingsModel) {
            urlField.text = settingsModel.jiraBaseUrl || "";
            emailField.text = settingsModel.jiraEmail || "";
            tokenField.text = settingsModel.jiraApiToken || "";
            var accountId = settingsModel.accountId;
            accountIdLabel.text = accountId && accountId.length > 0 ? accountId : qsTr("Não configurado");

            // Carregar configurações de Pomodoro
            pomodoroEnabledCheckbox.checked = settingsModel.pomodoroEnabled;
            pomodoroDurationSpinBox.value = settingsModel.pomodoroDurationMinutes;
            shortBreakSpinBox.value = settingsModel.shortBreakMinutes;
            longBreakSpinBox.value = settingsModel.longBreakMinutes;
            pomodorosBeforeLongBreakSpinBox.value = settingsModel.pomodorosBeforeLongBreak;
            autoContinueTimeoutSpinBox.value = settingsModel.autoContinueTimeoutSeconds;
            notificationsEnabledCheckbox.checked = settingsModel.notificationsEnabled;
            soundEnabledCheckbox.checked = settingsModel.soundEnabled;
            desktopNotificationsCheckbox.checked = settingsModel.desktopNotifications;
            shortSoundFileField.text = settingsModel.shortSoundFile || "short";
            longSoundFileField.text = settingsModel.longSoundFile || "long";
            shortSoundFileField.enabled = soundEnabledCheckbox.checked;
            longSoundFileField.enabled = soundEnabledCheckbox.checked;
        }
        validateFields();
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
            accountIdBusyIndicator.running = false;
            accountIdBusyIndicator.visible = false;
            // Se o erro for relacionado ao accountId, manter o label visível
            if (message.includes("accountId") || message.includes("AccountId")) {
                accountIdLabel.text = qsTr("Erro ao buscar");
                accountIdLabel.color = Kirigami.Theme.negativeTextColor;
            }
        }

        function onAccountIdFetched(accountId) {
            isSaving = false;
            accountIdLabel.text = accountId;
            accountIdLabel.color = Kirigami.Theme.positiveTextColor;
            accountIdBusyIndicator.running = false;
            accountIdBusyIndicator.visible = false;
            statusMessage.text = qsTr("✓ AccountId obtido com sucesso!");
            statusMessage.color = Kirigami.Theme.positiveTextColor;
            statusMessage.visible = true;
            successMessage.visible = true;
            successMessage.text = qsTr("✓ Configuração salva e accountId obtido com sucesso!");

            // Recarregar configurações nos outros modelos
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
            accountIdBusyIndicator.running = true;
            accountIdBusyIndicator.visible = true;
            accountIdLabel.text = qsTr("Buscando...");
            accountIdLabel.color = Kirigami.Theme.textColor;
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

                // Bloco 1: Conexão Jira
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: connectionBlock.implicitHeight + (Kirigami.Units.largeSpacing * 2)
                    color: Kirigami.Theme.backgroundColor || "#f0f0f0"
                    border.color: Kirigami.Theme.separatorColor || "#d0d0d0"
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

                        // URL do Servidor
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
                                validateFields();
                                if (settingsModel) {
                                    settingsModel.jiraBaseUrl = text.trim();
                                }
                            }
                        }

                        // Email
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
                                validateFields();
                                if (settingsModel) {
                                    settingsModel.jiraEmail = text.trim();
                                }
                            }
                        }

                        // Token de API
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
                                validateFields();
                                if (settingsModel) {
                                    settingsModel.jiraApiToken = text;
                                }
                            }
                        }

                        // AccountId (read-only)
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

                            // Indicador visual de busca em andamento
                            Controls.BusyIndicator {
                                id: accountIdBusyIndicator
                                Layout.preferredWidth: 20
                                Layout.preferredHeight: 20
                                running: false
                                visible: false
                            }
                        }
                    }
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

                // Bloco 2: Configurações de Pomodoro
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: pomodoroBlock.implicitHeight + (Kirigami.Units.largeSpacing * 2)
                    color: Kirigami.Theme.backgroundColor || "#f0f0f0"
                    border.color: Kirigami.Theme.separatorColor || "#d0d0d0"
                    border.width: 1
                    radius: Kirigami.Units.smallSpacing

                    ColumnLayout {
                        id: pomodoroBlock
                        anchors.fill: parent
                        anchors.margins: 20
                        spacing: Kirigami.Units.mediumSpacing

                        Kirigami.Heading {
                            text: qsTr("Configurações de Pomodoro")
                            level: 3
                            Layout.fillWidth: true
                        }

                        // Habilitar Pomodoro
                        Controls.CheckBox {
                            id: pomodoroEnabledCheckbox
                            text: qsTr("Habilitar Pomodoro")
                            Layout.fillWidth: true
                            checked: true
                            onCheckedChanged: {
                                if (settingsModel) {
                                    settingsModel.pomodoroEnabled = checked;
                                }
                                // Desabilitar campos se Pomodoro estiver desabilitado
                                pomodoroDurationSpinBox.enabled = checked;
                                shortBreakSpinBox.enabled = checked;
                                longBreakSpinBox.enabled = checked;
                                pomodorosBeforeLongBreakSpinBox.enabled = checked;
                                autoContinueTimeoutSpinBox.enabled = checked;
                                notificationsEnabledCheckbox.enabled = checked;
                                soundEnabledCheckbox.enabled = checked;
                                desktopNotificationsCheckbox.enabled = checked;
                            }
                        }

                        // Duração do Pomodoro
                        Controls.Label {
                            text: qsTr("Duração do Pomodoro (minutos):")
                            font.bold: true
                            Layout.fillWidth: true
                        }

                        Controls.SpinBox {
                            id: pomodoroDurationSpinBox
                            from: 1
                            to: 120
                            value: 25
                            onValueChanged: {
                                if (settingsModel) {
                                    settingsModel.pomodoroDurationMinutes = value;
                                }
                            }
                        }

                        // Pausa Curta
                        Controls.Label {
                            text: qsTr("Pausa Curta (minutos):")
                            font.bold: true
                            Layout.fillWidth: true
                        }

                        Controls.SpinBox {
                            id: shortBreakSpinBox
                            from: 1
                            to: 60
                            value: 5
                            onValueChanged: {
                                if (settingsModel) {
                                    settingsModel.shortBreakMinutes = value;
                                }
                            }
                        }

                        // Pausa Longa
                        Controls.Label {
                            text: qsTr("Pausa Longa (minutos):")
                            font.bold: true
                            Layout.fillWidth: true
                        }

                        Controls.SpinBox {
                            id: longBreakSpinBox
                            from: 1
                            to: 120
                            value: 15
                            onValueChanged: {
                                if (settingsModel) {
                                    settingsModel.longBreakMinutes = value;
                                }
                            }
                        }

                        // Pomodoros antes da Pausa Longa
                        Controls.Label {
                            text: qsTr("Pomodoros antes da Pausa Longa:")
                            font.bold: true
                            Layout.fillWidth: true
                        }

                        Controls.SpinBox {
                            id: pomodorosBeforeLongBreakSpinBox
                            from: 1
                            to: 10
                            value: 4
                            onValueChanged: {
                                if (settingsModel) {
                                    settingsModel.pomodorosBeforeLongBreak = value;
                                }
                            }
                        }

                        // Timeout de Auto-continuação
                        Controls.Label {
                            text: qsTr("Timeout de Auto-continuação (segundos):")
                            font.bold: true
                            Layout.fillWidth: true
                        }

                        Controls.SpinBox {
                            id: autoContinueTimeoutSpinBox
                            from: 5
                            to: 300
                            value: 30
                            stepSize: 5
                            onValueChanged: {
                                if (settingsModel) {
                                    settingsModel.autoContinueTimeoutSeconds = value;
                                }
                            }
                        }
                    }
                }

                // Bloco 3: Notificações
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: notificationsBlock.implicitHeight + (Kirigami.Units.largeSpacing * 2)
                    color: Kirigami.Theme.backgroundColor || "#f0f0f0"
                    border.color: Kirigami.Theme.separatorColor || "#d0d0d0"
                    border.width: 1
                    radius: Kirigami.Units.smallSpacing

                    ColumnLayout {
                        id: notificationsBlock
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.largeSpacing
                        spacing: Kirigami.Units.mediumSpacing

                        Kirigami.Heading {
                            text: qsTr("Notificações")
                            level: 3
                            Layout.fillWidth: true
                        }

                        // Notificações Desktop
                        Controls.CheckBox {
                            id: notificationsEnabledCheckbox
                            text: qsTr("Notificações Desktop")
                            Layout.fillWidth: true
                            checked: true
                            onCheckedChanged: {
                                if (settingsModel) {
                                    settingsModel.notificationsEnabled = checked;
                                }
                            }
                        }

                        // Som de Alerta
                        Controls.CheckBox {
                            id: soundEnabledCheckbox
                            text: qsTr("Som de Alerta")
                            Layout.fillWidth: true
                            checked: false
                            onCheckedChanged: {
                                if (settingsModel) {
                                    settingsModel.soundEnabled = checked;
                                }
                                // Habilitar/desabilitar campos de arquivos de som
                                shortSoundFileField.enabled = checked;
                                longSoundFileField.enabled = checked;
                            }
                        }

                        // Arquivo de som para pausa curta
                        Controls.Label {
                            text: qsTr("Arquivo de som - Pausa Curta:")
                            font.bold: true
                            Layout.fillWidth: true
                            enabled: soundEnabledCheckbox.checked
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            Controls.TextField {
                                id: shortSoundFileField
                                Layout.fillWidth: true
                                placeholderText: qsTr("short")
                                enabled: soundEnabledCheckbox.checked
                                onTextChanged: {
                                    if (settingsModel && text.length > 0) {
                                        settingsModel.shortSoundFile = text;
                                    }
                                }
                            }

                            Controls.Button {
                                icon.name: "folder"
                                enabled: soundEnabledCheckbox.checked
                                onClicked: {
                                    shortSoundFileDialog.open();
                                }
                            }
                        }

                        FileDialog {
                            id: shortSoundFileDialog
                            title: qsTr("Escolher arquivo de som - Pausa Curta")
                            nameFilters: ["Arquivos de áudio (*.ogg *.mp3 *.m4r *.wav)", "Todos os arquivos (*)"]
                            fileMode: FileDialog.ExistingFile
                            onAccepted: {
                                var urlString = selectedFile.toString();
                                var filePath = urlString.replace(/^file:\/{2,3}/, "");
                                filePath = decodeURIComponent(filePath);
                                shortSoundFileField.text = filePath;
                                if (settingsModel) {
                                    settingsModel.shortSoundFile = filePath;
                                }
                            }
                        }

                        // Arquivo de som para pausa longa
                        Controls.Label {
                            text: qsTr("Arquivo de som - Pausa Longa:")
                            font.bold: true
                            Layout.fillWidth: true
                            enabled: soundEnabledCheckbox.checked
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            Controls.TextField {
                                id: longSoundFileField
                                Layout.fillWidth: true
                                placeholderText: qsTr("long")
                                enabled: soundEnabledCheckbox.checked
                                onTextChanged: {
                                    if (settingsModel && text.length > 0) {
                                        settingsModel.longSoundFile = text;
                                    }
                                }
                            }

                            Controls.Button {
                                icon.name: "folder"
                                enabled: soundEnabledCheckbox.checked
                                onClicked: {
                                    longSoundFileDialog.open();
                                }
                            }
                        }

                        FileDialog {
                            id: longSoundFileDialog
                            title: qsTr("Escolher arquivo de som - Pausa Longa")
                            nameFilters: ["Arquivos de áudio (*.ogg *.mp3 *.m4r *.wav)", "Todos os arquivos (*)"]
                            fileMode: FileDialog.ExistingFile
                            onAccepted: {
                                var urlString = selectedFile.toString();
                                var filePath = urlString.replace(/^file:\/{2,3}/, "");
                                filePath = decodeURIComponent(filePath);
                                longSoundFileField.text = filePath;
                                if (settingsModel) {
                                    settingsModel.longSoundFile = filePath;
                                }
                            }
                        }

                        // Notificações Desktop (checkbox adicional para desktop_notifications)
                        Controls.CheckBox {
                            id: desktopNotificationsCheckbox
                            text: qsTr("Usar Notificações do Sistema")
                            Layout.fillWidth: true
                            checked: true
                            onCheckedChanged: {
                                if (settingsModel) {
                                    settingsModel.desktopNotifications = checked;
                                }
                            }
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

                // Espaço flexível
                Item {
                    Layout.fillHeight: true
                }
            }
        }
    }
}
