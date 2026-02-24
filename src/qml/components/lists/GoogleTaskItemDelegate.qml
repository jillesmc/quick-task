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

    function formatDueDate(rfc3339Str) {
        if (!rfc3339Str || typeof rfc3339Str !== "string") return ""
        var s = rfc3339Str.trim()
        if (s.indexOf("T") >= 0) return s.split("T")[0] || ""
        return s.split(" ")[0] || s
    }

    function sourceLabel() {
        if (!root.itemData) return ""
        var src = root.itemData.assignment_source || ""
        if (src === "SPACE") {
            var displayName = (root.itemData.space_display_name || "").trim()
            return displayName.length > 0 ? displayName : qsTr("Chat Space")
        }
        if (src === "DOCUMENT") return qsTr("Google Docs")
        return ""
    }

    function isOverdue() {
        if (!root.itemData || !root.itemData.due) return false
        var dueStr = root.formatDueDate(root.itemData.due)
        if (!dueStr) return false
        var parts = dueStr.split("-")
        if (parts.length < 3) return false
        var dueDate = new Date(parseInt(parts[0]), parseInt(parts[1]) - 1, parseInt(parts[2]))
        var today = new Date()
        today.setHours(0, 0, 0, 0)
        dueDate.setHours(0, 0, 0, 0)
        return dueDate.getTime() < today.getTime()
    }

    function hasSpaceLink() {
        return root.itemData && (root.itemData.assignment_link || "").trim().length > 0
    }

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

        // Linha 1: Lista e Vencimento (metadados da tarefa)
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing * 2

            Controls.Label {
                text: root.itemData && root.itemData.list_title
                    ? qsTr("Lista: %1").arg(root.itemData.list_title)
                    : ""
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                color: Kirigami.Theme.disabledTextColor
            }
            Controls.Label {
                text: "·"
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                color: Kirigami.Theme.disabledTextColor
                visible: !!(root.itemData && root.itemData.list_title) && !!(root.itemData && root.itemData.due)
            }
            Controls.Label {
                text: root.itemData && root.itemData.due
                    ? qsTr("Vencimento: %1").arg(root.formatDueDate(root.itemData.due))
                    : ""
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                color: root.isOverdue() ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.disabledTextColor
                visible: !!(root.itemData && root.itemData.due)
            }
        }

        // Linha 2: Origem (Space/Docs) — link em linha própria, afastado do botão de ação
        RowLayout {
            Layout.fillWidth: true
            visible: root.sourceLabel().length > 0

            Item {
                Layout.preferredWidth: spaceLabel.implicitWidth
                Layout.preferredHeight: spaceLabel.implicitHeight

                Controls.Label {
                    id: spaceLabel
                    anchors.fill: parent
                    text: root.sourceLabel()
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    color: root.hasSpaceLink() ? Kirigami.Theme.linkColor : Kirigami.Theme.disabledTextColor
                }
                MouseArea {
                    enabled: root.hasSpaceLink()
                    hoverEnabled: root.hasSpaceLink()
                    anchors.fill: parent
                    cursorShape: root.hasSpaceLink() ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: {
                        if (root.hasSpaceLink()) {
                            var link = (root.itemData.assignment_link || "").trim()
                            if (link) Qt.openUrlExternally(link)
                        }
                    }
                }
                Accessible.role: Accessible.Link
                Accessible.name: root.sourceLabel()
                Accessible.description: root.hasSpaceLink() ? qsTr("Abrir no Google Chat") : ""
            }
        }

        // Área de ação: margem superior para separar claramente do conteúdo
        Controls.Button {
            text: qsTr("Importar para Jira")
            icon.name: "document-import"
            Layout.topMargin: Kirigami.Units.largeSpacing
            Layout.alignment: Qt.AlignRight
            Accessible.name: qsTr("Importar tarefa para Jira")
            onClicked: {
                if (root.itemData) {
                    root.importRequested(root.itemData);
                }
            }
        }
    }
}
