pragma ComponentBehavior: Bound
/**
 * DevelopmentHeaderBar.qml
 *
 * Barra compacta: link Jira + PRs + branches em uma linha, com ícones.
 * Clique no chip abre popover com detalhes; botão no popover abre URL.
 */
import QtQuick
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

Item {
    id: root

    property var developmentData: null
    property var enrichedPrs: null
    property var enrichedBranches: null
    property string issueKey: ""
    property string issueSummary: ""
    property var jiraService: null
    property var clipboardHelper: null
    property var applicationWindow: null
    property var gitCommandHelper: null
    /** Chamado quando o usuário clica em Atualizar; recarrega detalhes da issue. */
    signal reloadRequested

    readonly property var branches: {
        var d = root.developmentData;
        if (!d || !d.branches)
            return [];
        return Array.isArray(d.branches) ? d.branches : Array.from(d.branches);
    }
    readonly property var pullRequests: {
        var d = root.developmentData;
        if (!d || !d.pullRequests)
            return [];
        return Array.isArray(d.pullRequests) ? d.pullRequests : Array.from(d.pullRequests);
    }
    readonly property bool hasData: branches.length > 0 || pullRequests.length > 0
    readonly property bool hasAny: developmentData !== null && typeof developmentData === "object"
    readonly property string singleRepoForBranch: {
        var repos = (developmentData && developmentData.repositories) ? developmentData.repositories : [];
        if (!repos || repos.length !== 1)
            return "";
        var r = Array.isArray(repos) ? repos[0] : (repos[0] !== undefined ? repos[0] : null);
        return (r && r.name) ? r.name : "";
    }

    visible: issueKey !== "" || hasAny
    implicitHeight: visible ? barRow.implicitHeight : 0

    function openPopoverForItem(chip, itemData, itemType, enrichedData) {
        var overlay = Controls.Overlay.overlay;
        if (!overlay || !chip)
            return;
        if (!popoverLoader.item)
            return;
        popoverLoader.item.itemData = itemData;
        popoverLoader.item.itemType = itemType;
        popoverLoader.item.enrichedPr = (itemType === "pr" ? enrichedData : null) || null;
        popoverLoader.item.enrichedBranch = (itemType === "branch" ? enrichedData : null) || null;
        popoverLoader.item.clipboardHelper = root.clipboardHelper;
        popoverLoader.item.applicationWindow = root.applicationWindow;
        popoverLoader.item.gitCommandHelper = root.gitCommandHelper;
        var pos = chip.mapToItem(overlay, 0, chip.height);
        popoverLoader.item.x = pos.x;
        popoverLoader.item.y = pos.y;
        // qmllint disable missing-property
        popoverLoader.item.open();
    // qmllint enable missing-property
    }

    Loader {
        id: popoverLoader
        active: root.hasAny || root.issueKey !== ""
        source: "../dialogs/DevelopmentItemPopover.qml"
        onLoaded: {
            if (item && Controls.Overlay.overlay)
                item.parent = Controls.Overlay.overlay;
            if (item) {
                item.clipboardHelper = root.clipboardHelper;
                item.applicationWindow = root.applicationWindow;
                item.gitCommandHelper = root.gitCommandHelper;
            }
        }
    }

    Flow {
        id: barRow
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Kirigami.Units.smallSpacing

        // Link Jira (ícone + issue key)
        Controls.Button {
            id: jiraLinkButton
            visible: root.issueKey !== ""
            flat: true
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            palette.buttonText: Kirigami.Theme.linkColor
            hoverEnabled: true
            icon.name: "globe"
            text: root.issueKey || ""
            display: Controls.AbstractButton.TextBesideIcon
            onClicked: {
                if (root.jiraService && root.issueKey && typeof root.jiraService.getIssueUrl === "function") {
                    var url = root.jiraService.getIssueUrl(root.issueKey);
                    if (url)
                        Qt.openUrlExternally(url);
                }
            }
            Controls.ToolTip.visible: hovered
            Controls.ToolTip.text: qsTr("Abrir issue no Jira")
        }

        // Botão Atualizar (reload development)
        Controls.Button {
            visible: root.issueKey !== "" && root.hasAny
            flat: true
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            icon.name: "view-refresh"
            display: Controls.AbstractButton.IconOnly
            onClicked: root.reloadRequested()
            Controls.ToolTip.visible: hovered
            Controls.ToolTip.text: qsTr("Atualizar painel Development")
        }

        // PRs (ícone + chip)
        Repeater {
            model: Math.min(root.pullRequests.length, 3)
            delegate: Controls.Button {
                id: prChip
                required property int index
                readonly property var pr: root.pullRequests[prChip.index]
                flat: true
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                palette.buttonText: Kirigami.Theme.linkColor
                hoverEnabled: true
                icon.name: "vcs-merge"
                text: {
                    var num = pr ? String(pr.number || "").replace(/^#+/, "") : "";
                    return num ? "#" + num : "";
                }
                display: Controls.AbstractButton.TextBesideIcon
                onClicked: {
                    var e = root.enrichedPrs && (Array.isArray(root.enrichedPrs) ? root.enrichedPrs[prChip.index] : root.enrichedPrs[prChip.index]);
                    root.openPopoverForItem(prChip, pr, "pr", e);
                }
            }
        }

        // Branches (ícone + chip)
        Repeater {
            model: Math.min(root.branches.length, 3)
            delegate: Controls.Button {
                id: brChip
                required property int index
                readonly property var br: root.branches[brChip.index]
                flat: true
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                palette.buttonText: Kirigami.Theme.linkColor
                hoverEnabled: true
                icon.name: "vcs-branch"
                text: {
                    var n = br ? br.name : "";
                    return n.length > 35 ? n.slice(0, 32) + "..." : n;
                }
                display: Controls.AbstractButton.TextBesideIcon
                onClicked: {
                    var eb = root.enrichedBranches && (Array.isArray(root.enrichedBranches) ? root.enrichedBranches[brChip.index] : root.enrichedBranches[brChip.index]);
                    root.openPopoverForItem(brChip, br, "branch", eb);
                }
            }
        }
    }
}
