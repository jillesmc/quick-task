pragma ComponentBehavior: Bound
/**
 * DevelopmentItemPopover.qml
 *
 * Popup rico para exibir detalhes de PR ou branch. Status com cor, botão "Abrir no GitHub".
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

Controls.Popup {
    id: root

    property var itemData: null
    property string itemType: "pr"  // "pr" | "branch"
    property var enrichedPr: null
    /** Para branch: dados enriquecidos do GitHub (commitsAhead, commitsBehind). Só exibimos ahead/behind quando presente. */
    property var enrichedBranch: null

    modal: false
    closePolicy: Controls.Popup.CloseOnEscape | Controls.Popup.CloseOnPressOutside
    padding: Kirigami.Units.smallSpacing * 2

    readonly property bool isPr: itemType === "pr"
    readonly property bool isBranch: itemType === "branch"

    contentWidth: contentColumn.implicitWidth + root.padding * 2
    contentHeight: contentColumn.implicitHeight + root.padding * 2

    background: Rectangle {
        color: Kirigami.Theme.backgroundColor
        border.color: Kirigami.Theme.disabledTextColor
        border.width: 1
        radius: 4
    }

    ColumnLayout {
        id: contentColumn
        spacing: Kirigami.Units.smallSpacing

        Controls.Label {
            visible: root.isPr && root.itemData
            Layout.fillWidth: true
            text: (root.itemData && root.itemData.title) ? root.itemData.title : ""
            wrapMode: Text.WordWrap
            maximumLineCount: 3
            elide: Text.ElideRight
            font.bold: true
        }

        Controls.Label {
            visible: root.isBranch && root.itemData
            Layout.fillWidth: true
            text: (root.itemData && root.itemData.name) ? root.itemData.name : ""
            wrapMode: Text.NoWrap
            elide: Text.ElideRight
            font.bold: true
        }

        RowLayout {
            visible: root.isPr && root.itemData
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Controls.Label {
                id: statusLabel
                text: root.itemData ? (root.itemData.state || "").toUpperCase() : ""
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                font.bold: true
                color: {
                    if (!root.itemData) return Kirigami.Theme.textColor
                    var s = (root.itemData.state || "").toLowerCase()
                    if (s === "open") return Kirigami.Theme.positiveTextColor
                    if (s === "merged") return Kirigami.Theme.disabledTextColor
                    return Kirigami.Theme.textColor
                }
            }
            Controls.Label {
                text: "•"
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                color: Kirigami.Theme.disabledTextColor
            }
            Controls.Label {
                Layout.fillWidth: true
                text: root.itemData ? ((root.itemData.sourceBranch || "") + " → " + (root.itemData.targetBranch || "")) : ""
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                color: Kirigami.Theme.disabledTextColor
                elide: Text.ElideRight
            }
        }

        Controls.Label {
            visible: root.isBranch && root.itemData && root.enrichedBranch && (root.enrichedBranch.commitsAhead !== undefined || root.enrichedBranch.commitsBehind !== undefined)
            text: root.enrichedBranch ? qsTr("Ahead %1 • Behind %2").arg(root.enrichedBranch.commitsAhead || 0).arg(root.enrichedBranch.commitsBehind || 0) : ""
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            color: Kirigami.Theme.disabledTextColor
        }

        Controls.Label {
            visible: root.isBranch && root.itemData && root.itemData.lastCommitTime
            text: root.itemData ? qsTr("Last commit: %1").arg(root.itemData.lastCommitTime) : ""
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            color: Kirigami.Theme.disabledTextColor
        }

        Controls.Label {
            visible: root.isPr && root.enrichedPr && (root.enrichedPr.approvalsCount !== undefined || root.enrichedPr.changesRequested || root.enrichedPr.mergeableState)
            text: {
                if (!root.enrichedPr) return ""
                var parts = []
                if (root.enrichedPr.approvalsCount !== undefined) parts.push(qsTr("%1 approval(s)").arg(root.enrichedPr.approvalsCount))
                if (root.enrichedPr.changesRequested) parts.push(qsTr("Changes requested"))
                if (root.enrichedPr.mergeableState) parts.push(root.enrichedPr.mergeableState)
                return parts.join(" • ")
            }
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            color: Kirigami.Theme.disabledTextColor
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        Controls.Button {
            Layout.alignment: Qt.AlignRight
            text: root.isPr ? qsTr("Abrir PR no GitHub") : qsTr("Abrir no GitHub")
            icon.name: "globe"
            flat: true
            onClicked: {
                var url = root.itemData ? root.itemData.url : ""
                if (url) Qt.openUrlExternally(url)
                root.close()
            }
        }
    }
}
