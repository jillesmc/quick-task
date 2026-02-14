/**
 * GoogleTaskItemDelegate.qml
 *
 * Um item de tarefa na aba Google Tasks: título, notas, due date, lista, botão Importar.
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

    ColumnLayout {
        id: contentColumn
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.smallSpacing
        visible: !!root.itemData

        Controls.Label {
            text: root.itemData ? (root.itemData.title || "(Sem título)") : ""
            font.bold: true
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        Controls.Label {
            text: root.itemData && root.itemData.notes
                ? root.itemData.notes
                : ""
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            color: Kirigami.Theme.disabledTextColor
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            maximumLineCount: 3
            elide: Text.ElideRight
            visible: !!(root.itemData && root.itemData.notes)
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Controls.Label {
                text: root.itemData && root.itemData.list_title
                    ? qsTr("Lista: %1").arg(root.itemData.list_title)
                    : ""
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                color: Kirigami.Theme.disabledTextColor
            }
            Controls.Label {
                text: root.itemData && root.itemData.due
                    ? qsTr("Vencimento: %1").arg(root.itemData.due)
                    : ""
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                color: Kirigami.Theme.disabledTextColor
                visible: !!(root.itemData && root.itemData.due)
            }
        }

        Controls.Button {
            text: qsTr("Importar para Jira")
            icon.name: "document-import"
            Layout.alignment: Qt.AlignRight
            onClicked: {
                if (root.itemData) {
                    root.importRequested(root.itemData);
                }
            }
        }
    }
}
