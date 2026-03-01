pragma ComponentBehavior: Bound
/**
 * CreateBranchDialog.qml
 *
 * Diálogo para criar uma branch no GitHub a partir da issue atual.
 * Repositório: busca com mínimo 2 caracteres e debounce.
 * Nome da branch: sugestão issueKey-slugify(summary); editável.
 * Base: opcional; preenchido com default do repo ao selecionar.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

Controls.Dialog {
    id: root

    parent: Controls.Overlay.overlay
    anchors.centerIn: parent

    title: qsTr("Criar branch no GitHub")
    modal: true
    closePolicy: Controls.Popup.CloseOnEscape
    standardButtons: Controls.Dialog.Cancel

    property string issueKey: ""
    property string issueSummary: ""
    /** Valor inicial do repositório (owner/repo) quando a issue tem um único repo no Jira. */
    property string initialRepo: ""
    property var githubService: null

    signal branchCreatedSuccess(string url)
    signal errorMessage(string message)

    /** Slugify: minúsculas, espaços → hífen, remove acentos e não-alfanuméricos (mantém a-z, 0-9, hífen). */
    function slugify(text) {
        if (!text || typeof text !== "string")
            return "";
        var s = text.trim().toLowerCase();
        var accents = {
            "á": "a",
            "à": "a",
            "ã": "a",
            "â": "a",
            "é": "e",
            "ê": "e",
            "í": "i",
            "ó": "o",
            "ô": "o",
            "õ": "o",
            "ú": "u",
            "ü": "u",
            "ç": "c",
            "ñ": "n"
        };
        for (var k in accents)
            s = s.split(k).join(accents[k]);
        s = s.replace(/\s+/g, "-");
        s = s.replace(/[^a-z0-9-]/g, "");
        s = s.replace(/-+/g, "-").replace(/^-|-$/g, "");
        return s;
    }

    function suggestedBranchName() {
        var key = (root.issueKey || "").trim();
        var slug = slugify(root.issueSummary || "");
        if (!key)
            return slug || "branch";
        if (!slug)
            return key;
        return key + "-" + slug;
    }

    function openWith(key, summary, repo, service) {
        issueKey = key || "";
        issueSummary = summary || "";
        initialRepo = (repo || "").trim();
        githubService = service || null;
        githubAvailable = !!(service && service.available);
        repoSearchText = "";
        repoSearchResultsModel.clear();
        selectedRepo = initialRepo;
        selectedDefaultBranch = "";
        errorLabel.text = "";
        createButton.enabled = true;
        open();
    }

    onOpened: {
        githubAvailable = !!(root.githubService && root.githubService.available);
        repoSearchField.text = selectedRepo;
        branchNameField.text = suggestedBranchName();
        baseField.text = selectedDefaultBranch;
        if (initialRepo && githubService && typeof githubService.searchRepositories === "function") {
            var part = initialRepo.indexOf("/") >= 0 ? initialRepo.split("/").pop() : initialRepo;
            if (part.length >= 2)
                githubService.searchRepositories(part);
        }
    }

    property string repoSearchText: ""
    property ListModel repoSearchResultsModel: ListModel {}
    readonly property int repoSearchCount: repoSearchResultsModel ? repoSearchResultsModel.count : 0
    property string selectedRepo: ""
    property string selectedDefaultBranch: ""

    /** Reavaliado em onOpened para refletir token salvo em Configurações. */
    property bool githubAvailable: false

    Timer {
        id: debounceTimer
        interval: 350
        onTriggered: {
            var q = root.repoSearchText.trim();
            var ok = root.githubService && q.length >= 2;
            console.log("[CreateBranchDialog] debounceTimer: query='" + q + "' len=" + q.length + " calling API=" + ok);
            if (ok) {
                root.githubService.searchRepositories(q);
            } else {
                root.repoSearchResultsModel.clear();
            }
        }
    }

    onRepoSearchTextChanged: {
        console.log("[CreateBranchDialog] repoSearchTextChanged: '" + repoSearchText + "' len=" + repoSearchText.trim().length);
        debounceTimer.restart();
        if (repoSearchText.trim().length < 2) {
            root.repoSearchResultsModel.clear();
        }
    }

    Connections {
        target: root.githubService || null
        function onReposSearchResults(queryUsed, list) {
            var raw = list || [];
            var currentQuery = root.repoSearchText.trim();
            var n = raw.length;
            console.log("[CreateBranchDialog] onReposSearchResults: queryUsed='" + (queryUsed || "") + "' currentQuery='" + currentQuery + "' count=" + n);
            if ((queryUsed || "").trim() !== currentQuery) {
                console.log("[CreateBranchDialog] resultado obsoleto (query mudou), buscando novamente com '" + currentQuery + "'");
                if (root.githubService && currentQuery.length >= 2)
                    root.githubService.searchRepositories(currentQuery);
                return;
            }
            var names = [];
            for (var i = 0; i < raw.length; i++) {
                var item = raw[i];
                var fn = (item && (item.full_name !== undefined ? item.full_name : item.fullName)) || "";
                names.push(fn);
            }
            console.log("[CreateBranchDialog] repos no resultado: " + names.join(" | "));
            root.repoSearchResultsModel.clear();
            for (var k = 0; k < raw.length; k++) {
                var it = raw[k];
                var fullName = (it && (it.full_name !== undefined ? it.full_name : it.fullName)) || "";
                var defaultBranch = (it && (it.default_branch !== undefined ? it.default_branch : it.defaultBranch)) || "main";
                root.repoSearchResultsModel.append({
                    "full_name": fullName,
                    "default_branch": defaultBranch
                });
            }
            if (!root.selectedRepo)
                return;
            for (var j = 0; j < root.repoSearchResultsModel.count; j++) {
                var fn2 = root.repoSearchResultsModel.get(j).full_name;
                if (fn2 === root.selectedRepo) {
                    root.selectedDefaultBranch = root.repoSearchResultsModel.get(j).default_branch;
                    baseField.text = root.selectedDefaultBranch;
                    break;
                }
            }
        }
        function onBranchCreated(owner, repo, branchName, url) {
            root.close();
            if (url)
                Qt.openUrlExternally(url);
            root.branchCreatedSuccess(url || "");
        }
        function onErrorOccurred(message) {
            errorLabel.text = message || "";
            createButton.enabled = true;
        }
    }

    contentItem: Item {
        implicitWidth: 420
        implicitHeight: column.implicitHeight

        ColumnLayout {
            id: column
            anchors.fill: parent
            spacing: Kirigami.Units.mediumSpacing

            Controls.Label {
                visible: !root.githubAvailable
                text: qsTr("Para criar branches, configure o token do GitHub em Configurações (aba Configurações ou GitHub).")
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                color: Kirigami.Theme.disabledTextColor
            }

            Controls.Label {
                visible: root.githubAvailable
                text: qsTr("Repositório (busque com 2+ caracteres)")
                Layout.fillWidth: true
            }
            Controls.TextField {
                id: repoSearchField
                visible: root.githubAvailable
                placeholderText: qsTr("ex.: owner/repo ou parte do nome (digite 2+ caracteres para buscar)")
                Layout.fillWidth: true
                onTextEdited: {
                    root.repoSearchText = text;
                    root.selectedRepo = text.trim();
                    root.selectedDefaultBranch = "";
                }
            }
            Controls.Frame {
                id: repoDropFrame
                visible: root.githubAvailable && root.repoSearchCount > 0 && repoSearchField.activeFocus
                Component.onCompleted: console.log("[CreateBranchDialog] repoDropFrame created")
                onVisibleChanged: console.log("[CreateBranchDialog] repoDropFrame.visible=" + visible + " count=" + root.repoSearchCount + " focus=" + repoSearchField.activeFocus)
                Layout.fillWidth: true
                Layout.preferredHeight: visible ? Math.min(root.repoSearchCount * (Kirigami.Units.gridUnit * 2), Kirigami.Units.gridUnit * 8) : 0
                padding: 0
                background: Rectangle {
                    color: Kirigami.Theme.backgroundColor
                    border.color: Kirigami.Theme.disabledTextColor
                    border.width: 1
                    radius: Kirigami.Units.smallSpacing
                }
                contentItem: ListView {
                    id: repoList
                    clip: true
                    model: root.repoSearchResultsModel
                    currentIndex: -1
                    delegate: Controls.ItemDelegate {
                        id: repoDelegate
                        width: repoList.width
                        height: Kirigami.Units.gridUnit * 2
                        required property string full_name
                        required property string default_branch
                        contentItem: Controls.Label {
                            text: repoDelegate.full_name || ""
                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignVCenter
                        }
                        onClicked: {
                            root.selectedRepo = repoDelegate.full_name || "";
                            root.selectedDefaultBranch = repoDelegate.default_branch || "main";
                            repoSearchField.text = root.selectedRepo;
                            baseField.text = root.selectedDefaultBranch;
                            root.repoSearchResultsModel.clear();
                            repoSearchField.focus = false;
                        }
                    }
                }
            }

            Controls.Label {
                visible: root.githubAvailable
                text: qsTr("Nome da branch")
                Layout.fillWidth: true
            }
            Controls.TextField {
                id: branchNameField
                visible: root.githubAvailable
                placeholderText: qsTr("ex.: PLATFORM-123-descricao")
                Layout.fillWidth: true
            }

            Controls.Label {
                visible: root.githubAvailable
                text: qsTr("Base (opcional; vazio = default do repo)")
                Layout.fillWidth: true
            }
            Controls.TextField {
                id: baseField
                visible: root.githubAvailable
                placeholderText: "main"
                Layout.fillWidth: true
            }

            Controls.Label {
                id: errorLabel
                visible: root.githubAvailable
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Kirigami.Theme.negativeTextColor
                text: ""
            }

            Controls.Button {
                id: createButton
                visible: root.githubAvailable
                text: qsTr("Criar")
                Layout.alignment: Qt.AlignRight
                onClicked: {
                    var ownerRepo = root.selectedRepo.trim();
                    var name = branchNameField.text.trim();
                    if (!ownerRepo) {
                        errorLabel.text = qsTr("Selecione ou digite o repositório (owner/repo).");
                        return;
                    }
                    if (!name) {
                        errorLabel.text = qsTr("Informe o nome da branch.");
                        return;
                    }
                    if (!root.githubService || typeof root.githubService.createBranch !== "function") {
                        errorLabel.text = qsTr("GitHub não configurado. Configure o token nas configurações.");
                        return;
                    }
                    errorLabel.text = "";
                    createButton.enabled = false;
                    root.githubService.createBranch(ownerRepo, name, baseField.text.trim());
                }
            }
        }
    }
}
