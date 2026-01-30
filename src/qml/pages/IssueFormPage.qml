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
import "../components/controls"
import "../controllers"
import "../utils/DialogHelpers.js" as DialogHelpers

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

    property var progressDialog: null

    // Controller para lógica de negócio
    property var controller: null

    // Intermediário para evitar binding loop ao passar context property ao IssueMetadataFields
    property var _ctxIssueModel: issueModel
    property var _ctxJiraService: jiraService

    // ------------------------------------------------------------------
    // Funções públicas para integração com Main.qml (botão global)
    // ------------------------------------------------------------------
    function createIssueFromToolbar() {
        // Mantém a mesma semântica original:
        // - Só cria se não estiver processando
        // - Valida antes de chamar o serviço
        if (!page.isProcessing && page.controller && page.controller.validate()) {
            page.controller.createIssue();
        }
    }

    // Função pública para cancelar (usada pelo botão global e pela tecla ESC)
    // Esconde a janela ao invés de fechar a aplicação
    function onCancelRequested() {
        if (!page.isProcessing) {
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
        page.summaryField.forceActiveFocus();

        // Inicializar worklog com data/hora atual se não estiver definido
        if (page._ctxIssueModel && (!page._ctxIssueModel.worklogInicio || page._ctxIssueModel.worklogInicio === "")) {
            var now = new Date();
            var dateStr = Qt.formatDateTime(now, "yyyy-MM-dd");
            var timeStr = Qt.formatDateTime(now, "HH:mm:ss");
            page._ctxIssueModel.worklogInicio = dateStr + " " + timeStr;
        }

        // Criar controller
        var component = Qt.createComponent("../controllers/IssueFormController.qml");
        if (component.status === Component.Ready) {
            page.controller = component.createObject(page, {
                jiraService: page._ctxJiraService,
                issueModel: page._ctxIssueModel,
                enabled: true
            });

            // Conectar signals do controller
            page.controller.createStarted.connect(function () {
                page.isProcessing = true;
                page.progressDialog = DialogHelpers.showProgress(page, "../components/dialogs/ProgressDialog.qml");
            });

            page.controller.createCompleted.connect(function (issueKey, issueUrl) {
                page.isProcessing = false;
                DialogHelpers.hideProgress(page.progressDialog);
                page.progressDialog = null;
                DialogHelpers.showSuccess(page, "../components/dialogs/SuccessDialog.qml", issueKey, issueUrl || "", false);
                page.resetForm();
                page.issueCreated(issueKey);
            });

            page.controller.createFailed.connect(function (errorMessage) {
                page.isProcessing = false;
                DialogHelpers.hideProgress(page.progressDialog);
                page.progressDialog = null;
                DialogHelpers.showError(page, "../components/dialogs/ErrorDialog.qml", errorMessage);
            });
        }
    }

    // Conectar signals do jiraService para progresso
    Connections {
        target: page._ctxJiraService

        function onProgressUpdated(percentage, message) {
            if (page.progressDialog) {
                page.progressDialog.updateProgress(percentage, message);
            }
        }
    }

    // Wrapper para ter splitView e overlay de resize como irmãos
    Item {
        anchors.fill: parent

        Controls.SplitView {
            id: splitView
            anchors.fill: parent
            orientation: Qt.Horizontal
            handle: SplitViewHandle { }

            // Coluna Esquerda: Summary, Description e Epic Parent (ScrollView único com dividers)
            Controls.ScrollView {
                id: leftScrollView
                Controls.SplitView.preferredWidth: parent.width * 0.6
                Controls.SplitView.minimumWidth: 400
                clip: true
                contentWidth: availableWidth

                // Propriedades para alturas das seções (redimensionáveis via dividers)
                property real topSectionHeight: 300
                property real epicSectionHeight: 300

                Item {
                    width: leftScrollView.width
                    implicitHeight: leftColumn.implicitHeight

                    ColumnLayout {
                        id: leftColumn
                        anchors.fill: parent
                        anchors.leftMargin: 20
                        anchors.rightMargin: 20
                        spacing: 0

                        // Seção superior: Summary e Description
                        ColumnLayout {
                            id: topSection
                            Layout.fillWidth: true
                            Layout.preferredHeight: leftScrollView.topSectionHeight
                        Layout.minimumHeight: 450
                        spacing: 0

                        ColumnLayout {
                            Layout.fillWidth: true
                            // Layout.margins: 20
                            // Layout.bottomMargin: 10
                            spacing: Kirigami.Units.smallSpacing

                            Controls.Label {
                                text: qsTr("Summary:")
                                font.bold: true
                                Layout.fillWidth: true
                            }

                            Controls.TextField {
                                id: summaryField
                                Layout.fillWidth: true
                                enabled: !isProcessing
                                text: page._ctxIssueModel ? page._ctxIssueModel.summary : ""
                                onTextChanged: if (page._ctxIssueModel) page._ctxIssueModel.summary = text
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            // Layout.margins: 20
                            // Layout.topMargin: 0
                            spacing: Kirigami.Units.smallSpacing

                            Controls.Label {
                                text: qsTr("Description:")
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
                                    text: page._ctxIssueModel ? page._ctxIssueModel.description : ""
                                    onTextChanged: if (page._ctxIssueModel) page._ctxIssueModel.description = text
                                }
                            }
                        }

                        Item {
                            Layout.fillHeight: true
                            Layout.fillWidth: true
                        }
                    }

                        DividerBar {
                            id: divider1
                            Layout.fillWidth: true
                        }

                        // Seção Epic Parent
                        ColumnLayout {
                            id: epicSection
                            Layout.fillWidth: true
                            Layout.preferredHeight: leftScrollView.epicSectionHeight
                            Layout.minimumHeight: 450
                            spacing: Kirigami.Units.smallSpacing

                            Controls.Label {
                                text: qsTr("Epic Parent:")
                                font.bold: true
                                Layout.fillWidth: true
                            }

                            EpicSearchForm {
                                id: epicSearchForm
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                enabled: !isProcessing

                                Binding {
                                    target: page.epicSearchForm
                                    property: "jiraService"
                                    value: typeof jiraService !== "undefined" ? jiraService : null
                                    when: typeof jiraService !== "undefined"
                                }

                                Binding {
                                    target: page._ctxIssueModel
                                    property: "epicParentKey"
                                    value: page.epicSearchForm.selectedEpicKey
                                    when: page._ctxIssueModel
                                }

                                Binding {
                                    target: page._ctxIssueModel
                                    property: "epicParentSummary"
                                    value: page.epicSearchForm.selectedEpicSummary
                                    when: page._ctxIssueModel
                                }

                                onEpicSelected: function (key, summary) {
                                    if (page._ctxIssueModel) {
                                        page._ctxIssueModel.epicParentKey = key;
                                        page._ctxIssueModel.epicParentSummary = summary;
                                    }
                                    page.epicSelected(key, summary);
                                }

                                onEpicCleared: {
                                    page.sharedEpicKey = "";
                                    page.sharedEpicSummary = "";
                                    if (page._ctxIssueModel) {
                                        page._ctxIssueModel.epicParentKey = "";
                                        page._ctxIssueModel.epicParentSummary = "";
                                    }
                                }

                                Binding {
                                    target: page.epicSearchForm
                                    property: "selectedEpicKey"
                                    value: page.sharedEpicKey
                                    when: page.sharedEpicKey !== ""
                                }

                                Binding {
                                    target: page.epicSearchForm
                                    property: "selectedEpicSummary"
                                    value: page.sharedEpicSummary
                                    when: page.sharedEpicSummary !== ""
                                }

                                Binding {
                                    target: page.epicSearchForm
                                    property: "selectedEpicKey"
                                    value: page._ctxIssueModel ? page._ctxIssueModel.epicParentKey : ""
                                    when: page._ctxIssueModel
                                }

                                Binding {
                                    target: page.epicSearchForm
                                    property: "selectedEpicSummary"
                                    value: page._ctxIssueModel ? page._ctxIssueModel.epicParentSummary : ""
                                    when: page._ctxIssueModel
                                }
                            }
                        }

                        DividerBar {
                            id: divider2
                            Layout.fillWidth: true
                        }

                        // Espaço final (fillHeight para permitir redimensionamento do epicSection)
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
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

                Item {
                    width: rightScrollView.availableWidth
                    implicitHeight: rightColumn.implicitHeight + 40

                    ColumnLayout {
                        id: rightColumn
                        anchors.fill: parent
                        anchors.leftMargin: 20
                        spacing: Kirigami.Units.largeSpacing

                        // Worklog (Primeiro campo, conforme solicitado)
                        Controls.CheckBox {
                            id: worklogCheckbox
                            text: qsTr("Registrar worklog")
                            Layout.fillWidth: true
                            enabled: !isProcessing
                            checked: page._ctxIssueModel ? page._ctxIssueModel.registrarWorklog : false
                            onCheckedChanged: {
                                if (page._ctxIssueModel) {
                                    page._ctxIssueModel.registrarWorklog = checked;
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
                                target: page._ctxIssueModel
                                property: "worklogInicio"
                                value: page.worklogForm.date && page.worklogForm.time ? page.worklogForm.date + " " + page.worklogForm.time : ""
                                when: page._ctxIssueModel && page.worklogForm.date && page.worklogForm.time
                            }

                            Binding {
                                target: page._ctxIssueModel
                                property: "worklogDuracao"
                                value: Math.round(page.worklogForm.duration)
                                when: page._ctxIssueModel
                            }

                            Binding {
                                target: page._ctxIssueModel
                                property: "worklogComment"
                                value: page.worklogForm.comment
                                when: page._ctxIssueModel
                            }

                            // Binding reverso para inicializar campos
                            Component.onCompleted: {
                                if (page._ctxIssueModel && page._ctxIssueModel.worklogInicio) {
                                    var parts = page._ctxIssueModel.worklogInicio.split(" ");
                                    if (parts.length >= 2) {
                                        page.worklogForm.date = parts[0];
                                        page.worklogForm.time = parts[1];
                                    }
                                }
                                if (page._ctxIssueModel) {
                                    page.worklogForm.duration = page._ctxIssueModel.worklogDuracao || 30;
                                    page.worklogForm.comment = page._ctxIssueModel.worklogComment || "";
                                }
                            }
                        }

                        IssueMetadataFields {
                            Layout.fillWidth: true
                            issueModel: page._ctxIssueModel
                            enabled: !isProcessing
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

        // Overlay para redimensionar dividers (irmão do splitView, cobre só a coluna esquerda)
        Item {
            id: resizeOverlay
            z: 10
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: leftScrollView.width
            property int activeDivider: 0
            property real startGlobalY: 0
            property real startHeight: 0

            MouseArea {
                anchors.fill: parent
                hoverEnabled: false
                cursorShape: parent.activeDivider ? Qt.SizeVerCursor : Qt.ArrowCursor
                onPressed: function (mouse) {
                    var margin = 8;
                    var p1 = divider1.mapToItem(resizeOverlay, 0, 0);
                    if (mouse.y >= p1.y - margin && mouse.y < p1.y + divider1.height + margin) {
                        resizeOverlay.activeDivider = 1;
                        resizeOverlay.startGlobalY = resizeOverlay.mapToGlobal(mouse.x, mouse.y).y;
                        resizeOverlay.startHeight = leftScrollView.topSectionHeight;
                        mouse.accepted = true;
                        return;
                    }
                    var p2 = divider2.mapToItem(resizeOverlay, 0, 0);
                    if (mouse.y >= p2.y - margin && mouse.y < p2.y + divider2.height + margin) {
                        resizeOverlay.activeDivider = 2;
                        resizeOverlay.startGlobalY = resizeOverlay.mapToGlobal(mouse.x, mouse.y).y;
                        resizeOverlay.startHeight = leftScrollView.epicSectionHeight;
                        mouse.accepted = true;
                        return;
                    }
                    mouse.accepted = false;
                }
                onPositionChanged: function (mouse) {
                    if (resizeOverlay.activeDivider === 0) return;
                    var cur = resizeOverlay.mapToGlobal(mouse.x, mouse.y).y;
                    var delta = cur - resizeOverlay.startGlobalY;
                    if (resizeOverlay.activeDivider === 1) {
                        leftScrollView.topSectionHeight = Math.max(150, resizeOverlay.startHeight + delta);
                    } else if (resizeOverlay.activeDivider === 2) {
                        leftScrollView.epicSectionHeight = Math.max(150, resizeOverlay.startHeight + delta);
                    }
                }
                onReleased: {
                    resizeOverlay.activeDivider = 0;
                }
            }
        }
    }

    // Funções auxiliares
    function resetForm() {
        // Resetar campos para valores padrão
        if (page._ctxIssueModel) {
            page._ctxIssueModel.summary = "";
            page._ctxIssueModel.description = "";

            // Tipo de atividade padrão
            var defaultTipo = "Suporte Dúvidas/Suporte uso incorreto";
            var tipoValues = page._ctxIssueModel.tipoAtividadeValues;
            if (tipoValues.indexOf(defaultTipo) >= 0) {
                page._ctxIssueModel.tipoAtividade = defaultTipo;
            } else if (tipoValues.length > 0) {
                page._ctxIssueModel.tipoAtividade = tipoValues[0];
            }

            // Status inicial padrão
            if (page._ctxIssueModel.statusSequence && page._ctxIssueModel.statusSequence.length > 0) {
                page._ctxIssueModel.statusInicial = page._ctxIssueModel.statusSequence[0];
            }

            // Valores padrão
            page._ctxIssueModel.documentacaoAnexa = "Não";
            page._ctxIssueModel.utilizacaoIA = "Não";

            // Resetar Valor Entregue e Plataformas afetadas
            var valorEntregueValues = page._ctxIssueModel.valorEntregueValues;
            if (valorEntregueValues && valorEntregueValues.length > 0) {
                page._ctxIssueModel.valorEntregue = valorEntregueValues[0];
            } else {
                page._ctxIssueModel.valorEntregue = "";
            }
            page._ctxIssueModel.plataformasAfetadas = [];

            // Limpar Epic Parent
            page._ctxIssueModel.epicParentKey = "";
            page._ctxIssueModel.epicParentSummary = "";
            if (page.epicSearchForm) {
                page.epicSearchForm.reset();
            }

            // Resetar worklog
            page._ctxIssueModel.registrarWorklog = false;
            var now = new Date();
            var dateStr = Qt.formatDateTime(now, "yyyy-MM-dd");
            var timeStr = Qt.formatDateTime(now, "HH:mm:ss");
            page._ctxIssueModel.worklogInicio = dateStr + " " + timeStr;
            page._ctxIssueModel.worklogDuracao = 30;
            if (page.worklogForm) {
                page.worklogForm.reset();
            }
        }
    }

    function validateForm() {
        if (page.controller) {
            return page.controller.validate();
        }
        return false;
    }

}
