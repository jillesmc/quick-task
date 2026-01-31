pragma ComponentBehavior: Bound
/**
 * IssueRadioGroup.qml
 *
 * Grupo de radio buttons a partir de um model (array de strings ou array de { value, label }).
 * Quando model é array de objetos, value é o identificador (ex.: objectId) e label é exibido.
 * Recebe model, enabled, selectedValue; emite valueChanged(value).
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

    function itemValue(data) {
        if (typeof data === "string") return data
        if (data && typeof data.value !== "undefined") return String(data.value)
        return data ? String(data.label || data) : ""
    }
    function itemLabel(data) {
        if (typeof data === "string") return data
        if (data && typeof data.label !== "undefined") return String(data.label)
        return data ? String(data) : ""
    }

    Column {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        Repeater {
            id: repeater
            model: group.model

            Controls.RadioButton {
                id: radioButton
                required property var modelData
                text: group.itemLabel(radioButton.modelData)
                enabled: group.enabled
                checked: group.selectedValue === group.itemValue(radioButton.modelData)
                onCheckedChanged: {
                    if (checked) {
                        group.valueChanged(group.itemValue(radioButton.modelData))
                    }
                }
            }
        }
    }
}
