pragma ComponentBehavior: Bound
/**
 * DevelopmentPanel.qml
 *
 * Exibe branches e pull requests vinculados à issue (dados do Jira dev-status).
 * PRs primeiro, depois branches; links abrem no GitHub. Estado vazio quando não há dados.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami
import "../controls"

Item {
    id: root

    /** Objeto com branches e pullRequests (listas), ou null quando o painel de development está desativado. */
    property var developmentData: null
    /** Lista enriquecida de PRs (mesma ordem que pullRequests), com approvalsCount, changesRequested, mergeableState. */
    property var enrichedPrs: null
    /** Chave da issue (para link "Ver mais no Jira") */
    property string issueKey: ""
    /** Resumo da issue (para sugestão do nome da branch) */
    property string issueSummary: ""
    /** Serviço Jira para getIssueUrl (opcional) */
    property var jiraService: null
    /** Serviço GitHub para criar branch (opcional) */
    property var githubService: null

    readonly property var branches: {
        var d = root.developmentData
        if (!d || !Array.isArray(d.branches)) return []
        return d.branches
    }
    readonly property var pullRequests: {
        var d = root.developmentData
        if (!d || !Array.isArray(d.pullRequests)) return []
        return d.pullRequests
    }
    readonly property bool hasData: branches.length > 0 || pullRequests.length > 0
    /** Mostrar bloco quando development foi carregado (developmentData não é null). */
    readonly property bool hasAny: developmentData !== null && typeof developmentData === "object"
    /** Um único repo nos dados do Jira para pré-preencher o diálogo Criar branch. */
    readonly property string singleRepoForBranch: {
        var repos = (developmentData && developmentData.repositories) ? developmentData.repositories : []
        if (!Array.isArray(repos) || repos.length !== 1) return ""
        var r = repos[0]
        return (r && r.name) ? r.name : ""
    }

    visible: hasAny
    implicitHeight: visible ? contentColumn.implicitHeight : 0

    ColumnLayout {
        id: contentColumn
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Kirigami.Units.smallSpacing
        visible: root.hasAny

        DividerBar {
            Layout.fillWidth: true
        }

        RowLayout {
            Layout.fillWidth: true
            Kirigami.Heading {
                level: 4
                text: qsTr("Development")
                Layout.fillWidth: true
            }
            Controls.Button {
                visible: root.githubService && root.githubService.available
                text: qsTr("Criar branch")
                flat: true
                onClicked: {
                    // qmllint disable missing-property
                    if (createBranchDialogLoader.item && typeof createBranchDialogLoader.item.openWith === "function") {
                        createBranchDialogLoader.item.openWith(
                            root.issueKey,
                            root.issueSummary,
                            root.singleRepoForBranch,
                            root.githubService
                        )
                    }
                    // qmllint enable missing-property
                }
            }
        }
        Loader {
            id: createBranchDialogLoader
            active: root.hasAny
            source: "../dialogs/CreateBranchDialog.qml"
            onLoaded: if (item) item.visible = false
        }

        // Pull Requests (primeiro)
        Repeater {
            model: Math.min(root.pullRequests.length, 3)
            delegate: Item {
                id: prItem
                required property int index
                readonly property int idx: index
                Layout.fillWidth: true
                Layout.preferredHeight: prDelegate.implicitHeight
                implicitHeight: prDelegate.implicitHeight

                ColumnLayout {
                    id: prDelegate
                    anchors.fill: parent
                    spacing: 2

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        Controls.Label {
                            text: "#" + (root.pullRequests[prItem.idx].number || "") + ": " + (root.pullRequests[prItem.idx].title || "")
                            font.bold: true
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            color: Kirigami.Theme.linkColor
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                        }
                        Controls.Button {
                            text: qsTr("Ver PR →")
                            flat: true
                            Layout.alignment: Qt.AlignRight
                            onClicked: {
                                var url = root.pullRequests[prItem.idx].url
                                if (url) Qt.openUrlExternally(url)
                            }
                        }
                    }
                    Controls.Label {
                        text: (root.pullRequests[prItem.idx].state || "").toUpperCase() + " • " +
                              (root.pullRequests[prItem.idx].sourceBranch || "") + " → " + (root.pullRequests[prItem.idx].targetBranch || "")
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        color: Kirigami.Theme.disabledTextColor
                        Layout.fillWidth: true
                    }
                    Controls.Label {
                        visible: root.enrichedPrs && Array.isArray(root.enrichedPrs) && root.enrichedPrs[prItem.idx] && (root.enrichedPrs[prItem.idx].approvalsCount !== undefined || root.enrichedPrs[prItem.idx].mergeableState)
                        text: {
                            var e = root.enrichedPrs && root.enrichedPrs[prItem.idx] ? root.enrichedPrs[prItem.idx] : null
                            if (!e) return ""
                            var parts = []
                            if (e.approvalsCount !== undefined) parts.push(qsTr("%1 approval(s)").arg(e.approvalsCount))
                            if (e.changesRequested) parts.push(qsTr("Changes requested"))
                            if (e.mergeableState) parts.push(e.mergeableState)
                            return parts.join(" • ")
                        }
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        color: Kirigami.Theme.disabledTextColor
                        Layout.fillWidth: true
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        var url = root.pullRequests[prItem.idx].url
                        if (url) Qt.openUrlExternally(url)
                    }
                }
            }
        }

        // Branches
        Repeater {
            model: Math.min(root.branches.length, 3)
            delegate: Item {
                id: brItem
                required property int index
                readonly property int idx: index
                Layout.fillWidth: true
                Layout.preferredHeight: brDelegate.implicitHeight
                implicitHeight: brDelegate.implicitHeight

                ColumnLayout {
                    id: brDelegate
                    anchors.fill: parent
                    spacing: 2

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        Controls.Label {
                            text: root.branches[brItem.idx].name || ""
                            font.bold: true
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            color: Kirigami.Theme.linkColor
                        }
                        Controls.Button {
                            text: qsTr("Ver no GitHub →")
                            flat: true
                            Layout.alignment: Qt.AlignRight
                            onClicked: {
                                var url = root.branches[brItem.idx].url
                                if (url) Qt.openUrlExternally(url)
                            }
                        }
                    }
                    Controls.Label {
                        text: qsTr("Ahead %1 • Behind %2").arg(root.branches[brItem.idx].commitsAhead || 0).arg(root.branches[brItem.idx].commitsBehind || 0) +
                              (root.branches[brItem.idx].lastCommitTime ? " • " + qsTr("Last commit: %1").arg(root.branches[brItem.idx].lastCommitTime) : "")
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        color: Kirigami.Theme.disabledTextColor
                        Layout.fillWidth: true
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        var url = root.branches[brItem.idx].url
                        if (url) Qt.openUrlExternally(url)
                    }
                }
            }
        }

        // Ver mais no Jira (quando há muitos itens)
        Controls.Label {
            visible: root.issueKey && (root.pullRequests.length > 3 || root.branches.length > 3)
            text: qsTr("Ver mais no Jira")
            color: Kirigami.Theme.linkColor
            Layout.fillWidth: true
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (root.jiraService && root.issueKey && typeof root.jiraService.getIssueUrl === "function") {
                        var url = root.jiraService.getIssueUrl(root.issueKey)
                        if (url) Qt.openUrlExternally(url)
                    }
                }
            }
        }

        // Estado vazio (development carregado mas sem branches/PRs)
        ColumnLayout {
            visible: !root.hasData && root.hasAny
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.smallSpacing
            Layout.bottomMargin: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing

            Controls.Label {
                text: qsTr("Nenhum branch ou PR vinculado a esta issue.") + "\n" + qsTr("Dica: Crie um branch a partir da issue no Jira ou GitHub.")
                wrapMode: Text.WordWrap
                color: Kirigami.Theme.disabledTextColor
                Layout.fillWidth: true
            }
            Controls.Button {
                text: qsTr("Criar branch no GitHub")
                Layout.alignment: Qt.AlignLeft
                onClicked: {
                    // qmllint disable missing-property
                    if (createBranchDialogLoader.item && typeof createBranchDialogLoader.item.openWith === "function") {
                        createBranchDialogLoader.item.openWith(
                            root.issueKey,
                            root.issueSummary,
                            root.singleRepoForBranch,
                            root.githubService
                        )
                    }
                    // qmllint enable missing-property
                }
            }
        }
    }
}
