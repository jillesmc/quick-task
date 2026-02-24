/**
 * GoogleDriveCommentDelegate.qml
 *
 * Card for a Google Drive comment (Issue #18): file, author, content, actions (Abrir no Drive, Importar para Jira, Resolver).
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

Rectangle {
    id: root

    required property var itemData
    property var googleDriveCommentsService: null

    signal openInDriveRequested(var item)
    signal importRequested(var item)
    signal resolveRequested(var item)

    function formatTime(createdTimeStr) {
        if (!createdTimeStr || typeof createdTimeStr !== "string") return ""
        var s = createdTimeStr.trim()
        if (s.length < 10) return s
        var datePart = s.indexOf("T") >= 0 ? s.split("T")[0] : s.substring(0, 10)
        var parts = datePart.split("-")
        if (parts.length >= 3) {
            var d = new Date(parseInt(parts[0]), parseInt(parts[1]) - 1, parseInt(parts[2]))
            if (!isNaN(d.getTime())) {
                var now = new Date()
                var delta = now - d
                var mins = Math.floor(delta / 60000)
                var hours = Math.floor(delta / 3600000)
                var days = Math.floor(delta / 86400000)
                if (mins < 60) return qsTr("Há %1 min").arg(mins)
                if (hours < 24) return qsTr("Há %1 h").arg(hours)
                if (days < 7) return qsTr("Há %1 dias").arg(days)
                return d.toLocaleDateString(Qt.locale(), "dd/MM/yyyy")
            }
        }
        return createdTimeStr
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
            text: root.itemData ? (root.itemData.file_type + ": " + (root.itemData.file_name || "")) : ""
            font.bold: true
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        Controls.Label {
            text: root.itemData && root.itemData.author
                ? (root.itemData.author + ": \"" + (root.itemData.content || "").substring(0, 120) + (root.itemData.content && root.itemData.content.length > 120 ? "…" : "") + "\"")
                : ""
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            maximumLineCount: 3
            elide: Text.ElideRight
        }

        Controls.Label {
            text: root.itemData ? root.formatTime(root.itemData.createdTime) : ""
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            color: Kirigami.Theme.disabledTextColor
            visible: !!(root.itemData && root.itemData.createdTime)
        }

        Controls.Label {
            text: root.itemData && root.itemData.quoted_text
                ? (qsTr("Contexto: ") + "\"" + (root.itemData.quoted_text || "").substring(0, 80) + (root.itemData.quoted_text.length > 80 ? "…" : "") + "\"")
                : ""
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            color: Kirigami.Theme.disabledTextColor
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            visible: !!(root.itemData && root.itemData.quoted_text)
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.largeSpacing
            Layout.alignment: Qt.AlignRight
            spacing: Kirigami.Units.smallSpacing

            Item { Layout.fillWidth: true }

            Controls.Button {
                text: qsTr("Abrir no Drive")
                icon.name: "document-open-remote"
                Accessible.name: qsTr("Abrir comentário no Google Drive")
                onClicked: {
                    if (root.itemData && root.itemData.file_url) {
                        Qt.openUrlExternally(root.itemData.file_url)
                    }
                    root.openInDriveRequested(root.itemData)
                }
            }
            Controls.Button {
                text: qsTr("Importar para Jira")
                icon.name: "document-import"
                Accessible.name: qsTr("Importar comentário para Jira")
                onClicked: {
                    if (root.itemData) {
                        root.importRequested(root.itemData)
                    }
                }
            }
            Controls.Button {
                text: qsTr("Resolver")
                icon.name: "dialog-ok-apply"
                enabled: !!root.googleDriveCommentsService
                Accessible.name: qsTr("Marcar comentário como resolvido")
                onClicked: {
                    if (root.itemData && root.googleDriveCommentsService) {
                        root.googleDriveCommentsService.resolveComment(root.itemData.file_id || "", root.itemData.id || "")
                    }
                    root.resolveRequested(root.itemData)
                }
            }
        }
    }
}
