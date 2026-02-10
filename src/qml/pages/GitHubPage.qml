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
    property bool isLoading: false
    property string errorMessage: ""

    function reload() {
        if (!page.githubService) return;
        page.errorMessage = "";
        page.isLoading = true;
        page.githubService.loadItems();
    }

    function buildTitleAndDescription(item) {
        var url = (item && item.url) ? item.url : "";
        var title = (item && item.title) ? item.title : "";
        var body = (item && item.body) ? item.body : "";
        var isPr = (item && item.type) === "pr";
        if (isPr) {
            return {
                summary: "Revisão de código do PR - " + url,
                description: "É necessário fazer a revisão de código do PR\n"
                    + title + "\n"
                    + url + "\n\n"
                    + "Abaixo temos a descrição do que foi feito nesse PR:\n"
                    + "---\n"
                    + body
            };
        }
        return {
            summary: "Implementação da issue - " + url,
            description: "É necessário fazer a implementação da issue descrita em:\n"
                + title + "\n"
                + url + "\n\n"
                + "Abaixo temos a descrição da issue:\n"
                + "---\n"
                + body
        };
    }

    function importToJira(item) {
        if (!page.issueModel || !page.tabBar || !item) return;
        var built = page.buildTitleAndDescription(item);
        page.issueModel.summary = built.summary;
        page.issueModel.description = built.description;
        page.tabBar.currentIndex = 0;
    }

    actions: [
        Kirigami.Action {
            text: qsTr("Atualizar")
            icon.name: "view-refresh"
            enabled: page.githubService && page.githubService.available && !page.isLoading
            onTriggered: page.reload()
        }
    ]

    Connections {
        target: page.githubService || null

        function onDataReady(data) {
            if (!data) return;
            page.prsRequestedForUser = data.prsRequestedForUser || [];
            page.prsRequestedForTeam = data.prsRequestedForTeam || [];
            page.issues = data.issues || [];
            page.isLoading = false;
            page.errorMessage = "";
        }

        function onErrorOccurred(msg) {
            page.isLoading = false;
            page.errorMessage = msg || qsTr("Erro ao carregar.");
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.mediumSpacing

        Controls.Label {
            Layout.fillWidth: true
            visible: page.errorMessage.length > 0
            text: page.errorMessage
            color: Kirigami.Theme.negativeTextColor
            wrapMode: Text.WordWrap
        }

        Controls.BusyIndicator {
            Layout.alignment: Qt.AlignHCenter
            running: page.isLoading
            visible: page.isLoading
        }

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
            visible: page.githubService && page.githubService.available && !page.isLoading
            handle: SplitViewHandle { }

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

                    Kirigami.Heading {
                        level: 4
                        text: qsTr("PRs — Review solicitado a você")
                        Layout.fillWidth: true
                        visible: page.prsRequestedForUser.length > 0
                    }
                    Repeater {
                        model: page.prsRequestedForUser
                        delegate: Item {
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: prDelegate.height
                            GitHubItemDelegate {
                                id: prDelegate
                                itemData: parent.modelData
                                width: parent.width - Kirigami.Units.smallSpacing * 2
                                onImportToJiraRequested: (item) => page.importToJira(item)
                            }
                        }
                    }
                    Item {
                        Layout.preferredHeight: 1
                        visible: page.prsRequestedForUser.length === 0 && page.prsRequestedForTeam.length === 0
                    }
                    Controls.Label {
                        text: qsTr("Nenhum PR com review solicitado a você.")
                        color: Kirigami.Theme.disabledTextColor
                        visible: page.prsRequestedForUser.length === 0 && page.prsRequestedForTeam.length > 0
                        Layout.fillWidth: true
                    }
                    Controls.Label {
                        text: qsTr("Nenhum PR encontrado.")
                        color: Kirigami.Theme.disabledTextColor
                        visible: page.prsRequestedForUser.length === 0 && page.prsRequestedForTeam.length === 0
                        Layout.fillWidth: true
                    }

                    Kirigami.Heading {
                        level: 4
                        text: qsTr("PRs — Review solicitado ao time")
                        Layout.fillWidth: true
                        Layout.topMargin: Kirigami.Units.largeSpacing
                        visible: page.prsRequestedForTeam.length > 0
                    }
                    Repeater {
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
                                onImportToJiraRequested: (item) => page.importToJira(item)
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

                    Kirigami.Heading {
                        level: 4
                        text: qsTr("Issues (atribuídas a mim)")
                        Layout.fillWidth: true
                    }
                    Repeater {
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
                                onImportToJiraRequested: (item) => page.importToJira(item)
                            }
                        }
                    }
                    Controls.Label {
                        text: qsTr("Nenhuma issue atribuída.")
                        color: Kirigami.Theme.disabledTextColor
                        visible: page.issues.length === 0
                        Layout.fillWidth: true
                    }
                }
            }
        }
    }
}
