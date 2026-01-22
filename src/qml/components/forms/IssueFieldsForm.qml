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
import QtQuick 2.12
import QtQuick.Layouts 1.12
import QtQuick.Controls 2.12 as Controls
import org.kde.kirigami 2.12 as Kirigami

ColumnLayout {
    id: root
    
    property bool enabled: true
    property alias description: descriptionField.text
    property string tipoAtividade: ""
    property string status: ""
    property string documentacaoAnexa: "Não"
    property string utilizacaoIA: "Não"
    property var tipoAtividadeValues: []
    property var statusSequence: []
    
    signal fieldChanged(string fieldName, var value)
    
    spacing: Kirigami.Units.largeSpacing
    
    // Description
    Controls.Label {
        text: qsTr("Description:")
        font.bold: true
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignLeft | Qt.AlignTop
    }
    
    // Scroll vertical para descrições longas
    Controls.ScrollView {
        id: descriptionScrollView
        Layout.fillWidth: true
        Layout.preferredHeight: 120
        Layout.leftMargin: Kirigami.Units.mediumSpacing
        Layout.rightMargin: Kirigami.Units.mediumSpacing
        Layout.alignment: Qt.AlignLeft | Qt.AlignTop
        clip: true

        Controls.TextArea {
            id: descriptionField
            width: descriptionScrollView.availableWidth
            wrapMode: Controls.TextArea.Wrap
            enabled: root.enabled
            focus: true
            
            // Interceptar Tab para avançar para o próximo campo
            Keys.onTabPressed: function(event) {
                event.accepted = true
                var nextItem = nextItemInFocusChain(true)
                if (nextItem) {
                    nextItem.forceActiveFocus()
                }
            }
            
            // Interceptar Shift+Tab para voltar ao campo anterior
            Keys.onBacktabPressed: function(event) {
                event.accepted = true
                var prevItem = nextItemInFocusChain(false)
                if (prevItem) {
                    prevItem.forceActiveFocus()
                }
            }
            
            onTextChanged: {
                root.fieldChanged("description", text)
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
                    model: tipoAtividadeValues
                    
                    Controls.RadioButton {
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
