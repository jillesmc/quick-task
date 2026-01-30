/**
 * DividerBar.qml
 *
 * Visual divider bar: 3 dots with hover cursor. Resize logic stays in the
 * parent (e.g. overlay with global coordinates). Used between resizable
 * sections in detail pane.
 */
import QtQuick
import org.kde.kirigami as Kirigami

Rectangle {
    id: root

    implicitHeight: 14
    color: "transparent"

    Row {
        anchors.centerIn: parent
        spacing: 4
        Repeater {
            model: 3
            Rectangle {
                width: 3
                height: 3
                radius: 1.5
                color: root.barMouseArea.containsMouse ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
                opacity: root.barMouseArea.containsMouse ? 1 : 0.6
                Behavior on color { ColorAnimation { duration: 150 } }
                Behavior on opacity { NumberAnimation { duration: 150 } }
            }
        }
    }

    MouseArea {
        id: barMouseArea
        anchors.fill: parent
        anchors.margins: -5
        hoverEnabled: true
        cursorShape: containsMouse ? Qt.SizeVerCursor : Qt.ArrowCursor
        propagateComposedEvents: true
        onPressed: function (mouse) { mouse.accepted = false; }
        onReleased: function (mouse) { mouse.accepted = false; }
        onPositionChanged: function (mouse) { mouse.accepted = false; }
    }
}
