/**
 * GoogleCalendarEventDelegate.qml
 *
 * Um item de evento na aba Google Calendar: título, horário, duração, botão Importar.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

Rectangle {
    id: root

    required property var itemData

    signal importRequested(var item)

    width: parent ? parent.width - Kirigami.Units.smallSpacing * 2 : 200
    height: itemData ? (contentColumn.implicitHeight + Kirigami.Units.largeSpacing * 2) : 0
    visible: !!itemData
    color: Kirigami.Theme.backgroundColor
    border.color: Kirigami.Theme.disabledTextColor
    border.width: 1
    radius: Kirigami.Units.smallSpacing

    function formatTime(isoStr) {
        if (!isoStr || typeof isoStr !== "string") return ""
        if (isoStr.indexOf("T") >= 0) {
            var t = isoStr.split("T")[1] || ""
            return t.replace(/[+-]\d{2}:\d{2}$/, "").substring(0, 5)
        }
        return ""
    }

    ColumnLayout {
        id: contentColumn
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.smallSpacing
        visible: !!root.itemData

        Controls.Label {
            text: root.itemData ? (root.itemData.summary || "(Sem título)") : ""
            font.bold: true
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Controls.Label {
                text: root.itemData ? root.formatTime(root.itemData.start) : ""
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                color: Kirigami.Theme.disabledTextColor
            }
            Controls.Label {
                text: root.itemData ? qsTr("%1 min").arg(root.itemData.duration_minutes || 0) : ""
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                color: Kirigami.Theme.disabledTextColor
            }
        }

        Controls.Button {
            text: qsTr("Importar para Jira")
            icon.name: "document-import"
            Layout.topMargin: Kirigami.Units.largeSpacing
            Layout.alignment: Qt.AlignRight
            Accessible.name: qsTr("Importar evento para Jira")
            onClicked: {
                if (root.itemData) {
                    root.importRequested(root.itemData);
                }
            }
        }
    }
}
