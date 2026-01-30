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
                page.progressDialog = DialogHelpers.showProgress(page, "../components/dialogs/ProgressDialog.qml");
            });

            controller.createCompleted.connect(function (issueKey, issueUrl) {
                isProcessing = false;
                DialogHelpers.hideProgress(page.progressDialog);
                page.progressDialog = null;
                DialogHelpers.showSuccess(page, "../components/dialogs/SuccessDialog.qml", issueKey, issueUrl || "", false);
                resetForm();
                page.issueCreated(issueKey);
            });

            controller.createFailed.connect(function (errorMessage) {
                isProcessing = false;
                DialogHelpers.hideProgress(page.progressDialog);
                page.progressDialog = null;
                DialogHelpers.showError(page, "../components/dialogs/ErrorDialog.qml", errorMessage);
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

    // Wrapper para ter splitView e overlay de resize como irmãos
    Item {
        anchors.fill: parent

        Controls.SplitView {
            id: splitView
            anchors.fill: parent
            orientation: Qt.Horizontal

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
                                text: issueModel ? issueModel.summary : ""
                                onTextChanged: if (issueModel) issueModel.summary = text
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
                                    text: issueModel ? issueModel.description : ""
                                    onTextChanged: if (issueModel) issueModel.description = text
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
                                    target: epicSearchForm
                                    property: "jiraService"
                                    value: typeof jiraService !== "undefined" ? jiraService : null
                                    when: typeof jiraService !== "undefined"
                                }

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

                                onEpicSelected: function (key, summary) {
                                    if (issueModel) {
                                        issueModel.epicParentKey = key;
                                        issueModel.epicParentSummary = summary;
                                    }
                                    page.epicSelected(key, summary);
                                }

                                onEpicCleared: {
                                    page.sharedEpicKey = "";
                                    page.sharedEpicSummary = "";
                                    if (issueModel) {
                                        issueModel.epicParentKey = "";
                                        issueModel.epicParentSummary = "";
                                    }
                                }

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

}
