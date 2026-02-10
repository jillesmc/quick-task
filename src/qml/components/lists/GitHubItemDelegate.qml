/**
 * GitHubItemDelegate.qml
 *
 * Um item de PR ou Issue na aba GitHub: repo #num, título, data, clicável para abrir no navegador, botão Importar para Jira.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

Rectangle {
    id: root

    required property var itemData
    property bool isIssue: false
    property bool showReviewKind: false
    property string reviewKindLabel: ""

    signal importToJiraRequested(var item)

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

        Item {
            Layout.fillWidth: true
            implicitHeight: repoTitleColumn.implicitHeight

            ColumnLayout {
                id: repoTitleColumn
                anchors.fill: parent
                spacing: Kirigami.Units.smallSpacing

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    Controls.Label {
                        text: root.itemData ? ((root.itemData.repo || "") + " #" + (root.itemData.number || "")) : ""
                        font.bold: true
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                    Controls.Label {
                        text: root.isIssue ? qsTr("Issue") : qsTr("PR")
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        color: Kirigami.Theme.disabledTextColor
                    }
                    Controls.Label {
                        text: root.showReviewKind ? root.reviewKindLabel : ""
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        color: Kirigami.Theme.highlightColor
                        visible: root.showReviewKind && root.reviewKindLabel
                    }
                }

                Controls.Label {
                    text: root.itemData ? (root.itemData.title || "") : ""
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                hoverEnabled: true
                onClicked: {
                    if (root.itemData && root.itemData.url) {
                        Qt.openUrlExternally(root.itemData.url);
                    }
                }
            }
        }

        Controls.Label {
            text: root.itemData ? qsTr("Criado em: %1").arg(root.itemData.created_at || "") : ""
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            color: Kirigami.Theme.disabledTextColor
            Layout.fillWidth: true
        }

        Controls.Button {
            text: qsTr("Importar para Jira")
            icon.name: "document-import"
            Layout.alignment: Qt.AlignRight
            onClicked: {
                if (root.itemData) {
                    root.importToJiraRequested(root.itemData);
                }
            }
        }
    }
}
