/**
 * MyIssuesPage.qml
 *
 * Página para listar issues do usuário e atualizar issues selecionadas
 * Refatorado seguindo Clean Code e SOLID
 * Usa componentes reutilizáveis e controllers
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import QtQuick.Controls
import org.kde.kirigami as Kirigami
import "../components/forms"
import "../components/lists"
import "../controllers"

Kirigami.Page {
    id: page

    title: qsTr("Minhas Issues")

    // Habilitar foco para capturar atalhos de teclado
    focus: true

    // Issue selecionada atualmente
    property string selectedIssueKey: ""

    // Status original da issue (para comparar antes de atualizar)
    property string originalStatus: ""

    // Estado do processamento
    property bool isProcessing: false

    // Propriedades compartilhadas para sincronizar epic entre abas
    property string sharedEpicKey: ""
    property string sharedEpicSummary: ""

    signal epicSelected(string key, string summary)
    // Estado de carregamento dos detalhes da issue (parte inferior)
    property bool isDetailsLoading: false

    // Flag para controlar busca automática inicial (apenas uma vez)
    property bool initialSearchDone: false

    // Diálogos
    property var progressDialog: null
    property var successDialog: null
    property var searchProgressDialog: null

    // Controller para lógica de negócio
    property var controller: null

    // Função pública para cancelar (usada pelo botão global e pela tecla ESC)
    // Esconde a janela ao invés de fechar a aplicação
    function onCancelRequested() {
        if (typeof hideWindow === "function") {
            hideWindow();  // Esconde a janela (minimiza ao tray)
        }
        // Se hideWindow não estiver disponível, não fazer nada
        // (a aplicação deve estar configurada corretamente)
    }

    // Ações da página (Kirigami 6 usa 'actions' ao invés de 'mainAction')
    actions: [
        Kirigami.Action {
            id: refreshAction
            text: qsTr("Buscar")
            icon.name: "search"
            enabled: !(myIssuesModel && myIssuesModel.isLoading)
            onTriggered: {
                if (issueSearchForm) {
                    var query = issueSearchForm.getQuery();
                    page.refreshIssues(query);
                }
            }
        }
    ]

    // Função pública para botão global (Main.qml)
    function refreshIssuesFromToolbar() {
        if (issueSearchForm) {
            var query = issueSearchForm.getQuery();
            page.refreshIssues(query);
        }
    }

    // Função pública para iniciar timer do header (Main.qml)
    function startTimerFromToolbar() {
        if (!timerService || !timerModel || !selectedIssueKey) {
            return;
        }

        // Se está em pausa, cancelar pausa e iniciar timer
        if (timerModel && timerModel.isOnBreak) {
            timerService.cancelBreak();
            Qt.callLater(function () {
                if (timerService && selectedIssueKey) {
                    timerService.start(selectedIssueKey);
                }
            });
            return;
        }

        // Se já há timer ativo para esta issue
        if (timerModel.issueKey === selectedIssueKey && timerModel.state !== "idle") {
            if (timerModel.state === "running") {
                timerService.stop();
            }
        } else
        // Se há timer ativo para outra issue, parar e iniciar novo
        if (timerModel.state !== "idle" && timerModel.issueKey !== selectedIssueKey) {
            // Parar timer atual e iniciar novo
            timerService.stop();
            // Usar callLater para garantir que o stop termine antes de iniciar
            Qt.callLater(function () {
                if (timerService && selectedIssueKey) {
                    timerService.start(selectedIssueKey);
                }
            });
        } else
        // Iniciar novo timer
        {
            timerService.start(selectedIssueKey);
        }
    }

    // Atalhos locais (Ctrl+Enter e ESC)
    Keys.onPressed: function (event) {
        // Ctrl+Enter: atualizar lista
        if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
            refreshIssuesFromToolbar();
            event.accepted = true;
            return;
        }

        // ESC: cancelar
        if (event.key === Qt.Key_Escape) {
            onCancelRequested();
            event.accepted = true;
        }
    }

    function refreshIssues(query) {
        if (!myIssuesModel) {
            return;
        }

        // Fechar diálogo anterior se existir
        if (searchProgressDialog) {
            searchProgressDialog.close();
            searchProgressDialog.destroy();
            searchProgressDialog = null;
        }

        // Mostrar diálogo de progresso durante a busca
        var component = Qt.createComponent("../components/dialogs/ProgressDialog.qml");
        if (component.status === Component.Ready) {
            var window = page.parent && page.parent.parent ? page.parent.parent : page;
            searchProgressDialog = component.createObject(window);
            if (searchProgressDialog) {
                searchProgressDialog.open();
                searchProgressDialog.updateProgress(0, "Buscando issues...");

                // Conectar ao sinal de loading para atualizar e fechar progresso
                var loadingConnection = function (isLoading) {
                    if (isLoading) {
                        if (searchProgressDialog) {
                            searchProgressDialog.updateProgress(50, "Buscando issues...");
                        }
                    } else {
                        Qt.callLater(function () {
                            if (searchProgressDialog) {
                                searchProgressDialog.updateProgress(100, "Busca concluída!");
                                Qt.callLater(function () {
                                    if (searchProgressDialog) {
                                        searchProgressDialog.close();
                                        searchProgressDialog.destroy();
                                        searchProgressDialog = null;
                                    }

                                    // Selecionar automaticamente a primeira issue se houver resultados
                                    Qt.callLater(function () {
                                        if (myIssuesModel && myIssuesModel.issues && myIssuesModel.issues.length > 0) {
                                            var firstIssue = myIssuesModel.issues[0];
                                            if (firstIssue && firstIssue.key) {
                                                if (issueList) {
                                                    issueList.selectIssue(firstIssue.key);
                                                }
                                            }
                                        }
                                    });
                                });
                            }
                            if (myIssuesModel) {
                                myIssuesModel.loadingChanged.disconnect(loadingConnection);
                            }
                        });
                    }
                };

                if (myIssuesModel) {
                    myIssuesModel.loadingChanged.connect(loadingConnection);
                }
            }
        }

        // Iniciar busca
        if (page.controller) {
            page.controller.searchIssues(query || "");
        } else {
            myIssuesModel.refreshIssues(query || "");
        }
    }

    // Criar controller
    Component.onCompleted: {
        var component = Qt.createComponent("../controllers/MyIssuesController.qml");
        if (component.status === Component.Ready) {
            page.controller = component.createObject(page, {
                jiraService: jiraService,
                myIssuesModel: myIssuesModel,
                issueModel: issueModel,
                enabled: true
            });

            if (page.controller) {
                page.controller.updateStarted.connect(function () {
                    page.isProcessing = true;
                    page.showProgressDialog();
                });

                page.controller.updateCompleted.connect(function (issueKey) {
                    page.isProcessing = false;
                    page.hideProgressDialog();
                    page.showSuccessDialog(issueKey);
                    if (issueSearchForm) {
                        var query = issueSearchForm.getQuery();
                        page.refreshIssues(query);
                    }
                });

                page.controller.updateFailed.connect(function (errorMessage) {
                    page.isProcessing = false;
                    page.hideProgressDialog();
                    page.showErrorDialog(errorMessage);
                });

                page.controller.issueSelected.connect(function (issueKey, issueData) {
                    if (issueKey) {
                        page.selectedIssueKey = issueKey;
                        page.loadIssueDetails(issueKey);
                    }
                });
            }
        }
    }

    Controls.SplitView {
        id: splitView
        anchors.fill: parent
        orientation: Qt.Horizontal

        // Coluna Esquerda (40% - Master): Busca, Lista e Botão Timer
        Item {
            id: leftPane
            Controls.SplitView.preferredWidth: parent.width * 0.4
            Controls.SplitView.minimumWidth: 300
            Controls.SplitView.fillHeight: true

            ColumnLayout {
                id: leftColumnLayout
                anchors.fill: parent
                anchors.margins: 20
                spacing: Kirigami.Units.largeSpacing

                // Busca de issues usando componente reutilizável
                IssueSearchForm {
                    id: issueSearchForm
                    Layout.fillWidth: true
                    enabled: !page.isProcessing
                    isLoading: myIssuesModel ? myIssuesModel.isLoading : false
                    placeholderText: qsTr("Buscar issues por resumo ou chave...")

                    onSearchRequested: function (query) {
                        page.refreshIssues(query);
                    }
                }

                Controls.Label {
                    text: qsTr("Issues atribuídas a você")
                    font.bold: true
                    Layout.fillWidth: true
                }

                // Lista de issues usando componente reutilizável
                Item {
                    id: issueListContainer
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    IssueList {
                        id: issueList
                        anchors.fill: parent
                        enabled: !page.isProcessing
                        model: myIssuesModel ? myIssuesModel.issues : []
                        isLoading: myIssuesModel ? myIssuesModel.isLoading : false
                        selectedIssueKey: page.selectedIssueKey

                        onIssueSelected: function (issueKey, issueData) {
                            page.selectedIssueKey = issueKey;
                            loadIssueDetails(issueKey);
                        }
                    }
                }
            }
        }

        // Coluna Direita (60% - Detail)
        Item {
            id: detailPane
            Controls.SplitView.fillWidth: true
            Controls.SplitView.minimumWidth: 400

            Controls.ScrollView {
                id: mainDetailsScrollView
                anchors.fill: parent
                clip: true
                // Garantir que o conteúdo role apenas verticalmente
                contentWidth: availableWidth

                // SplitView Triplo (3 panes = 2 barras de separação)
                Controls.SplitView {
                    id: mainTripleSplitView
                    width: mainDetailsScrollView.availableWidth
                    // Altura implícita grande o suficiente para ativar o scroll externo se necessário
                    implicitHeight: 1500
                    orientation: Qt.Vertical

                    // Pane 1: Topo (Heading, Worklog, Summary, Description)
                    Item {
                        id: topPane
                        Controls.SplitView.preferredHeight: 450
                        Controls.SplitView.minimumHeight: 250

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 0

                            // Heading e Link
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.margins: 20
                                Layout.bottomMargin: 5

                                Kirigami.Heading {
                                    text: qsTr("Atualizar Task")
                                    level: 3
                                    Layout.fillWidth: true
                                }

                                Controls.Label {
                                    id: taskLinkLabel
                                    text: page.selectedIssueKey || ""
                                    color: Kirigami.Theme.linkColor
                                    visible: page.selectedIssueKey !== ""
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (page.jiraService && page.selectedIssueKey && typeof page.jiraService.getIssueUrl === 'function') {
                                                var url = page.jiraService.getIssueUrl(page.selectedIssueKey);
                                                if (url) {
                                                    Qt.openUrlExternally(url);
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // Summary
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.margins: 20
                                Layout.topMargin: 0
                                Layout.bottomMargin: 10
                                spacing: Kirigami.Units.smallSpacing

                                Controls.Label {
                                    text: qsTr("Summary:")
                                    font.bold: true
                                    Layout.fillWidth: true
                                }

                                Controls.TextField {
                                    id: summaryFieldTab2
                                    Layout.fillWidth: true
                                    enabled: page.selectedIssueKey !== "" && !page.isProcessing
                                    text: issueModel ? issueModel.summary : ""
                                    onTextChanged: if (issueModel)
                                        issueModel.summary = text
                                }
                            }

                            // Description (Expande para preencher o resto deste pane)
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.margins: 20
                                Layout.topMargin: 0
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
                                        id: descriptionFieldTab2
                                        width: descriptionScrollView.availableWidth
                                        wrapMode: Controls.TextArea.Wrap
                                        enabled: page.selectedIssueKey !== "" && !page.isProcessing
                                        text: issueModel ? issueModel.description : ""
                                        onTextChanged: if (issueModel)
                                            issueModel.description = text
                                    }
                                }
                            }

                            // Spacer para empurrar tudo para cima se houver espaço sobrando
                            Item {
                                Layout.fillHeight: true
                                Layout.fillWidth: true
                            }
                        }
                    }

                    // Pane 2: Epic Parent (Barra de split acima e abaixo)
                    Item {
                        id: epicPane
                        Controls.SplitView.preferredHeight: 350
                        Controls.SplitView.minimumHeight: 200

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: Kirigami.Units.smallSpacing

                            Controls.Label {
                                text: qsTr("Epic Parent:")
                                font.bold: true
                                Layout.fillWidth: true
                                Layout.leftMargin: 20
                                Layout.topMargin: 10
                            }

                            EpicSearchForm {
                                id: epicSearchForm
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.margins: 20
                                Layout.topMargin: 0
                                enabled: page.selectedIssueKey !== "" && !page.isProcessing

                                // Bindings bi-direcionais e sinais sincronizados
                                Binding {
                                    target: epicSearchForm
                                    property: "jiraService"
                                    value: typeof jiraService !== "undefined" ? jiraService : null
                                    when: typeof jiraService !== "undefined"
                                }

                                onEpicSelected: function (key, summary) {
                                    page.epicSelected(key, summary);
                                    if (issueModel) {
                                        issueModel.epicParentKey = key;
                                        issueModel.epicParentSummary = summary;
                                    }
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
                                    when: page.sharedEpicKey !== "" && page.sharedEpicKey !== epicSearchForm.selectedEpicKey
                                }

                                Binding {
                                    target: epicSearchForm
                                    property: "selectedEpicSummary"
                                    value: page.sharedEpicSummary
                                    when: page.sharedEpicSummary !== "" && page.sharedEpicSummary !== epicSearchForm.selectedEpicSummary
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
                            }

                            // Spacer para empurrar EpicSearchForm para cima
                            Item {
                                Layout.fillHeight: true
                                Layout.fillWidth: true
                            }
                        }
                    }

                    // Pane 3: Demais Campos (Status, IA, Atividade, Valor, Plataformas)
                    Item {
                        id: bottomFieldsPane
                        Controls.SplitView.preferredHeight: 700
                        Controls.SplitView.minimumHeight: 400

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 0

                            // Worklog (Movido para cá para ficar acima do Status)
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.margins: 20
                                Layout.topMargin: 10
                                Layout.bottomMargin: 10
                                spacing: Kirigami.Units.smallSpacing

                                Controls.CheckBox {
                                    id: worklogCheckboxTab2
                                    text: qsTr("Registrar worklog")
                                    Layout.fillWidth: true
                                    enabled: page.selectedIssueKey !== "" && !page.isProcessing
                                    checked: issueModel ? issueModel.registrarWorklog : false
                                    onCheckedChanged: {
                                        if (issueModel) {
                                            issueModel.registrarWorklog = checked;
                                        }
                                    }
                                }

                                WorklogForm {
                                    id: worklogForm
                                    Layout.fillWidth: true
                                    enabled: page.selectedIssueKey !== "" && !page.isProcessing && worklogCheckboxTab2.checked
                                    visible: worklogCheckboxTab2.checked
                                    showCheckbox: false

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
                            }

                            GridLayout {
                                id: bottomGridLayout
                                Layout.fillWidth: true
                                Layout.margins: 20
                                columnSpacing: Kirigami.Units.largeSpacing
                                rowSpacing: Kirigami.Units.largeSpacing
                                columns: width > 650 ? 2 : 1

                                // Status
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
                                                enabled: page.selectedIssueKey !== "" && !page.isProcessing
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

                                // Documentação e IA
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
                                                enabled: page.selectedIssueKey !== "" && !page.isProcessing
                                                checked: issueModel && issueModel.documentacaoAnexa === "Não"
                                                onCheckedChanged: {
                                                    if (checked && issueModel) {
                                                        issueModel.documentacaoAnexa = "Não";
                                                    }
                                                }
                                            }
                                            Controls.RadioButton {
                                                text: qsTr("Sim")
                                                enabled: page.selectedIssueKey !== "" && !page.isProcessing
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
                                                enabled: page.selectedIssueKey !== "" && !page.isProcessing
                                                checked: issueModel && issueModel.utilizacaoIA === "Não"
                                                onCheckedChanged: {
                                                    if (checked && issueModel) {
                                                        issueModel.utilizacaoIA = "Não";
                                                    }
                                                }
                                            }
                                            Controls.RadioButton {
                                                text: qsTr("Sim")
                                                enabled: page.selectedIssueKey !== "" && !page.isProcessing
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

                                // Tipo de Atividade
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
                                                enabled: page.selectedIssueKey !== "" && !page.isProcessing
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

                                // Valor Entregue
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
                                                enabled: page.selectedIssueKey !== "" && !page.isProcessing
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

                            // Plataformas Afetadas
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.margins: 20
                                Layout.topMargin: 0
                                spacing: Kirigami.Units.smallSpacing

                                Controls.Label {
                                    text: qsTr("Plataformas afetadas:")
                                    font.bold: true
                                    Layout.fillWidth: true
                                }

                                ListView {
                                    id: plataformasListView
                                    Layout.fillWidth: true
                                    implicitHeight: contentHeight
                                    interactive: false
                                    clip: true
                                    model: issueModel ? issueModel.plataformasAfetadasValues : []

                                    delegate: Controls.CheckDelegate {
                                        width: plataformasListView.width
                                        enabled: page.selectedIssueKey !== "" && !page.isProcessing
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
                                            if (!issueModel || page.isDetailsLoading)
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
                            }

                            // Spacer Final para empurrar tudo para cima
                            Item {
                                Layout.fillHeight: true
                                Layout.fillWidth: true
                            }
                        }
                    }
                }
            }

            // Overlay de loading sobre toda a coluna direita
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.4)
                visible: page.isDetailsLoading
                z: 100

                Controls.BusyIndicator {
                    anchors.centerIn: parent
                    running: page.isDetailsLoading
                    visible: page.isDetailsLoading
                }
            }
        }
    }

    // Conectar signals do jiraService
    Connections {
        target: jiraService

        function onProgressUpdated(percentage, message) {
            if (page.progressDialog) {
                page.progressDialog.updateProgress(percentage, message);
            }
        }
    }

    // Conectar signals do myIssuesModel para fechar diálogo de busca
    Connections {
        target: myIssuesModel

        function onErrorOccurred(errorMessage) {
            if (page.searchProgressDialog) {
                page.searchProgressDialog.close();
                page.searchProgressDialog.destroy();
                page.searchProgressDialog = null;
            }
            page.showErrorDialog(errorMessage);
        }
    }

    // Funções auxiliares
    function loadIssueDetails(issueKey) {
        if (!issueKey || !jiraService) {
            return;
        }
        // Delegar carregamento para o JiraService em modo assíncrono.
        // O overlay e o preenchimento dos campos são controlados pelos
        // sinais issueDetailsStarted / issueDetailsLoaded abaixo.
        jiraService.getIssueDetailsAsync(issueKey);
    }

    // Função pública para atualizar issue (chamada pelo botão global / atalho)
    function updateIssue() {
        if (!page.selectedIssueKey || page.selectedIssueKey === "") {
            page.showErrorDialog("Por favor, selecione uma task para atualizar");
            return;
        }

        if (!page.controller) {
            page.showErrorDialog("Controller não disponível");
            return;
        }

        // Obter dados dos componentes
        var fieldData = {};
        // Incluir summary editado na aba 2
        if (summaryFieldTab2) {
            fieldData.summary = summaryFieldTab2.text || "";
        }
        if (descriptionFieldTab2) {
            fieldData.description = descriptionFieldTab2.text || "";
        }
        // Incluir todos os campos do issueModel
        if (issueModel) {
            fieldData.tipoAtividade = issueModel.tipoAtividade || "";
            fieldData.status = issueModel.statusInicial || "";
            fieldData.valorEntregue = issueModel.valorEntregue || "";
            fieldData.plataformasAfetadas = issueModel.plataformasAfetadas || [];
            fieldData.documentacaoAnexa = issueModel.documentacaoAnexa || "Não";
            fieldData.utilizacaoIA = issueModel.utilizacaoIA || "Não";
        }
        // Worklog só é incluído se o checkbox estiver marcado
        var worklogData = {};
        if (worklogCheckboxTab2 && worklogCheckboxTab2.checked && worklogForm) {
            worklogData = worklogForm.getWorklogData();
        }
        var epicKey = epicSearchForm ? epicSearchForm.selectedEpicKey : "";

        // Atualizar via controller
        page.controller.updateIssue(page.selectedIssueKey, fieldData, worklogData, epicKey, page.originalStatus);
    }

    function resetFields() {
        // Resetar campos para valores padrão
        if (summaryFieldTab2) {
            summaryFieldTab2.text = "";
        }
        if (descriptionFieldTab2) {
            descriptionFieldTab2.text = "";
        }
        if (issueModel) {
            if (issueModel.tipoAtividadeValues && issueModel.tipoAtividadeValues.length > 0) {
                issueModel.tipoAtividade = issueModel.tipoAtividadeValues[0];
            } else {
                issueModel.tipoAtividade = "";
            }
            if (issueModel.statusSequence && issueModel.statusSequence.length > 0) {
                issueModel.statusInicial = issueModel.statusSequence[0];
            } else {
                issueModel.statusInicial = "";
            }
            issueModel.documentacaoAnexa = "Não";
            issueModel.utilizacaoIA = "Não";
            issueModel.valorEntregue = "";
            issueModel.plataformasAfetadas = [];
            issueModel.registrarWorklog = false;
        }

        if (worklogForm) {
            worklogForm.reset();
        }

        if (epicSearchForm) {
            epicSearchForm.reset();
        }

        originalStatus = "";
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

    function showSuccessDialog(issueKey) {
        var component = Qt.createComponent("../components/dialogs/SuccessDialog.qml");
        if (component.status === Component.Ready) {
            var window = page.parent && page.parent.parent ? page.parent.parent : page;
            successDialog = component.createObject(window);
            if (successDialog) {
                var issueUrl = "";
                successDialog.show(issueKey, issueUrl, true);  // true indica que é atualização
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

    // Reagir aos sinais assíncronos de carregamento de detalhes de issue
    Connections {
        target: jiraService

        function onIssueDetailsStarted(issueKey) {
            // Sempre que iniciar o carregamento de detalhes, limpar campos
            // e exibir overlay.
            page.isDetailsLoading = true;
            page.resetFields();
        }

        function onIssueDetailsLoaded(details) {
            // Garantir que o overlay seja sempre removido ao final
            // (mesmo em caso de erro ou dados vazios).
            try {
                if (!details || !details.key) {
                    return;
                }

                // Preencher campos do formulário
                if (summaryFieldTab2) {
                    summaryFieldTab2.text = String(details.summary || "");
                }
                if (descriptionFieldTab2) {
                    descriptionFieldTab2.text = String(details.description || "");
                }

                // Preencher campos do issueModel
                if (issueModel) {
                    issueModel.tipoAtividade = String(details.tipoAtividade || "");
                    issueModel.statusInicial = String(details.status || "");
                    issueModel.valorEntregue = String(details.valorEntregue || "");
                    issueModel.plataformasAfetadas = details.plataformasAfetadas || [];
                    issueModel.documentacaoAnexa = String(details.documentacaoAnexa || "Não");
                    issueModel.utilizacaoIA = String(details.utilizacaoIA || "Não");
                    issueModel.registrarWorklog = false;  // Resetar checkbox de worklog ao carregar nova issue
                }

                // Armazenar status original
                originalStatus = String(details.status || "");

                // Epic Parent - regras específicas para aba 2
                if (details.parentKey) {
                    // Issue TEM parent
                    var parentKey = String(details.parentKey || "");
                    var parentSummary = String(details.parentSummary || "");

                    if (epicSearchForm && jiraService) {
                        // 1. Limpar todos os checkboxes (todos desmarcados)
                        epicSearchForm.clearFilters();

                        // 2. Limpar campo de busca e listview
                        epicSearchForm.clearAll();

                        // 3. Preencher campo de busca com parent key
                        epicSearchForm.setSearchText(parentKey);

                        // 4. Buscar epic exato por key
                        var epic = jiraService.searchEpicByKey(parentKey);

                        if (epic && epic.key) {
                            // Epic encontrado, adicionar à lista e selecionar
                            epicSearchForm.selectEpic(epic.key, epic.summary || parentSummary);
                        } else {
                            // Epic não encontrado, buscar normalmente (vai mostrar só ele pois busca por key)
                            epicSearchForm.requestAutoSelect(parentKey, parentSummary);
                            epicSearchForm.search(parentKey);
                        }
                    }
                } else {
                    // Issue NÃO TEM parent
                    if (epicSearchForm) {
                        // 1. Configurar checkboxes padrão
                        epicSearchForm.setDefaultFiltersForNoParent();

                        // 2. Limpar campo de busca, listview e seleção (sem buscar)
                        epicSearchForm.clearAll();
                    }
                }
            } finally {
                isDetailsLoading = false;
            }
        }
    }
}
