/**
 * GitHubPage.qml
 *
 * Duas colunas: à esquerda PRs (review solicitado a você, depois ao time);
 * à direita Issues atribuídas. Permite abrir no navegador e importar para Jira.
 */
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami
import "../components/controls"
import "../components/lists"

Kirigami.Page {
    id: page

    title: qsTr("GitHub")

    focus: true

    property var githubService: null
    property var issueModel: null
    property var tabBar: null

    property var prsRequestedForUser: []
    property var prsRequestedForTeam: []
    property var issues: []
    property bool isLoadingPRs: false
    property bool isLoadingIssues: false
    property string errorMessagePRs: ""
    property string errorMessageIssues: ""
    property bool hasCachedData: false

    function reload() {
        if (!page.githubService)
            return;
        page.errorMessagePRs = "";
        page.errorMessageIssues = "";
        page.isLoadingPRs = true;
        page.isLoadingIssues = true;
        page.githubService.loadPRs();
        page.githubService.loadIssues();
    }

    function buildTitleAndDescription(item) {
        var url = (item && item.url) ? item.url : "";
        var title = (item && item.title) ? item.title : "";
        var body = (item && item.body) ? item.body : "";
        var isPr = (item && item.type) === "pr";
        if (isPr) {
            return {
                summary: "Revisão de código do PR - " + url,
                description: "É necessário fazer a revisão de código do PR\n" + title + "\n" + url + "\n\n" + "Abaixo temos a descrição do que foi feito nesse PR:\n" + "---\n" + body
            };
        }
        return {
            summary: "Implementação da issue - " + url,
            description: "É necessário fazer a implementação da issue descrita em:\n" + title + "\n" + url + "\n\n" + "Abaixo temos a descrição da issue:\n" + "---\n" + body
        };
    }

    function importToJira(item) {
        if (!page.issueModel || !page.tabBar || !item)
            return;
        var built = page.buildTitleAndDescription(item);
        page.issueModel.summary = built.summary;
        page.issueModel.description = built.description;
        page.tabBar.currentIndex = 0;
    }

    actions: [
        Kirigami.Action {
            text: qsTr("Atualizar")
            icon.name: "view-refresh"
            enabled: page.githubService && page.githubService.available && !page.isLoadingPRs && !page.isLoadingIssues
            onTriggered: page.reload()
        }
    ]

    Connections {
        target: page.githubService || null

        function onPrsReady(prsUser, prsTeam) {
            page.prsRequestedForUser = prsUser || [];
            page.prsRequestedForTeam = prsTeam || [];
            page.isLoadingPRs = false;
            page.errorMessagePRs = "";
            if (page.isLoadingIssues === false)
                page.hasCachedData = true;
        }

        function onPrsErrorOccurred(msg) {
            page.isLoadingPRs = false;
            page.errorMessagePRs = msg || qsTr("Erro ao carregar PRs.");
            if (page.isLoadingIssues === false)
                page.hasCachedData = true;
        }

        function onIssuesReady(issuesList) {
            page.issues = issuesList || [];
            page.isLoadingIssues = false;
            page.errorMessageIssues = "";
            if (page.isLoadingPRs === false)
                page.hasCachedData = true;
        }

        function onIssuesErrorOccurred(msg) {
            page.isLoadingIssues = false;
            page.errorMessageIssues = msg || qsTr("Erro ao carregar issues.");
            if (page.isLoadingPRs === false)
                page.hasCachedData = true;
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.mediumSpacing

        Controls.Label {
            Layout.fillWidth: true
            visible: !page.githubService || !page.githubService.available
            text: qsTr("Configure o token e o username do GitHub nas Configurações.")
            color: Kirigami.Theme.disabledTextColor
            wrapMode: Text.WordWrap
        }

        Controls.SplitView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: page.githubService && page.githubService.available
            handle: SplitViewHandle {}

            // Coluna esquerda: PRs (review para você + review para o time)
            Controls.ScrollView {
                id: leftScroll
                Controls.SplitView.preferredWidth: parent.width * 0.5
                Controls.SplitView.minimumWidth: 280
                Controls.SplitView.fillHeight: true
                clip: true
                contentWidth: availableWidth
                leftPadding: Kirigami.Units.largeSpacing
                rightPadding: Kirigami.Units.largeSpacing

                ColumnLayout {
                    width: leftScroll.availableWidth
                    spacing: Kirigami.Units.largeSpacing

                    Controls.BusyIndicator {
                        Layout.alignment: Qt.AlignHCenter
                        running: page.isLoadingPRs
                        visible: page.isLoadingPRs
                    }
                    Controls.Label {
                        Layout.fillWidth: true
                        visible: page.errorMessagePRs.length > 0
                        text: page.errorMessagePRs
                        color: Kirigami.Theme.negativeTextColor
                        wrapMode: Text.WordWrap
                    }

                    Kirigami.Heading {
                        level: 4
                        text: qsTr("PRs — Review solicitado a você")
                        Layout.fillWidth: true
                        visible: !page.isLoadingPRs && page.prsRequestedForUser.length > 0
                    }
                    Repeater {
                        visible: !page.isLoadingPRs
                        model: page.prsRequestedForUser
                        delegate: Item {
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: prDelegate.height
                            GitHubItemDelegate {
                                id: prDelegate
                                itemData: parent.modelData
                                width: parent.width - Kirigami.Units.smallSpacing * 2
                                onImportToJiraRequested: item => page.importToJira(item)
                            }
                        }
                    }
                    Item {
                        Layout.preferredHeight: 1
                        visible: !page.isLoadingPRs && page.prsRequestedForUser.length === 0 && page.prsRequestedForTeam.length === 0
                    }
                    Controls.Label {
                        text: qsTr("Nenhum PR com review solicitado a você.")
                        color: Kirigami.Theme.disabledTextColor
                        visible: !page.isLoadingPRs && page.prsRequestedForUser.length === 0 && page.prsRequestedForTeam.length > 0
                        Layout.fillWidth: true
                    }
                    Controls.Label {
                        text: qsTr("Nenhum PR encontrado.")
                        color: Kirigami.Theme.disabledTextColor
                        visible: !page.isLoadingPRs && page.prsRequestedForUser.length === 0 && page.prsRequestedForTeam.length === 0
                        Layout.fillWidth: true
                    }

                    Kirigami.Heading {
                        level: 4
                        text: qsTr("PRs — Review solicitado ao time")
                        Layout.fillWidth: true
                        Layout.topMargin: Kirigami.Units.largeSpacing
                        visible: !page.isLoadingPRs && page.prsRequestedForTeam.length > 0
                    }
                    Repeater {
                        visible: !page.isLoadingPRs
                        model: page.prsRequestedForTeam
                        delegate: Item {
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: teamDelegate.height
                            GitHubItemDelegate {
                                id: teamDelegate
                                itemData: parent.modelData
                                width: parent.width - Kirigami.Units.smallSpacing * 2
                                showReviewKind: true
                                reviewKindLabel: qsTr("Time")
                                onImportToJiraRequested: item => page.importToJira(item)
                            }
                        }
                    }
                }
            }

            // Coluna direita: Issues
            Controls.ScrollView {
                id: rightScroll
                Controls.SplitView.fillWidth: true
                Controls.SplitView.minimumWidth: 280
                Controls.SplitView.fillHeight: true
                clip: true
                contentWidth: availableWidth
                leftPadding: Kirigami.Units.largeSpacing
                rightPadding: Kirigami.Units.largeSpacing

                ColumnLayout {
                    width: rightScroll.availableWidth
                    spacing: Kirigami.Units.largeSpacing

                    Controls.BusyIndicator {
                        Layout.alignment: Qt.AlignHCenter
                        running: page.isLoadingIssues
                        visible: page.isLoadingIssues
                    }
                    Controls.Label {
                        Layout.fillWidth: true
                        visible: page.errorMessageIssues.length > 0
                        text: page.errorMessageIssues
                        color: Kirigami.Theme.negativeTextColor
                        wrapMode: Text.WordWrap
                    }

                    Kirigami.Heading {
                        level: 4
                        text: qsTr("Issues (atribuídas a mim)")
                        Layout.fillWidth: true
                        visible: !page.isLoadingIssues
                    }
                    Repeater {
                        visible: !page.isLoadingIssues
                        model: page.issues
                        delegate: Item {
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: issueDelegate.height
                            GitHubItemDelegate {
                                id: issueDelegate
                                itemData: parent.modelData
                                width: parent.width - Kirigami.Units.smallSpacing * 2
                                isIssue: true
                                onImportToJiraRequested: item => page.importToJira(item)
                            }
                        }
                    }
                    Controls.Label {
                        text: qsTr("Nenhuma issue atribuída.")
                        color: Kirigami.Theme.disabledTextColor
                        visible: !page.isLoadingIssues && page.issues.length === 0
                        Layout.fillWidth: true
                    }
                }
            }
        }
    }
}
