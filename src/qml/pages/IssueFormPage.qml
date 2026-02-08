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
import "../utils/DialogHelpers.js" as DialogHelpers
Kirigami.Page {
    id: page

    title: "Preencha os dados da issue abaixo:"

    property var applicationWindow: null

    // Habilitar foco para capturar atalhos de teclado
    focus: true

    // Estado do processamento
    property bool isProcessing: false

    // Registrar worklog só permitido quando status inicial é IN DEVELOPMENT ou posterior
    property bool registrarWorklogEnabled: {
        if (!issueModel || !issueModel.statusSequence) return false
        var seq = issueModel.statusSequence
        var inDevIdx = seq.indexOf("IN DEVELOPMENT")
        if (inDevIdx < 0) return false
        var statusIdx = seq.indexOf(issueModel.statusInicial || "")
        return statusIdx >= inDevIdx
    }

    // Contador para placeholders de anexos na descrição (nova issue)
    property int _descriptionPlaceholderCounter: 0
    property var _allowedAttachmentExtensions: ["png", "jpg", "jpeg", "gif", "webp"]

    // Propriedades compartilhadas para sincronizar epic entre abas
    property string sharedEpicKey: ""
    property string sharedEpicSummary: ""

    signal epicSelected(string key, string summary)
    signal issueCreated(string issueKey)  // Emitido quando uma issue é criada com sucesso

    property var progressDialog: null

    // Controller para lógica de negócio
    property var controller: null

    // Recebidos do Main (passados explicitamente)
    property var issueModel: null
    property var jiraService: null
    property var clipboardHelper: null
    property var hideWindowFn: null
    property var timerService: null
    property var timerModel: null
    property var _ctxVoiceInputService: typeof voiceInputService !== "undefined" ? voiceInputService : null // qmllint disable unqualified

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

    function openVoiceDialog() {
        if (voiceDialogLoader.item && page._ctxVoiceInputService !== null && page._ctxVoiceInputService.isAvailable()) {
            voiceDialogLoader.item.open(); // qmllint disable missing-property
        }
    }

    // Função pública para cancelar (usada pelo botão global e pela tecla ESC)
    // Esconde a janela ao invés de fechar a aplicação
    function onCancelRequested() {
        if (!page.isProcessing) {
            if (page.hideWindowFn && typeof page.hideWindowFn === "function") {
                page.hideWindowFn(); // qmllint disable use-proper-function
            }
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

        // Pré-carregar ProgressDialog para que createComponent em showProgress esteja em cache quando o utilizador clicar
        Qt.createComponent("../components/dialogs/ProgressDialog.qml");

        // Inicializar worklog com data/hora atual se não estiver definido
        if (page.issueModel && (!page.issueModel.worklogInicio || page.issueModel.worklogInicio === "")) {
            var now = new Date();
            var dateStr = Qt.formatDateTime(now, "yyyy-MM-dd");
            var timeStr = Qt.formatDateTime(now, "HH:mm:ss");
            page.issueModel.worklogInicio = dateStr + " " + timeStr;
        }

        // Criar controller
        var component = Qt.createComponent("../controllers/IssueFormController.qml");
        if (component.status === Component.Ready) {
            page.controller = component.createObject(page, {
                jiraService: page.jiraService,
                issueModel: page.issueModel,
                enabled: true
            });

            page.controller.createStarted.connect(function () {
                page.isProcessing = true;
                page.progressDialog = DialogHelpers.showProgress(page, "../components/dialogs/ProgressDialog.qml", function (dlg) {
                    page.progressDialog = dlg;
                });
            });

            page.controller.createCompleted.connect(function (issueKey, issueUrl) {
                page.isProcessing = false;
                DialogHelpers.hideProgress(page.progressDialog);
                page.progressDialog = null;
                DialogHelpers.showSuccess(page, "../components/dialogs/SuccessDialog.qml", issueKey, issueUrl || "", false, page.timerService, page.timerModel, page.jiraService, page.applicationWindow);
                page.resetForm();
                page.issueCreated(issueKey);
            });

            page.controller.createFailed.connect(function (errorMessage) {
                page.isProcessing = false;
                DialogHelpers.hideProgress(page.progressDialog);
                page.progressDialog = null;
                DialogHelpers.showError(page, "../components/dialogs/ErrorDialog.qml", errorMessage, "IssueFormPage.jiraService");
            });
        }
    }

    // Conectar signals do jiraService para progresso
    Connections {
        target: page.jiraService

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

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing

                                Controls.Label {
                                    text: qsTr("Summary:")
                                    font.bold: true
                                    Layout.fillWidth: true
                                }

                                Controls.ToolButton {
                                    visible: page._ctxVoiceInputService !== null && page._ctxVoiceInputService.isAvailable()
                                    icon.name: "audio-input-microphone"
                                    text: qsTr("Criar por voz")
                                    onClicked: {
                                        if (voiceDialogLoader.item) {
                                            voiceDialogLoader.item.open() // qmllint disable missing-property
                                        }
                                    }
                                }
                                Controls.ToolButton {
                                    visible: page._ctxVoiceInputService !== null && page._ctxVoiceInputService.isAvailable()
                                    icon.name: "edit-find"
                                    text: qsTr("Expandir com IA")
                                    enabled: !page.isProcessing && page.issueModel && (page.issueModel.summary || page.issueModel.description)
                                    onClicked: {
                                        if (page._ctxVoiceInputService && page.issueModel) {
                                            page._ctxVoiceInputService.expandFromSummaryAndDescription(
                                                page.issueModel.summary || "",
                                                page.issueModel.description || "",
                                                false
                                            );
                                        }
                                    }
                                }
                            }

                            Controls.TextField {
                                id: summaryField
                                Layout.fillWidth: true
                                enabled: !page.isProcessing
                                text: page.issueModel ? page.issueModel.summary : ""
                                onTextChanged: if (page.issueModel) page.issueModel.summary = text
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

                            // DropArea como container: cliques vão para o filho (ScrollView/TextArea), drops para o DropArea.
                            Item {
                                id: descriptionContainer
                                Layout.fillWidth: true
                                Layout.fillHeight: true

                                DropArea {
                                    anchors.fill: parent
                                    enabled: !page.isProcessing
                                    onEntered: function(drag) {
                                        console.log("[DEBUG] IssueFormPage DropArea onEntered, drag.urls:", drag.urls ? drag.urls.length : 0)
                                    }
                                    onExited: {
                                        console.log("[DEBUG] IssueFormPage DropArea onExited")
                                    }
                                    onDropped: function(drop) {
                                        console.log("[DEBUG] IssueFormPage DropArea onDropped, drop.urls:", drop.urls ? drop.urls.length : 0, "issueModel:", !!page.issueModel, "clipboardHelper:", !!page.clipboardHelper)
                                        if (!drop.urls || drop.urls.length === 0 || !page.issueModel) {
                                            console.log("[DEBUG] IssueFormPage onDropped: saída cedo (sem urls ou issueModel)")
                                            return
                                        }
                                        var extList = page._allowedAttachmentExtensions || []
                                        for (var i = 0; i < drop.urls.length; i++) {
                                            var urlStr = drop.urls[i].toString()
                                            var path = urlStr.replace(/^file:\/\//, "")
                                            var filename = path.split("/").pop() || path.split("\\").pop() || "file"
                                            var ext = filename.indexOf(".") >= 0 ? filename.split(".").pop().toLowerCase() : ""
                                            console.log("[DEBUG] IssueFormPage onDropped file:", filename, "ext:", ext, "allowed:", extList.indexOf(ext) >= 0)
                                            if (extList.indexOf(ext) < 0) continue
                                            var pathToUse = ""
                                            if (page.clipboardHelper && typeof page.clipboardHelper.copyFileToTemp === "function") {
                                                pathToUse = page.clipboardHelper.copyFileToTemp(path)
                                                console.log("[DEBUG] IssueFormPage onDropped copyFileToTemp result:", pathToUse ? "ok" : "vazio")
                                            } else {
                                                console.log("[DEBUG] IssueFormPage onDropped: sem clipboardHelper ou copyFileToTemp")
                                            }
                                            if (!pathToUse) continue
                                            page._descriptionPlaceholderCounter += 1
                                            var placeholderId = "p" + page._descriptionPlaceholderCounter
                                            var list = page.issueModel.pendingAttachments || []
                                            list.push({ path: pathToUse, filename: filename, placeholderId: placeholderId })
                                            page.issueModel.pendingAttachments = list
                                            var markdown = "![" + filename + "](pending:" + placeholderId + ")"
                                            descriptionField.insert(descriptionField.cursorPosition, markdown)
                                            if (page.issueModel) page.issueModel.description = descriptionField.text
                                            console.log("[DEBUG] IssueFormPage onDropped: placeholder inserido", placeholderId)
                                        }
                                    }

                                    Controls.ScrollView {
                                        id: descriptionScrollView
                                        anchors.fill: parent
                                        clip: true
                                        contentWidth: descriptionField.implicitWidth

                                        Controls.TextArea {
                                            id: descriptionField
                                            width: descriptionContainer.width
                                            wrapMode: Controls.TextArea.Wrap
                                            enabled: !page.isProcessing
                                            placeholderText: qsTr("Arraste imagens ou use Ctrl+V para colar; o link será inserido em markdown.")
                                            text: page.issueModel ? page.issueModel.description : ""
                                            onTextChanged: if (page.issueModel) page.issueModel.description = text

                                            Keys.onPressed: function(event) {
                                                if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V) {
                                                    console.log("[DEBUG] IssueFormPage descriptionField Keys.onPressed Ctrl+V, clipboardHelper:", !!page.clipboardHelper, "issueModel:", !!page.issueModel)
                                                    if (!page.clipboardHelper || !page.issueModel) return
                                                    var hasImage = page.clipboardHelper.hasClipboardImage()
                                                    console.log("[DEBUG] IssueFormPage hasClipboardImage:", hasImage)
                                                    if (hasImage) {
                                                        var tempPath = page.clipboardHelper.getClipboardImageAsTempFile()
                                                        console.log("[DEBUG] IssueFormPage getClipboardImageAsTempFile result:", tempPath ? "ok" : "vazio")
                                                        if (tempPath) {
                                                            page._descriptionPlaceholderCounter += 1
                                                            var pid = "p" + page._descriptionPlaceholderCounter
                                                            var list = page.issueModel.pendingAttachments || []
                                                            list.push({ path: tempPath, filename: "paste.png", placeholderId: pid })
                                                            page.issueModel.pendingAttachments = list
                                                            descriptionField.insert(descriptionField.cursorPosition, "![paste.png](pending:" + pid + ")")
                                                            if (page.issueModel) page.issueModel.description = descriptionField.text
                                                            event.accepted = true
                                                            console.log("[DEBUG] IssueFormPage paste: placeholder inserido", pid)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
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
                                enabled: !page.isProcessing

                                Binding {
                                    target: epicSearchForm
                                    property: "jiraService"
                                    value: typeof page.jiraService !== "undefined" ? page.jiraService : null
                                    when: typeof page.jiraService !== "undefined"
                                }

                                Binding {
                                    target: page.issueModel
                                    property: "epicParentKey"
                                    value: epicSearchForm.selectedEpicKey
                                    when: page.issueModel
                                }

                                Binding {
                                    target: page.issueModel
                                    property: "epicParentSummary"
                                    value: epicSearchForm.selectedEpicSummary
                                    when: page.issueModel
                                }

                                onEpicSelected: function (key, summary) {
                                    if (page.issueModel) {
                                        page.issueModel.epicParentKey = key;
                                        page.issueModel.epicParentSummary = summary;
                                    }
                                    page.epicSelected(key, summary);
                                }

                                onEpicCleared: {
                                    page.sharedEpicKey = "";
                                    page.sharedEpicSummary = "";
                                    if (page.issueModel) {
                                        page.issueModel.epicParentKey = "";
                                        page.issueModel.epicParentSummary = "";
                                    }
                                }

                                // Epic no formulário de criação vem apenas do modelo de criação (issueModel),
                                // não de sharedEpicKey (que é atualizado pela aba Minhas Issues)
                                Binding {
                                    target: epicSearchForm
                                    property: "selectedEpicKey"
                                    value: page.issueModel ? page.issueModel.epicParentKey : ""
                                    when: page.issueModel
                                }

                                Binding {
                                    target: epicSearchForm
                                    property: "selectedEpicSummary"
                                    value: page.issueModel ? page.issueModel.epicParentSummary : ""
                                    when: page.issueModel
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

                        // Worklog (habilitado só quando status inicial é IN DEVELOPMENT ou posterior)
                        Controls.CheckBox {
                            id: worklogCheckbox
                            text: qsTr("Registrar worklog")
                            Layout.fillWidth: true
                            enabled: !page.isProcessing && page.registrarWorklogEnabled
                            checked: page.issueModel ? page.issueModel.registrarWorklog : false
                            onCheckedChanged: {
                                if (page.issueModel) {
                                    page.issueModel.registrarWorklog = checked;
                                }
                            }
                        }
                        Binding {
                            target: page.issueModel
                            property: "registrarWorklog"
                            value: false
                            when: page.issueModel && !page.registrarWorklogEnabled
                        }

                        // WorklogForm (oculto quando checkbox não está marcado)
                        WorklogForm {
                            id: worklogForm
                            jiraService: page.jiraService
                            Layout.fillWidth: true
                            enabled: !page.isProcessing && worklogCheckbox.checked
                            visible: worklogCheckbox.checked
                            showCheckbox: false  // Não mostrar checkbox aqui, já temos acima

                            // Bindings bidirecionais com issueModel
                            Binding {
                                target: page.issueModel
                                property: "worklogInicio"
                                value: worklogForm.date && worklogForm.time ? worklogForm.date + " " + worklogForm.time : ""
                                when: page.issueModel && worklogForm.date && worklogForm.time
                            }

                            Binding {
                                target: page.issueModel
                                property: "worklogDuracao"
                                value: Math.round(worklogForm.duration)
                                when: page.issueModel
                            }

                            Binding {
                                target: page.issueModel
                                property: "worklogComment"
                                value: worklogForm.comment
                                when: page.issueModel
                            }

                            // Binding reverso para inicializar campos
                            Component.onCompleted: {
                                if (page.issueModel && page.issueModel.worklogInicio) {
                                    var parts = page.issueModel.worklogInicio.split(" ");
                                    if (parts.length >= 2) {
                                        worklogForm.date = parts[0];
                                        worklogForm.time = parts[1];
                                    }
                                }
                                if (page.issueModel) {
                                    worklogForm.duration = page.issueModel.worklogDuracao || 30;
                                    worklogForm.comment = page.issueModel.worklogComment || "";
                                }
                            }
                        }

                        IssueMetadataFields {
                            Layout.fillWidth: true
                            issueModel: page.issueModel
                            enabled: !page.isProcessing
                            restrictStatusBySequence: false
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

    // Overlay de loading durante "Expandir com IA" (bloqueia a página)
    Item {
        anchors.fill: parent
        visible: page._ctxVoiceInputService !== null && page._ctxVoiceInputService.isExpanding
        z: 100

        Rectangle {
            anchors.fill: parent
            color: Kirigami.Theme.backgroundColor
            opacity: 0.85
        }
        MouseArea {
            anchors.fill: parent
            onPressed: function (event) { event.accepted = true }
            onReleased: function (event) { event.accepted = true }
        }
        ColumnLayout {
            anchors.centerIn: parent
            spacing: Kirigami.Units.largeSpacing

            Controls.BusyIndicator {
                Layout.alignment: Qt.AlignHCenter
                running: parent.parent.visible
            }
            Controls.Label {
                text: qsTr("A processar com IA…")
                Layout.alignment: Qt.AlignHCenter
            }
        }
    }

    Loader {
        id: voiceDialogLoader
        active: page._ctxVoiceInputService !== null && page._ctxVoiceInputService.isAvailable()
        source: "../components/dialogs/VoiceInputDialog.qml"
        onLoaded: {
            if (item) {
                // qmllint disable missing-property
                item.fieldsFilled.connect(function() { item.close(); })
                item.errorMessage.connect(function(msg) {
                    DialogHelpers.showError(page, "../components/dialogs/ErrorDialog.qml", msg, "IssueFormPage.voiceOrOther");
                })
                // qmllint enable missing-property
            }
        }
    }

    // Funções auxiliares
    function resetForm() {
        // Resetar campos para valores padrão
        if (page.issueModel) {
            page.issueModel.summary = "";
            page.issueModel.description = "";

            // Tipo de atividade padrão
            var defaultTipo = "Suporte Dúvidas/Suporte uso incorreto";
            var tipoValues = page.issueModel.tipoAtividadeValues;
            if (tipoValues.indexOf(defaultTipo) >= 0) {
                page.issueModel.tipoAtividade = defaultTipo;
            } else if (tipoValues.length > 0) {
                page.issueModel.tipoAtividade = tipoValues[0];
            }

            // Status inicial padrão
            if (page.issueModel.statusSequence && page.issueModel.statusSequence.length > 0) {
                page.issueModel.statusInicial = page.issueModel.statusSequence[0];
            }

            // Valores padrão
            page.issueModel.documentacaoAnexa = "Não";
            page.issueModel.utilizacaoIA = "Não";

            // Resetar Valor Entregue e Plataformas afetadas
            var valorEntregueValues = page.issueModel.valorEntregueValues;
            if (valorEntregueValues && valorEntregueValues.length > 0) {
                page.issueModel.valorEntregue = valorEntregueValues[0];
            } else {
                page.issueModel.valorEntregue = "";
            }
            page.issueModel.plataformasAfetadas = [];

            // Limpar Epic Parent
            page.issueModel.epicParentKey = "";
            page.issueModel.epicParentSummary = "";
            if (epicSearchForm) {
                epicSearchForm.reset();
            }

            // Resetar worklog
            page.issueModel.registrarWorklog = false;
            var now = new Date();
            var dateStr = Qt.formatDateTime(now, "yyyy-MM-dd");
            var timeStr = Qt.formatDateTime(now, "HH:mm:ss");
            page.issueModel.worklogInicio = dateStr + " " + timeStr;
            page.issueModel.worklogDuracao = 30;
            if (worklogForm) {
                worklogForm.reset();
            }

            // Limpar anexos pendentes da descrição
            page.issueModel.pendingAttachments = [];
            page._descriptionPlaceholderCounter = 0;
        }
    }

    function validateForm() {
        if (page.controller) {
            return page.controller.validate();
        }
        return false;
    }

}
