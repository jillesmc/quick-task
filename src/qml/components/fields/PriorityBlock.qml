/**
 * PriorityBlock.qml
 *
 * Bloco reutilizável: label "Prioridade:" + IssueRadioGroup (opções fixas).
 * Usado em CreateWorkItemPage e WorkItemDetailPane (abas 7 e 8) via WorkItemMetadataFields.
 * Contrato: model (prioridade/prioridadeChanged), enabled, labelText.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami
import "../controls"

ColumnLayout {
    id: root

    property var model: null
    property bool enabled: true
    property string labelText: qsTr("Prioridade:")

    spacing: Kirigami.Units.smallSpacing
    Layout.fillWidth: true
    Layout.alignment: Qt.AlignTop

    Controls.Label {
        text: root.labelText
        font.bold: true
        Layout.fillWidth: true
    }

    IssueRadioGroup {
        id: prioridadeRadioGroup
        Layout.fillWidth: true
        model: [
            {
                value: "Highest",
                label: "Highest",
                icon: "flag-red"
            },
            {
                value: "High",
                label: "High",
                icon: "flag-yellow"
            },
            {
                value: "Medium",
                label: "Medium",
                icon: "flag"
            },
            {
                value: "Low",
                label: "Low",
                icon: "flag-green"
            },
            {
                value: "Lowest",
                label: "Lowest",
                icon: "flag-blue"
            }
        ]
        enabled: root.enabled
        selectedValue: root.model ? root.model.prioridade : "Medium"
        onValueChanged: function (value) {
            if (root.model) {
                root.model.prioridade = value;
            }
        }
    }
}
