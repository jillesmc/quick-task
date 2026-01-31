import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

// Delegate para exibir um Epic na lista.
// Recebe key, summary, status e index via bind automático do ListView (ListModel com roles de mesmo nome).

Controls.ItemDelegate {
    id: root

    required property string key
    required property string summary
    required property string status
    required property int index

    width: ListView.view ? ListView.view.width : implicitWidth

    background: Rectangle {
        color: root.checked ? Kirigami.Theme.highlightColor : "transparent"
        opacity: root.checked ? 0.2 : 1.0
    }

    contentItem: RowLayout {
        spacing: Kirigami.Units.smallSpacing

        Controls.Label {
            text: root.key
            font.bold: true
            Layout.preferredWidth: 110
        }

        Controls.Label {
            text: root.summary
            Layout.fillWidth: true
            elide: Text.ElideRight
        }

        Controls.Label {
            text: root.status
            Layout.preferredWidth: 120
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
