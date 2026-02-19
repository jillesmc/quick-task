/**
 * EditPreviewToggle.qml
 *
 * RowLayout with two buttons: Edit and Preview. Active button highlighted,
 * inactive flat. Emits modeChanged(bool editMode).
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

RowLayout {
    id: root

    property bool isEditMode: true
    signal modeChanged(bool editMode)

    spacing: Kirigami.Units.smallSpacing

    Controls.ToolButton {
        icon.name: "document-edit"
        display: Controls.AbstractButton.IconOnly
        flat: !root.isEditMode
        highlighted: root.isEditMode
        Accessible.name: qsTr("Modo edição")
        onClicked: {
            if (!root.isEditMode) {
                root.isEditMode = true
                root.modeChanged(true)
            }
        }
    }

    Controls.ToolButton {
        icon.name: "document-preview"
        display: Controls.AbstractButton.IconOnly
        flat: root.isEditMode
        highlighted: !root.isEditMode
        Accessible.name: qsTr("Modo visualização")
        onClicked: {
            if (root.isEditMode) {
                root.isEditMode = false
                root.modeChanged(false)
            }
        }
    }
}
