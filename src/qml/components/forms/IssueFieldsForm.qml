pragma ComponentBehavior: Bound
/**
 * IssueFieldsForm.qml
 *
 * Componente reutilizável para campos de issue
 * Segue Single Responsibility Principle - apenas gerencia campos de issue
 * Segue Open/Closed Principle - pode ser estendido sem modificar
 * 
 * Propriedades:
 * - enabled: controla se o formulário está habilitado
 * - description: texto da descrição
 * - tipoAtividade: tipo de atividade selecionado
 * - status: status selecionado
 * - documentacaoAnexa: "Sim" ou "Não"
 * - utilizacaoIA: "Sim" ou "Não"
 * - tipoAtividadeValues: array de valores disponíveis (binding)
 * - statusSequence: array de status disponíveis (binding)
 * 
 * Signals:
 * - fieldChanged(string fieldName, var value): emitido quando qualquer campo muda
 * 
 * Métodos:
 * - reset(): reseta todos os campos para valores padrão
 * - setFieldData(data): define dados dos campos
 * - getFieldData(): retorna objeto com dados dos campos
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: root
    
    property bool enabled: true
    property alias description: descriptionField.text
    property string tipoAtividade: ""
    property string status: ""
    property string documentacaoAnexa: "Não"
    property string utilizacaoIA: "Não"
    property string valorEntregue: ""
    property var plataformasAfetadas: []
    property var tipoAtividadeValues: []
    property var statusSequence: []
    property var valorEntregueValues: []
    property var plataformasAfetadasValues: []
    /// Lista de anexos pendentes para nova issue: [{ path, filename, placeholderId }]
    property var pendingAttachments: []
    /// Extensões permitidas para anexos (imagens)
    property var allowedAttachmentExtensions: ["png", "jpg", "jpeg", "gif", "webp"]
    /// Helper de clipboard (passado pelo parent quando disponível)
    property var clipboardHelper: null
    property int _placeholderCounter: 0

    signal fieldChanged(string fieldName, var value)
    
    spacing: Kirigami.Units.largeSpacing
    
    // Description
    Controls.Label {
        text: qsTr("Description:")
        font.bold: true
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignLeft | Qt.AlignTop
    }
    
    // Scroll vertical para descrições longas + DropArea para anexos
    Controls.ScrollView {
        id: descriptionScrollView
        Layout.fillWidth: true
        Layout.preferredHeight: 120
        Layout.leftMargin: Kirigami.Units.mediumSpacing
        Layout.rightMargin: Kirigami.Units.mediumSpacing
        Layout.alignment: Qt.AlignLeft | Qt.AlignTop
        clip: true

        Item {
            width: descriptionScrollView.availableWidth
            height: descriptionField.implicitHeight

            DropArea {
                anchors.fill: parent
                enabled: root.enabled
                onDropped: function(drop) {
                    if (!drop.urls || drop.urls.length === 0) return
                    var extList = root.allowedAttachmentExtensions || []
                    for (var i = 0; i < drop.urls.length; i++) {
                        var urlStr = drop.urls[i].toString()
                        var path = urlStr.replace(/^file:\/\//, "")
                        var filename = path.split("/").pop() || path.split("\\").pop() || "file"
                        var ext = filename.indexOf(".") >= 0 ? filename.split(".").pop().toLowerCase() : ""
                        if (extList.indexOf(ext) < 0) continue
                        var pathToUse = ""
                        if (root.clipboardHelper && typeof root.clipboardHelper.copyFileToTemp === "function") {
                            pathToUse = root.clipboardHelper.copyFileToTemp(path)
                        }
                        if (!pathToUse) continue
                        root._placeholderCounter += 1
                        var placeholderId = "p" + root._placeholderCounter
                        root.pendingAttachments = root.pendingAttachments.concat([{
                            path: pathToUse,
                            filename: filename,
                            placeholderId: placeholderId
                        }])
                        var markdown = "![" + filename + "](pending:" + placeholderId + ")"
                        descriptionField.insert(descriptionField.cursorPosition, markdown)
                        root.fieldChanged("description", descriptionField.text)
                    }
                }
            }

            Controls.TextArea {
                id: descriptionField
                width: parent.width
                wrapMode: Controls.TextArea.Wrap
                enabled: root.enabled
                focus: true
                placeholderText: qsTr("Arraste imagens ou use Ctrl+V para colar; o link será inserido em markdown.")

                Keys.onTabPressed: function(event) {
                    event.accepted = true
                    var nextItem = nextItemInFocusChain(true)
                    if (nextItem) {
                        nextItem.forceActiveFocus()
                    }
                }

                Keys.onBacktabPressed: function(event) {
                    event.accepted = true
                    var prevItem = nextItemInFocusChain(false)
                    if (prevItem) {
                        prevItem.forceActiveFocus()
                    }
                }

                Keys.onPressed: function(event) {
                    if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V) {
                        if (root.clipboardHelper && root.clipboardHelper.hasClipboardImage()) {
                            var tempPath = root.clipboardHelper.getClipboardImageAsTempFile()
                            if (tempPath) {
                                root._placeholderCounter += 1
                                var pid = "p" + root._placeholderCounter
                                var list = root.pendingAttachments
                                list.push({ path: tempPath, filename: "paste.png", placeholderId: pid })
                                root.pendingAttachments = list
                                descriptionField.insert(descriptionField.cursorPosition, "![paste.png](pending:" + pid + ")")
                                root.fieldChanged("description", descriptionField.text)
                                event.accepted = true
                            }
                        }
                    }
                }

                onTextChanged: {
                    root.fieldChanged("description", text)
                }
            }
        }
    }
    
    // GridLayout para Tipo de atividade, Documentação anexa e Utilização de IA em 2 colunas
    GridLayout {
        id: twoColumnGrid
        columns: 2
        columnSpacing: Kirigami.Units.largeSpacing * 2
        rowSpacing: Kirigami.Units.mediumSpacing
        Layout.fillWidth: false
        Layout.fillHeight: false
        Layout.alignment: Qt.AlignLeft | Qt.AlignTop
        
        // Coluna 1: Tipo de atividade (largura fixa: 500px)
        ColumnLayout {
            id: tipoAtividadeColumn
            Layout.preferredWidth: 500
            Layout.maximumWidth: 500
            Layout.alignment: Qt.AlignLeft | Qt.AlignTop
            Layout.rowSpan: 2
            spacing: Kirigami.Units.smallSpacing
            
            Controls.Label {
                text: qsTr("Tipo de atividade:")
                font.bold: true
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignLeft | Qt.AlignTop
            }
            
            Column {
                id: tipoAtividadeRadioColumn
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.mediumSpacing
                Layout.alignment: Qt.AlignLeft | Qt.AlignTop
                spacing: Kirigami.Units.smallSpacing
                
                Repeater {
                    model: root.tipoAtividadeValues

                    Controls.RadioButton {
                        required property var modelData
                        text: modelData
                        enabled: root.enabled
                        checked: root.tipoAtividade === modelData
                        onCheckedChanged: {
                            if (checked) {
                                root.tipoAtividade = modelData
                                root.fieldChanged("tipoAtividade", modelData)
                            }
                        }
                    }
                }
            }
        }
        
        // Coluna 2, Linha 1: Documentação anexa (largura fixa: 250px)
        ColumnLayout {
            id: documentacaoColumn
            Layout.preferredWidth: 250
            Layout.maximumWidth: 250
            Layout.alignment: Qt.AlignLeft | Qt.AlignTop
            Layout.rowSpan: 1
            spacing: Kirigami.Units.smallSpacing
            
            Controls.Label {
                text: qsTr("Documentação anexa:")
                font.bold: true
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignLeft | Qt.AlignTop
            }
            
            Row {
                id: documentacaoRow
                Layout.leftMargin: 0
                Layout.alignment: Qt.AlignLeft | Qt.AlignTop
                spacing: Kirigami.Units.largeSpacing
                
                Controls.RadioButton {
                    id: docNaoRadio
                    text: qsTr("Não")
                    enabled: root.enabled
                    checked: root.documentacaoAnexa === "Não"
                    onCheckedChanged: {
                        if (checked) {
                            root.documentacaoAnexa = "Não"
                            root.fieldChanged("documentacaoAnexa", "Não")
                        }
                    }
                }
                
                Controls.RadioButton {
                    id: docSimRadio
                    text: qsTr("Sim")
                    enabled: root.enabled
                    checked: root.documentacaoAnexa === "Sim"
                    onCheckedChanged: {
                        if (checked) {
                            root.documentacaoAnexa = "Sim"
                            root.fieldChanged("documentacaoAnexa", "Sim")
                        }
                    }
                }
            }
        }
        
        // Coluna 2, Linha 2: Utilização de IA (largura fixa: 250px)
        ColumnLayout {
            id: utilizacaoIAColumn
            Layout.preferredWidth: 250
            Layout.maximumWidth: 250
            Layout.alignment: Qt.AlignLeft | Qt.AlignTop
            Layout.rowSpan: 1
            spacing: Kirigami.Units.smallSpacing
            
            Controls.Label {
                text: qsTr("Utilização de IA:")
                font.bold: true
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignLeft | Qt.AlignTop
            }
            
            Row {
                id: utilizacaoIARow
                Layout.leftMargin: 0
                Layout.alignment: Qt.AlignLeft | Qt.AlignTop
                spacing: Kirigami.Units.largeSpacing
                
                Controls.RadioButton {
                    id: iaNaoRadio
                    text: qsTr("Não")
                    enabled: root.enabled
                    checked: root.utilizacaoIA === "Não"
                    onCheckedChanged: {
                        if (checked) {
                            root.utilizacaoIA = "Não"
                            root.fieldChanged("utilizacaoIA", "Não")
                        }
                    }
                }
                
                Controls.RadioButton {
                    id: iaSimRadio
                    text: qsTr("Sim")
                    enabled: root.enabled
                    checked: root.utilizacaoIA === "Sim"
                    onCheckedChanged: {
                        if (checked) {
                            root.utilizacaoIA = "Sim"
                            root.fieldChanged("utilizacaoIA", "Sim")
                        }
                    }
                }
            }
        }
    }
    
    /**
     * Reseta todos os campos para valores padrão
     */
    function reset() {
        descriptionField.text = ""
        pendingAttachments = []
        _placeholderCounter = 0
        if (tipoAtividadeValues && tipoAtividadeValues.length > 0) {
            tipoAtividade = tipoAtividadeValues[0]
        } else {
            tipoAtividade = ""
        }
        if (statusSequence && statusSequence.length > 0) {
            status = statusSequence[0]
        } else {
            status = ""
        }
        documentacaoAnexa = "Não"
        utilizacaoIA = "Não"
    }
    
    /**
     * Retorna objeto com dados dos campos
     * @returns {object} Objeto com description, tipoAtividade, status, documentacaoAnexa, utilizacaoIA
     */
    function getFieldData() {
        return {
            description: description,
            tipoAtividade: tipoAtividade,
            status: status,
            documentacaoAnexa: documentacaoAnexa,
            utilizacaoIA: utilizacaoIA
        }
    }
    
    /**
     * Define dados dos campos
     * @param {object} data - Objeto com description, tipoAtividade, status, documentacaoAnexa, utilizacaoIA
     */
    function setFieldData(data) {
        if (!data) return
        
        if (data.description !== undefined) {
            descriptionField.text = data.description
        }
        if (data.tipoAtividade !== undefined) {
            tipoAtividade = data.tipoAtividade
        }
        if (data.status !== undefined) {
            status = data.status
        }
        if (data.documentacaoAnexa !== undefined) {
            documentacaoAnexa = data.documentacaoAnexa
        }
        if (data.utilizacaoIA !== undefined) {
            utilizacaoIA = data.utilizacaoIA
        }
    }
}
