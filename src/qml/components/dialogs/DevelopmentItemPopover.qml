pragma ComponentBehavior: Bound
/**
 * DevelopmentItemPopover.qml
 *
 * Popup rico para exibir detalhes de PR ou branch. Status com cor, botão "Abrir no GitHub".
 * Para branches e PRs: seção gh CLI com comandos clone e checkout.
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
    property var clipboardHelper: null
    property var applicationWindow: null
    property var gitCommandHelper: null

    modal: false
    closePolicy: Controls.Popup.CloseOnEscape | Controls.Popup.CloseOnPressOutside
    padding: Kirigami.Units.smallSpacing * 2

    readonly property bool isPr: itemType === "pr"
    readonly property bool isBranch: itemType === "branch"

    // Branch: gh repo clone + git checkout
    readonly property string ghBranchCloneCommand: {
        if (!root.isBranch || !root.itemData || !root.gitCommandHelper)
            return "";
        return root.gitCommandHelper.getGhBranchCloneCommand(root.itemData.url || "", root.itemData.name || "");
    }
    readonly property string ghBranchCheckoutCommand: {
        if (!root.isBranch || !root.itemData || !root.gitCommandHelper)
            return "";
        return root.gitCommandHelper.getGhBranchCheckoutCommand(root.itemData.name || "");
    }
    readonly property bool showBranchCommands: root.isBranch && root.ghBranchCloneCommand !== ""

    // PR: gh repo clone + gh pr checkout
    readonly property string ghPrCloneCommand: {
        if (!root.isPr || !root.itemData || !root.gitCommandHelper)
            return "";
        return root.gitCommandHelper.getGhPrCloneCommand(root.itemData.url || "", root.itemData.number || "");
    }
    readonly property string ghPrCheckoutCommand: {
        if (!root.isPr || !root.itemData || !root.gitCommandHelper)
            return "";
        return root.gitCommandHelper.getGhPrCheckoutCommand(root.itemData.url || "", root.itemData.number || "");
    }
    readonly property bool showPrCommands: root.isPr && root.ghPrCloneCommand !== ""

    contentWidth: contentColumn.implicitWidth + root.padding * 2
    contentHeight: contentColumn.implicitHeight + root.padding * 2

    background: Rectangle {
        color: Kirigami.Theme.backgroundColor
        border.color: Kirigami.Theme.disabledTextColor
        border.width: 1
        radius: Kirigami.Units.smallSpacing
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
                    if (!root.itemData)
                        return Kirigami.Theme.textColor;
                    var s = (root.itemData.state || "").toLowerCase();
                    if (s === "open")
                        return Kirigami.Theme.positiveTextColor;
                    if (s === "merged")
                        return Kirigami.Theme.disabledTextColor;
                    return Kirigami.Theme.textColor;
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
                if (!root.enrichedPr)
                    return "";
                var parts = [];
                if (root.enrichedPr.approvalsCount !== undefined)
                    parts.push(qsTr("%1 approval(s)").arg(root.enrichedPr.approvalsCount));
                if (root.enrichedPr.changesRequested)
                    parts.push(qsTr("Changes requested"));
                if (root.enrichedPr.mergeableState)
                    parts.push(root.enrichedPr.mergeableState);
                return parts.join(" • ");
            }
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            color: Kirigami.Theme.disabledTextColor
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        // gh CLI Commands (branches e PRs GitHub)
        ColumnLayout {
            visible: root.showBranchCommands || root.showPrCommands
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Controls.Label {
                text: qsTr("gh CLI")
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                font.bold: true
                color: Kirigami.Theme.disabledTextColor
            }

            // Branch: Clone + Checkout
            ColumnLayout {
                visible: root.showBranchCommands
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing / 2

                Controls.Label {
                    text: qsTr("Clone")
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    color: Kirigami.Theme.disabledTextColor
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: branchCloneText.implicitHeight + Kirigami.Units.smallSpacing * 2
                    color: Kirigami.Theme.alternateBackgroundColor
                    radius: Kirigami.Units.smallSpacing
                    border.color: Kirigami.Theme.disabledTextColor
                    border.width: 1

                    Controls.Label {
                        id: branchCloneText
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.smallSpacing
                        text: root.ghBranchCloneCommand
                        font.family: "monospace"
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        wrapMode: Text.Wrap
                        elide: Text.ElideRight
                    }
                }
                Controls.Button {
                    text: qsTr("Copiar Clone")
                    icon.name: "edit-copy"
                    flat: true
                    Layout.alignment: Qt.AlignLeft
                    onClicked: {
                        if (root.clipboardHelper && root.ghBranchCloneCommand) {
                            root.clipboardHelper.setText(root.ghBranchCloneCommand);
                            if (root.applicationWindow && typeof root.applicationWindow.showPassiveNotification === "function") {
                                root.applicationWindow.showPassiveNotification(qsTr("Comando clone copiado!"), 2000);
                            }
                        }
                    }
                }

                Controls.Label {
                    text: qsTr("Checkout")
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    color: Kirigami.Theme.disabledTextColor
                    Layout.topMargin: Kirigami.Units.smallSpacing
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: branchCheckoutText.implicitHeight + Kirigami.Units.smallSpacing * 2
                    color: Kirigami.Theme.alternateBackgroundColor
                    radius: Kirigami.Units.smallSpacing
                    border.color: Kirigami.Theme.disabledTextColor
                    border.width: 1

                    Controls.Label {
                        id: branchCheckoutText
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.smallSpacing
                        text: root.ghBranchCheckoutCommand
                        font.family: "monospace"
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        wrapMode: Text.Wrap
                        elide: Text.ElideRight
                    }
                }
                Controls.Button {
                    text: qsTr("Copiar Checkout")
                    icon.name: "edit-copy"
                    flat: true
                    Layout.alignment: Qt.AlignLeft
                    onClicked: {
                        if (root.clipboardHelper && root.ghBranchCheckoutCommand) {
                            root.clipboardHelper.setText(root.ghBranchCheckoutCommand);
                            if (root.applicationWindow && typeof root.applicationWindow.showPassiveNotification === "function") {
                                root.applicationWindow.showPassiveNotification(qsTr("Comando checkout copiado!"), 2000);
                            }
                        }
                    }
                }
            }

            // PR: Clone + Checkout
            ColumnLayout {
                visible: root.showPrCommands
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing / 2

                Controls.Label {
                    text: qsTr("Clone")
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    color: Kirigami.Theme.disabledTextColor
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: prCloneText.implicitHeight + Kirigami.Units.smallSpacing * 2
                    color: Kirigami.Theme.alternateBackgroundColor
                    radius: Kirigami.Units.smallSpacing
                    border.color: Kirigami.Theme.disabledTextColor
                    border.width: 1

                    Controls.Label {
                        id: prCloneText
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.smallSpacing
                        text: root.ghPrCloneCommand
                        font.family: "monospace"
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        wrapMode: Text.Wrap
                        elide: Text.ElideRight
                    }
                }
                Controls.Button {
                    text: qsTr("Copiar Clone")
                    icon.name: "edit-copy"
                    flat: true
                    Layout.alignment: Qt.AlignLeft
                    onClicked: {
                        if (root.clipboardHelper && root.ghPrCloneCommand) {
                            root.clipboardHelper.setText(root.ghPrCloneCommand);
                            if (root.applicationWindow && typeof root.applicationWindow.showPassiveNotification === "function") {
                                root.applicationWindow.showPassiveNotification(qsTr("Comando clone copiado!"), 2000);
                            }
                        }
                    }
                }

                Controls.Label {
                    text: qsTr("Checkout")
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    color: Kirigami.Theme.disabledTextColor
                    Layout.topMargin: Kirigami.Units.smallSpacing
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: prCheckoutText.implicitHeight + Kirigami.Units.smallSpacing * 2
                    color: Kirigami.Theme.alternateBackgroundColor
                    radius: Kirigami.Units.smallSpacing
                    border.color: Kirigami.Theme.disabledTextColor
                    border.width: 1

                    Controls.Label {
                        id: prCheckoutText
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.smallSpacing
                        text: root.ghPrCheckoutCommand
                        font.family: "monospace"
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        wrapMode: Text.Wrap
                        elide: Text.ElideRight
                    }
                }
                Controls.Button {
                    text: qsTr("Copiar Checkout")
                    icon.name: "edit-copy"
                    flat: true
                    Layout.alignment: Qt.AlignLeft
                    onClicked: {
                        if (root.clipboardHelper && root.ghPrCheckoutCommand) {
                            root.clipboardHelper.setText(root.ghPrCheckoutCommand);
                            if (root.applicationWindow && typeof root.applicationWindow.showPassiveNotification === "function") {
                                root.applicationWindow.showPassiveNotification(qsTr("Comando checkout copiado!"), 2000);
                            }
                        }
                    }
                }
            }
        }

        Controls.Button {
            Layout.alignment: Qt.AlignRight
            text: root.isPr ? qsTr("Abrir PR no GitHub") : qsTr("Abrir no GitHub")
            icon.name: "globe"
            flat: true
            onClicked: {
                var url = root.itemData ? root.itemData.url : "";
                if (url)
                    Qt.openUrlExternally(url);
                root.close();
            }
        }
    }
}
