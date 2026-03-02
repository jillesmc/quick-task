/**
 * WorkItemMetadataFields.qml
 *
 * Grid de metadados para work items (abas 7 e 8): Prioridade (via PriorityBlock),
 * Status, Documentação anexa, Utilização de IA, Tipo de atividade, Valor Entregue,
 * Plataformas afetadas. Binds to workItemModel. Não modificar IssueMetadataFields (abas 0/1).
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami
import "../fields"

ColumnLayout {
    id: metadataFieldsRoot

    property var workItemModel: null
    property bool enabled: true
    /** Se true, desabilita status anteriores ao atual na sequência (regra de não voltar atrás). Use false na tela de criar issue. */
    property bool restrictStatusBySequence: true
    /** Status persistido (ex.: do Jira); quando definido, a desativação usa só este valor, não o escolhido no formulário. Use na Minhas Issues. */
    property string statusForRestriction: ""

    /** Índice do status atual no formulário (statusInicial). */
    property int statusCurrentIndex: {
        if (!metadataFieldsRoot.workItemModel || !metadataFieldsRoot.workItemModel.statusSequence)
            return -1;
        var seq = metadataFieldsRoot.workItemModel.statusSequence;
        var current = String(metadataFieldsRoot.workItemModel.statusInicial || "").trim().toUpperCase();
        for (var i = 0; i < seq.length; i++) {
            if (String(seq[i] || "").trim().toUpperCase() === current)
                return i;
        }
        return -1;
    }
    /** Índice do status persistido (statusForRestriction) na sequência; usado para minEnabledIndex quando definido. */
    property int statusRestrictionIndex: {
        if (!metadataFieldsRoot.workItemModel || !metadataFieldsRoot.workItemModel.statusSequence || !metadataFieldsRoot.statusForRestriction)
            return -1;
        var seq = metadataFieldsRoot.workItemModel.statusSequence;
        var saved = String(metadataFieldsRoot.statusForRestriction || "").trim().toUpperCase();
        for (var i = 0; i < seq.length; i++) {
            if (String(seq[i] || "").trim().toUpperCase() === saved)
                return i;
        }
        return -1;
    }
    property int _statusMinEnabledIndex: {
        if (!metadataFieldsRoot.restrictStatusBySequence)
            return -1;
        var idx = metadataFieldsRoot.statusForRestriction ? metadataFieldsRoot.statusRestrictionIndex : metadataFieldsRoot.statusCurrentIndex;
        return idx >= 0 ? idx : -1;
    }

    spacing: Kirigami.Units.largeSpacing

    GridLayout {
        id: metadataGrid
        Layout.fillWidth: true
        columnSpacing: Kirigami.Units.largeSpacing
        rowSpacing: Kirigami.Units.largeSpacing * 1.5
        columns: width > 650 ? 2 : 1

        // Prioridade (componente reutilizável para abas 7 e 8)
        PriorityBlock {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            model: metadataFieldsRoot.workItemModel
            enabled: metadataFieldsRoot.enabled
            labelText: qsTr("Prioridade:")
        }

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
                // Novo workflow: TO DO → IN PROGRESS → DONE; fallback quando config ainda não carregou
                model: (metadataFieldsRoot.workItemModel && metadataFieldsRoot.workItemModel.statusSequence && metadataFieldsRoot.workItemModel.statusSequence.length > 0) ? metadataFieldsRoot.workItemModel.statusSequence : ["TO DO", "IN PROGRESS", "DONE"]
                enabled: metadataFieldsRoot.enabled
                selectedValue: metadataFieldsRoot.workItemModel ? metadataFieldsRoot.workItemModel.statusInicial : ""
                minEnabledIndex: metadataFieldsRoot._statusMinEnabledIndex
                onValueChanged: function (value) {
                    if (metadataFieldsRoot.workItemModel) {
                        metadataFieldsRoot.workItemModel.statusInicial = value;
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
                        checked: metadataFieldsRoot.workItemModel && metadataFieldsRoot.workItemModel.documentacaoAnexa === "Não"
                        onCheckedChanged: {
                            if (checked && metadataFieldsRoot.workItemModel) {
                                metadataFieldsRoot.workItemModel.documentacaoAnexa = "Não";
                            }
                        }
                    }
                    Controls.RadioButton {
                        text: qsTr("Sim")
                        enabled: metadataFieldsRoot.enabled
                        checked: metadataFieldsRoot.workItemModel && metadataFieldsRoot.workItemModel.documentacaoAnexa === "Sim"
                        onCheckedChanged: {
                            if (checked && metadataFieldsRoot.workItemModel) {
                                metadataFieldsRoot.workItemModel.documentacaoAnexa = "Sim";
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
                        checked: metadataFieldsRoot.workItemModel && metadataFieldsRoot.workItemModel.utilizacaoIA === "Não"
                        onCheckedChanged: {
                            if (checked && metadataFieldsRoot.workItemModel) {
                                metadataFieldsRoot.workItemModel.utilizacaoIA = "Não";
                            }
                        }
                    }
                    Controls.RadioButton {
                        text: qsTr("Sim")
                        enabled: metadataFieldsRoot.enabled
                        checked: metadataFieldsRoot.workItemModel && metadataFieldsRoot.workItemModel.utilizacaoIA === "Sim"
                        onCheckedChanged: {
                            if (checked && metadataFieldsRoot.workItemModel) {
                                metadataFieldsRoot.workItemModel.utilizacaoIA = "Sim";
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
                model: metadataFieldsRoot.workItemModel ? metadataFieldsRoot.workItemModel.tipoAtividadeValues : []
                enabled: metadataFieldsRoot.enabled
                selectedValue: metadataFieldsRoot.workItemModel ? metadataFieldsRoot.workItemModel.tipoAtividade : ""
                onValueChanged: function (value) {
                    if (metadataFieldsRoot.workItemModel) {
                        metadataFieldsRoot.workItemModel.tipoAtividade = value;
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
                model: metadataFieldsRoot.workItemModel ? metadataFieldsRoot.workItemModel.valorEntregueOptions : []
                enabled: metadataFieldsRoot.enabled
                selectedValue: metadataFieldsRoot.workItemModel ? metadataFieldsRoot.workItemModel.valorEntregue : ""
                onValueChanged: function (value) {
                    if (metadataFieldsRoot.workItemModel) {
                        metadataFieldsRoot.workItemModel.valorEntregue = value;
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
            model: metadataFieldsRoot.workItemModel ? metadataFieldsRoot.workItemModel.plataformasAfetadasOptions : []
            enabled: metadataFieldsRoot.enabled
            selectedValues: metadataFieldsRoot.workItemModel ? (metadataFieldsRoot.workItemModel.plataformasAfetadas || []) : []
            onSelectionChanged: function (values) {
                if (metadataFieldsRoot.workItemModel) {
                    metadataFieldsRoot.workItemModel.plataformasAfetadas = values;
                }
            }
        }
    }
}
