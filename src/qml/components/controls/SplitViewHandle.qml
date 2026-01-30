/**
 * SplitViewHandle.qml
 *
 * Handle minimalista estilo macOS para SplitView: três pontinhos verticais.
 * Usa Kirigami.Theme para light/dark. Área clicável ampla (implicitWidth/Height).
 * Puramente visual — não trata eventos para não interferir em hovered/pressed.
 */
import QtQuick
import QtQuick.Controls
import org.kde.kirigami as Kirigami

Item {
    id: root

    implicitWidth: 10
    implicitHeight: 10

    // Três pontinhos verticais (orientação horizontal do SplitView = divisor vertical)
    Column {
        anchors.centerIn: parent
        spacing: 4

        Repeater {
            model: 3
            Rectangle {
                width: 4
                height: 4
                radius: 2
                color: {
                    var base = Kirigami.Theme.neutralTextColor
                    if (SplitHandle.hovered) {
                        return Qt.darker(base, 1.3)
                    }
                    return base
                }
                opacity: SplitHandle.hovered ? 1.0 : 0.65

                Behavior on color {
                    ColorAnimation { duration: 150 }
                }
                Behavior on opacity {
                    NumberAnimation { duration: 150 }
                }
            }
        }
    }
}
