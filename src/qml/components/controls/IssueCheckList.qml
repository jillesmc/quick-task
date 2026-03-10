pragma ComponentBehavior: Bound
/**
 * IssueCheckList.qml
 *
 * Lista de checkboxes a partir de um model (array de { value, label } ou { col1, col2 }).
 * value/col1 é o identificador (ex.: objectId); label/col2 é exibido.
 * Recebe model, enabled, selectedValues (array de value); emite selectionChanged(values).
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: checkList

    property var model: []
    property bool enabled: true
    property var selectedValues: []  // array of value strings (e.g. objectIds)

    signal selectionChanged(var values)

    spacing: Kirigami.Units.smallSpacing

    function itemValue(data) {
        if (!data)
            return "";
        if (typeof data.value !== "undefined")
            return String(data.value);
        if (typeof data.col1 !== "undefined")
            return String(data.col1);
        return String(data);
    }
    function itemLabel(data) {
        if (!data)
            return "";
        if (typeof data.label !== "undefined")
            return String(data.label);
        if (typeof data.col2 !== "undefined")
            return String(data.col2);
        if (typeof data.col1 !== "undefined")
            return String(data.col1);
        return String(data);
    }

    ListView {
        id: listView
        Layout.fillWidth: true
        implicitHeight: contentHeight
        interactive: false
        clip: true
        model: checkList.model

        delegate: Controls.CheckDelegate {
            id: checkDelegate
            required property var modelData
            width: ListView.view ? ListView.view.width : 0
            enabled: checkList.enabled
            checked: {
                var vals = checkList.selectedValues || [];
                return vals.indexOf(checkList.itemValue(checkDelegate.modelData)) >= 0;
            }

            contentItem: Controls.Label {
                text: checkList.itemLabel(checkDelegate.modelData)
                font.bold: true
            }

            onCheckedChanged: {
                var vals = (checkList.selectedValues || []).slice();
                var v = checkList.itemValue(checkDelegate.modelData);
                var idx = vals.indexOf(v);
                if (checked) {
                    if (idx < 0)
                        vals.push(v);
                } else {
                    if (idx >= 0)
                        vals.splice(idx, 1);
                }
                checkList.selectionChanged(vals);
            }
        }
    }
}
