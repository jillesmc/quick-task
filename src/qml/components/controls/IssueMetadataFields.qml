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
    id: root

    property var issueModel: null
    property bool enabled: true

    spacing: 0

    GridLayout {
        id: metadataGrid
        Layout.fillWidth: true
        // Layout.margins: 20
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
                    model: root.issueModel ? root.issueModel.statusSequence : []

                    Controls.RadioButton {
                        text: modelData
                        enabled: root.enabled
                        checked: root.issueModel && root.issueModel.statusInicial === modelData
                        onCheckedChanged: {
                            if (checked && root.issueModel) {
                                root.issueModel.statusInicial = modelData;
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
                        enabled: root.enabled
                        checked: root.issueModel && root.issueModel.documentacaoAnexa === "Não"
                        onCheckedChanged: {
                            if (checked && root.issueModel) {
                                root.issueModel.documentacaoAnexa = "Não";
                            }
                        }
                    }
                    Controls.RadioButton {
                        text: qsTr("Sim")
                        enabled: root.enabled
                        checked: root.issueModel && root.issueModel.documentacaoAnexa === "Sim"
                        onCheckedChanged: {
                            if (checked && root.issueModel) {
                                root.issueModel.documentacaoAnexa = "Sim";
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
                        enabled: root.enabled
                        checked: root.issueModel && root.issueModel.utilizacaoIA === "Não"
                        onCheckedChanged: {
                            if (checked && root.issueModel) {
                                root.issueModel.utilizacaoIA = "Não";
                            }
                        }
                    }
                    Controls.RadioButton {
                        text: qsTr("Sim")
                        enabled: root.enabled
                        checked: root.issueModel && root.issueModel.utilizacaoIA === "Sim"
                        onCheckedChanged: {
                            if (checked && root.issueModel) {
                                root.issueModel.utilizacaoIA = "Sim";
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
                    model: root.issueModel ? root.issueModel.tipoAtividadeValues : []

                    Controls.RadioButton {
                        text: modelData
                        enabled: root.enabled
                        checked: root.issueModel && root.issueModel.tipoAtividade === modelData
                        onCheckedChanged: {
                            if (checked && root.issueModel) {
                                root.issueModel.tipoAtividade = modelData;
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
                    model: root.issueModel ? root.issueModel.valorEntregueValues : []

                    Controls.RadioButton {
                        text: modelData
                        enabled: root.enabled
                        checked: root.issueModel && root.issueModel.valorEntregue === modelData
                        onCheckedChanged: {
                            if (checked && root.issueModel) {
                                root.issueModel.valorEntregue = modelData;
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
        // Layout.margins: 20
        // Layout.topMargin: 0
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
            model: root.issueModel ? root.issueModel.plataformasAfetadasValues : []

            delegate: Controls.CheckDelegate {
                width: plataformasListView.width
                enabled: root.enabled
                checked: {
                    if (!root.issueModel)
                        return false;
                    var plataformas = root.issueModel.plataformasAfetadas || [];
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
                    if (!root.issueModel)
                        return;
                    var plataformas = root.issueModel.plataformasAfetadas || [];
                    var val = modelData.col1;
                    if (checked) {
                        if (plataformas.indexOf(val) < 0) {
                            plataformas.push(val);
                            root.issueModel.plataformasAfetadas = plataformas;
                        }
                    } else {
                        var index = plataformas.indexOf(val);
                        if (index >= 0) {
                            plataformas.splice(index, 1);
                            root.issueModel.plataformasAfetadas = plataformas;
                        }
                    }
                }
            }
        }
    }
}
