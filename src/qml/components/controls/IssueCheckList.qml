pragma ComponentBehavior: Bound
/**
 * IssueCheckList.qml
 *
 * Lista de checkboxes a partir de um model (array de {col1, col2}).
 * Recebe model, enabled, selectedValues (array de col1); emite selectionChanged(values).
 * Não referencia hierarquia externa - apenas propriedades passadas.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: checkList

    property var model: []
    property bool enabled: true
    property var selectedValues: []  // array of col1 strings

    signal selectionChanged(var values)

    spacing: Kirigami.Units.smallSpacing

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
                var vals = checkList.selectedValues || []
                return vals.indexOf(checkDelegate.modelData.col1) >= 0
            }

            contentItem: RowLayout {
                spacing: Kirigami.Units.largeSpacing
                Controls.Label {
                    text: checkDelegate.modelData.col1 || ""
                    font.bold: true
                    Layout.preferredWidth: 150
                }
                Controls.Label {
                    text: checkDelegate.modelData.col2 || ""
                    font.italic: true
                    opacity: 0.7
                    Layout.fillWidth: true
                }
            }

            onCheckedChanged: {
                var vals = (checkList.selectedValues || []).slice()
                var col1 = checkDelegate.modelData.col1
                var idx = vals.indexOf(col1)
                if (checked) {
                    if (idx < 0) {
                        vals.push(col1)
                    }
                } else {
                    if (idx >= 0) {
                        vals.splice(idx, 1)
                    }
                }
                checkList.selectionChanged(vals)
            }
        }
    }
}
