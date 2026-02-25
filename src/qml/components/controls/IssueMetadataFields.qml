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
    /** Se true, desabilita status anteriores ao atual na sequência (regra de não voltar atrás). Use false na tela de criar issue. */
    property bool restrictStatusBySequence: true
    /** Status persistido (ex.: do Jira); quando definido, a desativação usa só este valor, não o escolhido no formulário. Use na Minhas Issues. */
    property string statusForRestriction: ""

    /** Índice do status atual no formulário (statusInicial). */
    property int statusCurrentIndex: {
        if (!metadataFieldsRoot.issueModel || !metadataFieldsRoot.issueModel.statusSequence) return -1
        var seq = metadataFieldsRoot.issueModel.statusSequence
        var current = String(metadataFieldsRoot.issueModel.statusInicial || "").trim().toUpperCase()
        for (var i = 0; i < seq.length; i++) {
            if (String(seq[i] || "").trim().toUpperCase() === current) return i
        }
        return -1
    }
    /** Índice do status persistido (statusForRestriction) na sequência; usado para minEnabledIndex quando definido. */
    property int statusRestrictionIndex: {
        if (!metadataFieldsRoot.issueModel || !metadataFieldsRoot.issueModel.statusSequence || !metadataFieldsRoot.statusForRestriction) return -1
        var seq = metadataFieldsRoot.issueModel.statusSequence
        var saved = String(metadataFieldsRoot.statusForRestriction || "").trim().toUpperCase()
        for (var i = 0; i < seq.length; i++) {
            if (String(seq[i] || "").trim().toUpperCase() === saved) return i
        }
        return -1
    }
    property int _statusMinEnabledIndex: {
        if (!metadataFieldsRoot.restrictStatusBySequence) return -1
        var idx = metadataFieldsRoot.statusForRestriction ? metadataFieldsRoot.statusRestrictionIndex : metadataFieldsRoot.statusCurrentIndex
        return idx >= 0 ? idx : -1
    }

    spacing: Kirigami.Units.largeSpacing

    GridLayout {
        id: metadataGrid
        Layout.fillWidth: true
        columnSpacing: Kirigami.Units.largeSpacing
        rowSpacing: Kirigami.Units.largeSpacing * 1.5
        columns: width > 650 ? 2 : 1

        // Prioridade
        ColumnLayout {
            id: prioridadeColumnLayout
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            spacing: Kirigami.Units.smallSpacing

            Controls.Label {
                text: qsTr("Prioridade:")
                font.bold: true
                Layout.fillWidth: true
            }

            IssueRadioGroup {
                id: prioridadeRadioGroup
                Layout.fillWidth: true
                model: [
                    { value: "Highest", label: "Highest", icon: "flag-red" },
                    { value: "High", label: "High", icon: "flag-yellow" },
                    { value: "Medium", label: "Medium", icon: "flag" },
                    { value: "Low", label: "Low", icon: "flag-green" },
                    { value: "Lowest", label: "Lowest", icon: "flag-blue" }
                ]
                enabled: metadataFieldsRoot.enabled
                selectedValue: metadataFieldsRoot.issueModel ? metadataFieldsRoot.issueModel.prioridade : "Medium"
                onValueChanged: function(value) {
                    if (metadataFieldsRoot.issueModel) {
                        metadataFieldsRoot.issueModel.prioridade = value
                    }
                }
            }
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
                model: (metadataFieldsRoot.issueModel && metadataFieldsRoot.issueModel.statusSequence && metadataFieldsRoot.issueModel.statusSequence.length > 0)
                    ? metadataFieldsRoot.issueModel.statusSequence
                    : ["TO DO", "IN PROGRESS", "DONE"]
                enabled: metadataFieldsRoot.enabled
                selectedValue: metadataFieldsRoot.issueModel ? metadataFieldsRoot.issueModel.statusInicial : ""
                minEnabledIndex: metadataFieldsRoot._statusMinEnabledIndex
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
