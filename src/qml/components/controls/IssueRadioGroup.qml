pragma ComponentBehavior: Bound
/**
 * IssueRadioGroup.qml
 *
 * Grupo de radio buttons a partir de um model (array de strings).
 * Recebe model, enabled, selectedValue; emite valueChanged(value).
 * Não referencia hierarquia externa - apenas propriedades passadas.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: group

    property var model: []
    property bool enabled: true
    property string selectedValue: ""

    signal valueChanged(string value)

    spacing: Kirigami.Units.smallSpacing

    Column {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        Repeater {
            id: repeater
            model: group.model

            Controls.RadioButton {
                id: radioButton
                required property var modelData
                text: String(radioButton.modelData)
                enabled: group.enabled
                checked: group.selectedValue === String(radioButton.modelData)
                onCheckedChanged: {
                    if (checked) {
                        group.valueChanged(String(radioButton.modelData))
                    }
                }
            }
        }
    }
}
