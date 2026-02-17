pragma ComponentBehavior: Bound
/**
 * IssueRadioGroup.qml
 *
 * Grupo de radio buttons a partir de um model (array de strings ou array de { value, label, icon }).
 * Quando model é array de objetos, value é o identificador, label é exibido, icon (opcional) à esquerda.
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
    /** Se >= 0, apenas itens com index >= minEnabledIndex ficam habilitados (ex.: status não pode voltar atrás). -1 = todos habilitados. */
    property int minEnabledIndex: -1

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
    function itemIcon(data) {
        if (!data || typeof data !== "object") return ""
        if (data.icon !== undefined) return String(data.icon)
        return ""
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
                required property int index
                display: group.itemIcon(radioButton.modelData) ? Controls.AbstractButton.TextBesideIcon : Controls.AbstractButton.TextOnly
                icon.name: group.itemIcon(radioButton.modelData) || undefined
                text: group.itemLabel(radioButton.modelData)
                enabled: group.enabled && (group.minEnabledIndex < 0 || radioButton.index >= group.minEnabledIndex)
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
