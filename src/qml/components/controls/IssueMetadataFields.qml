/**
 * IssueMetadataFields.qml
 *
 * Reusable grid of issue metadata: Status, Documentação anexa, Utilização de IA,
 * Tipo de atividade, Valor Entregue, Plataformas afetadas. Binds to issueModel;
 * no business logic, only bindings and handlers that update issueModel.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: metadataFieldsRoot

    property var issueModel: null
    property bool enabled: true

    spacing: 0

    GridLayout {
        id: metadataGrid
        Layout.fillWidth: true
        columnSpacing: Kirigami.Units.largeSpacing
        rowSpacing: Kirigami.Units.largeSpacing
        columns: width > 650 ? 2 : 1

        // Status
        ColumnLayout {
            id: statusColumnLayout
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            spacing: Kirigami.Units.smallSpacing

            Controls.Label {
                text: qsTr("Status:")
                font.bold: true
                Layout.fillWidth: true
            }

            IssueRadioGroup {
                id: statusRadioGroup
                Layout.fillWidth: true
                model: metadataFieldsRoot.issueModel ? metadataFieldsRoot.issueModel.statusSequence : []
                enabled: metadataFieldsRoot.enabled
                selectedValue: metadataFieldsRoot.issueModel ? metadataFieldsRoot.issueModel.statusInicial : ""
                onValueChanged: function(value) {
                    if (metadataFieldsRoot.issueModel) {
                        metadataFieldsRoot.issueModel.statusInicial = value
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
                        enabled: metadataFieldsRoot.enabled
                        checked: metadataFieldsRoot.issueModel && metadataFieldsRoot.issueModel.documentacaoAnexa === "Não"
                        onCheckedChanged: {
                            if (checked && metadataFieldsRoot.issueModel) {
                                metadataFieldsRoot.issueModel.documentacaoAnexa = "Não"
                            }
                        }
                    }
                    Controls.RadioButton {
                        text: qsTr("Sim")
                        enabled: metadataFieldsRoot.enabled
                        checked: metadataFieldsRoot.issueModel && metadataFieldsRoot.issueModel.documentacaoAnexa === "Sim"
                        onCheckedChanged: {
                            if (checked && metadataFieldsRoot.issueModel) {
                                metadataFieldsRoot.issueModel.documentacaoAnexa = "Sim"
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
                        enabled: metadataFieldsRoot.enabled
                        checked: metadataFieldsRoot.issueModel && metadataFieldsRoot.issueModel.utilizacaoIA === "Não"
                        onCheckedChanged: {
                            if (checked && metadataFieldsRoot.issueModel) {
                                metadataFieldsRoot.issueModel.utilizacaoIA = "Não"
                            }
                        }
                    }
                    Controls.RadioButton {
                        text: qsTr("Sim")
                        enabled: metadataFieldsRoot.enabled
                        checked: metadataFieldsRoot.issueModel && metadataFieldsRoot.issueModel.utilizacaoIA === "Sim"
                        onCheckedChanged: {
                            if (checked && metadataFieldsRoot.issueModel) {
                                metadataFieldsRoot.issueModel.utilizacaoIA = "Sim"
                            }
                        }
                    }
                }
            }
        }

        // Tipo de Atividade
        ColumnLayout {
            id: tipoAtividadeColumnLayout
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            spacing: Kirigami.Units.smallSpacing

            Controls.Label {
                text: qsTr("Tipo de atividade:")
                font.bold: true
                Layout.fillWidth: true
            }

            IssueRadioGroup {
                id: tipoAtividadeRadioGroup
                Layout.fillWidth: true
                model: metadataFieldsRoot.issueModel ? metadataFieldsRoot.issueModel.tipoAtividadeValues : []
                enabled: metadataFieldsRoot.enabled
                selectedValue: metadataFieldsRoot.issueModel ? metadataFieldsRoot.issueModel.tipoAtividade : ""
                onValueChanged: function(value) {
                    if (metadataFieldsRoot.issueModel) {
                        metadataFieldsRoot.issueModel.tipoAtividade = value
                    }
                }
            }
        }

        // Valor Entregue
        ColumnLayout {
            id: valorEntregueColumnLayout
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            spacing: Kirigami.Units.smallSpacing

            Controls.Label {
                text: qsTr("Valor Entregue:")
                font.bold: true
                Layout.fillWidth: true
            }

            IssueRadioGroup {
                id: valorEntregueRadioGroup
                Layout.fillWidth: true
                model: metadataFieldsRoot.issueModel ? metadataFieldsRoot.issueModel.valorEntregueOptions : []
                enabled: metadataFieldsRoot.enabled
                selectedValue: metadataFieldsRoot.issueModel ? metadataFieldsRoot.issueModel.valorEntregue : ""
                onValueChanged: function(value) {
                    if (metadataFieldsRoot.issueModel) {
                        metadataFieldsRoot.issueModel.valorEntregue = value
                    }
                }
            }
        }
    }

    // Plataformas Afetadas
    ColumnLayout {
        id: plataformasColumnLayout
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        Controls.Label {
            text: qsTr("Plataformas afetadas:")
            font.bold: true
            Layout.fillWidth: true
        }

        IssueCheckList {
            id: plataformasCheckList
            Layout.fillWidth: true
            model: metadataFieldsRoot.issueModel ? metadataFieldsRoot.issueModel.plataformasAfetadasOptions : []
            enabled: metadataFieldsRoot.enabled
            selectedValues: metadataFieldsRoot.issueModel ? (metadataFieldsRoot.issueModel.plataformasAfetadas || []) : []
            onSelectionChanged: function(values) {
                if (metadataFieldsRoot.issueModel) {
                    metadataFieldsRoot.issueModel.plataformasAfetadas = values
                }
            }
        }
    }
}
