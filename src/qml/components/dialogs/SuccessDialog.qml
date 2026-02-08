// Diálogo de sucesso
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Controls.Dialog {
    id: dialog
    
    property bool isUpdate: false  // Se true, é uma atualização, senão é criação
    title: isUpdate ? "Task Atualizada" : "Issue Criada"
    modal: true
    closePolicy: Controls.Popup.CloseOnEscape

    // Definir tamanho mínimo adequado para acomodar todos os elementos com padding
    implicitWidth: 480
    implicitHeight: isUpdate ? 220 : 280
    width: implicitWidth
    height: implicitHeight
    
    property string issueKey: ""
    property string issueUrl: ""
    property var timerService: null
    property var timerModel: null
    property var jiraService: null
    property var applicationWindow: null
    property bool _waitingForInDevelopment: false
    property string _errorMessage: ""  // Quando preenchido, mostra erro no diálogo (ex.: falha ao transicionar para IN DEVELOPMENT)

    // Não usar botões padrão, vamos criar botões customizados
    standardButtons: Controls.Dialog.NoButton
    
    // Centralizar o diálogo
    function centerDialog() {
        if (parent && width > 0 && height > 0) {
            x = (parent.width - width) / 2
            y = (parent.height - height) / 2
        }
    }
    
    Component.onCompleted: centerDialog()
    onWidthChanged: centerDialog()
    onHeightChanged: centerDialog()

    onClosed: {
        if (dialog.applicationWindow && dialog.applicationWindow._jiraErrorShownInCreateFlow !== undefined) {
            dialog.applicationWindow._jiraErrorShownInCreateFlow = false;
        }
        dialog._errorMessage = "";
    }

    // Conteúdo do diálogo com padding adequado
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing * 1.5  // Padding generoso
        spacing: Kirigami.Units.mediumSpacing

        // Erro (ex.: falha ao transicionar para IN DEVELOPMENT ao clicar Iniciar Timer)
        Controls.Label {
            visible: dialog._errorMessage !== ""
            text: dialog._errorMessage
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.smallSpacing
            Layout.rightMargin: Kirigami.Units.smallSpacing
            wrapMode: Text.Wrap
            font.pointSize: Kirigami.Theme.defaultFont.pointSize
            color: Kirigami.Theme.negativeTextColor
        }

        // Mensagem de sucesso (oculta quando há erro)
        Controls.Label {
            visible: dialog._errorMessage === ""
            text: dialog.isUpdate ? "Task atualizada com sucesso!" : "Issue criada com sucesso!"
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.smallSpacing
            Layout.rightMargin: Kirigami.Units.smallSpacing
            wrapMode: Text.Wrap
            font.pointSize: Kirigami.Theme.defaultFont.pointSize
        }
        
        // Issue Key (oculto quando mostra erro)
        Controls.Label {
            visible: dialog._errorMessage === ""
            text: "Issue: " + dialog.issueKey
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.smallSpacing
            Layout.rightMargin: Kirigami.Units.smallSpacing
            wrapMode: Text.Wrap
            font.pointSize: Kirigami.Theme.defaultFont.pointSize
            font.bold: true
        }

        // URL clicável (oculto quando mostra erro)
        Controls.Label {
            text: dialog.issueUrl
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.smallSpacing
            Layout.rightMargin: Kirigami.Units.smallSpacing
            visible: dialog._errorMessage === "" && dialog.issueUrl !== ""
            color: Kirigami.Theme.linkColor
            wrapMode: Text.Wrap
            elide: Text.ElideMiddle
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (dialog.issueUrl) {
                        Qt.openUrlExternally(dialog.issueUrl)
                    }
                }
            }
        }
        
        // Espaçador para empurrar botões para baixo (oculto quando mostra erro)
        Item {
            Layout.fillHeight: true
            visible: dialog._errorMessage === ""
        }

        // Feedback visual enquanto transiciona para IN DEVELOPMENT
        RowLayout {
            visible: dialog._waitingForInDevelopment && dialog._errorMessage === ""
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            Controls.BusyIndicator {
                running: dialog._waitingForInDevelopment
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
            }
            Controls.Label {
                text: qsTr("Transicionando para IN DEVELOPMENT...")
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
        }

        // Botão Iniciar Timer (apenas para criação; oculto quando mostra erro)
        Controls.Button {
            text: qsTr("Iniciar Timer")
            icon.name: "chronometer"
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.smallSpacing
            Layout.rightMargin: Kirigami.Units.smallSpacing
            visible: dialog._errorMessage === "" && !dialog.isUpdate && dialog.issueKey !== "" && dialog.timerService && dialog.timerModel
            enabled: dialog.timerService && dialog.timerModel && !dialog._waitingForInDevelopment

            onClicked: {
                if (!dialog.timerService || !dialog.issueKey) return
                if (dialog.jiraService && dialog.jiraService.transitionToInDevelopmentIfNeeded && dialog.jiraService.transitionToInDevelopmentIfNeeded(dialog.issueKey)) {
                    dialog._waitingForInDevelopment = true
                    if (dialog.applicationWindow && dialog.applicationWindow._jiraErrorShownInCreateFlow !== undefined) {
                        dialog.applicationWindow._jiraErrorShownInCreateFlow = true
                    }
                } else {
                    dialog.timerService.start(dialog.issueKey)
                    dialog.close()
                }
            }
        }

        Connections {
            target: dialog.jiraService || null
            function onInDevelopmentReady(key) {
                if (dialog._waitingForInDevelopment && key === dialog.issueKey) {
                    dialog._waitingForInDevelopment = false
                    if (dialog.applicationWindow && dialog.applicationWindow._jiraErrorShownInCreateFlow !== undefined) {
                        dialog.applicationWindow._jiraErrorShownInCreateFlow = false
                    }
                    if (dialog.timerService) dialog.timerService.start(key)
                    dialog.close()
                }
            }
            function onErrorOccurred(message) {
                if (dialog._waitingForInDevelopment) {
                    dialog._waitingForInDevelopment = false
                    dialog._errorMessage = message || qsTr("Erro ao transicionar")
                    // Erro mostrado neste diálogo; Pane e MyIssuesPage não devem abrir ErrorDialog/ProcessDialog
                }
            }
        }
        
        // Botões: Abrir (quando há URL e sem erro), Fechar
        RowLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Kirigami.Units.smallSpacing

            Item { Layout.fillWidth: true }
            Controls.Button {
                visible: dialog._errorMessage === "" && !dialog.isUpdate && dialog.issueUrl !== ""
                text: qsTr("Abrir")
                Layout.preferredWidth: 120
                onClicked: {
                    if (dialog.issueUrl) Qt.openUrlExternally(dialog.issueUrl)
                    dialog.close()
                }
            }
            Controls.Button {
                text: qsTr("Fechar")
                Layout.preferredWidth: 120
                onClicked: dialog.close()
            }
            Item { Layout.fillWidth: true }
        }
    }

    function show(key, url, update) {
        issueKey = key
        issueUrl = url || ""
        isUpdate = update || false
        open()
    }
}
