/**
 * IssueFormPage.qml
 *
 * Página do formulário de criação de issue
 * Refatorado seguindo Clean Code e SOLID
 * Usa componentes reutilizáveis e controllers
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami
import "../components/forms"
import "../controllers"

Kirigami.Page {
    id: page

    title: "Preencha os dados da issue abaixo:"

    // Habilitar foco para capturar atalhos de teclado
    focus: true

    // Estado do processamento
    property bool isProcessing: false

    // Propriedades compartilhadas para sincronizar epic entre abas
    property string sharedEpicKey: ""
    property string sharedEpicSummary: ""

    signal epicSelected(string key, string summary)
    signal issueCreated(string issueKey)  // Emitido quando uma issue é criada com sucesso

    // Diálogos
    property var progressDialog: null
    property var successDialog: null

    // Controller para lógica de negócio
    property var controller: null

    // ------------------------------------------------------------------
    // Funções públicas para integração com Main.qml (botão global)
    // ------------------------------------------------------------------
    function createIssueFromToolbar() {
        // Mantém a mesma semântica original:
        // - Só cria se não estiver processando
        // - Valida antes de chamar o serviço
        if (!isProcessing && controller && controller.validate()) {
            controller.createIssue();
        }
    }

    // Função pública para cancelar (usada pelo botão global e pela tecla ESC)
    // Esconde a janela ao invés de fechar a aplicação
    function onCancelRequested() {
        if (!isProcessing) {
            if (typeof hideWindow === "function") {
                hideWindow();  // Esconde a janela (minimiza ao tray)
            }
            // Se hideWindow não estiver disponível, não fazer nada
            // (a aplicação deve estar configurada corretamente)
        }
    }

    // Atalhos de teclado locais (apenas ESC).
    // Ctrl+Enter é tratado globalmente em Main.qml via createIssueAction.
    Keys.onPressed: function (event) {
        // ESC: cancelar
        if (event.key === Qt.Key_Escape) {
            event.accepted = true;
            onCancelRequested();
            return;
        }
    }

    // Definir foco inicial no campo Summary quando a página for carregada
    Component.onCompleted: {
        summaryField.forceActiveFocus();

        // Inicializar worklog com data/hora atual se não estiver definido
        if (issueModel && (!issueModel.worklogInicio || issueModel.worklogInicio === "")) {
            var now = new Date();
            var dateStr = Qt.formatDateTime(now, "yyyy-MM-dd");
            var timeStr = Qt.formatDateTime(now, "HH:mm:ss");
            issueModel.worklogInicio = dateStr + " " + timeStr;
        }

        // Criar controller
        var component = Qt.createComponent("../controllers/IssueFormController.qml");
        if (component.status === Component.Ready) {
            controller = component.createObject(page, {
                jiraService: jiraService,
                issueModel: issueModel,
                enabled: true
            });

            // Conectar signals do controller
            controller.createStarted.connect(function () {
                isProcessing = true;
                showProgressDialog();
            });

            controller.createCompleted.connect(function (issueKey, issueUrl) {
                isProcessing = false;
                hideProgressDialog();
                showSuccessDialog(issueKey, issueUrl);
                resetForm();
                // Emitir signal para notificar que uma issue foi criada
                page.issueCreated(issueKey);
            });

            controller.createFailed.connect(function (errorMessage) {
                isProcessing = false;
                hideProgressDialog();
                showErrorDialog(errorMessage);
            });
        }
    }

    // Conectar signals do jiraService para progresso
    Connections {
        target: jiraService

        function onProgressUpdated(percentage, message) {
            if (progressDialog) {
                progressDialog.updateProgress(percentage, message);
            }
        }
    }

    Controls.SplitView {
        id: splitView
        anchors.fill: parent
        orientation: Qt.Horizontal

        // Coluna Esquerda: Summary, Description e Epic Parent (com split vertical)
        Controls.SplitView {
            id: leftSplitView
            Controls.SplitView.preferredWidth: parent.width * 0.6
            Controls.SplitView.minimumWidth: 400
            orientation: Qt.Vertical

            // Parte Superior: Summary e Description
            Item {
                id: topLeftPane
                Controls.SplitView.preferredHeight: parent.height * 0.5
                Controls.SplitView.minimumHeight: 200
                clip: true

                ColumnLayout {
                    id: topLeftColumn
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: Kirigami.Units.largeSpacing

                    // Summary
                    Controls.Label {
                        text: "Summary:"
                        font.bold: true
                        Layout.fillWidth: true
                    }

                    Controls.TextField {
                        id: summaryField
                        Layout.fillWidth: true

                        enabled: !isProcessing
                        text: issueModel ? issueModel.summary : ""
                        onTextChanged: if (issueModel)
                            issueModel.summary = text
                    }

                    // Description (ocupa espaço disponível)
                    Controls.Label {
                        text: "Description:"
                        font.bold: true
                        Layout.fillWidth: true
                    }

                    Controls.ScrollView {
                        id: descriptionScrollView
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true

                        Controls.TextArea {
                            id: descriptionField
                            width: descriptionScrollView.availableWidth
                            wrapMode: Controls.TextArea.Wrap
                            enabled: !isProcessing
                            text: issueModel ? issueModel.description : ""
                            onTextChanged: if (issueModel)
                                issueModel.description = text
                        }
                    }
                }
            }

            // Parte Inferior: Epic Parent (ocupa espaço disponível)
            Item {
                id: bottomLeftPane
                Controls.SplitView.fillHeight: true
                Controls.SplitView.minimumHeight: 200
                clip: true

                ColumnLayout {
                    id: bottomLeftColumn
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: Kirigami.Units.largeSpacing

                    // Epic Parent usando componente reutilizável
                    EpicSearchForm {
                        id: epicSearchForm
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        enabled: !isProcessing
                        // Binding para garantir que jiraService seja sempre atualizado
                        Binding {
                            target: epicSearchForm
                            property: "jiraService"
                            value: typeof jiraService !== "undefined" ? jiraService : null
                            when: typeof jiraService !== "undefined"
                        }

                        // Bindings bidirecionais com issueModel
                        Binding {
                            target: issueModel
                            property: "epicParentKey"
                            value: epicSearchForm.selectedEpicKey
                            when: issueModel
                        }

                        Binding {
                            target: issueModel
                            property: "epicParentSummary"
                            value: epicSearchForm.selectedEpicSummary
                            when: issueModel
                        }

                        // Sincronizar epic selecionado com sharedEpicKey e issueModel
                        onEpicSelected: function (key, summary) {
                            if (issueModel) {
                                issueModel.epicParentKey = key;
                                issueModel.epicParentSummary = summary;
                            }
                            page.epicSelected(key, summary);
                        }

                        // Limpar sharedEpicKey quando epic é limpo
                        onEpicCleared: {
                            page.sharedEpicKey = "";
                            page.sharedEpicSummary = "";
                            if (issueModel) {
                                issueModel.epicParentKey = "";
                                issueModel.epicParentSummary = "";
                            }
                        }

                        // Sincronizar epic compartilhado da aba 2
                        Binding {
                            target: epicSearchForm
                            property: "selectedEpicKey"
                            value: page.sharedEpicKey
                            when: page.sharedEpicKey !== ""
                        }

                        Binding {
                            target: epicSearchForm
                            property: "selectedEpicSummary"
                            value: page.sharedEpicSummary
                            when: page.sharedEpicSummary !== ""
                        }

                        // Binding reverso
                        Binding {
                            target: epicSearchForm
                            property: "selectedEpicKey"
                            value: issueModel ? issueModel.epicParentKey : ""
                            when: issueModel
                        }

                        Binding {
                            target: epicSearchForm
                            property: "selectedEpicSummary"
                            value: issueModel ? issueModel.epicParentSummary : ""
                            when: issueModel
                        }
                    }
                }
            }
        }

        // Coluna Direita: Tipo de atividade, Valor entregue, Plataformas afetadas, Documentação anexa, Utilização de IA, Worklog
        Controls.ScrollView {
            id: rightScrollView
            Controls.SplitView.fillWidth: true
            Controls.SplitView.minimumWidth: 300
            clip: true
            // Removed padding: 20

            Item {
                width: rightScrollView.availableWidth
                implicitHeight: rightColumn.implicitHeight + 40

                ColumnLayout {
                    id: rightColumn
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: Kirigami.Units.largeSpacing

                    // Worklog (Primeiro campo, conforme solicitado)
                    Controls.CheckBox {
                        id: worklogCheckbox
                        text: qsTr("Registrar worklog")
                        Layout.fillWidth: true
                        enabled: !isProcessing
                        checked: issueModel ? issueModel.registrarWorklog : false
                        onCheckedChanged: {
                            if (issueModel) {
                                issueModel.registrarWorklog = checked;
                            }
                        }
                    }

                    // WorklogForm (oculto quando checkbox não está marcado)
                    WorklogForm {
                        id: worklogForm
                        Layout.fillWidth: true

                        enabled: !isProcessing && worklogCheckbox.checked
                        visible: worklogCheckbox.checked
                        showCheckbox: false  // Não mostrar checkbox aqui, já temos acima

                        // Bindings bidirecionais com issueModel
                        Binding {
                            target: issueModel
                            property: "worklogInicio"
                            value: worklogForm.date && worklogForm.time ? worklogForm.date + " " + worklogForm.time : ""
                            when: issueModel && worklogForm.date && worklogForm.time
                        }

                        Binding {
                            target: issueModel
                            property: "worklogDuracao"
                            value: Math.round(worklogForm.duration)
                            when: issueModel
                        }

                        Binding {
                            target: issueModel
                            property: "worklogComment"
                            value: worklogForm.comment
                            when: issueModel
                        }

                        // Binding reverso para inicializar campos
                        Component.onCompleted: {
                            if (issueModel && issueModel.worklogInicio) {
                                var parts = issueModel.worklogInicio.split(" ");
                                if (parts.length >= 2) {
                                    worklogForm.date = parts[0];
                                    worklogForm.time = parts[1];
                                }
                            }
                            if (issueModel) {
                                worklogForm.duration = issueModel.worklogDuracao || 30;
                                worklogForm.comment = issueModel.worklogComment || "";
                            }
                        }
                    }

                    // GridLayout unificada para Status, Documentação, IA, Tipo de Atividade e Valor Entregue
                    GridLayout {
                        Layout.fillWidth: true
                        columnSpacing: Kirigami.Units.largeSpacing
                        rowSpacing: Kirigami.Units.largeSpacing
                        columns: width > 650 ? 2 : 1

                        // Status (Linha 1, Coluna 1)
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignTop
                            spacing: Kirigami.Units.smallSpacing

                            Controls.Label {
                                text: qsTr("Status:")
                                font.bold: true
                                Layout.fillWidth: true
                            }

                            Column {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing

                                Repeater {
                                    model: issueModel ? issueModel.statusSequence : []

                                    Controls.RadioButton {
                                        text: modelData
                                        enabled: !isProcessing
                                        checked: issueModel && issueModel.statusInicial === modelData
                                        onCheckedChanged: {
                                            if (checked && issueModel) {
                                                issueModel.statusInicial = modelData;
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Documentação e IA (Linha 1, Coluna 2)
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignTop
                            spacing: Kirigami.Units.largeSpacing

                            // Documentação anexa
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing

                                Controls.Label {
                                    text: qsTr("Documentação anexa:")
                                    font.bold: true
                                    Layout.fillWidth: true
                                }

                                Row {
                                    spacing: Kirigami.Units.largeSpacing
                                    Controls.RadioButton {
                                        text: qsTr("Não")
                                        enabled: !isProcessing
                                        checked: issueModel && issueModel.documentacaoAnexa === "Não"
                                        onCheckedChanged: {
                                            if (checked && issueModel) {
                                                issueModel.documentacaoAnexa = "Não";
                                            }
                                        }
                                    }
                                    Controls.RadioButton {
                                        text: qsTr("Sim")
                                        enabled: !isProcessing
                                        checked: issueModel && issueModel.documentacaoAnexa === "Sim"
                                        onCheckedChanged: {
                                            if (checked && issueModel) {
                                                issueModel.documentacaoAnexa = "Sim";
                                            }
                                        }
                                    }
                                }
                            }

                            // Utilização de IA
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing

                                Controls.Label {
                                    text: qsTr("Utilização de IA:")
                                    font.bold: true
                                    Layout.fillWidth: true
                                }

                                Row {
                                    spacing: Kirigami.Units.largeSpacing
                                    Controls.RadioButton {
                                        text: qsTr("Não")
                                        enabled: !isProcessing
                                        checked: issueModel && issueModel.utilizacaoIA === "Não"
                                        onCheckedChanged: {
                                            if (checked && issueModel) {
                                                issueModel.utilizacaoIA = "Não";
                                            }
                                        }
                                    }
                                    Controls.RadioButton {
                                        text: qsTr("Sim")
                                        enabled: !isProcessing
                                        checked: issueModel && issueModel.utilizacaoIA === "Sim"
                                        onCheckedChanged: {
                                            if (checked && issueModel) {
                                                issueModel.utilizacaoIA = "Sim";
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Tipo de Atividade (Linha 2, Coluna 1)
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignTop
                            spacing: Kirigami.Units.smallSpacing

                            Controls.Label {
                                text: qsTr("Tipo de atividade:")
                                font.bold: true
                                Layout.fillWidth: true
                            }

                            Column {
                                Layout.fillWidth: true
                                spacing: 0

                                Repeater {
                                    model: issueModel ? issueModel.tipoAtividadeValues : []

                                    Controls.RadioButton {
                                        text: modelData
                                        enabled: !isProcessing
                                        checked: issueModel && issueModel.tipoAtividade === modelData
                                        onCheckedChanged: {
                                            if (checked && issueModel) {
                                                issueModel.tipoAtividade = modelData;
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Valor Entregue (Linha 2, Coluna 2)
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignTop
                            spacing: Kirigami.Units.smallSpacing

                            Controls.Label {
                                text: qsTr("Valor Entregue:")
                                font.bold: true
                                Layout.fillWidth: true
                            }

                            Column {
                                Layout.fillWidth: true
                                spacing: 0

                                Repeater {
                                    model: issueModel ? issueModel.valorEntregueValues : []

                                    Controls.RadioButton {
                                        text: modelData
                                        enabled: !isProcessing
                                        checked: issueModel && issueModel.valorEntregue === modelData
                                        onCheckedChanged: {
                                            if (checked && issueModel) {
                                                issueModel.valorEntregue = modelData;
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Plataformas afetadas
                    Controls.Label {
                        text: qsTr("Plataformas afetadas:")
                        font.bold: true
                        Layout.fillWidth: true
                    }

                    // Usando ListView com CheckDelegate para multisseleção (duas colunas no item)
                    ListView {
                        id: plataformasListViewForm
                        Layout.fillWidth: true
                        implicitHeight: contentHeight
                        interactive: false
                        clip: true
                        model: issueModel ? issueModel.plataformasAfetadasValues : []

                        delegate: Controls.CheckDelegate {
                            width: plataformasListViewForm.width
                            enabled: !isProcessing
                            checked: {
                                if (!issueModel)
                                    return false;
                                var plataformas = issueModel.plataformasAfetadas || [];
                                return plataformas.indexOf(modelData.col1) >= 0;
                            }

                            contentItem: RowLayout {
                                spacing: Kirigami.Units.largeSpacing
                                Controls.Label {
                                    text: modelData.col1
                                    font.bold: true
                                    Layout.preferredWidth: 150
                                }
                                Controls.Label {
                                    text: modelData.col2
                                    font.italic: true
                                    opacity: 0.7
                                    Layout.fillWidth: true
                                }
                            }

                            onCheckedChanged: {
                                if (!issueModel)
                                    return;
                                var plataformas = issueModel.plataformasAfetadas || [];
                                var val = modelData.col1;
                                if (checked) {
                                    if (plataformas.indexOf(val) < 0) {
                                        plataformas.push(val);
                                        issueModel.plataformasAfetadas = plataformas;
                                    }
                                } else {
                                    var index = plataformas.indexOf(val);
                                    if (index >= 0) {
                                        plataformas.splice(index, 1);
                                        issueModel.plataformasAfetadas = plataformas;
                                    }
                                }
                            }
                        }
                    }

                    // Espaço extra no final para não "comer" o último campo
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Kirigami.Units.largeSpacing * 2
                    }
                }
            }
        }
    }

    // Funções auxiliares
    function resetForm() {
        // Resetar campos para valores padrão
        if (issueModel) {
            issueModel.summary = "";
            issueModel.description = "";

            // Tipo de atividade padrão
            var defaultTipo = "Suporte Dúvidas/Suporte uso incorreto";
            var tipoValues = issueModel.tipoAtividadeValues;
            if (tipoValues.indexOf(defaultTipo) >= 0) {
                issueModel.tipoAtividade = defaultTipo;
            } else if (tipoValues.length > 0) {
                issueModel.tipoAtividade = tipoValues[0];
            }

            // Status inicial padrão
            if (issueModel.statusSequence && issueModel.statusSequence.length > 0) {
                issueModel.statusInicial = issueModel.statusSequence[0];
            }

            // Valores padrão
            issueModel.documentacaoAnexa = "Não";
            issueModel.utilizacaoIA = "Não";

            // Resetar Valor Entregue e Plataformas afetadas
            var valorEntregueValues = issueModel.valorEntregueValues;
            if (valorEntregueValues && valorEntregueValues.length > 0) {
                issueModel.valorEntregue = valorEntregueValues[0];
            } else {
                issueModel.valorEntregue = "";
            }
            issueModel.plataformasAfetadas = [];

            // Limpar Epic Parent
            issueModel.epicParentKey = "";
            issueModel.epicParentSummary = "";
            if (epicSearchForm) {
                epicSearchForm.reset();
            }

            // Resetar worklog
            issueModel.registrarWorklog = false;
            var now = new Date();
            var dateStr = Qt.formatDateTime(now, "yyyy-MM-dd");
            var timeStr = Qt.formatDateTime(now, "HH:mm:ss");
            issueModel.worklogInicio = dateStr + " " + timeStr;
            issueModel.worklogDuracao = 30;
            if (worklogForm) {
                worklogForm.reset();
            }
        }
    }

    function validateForm() {
        if (controller) {
            return controller.validate();
        }
        return false;
    }

    function showProgressDialog() {
        var component = Qt.createComponent("../components/dialogs/ProgressDialog.qml");
        if (component.status === Component.Ready) {
            var window = page.parent && page.parent.parent ? page.parent.parent : page;
            progressDialog = component.createObject(window);
            if (progressDialog) {
                progressDialog.open();
            }
        } else {
            console.error("Erro ao criar ProgressDialog:", component.errorString());
        }
    }

    function hideProgressDialog() {
        if (progressDialog) {
            progressDialog.close();
            progressDialog.destroy();
            progressDialog = null;
        }
    }

    function showSuccessDialog(issueKey, issueUrl) {
        var component = Qt.createComponent("../components/dialogs/SuccessDialog.qml");
        if (component.status === Component.Ready) {
            var window = page.parent && page.parent.parent ? page.parent.parent : page;
            successDialog = component.createObject(window);
            if (successDialog) {
                successDialog.show(issueKey, issueUrl, false);  // false indica que é criação
            }
        } else {
            console.error("Erro ao criar SuccessDialog:", component.errorString());
        }
    }

    function showErrorDialog(message) {
        var component = Qt.createComponent("../components/dialogs/ErrorDialog.qml");
        if (component.status === Component.Ready) {
            var window = page.parent && page.parent.parent ? page.parent.parent : page;
            var dialog = component.createObject(window);
            if (dialog) {
                dialog.show(message);
            }
        } else {
            console.error("Erro:", message);
            console.error("Erro ao criar ErrorDialog:", component.errorString());
        }
    }
}
