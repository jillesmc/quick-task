/**
 * PendingWorklogsPage.qml
 *
 * Página para gerenciar worklogs pendentes de sincronização
 */
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami
import "../components/forms"
import "../utils/PendingWorklogsLogic.js" as PendingWorklogsLogic

Kirigami.Page {
    id: page

    title: qsTr("Worklogs Pendentes")

    focus: true

    // Recebidos do Main (passados explicitamente)
    property var worklogSyncService: null
    property var jiraService: null
    property var pendingWorklogs: []
    property var issueSummaries: ({})  // Cache de summaries por issue_key
    property var filteredWorklogs: []  // Worklogs filtrados
    property string filterIssueKey: filtersBar ? filtersBar.filterIssueKey : ""
    property string filterDateFrom: filtersBar ? filtersBar.filterDateFrom : ""
    property string filterDateTo: filtersBar ? filtersBar.filterDateTo : ""

    function applyFilters() {
        page.filteredWorklogs = PendingWorklogsLogic.applyFilters(page.pendingWorklogs, page.filterIssueKey, page.filterDateFrom, page.filterDateTo);
    }

    // Função para recarregar worklogs (pode ser chamada externamente)
    function reloadWorklogs() {
        if (page.worklogSyncService) {
            page.pendingWorklogs = page.worklogSyncService.get_pending_worklogs();
            console.log("PendingWorklogsPage: Worklogs pendentes carregados:", page.pendingWorklogs.length);
            // Aplicar filtros
            page.applyFilters();
            // Carregar summaries das issues
            page.loadIssueSummaries();
        } else {
            console.error("PendingWorklogsPage: worklogSyncService não está disponível!");
        }
    }

    // Função para integração com MainHeader (botão Sincronizar no header)
    function syncAllFromToolbar() {
        if (!page.worklogSyncService || page.filteredWorklogs.length === 0) return;
        var hasFilters = page.filterIssueKey !== "" || page.filterDateFrom !== "" || page.filterDateTo !== "";
        if (hasFilters) {
            var sessionIds = [];
            for (var i = 0; i < page.filteredWorklogs.length; i++) {
                if (page.filteredWorklogs[i].id) {
                    sessionIds.push(page.filteredWorklogs[i].id);
                }
            }
            console.log("PendingWorklogsPage: Sincronizando %d worklogs filtrados", sessionIds.length);
            page.worklogSyncService.sync_pending_worklogs(sessionIds);
        } else {
            console.log("PendingWorklogsPage: Sincronizando todos os worklogs pendentes");
            page.worklogSyncService.sync_pending_worklogs([]);
        }
    }

    // Aplicar filtros quando mudarem
    onFilterIssueKeyChanged: applyFilters()
    onFilterDateFromChanged: applyFilters()
    onFilterDateToChanged: applyFilters()
    onPendingWorklogsChanged: applyFilters()

    // Carregar worklogs pendentes ao carregar a página
    Component.onCompleted: {
        reloadWorklogs();
    }

    function loadIssueSummaries() {
        var uniqueKeys = [];
        var keysSet = {};
        for (var i = 0; i < page.pendingWorklogs.length; i++) {
            var key = page.pendingWorklogs[i].issue_key;
            if (key && !keysSet[key]) {
                uniqueKeys.push(key);
                keysSet[key] = true;
            }
        }
        page.issueSummaries = PendingWorklogsLogic.loadSummaries(page.jiraService, uniqueKeys);
    }

    // Conectar sinais do worklogSyncService para atualizar lista
    Connections {
        target: page.worklogSyncService || null

        function onSyncCompleted(count) {
            console.log("PendingWorklogsPage: Sincronização concluída, %d worklogs sincronizados", count);
            if (page.worklogSyncService) {
                page.pendingWorklogs = page.worklogSyncService.get_pending_worklogs();
                page.applyFilters();
                page.loadIssueSummaries();
            }
        }

        function onSessionSynced(sessionId, jiraWorklogId) {
            console.log("PendingWorklogsPage: Worklog sincronizado ou deletado:", sessionId, "->", jiraWorklogId);
            if (page.worklogSyncService) {
                page.pendingWorklogs = page.worklogSyncService.get_pending_worklogs();
                page.applyFilters();
                page.loadIssueSummaries();
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: Kirigami.Units.largeSpacing

        // Cabeçalho com estatísticas
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 120
            color: Kirigami.Theme.backgroundColor || "#f0f0f0"
            border.color: Kirigami.Theme.textColor || "#d0d0d0"
            border.width: 1
            radius: Kirigami.Units.smallSpacing

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Kirigami.Units.largeSpacing
                spacing: Kirigami.Units.mediumSpacing

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.largeSpacing

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        Controls.Label {
                            text: qsTr("Total de Worklogs Pendentes")
                            font.bold: true
                            font.pointSize: Kirigami.Theme.defaultFont.pointSize
                            Layout.fillWidth: true
                        }

                        Controls.Label {
                            text: page.filteredWorklogs.length
                            font.pointSize: Kirigami.Theme.defaultFont.pointSize + 4
                            font.bold: true
                            color: Kirigami.Theme.highlightColor || "#3daee9"
                            Layout.fillWidth: true
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        Controls.Label {
                            text: qsTr("Tempo Total Pendente")
                            font.bold: true
                            font.pointSize: Kirigami.Theme.defaultFont.pointSize
                            Layout.fillWidth: true
                        }

                        Controls.Label {
                            text: {
                                var totalSeconds = 0;
                                for (var i = 0; i < page.filteredWorklogs.length; i++) {
                                    totalSeconds += page.filteredWorklogs[i].duration_seconds || 0;
                                }
                                var hours = Math.floor(totalSeconds / 3600);
                                var minutes = Math.floor((totalSeconds % 3600) / 60);
                                return qsTr("%1h %2m").arg(hours).arg(minutes);
                            }
                            font.pointSize: Kirigami.Theme.defaultFont.pointSize + 4
                            font.bold: true
                            color: Kirigami.Theme.highlightColor || "#3daee9"
                            Layout.fillWidth: true
                        }
                    }

                    Controls.ToolButton {
                        icon.name: "document-send"
                        enabled: page.worklogSyncService && page.filteredWorklogs.length > 0
                        Layout.preferredWidth: 40
                        Controls.ToolTip.visible: hovered
                        Controls.ToolTip.text: {
                            var hasFilters = page.filterIssueKey !== "" || page.filterDateFrom !== "" || page.filterDateTo !== "";
                            if (hasFilters) {
                                return qsTr("Sincronizar todos os worklogs filtrados (%1)").arg(page.filteredWorklogs.length);
                            }
                            return qsTr("Sincronizar todos os worklogs pendentes (%1)").arg(page.filteredWorklogs.length);
                        }
                        onClicked: {
                            if (page.worklogSyncService && page.filteredWorklogs.length > 0) {
                                // Se houver filtros ativos, sincronizar apenas os filtrados
                                // Caso contrário, sincronizar todos (passando lista vazia ou null)
                                var hasFilters = page.filterIssueKey !== "" || page.filterDateFrom !== "" || page.filterDateTo !== "";
                                if (hasFilters) {
                                    // Coletar IDs dos worklogs filtrados
                                    var sessionIds = [];
                                    for (var i = 0; i < page.filteredWorklogs.length; i++) {
                                        if (page.filteredWorklogs[i].id) {
                                            sessionIds.push(page.filteredWorklogs[i].id);
                                        }
                                    }
                                    console.log("PendingWorklogsPage: Sincronizando %d worklogs filtrados", sessionIds.length);
                                    page.worklogSyncService.sync_pending_worklogs(sessionIds);
                                } else {
                                    // Sincronizar todos os worklogs pendentes
                                    console.log("PendingWorklogsPage: Sincronizando todos os worklogs pendentes");
                                    page.worklogSyncService.sync_pending_worklogs([]);
                                }
                            }
                        }
                    }

                    Controls.ToolButton {
                        icon.name: "edit-delete"
                        enabled: page.worklogSyncService && page.filteredWorklogs.length > 0
                        Layout.preferredWidth: 40
                        Controls.ToolTip.visible: hovered
                        Controls.ToolTip.text: {
                            var hasFilters = page.filterIssueKey !== "" || page.filterDateFrom !== "" || page.filterDateTo !== "";
                            if (hasFilters) {
                                return qsTr("Excluir todos os worklogs filtrados (%1)").arg(page.filteredWorklogs.length);
                            }
                            return qsTr("Excluir todos os worklogs pendentes (%1)").arg(page.filteredWorklogs.length);
                        }
                        onClicked: {
                            if (page.worklogSyncService && page.filteredWorklogs.length > 0) {
                                // Se houver filtros ativos, deletar apenas os filtrados
                                // Caso contrário, deletar todos usando delete_all_worklogs()
                                var hasFilters = page.filterIssueKey !== "" || page.filterDateFrom !== "" || page.filterDateTo !== "";
                                if (hasFilters) {
                                    // Coletar IDs dos worklogs filtrados
                                    var sessionIds = [];
                                    for (var i = 0; i < page.filteredWorklogs.length; i++) {
                                        if (page.filteredWorklogs[i].id) {
                                            sessionIds.push(page.filteredWorklogs[i].id);
                                        }
                                    }
                                    // Deletar cada worklog filtrado
                                    var deleted = 0;
                                    for (var j = 0; j < sessionIds.length; j++) {
                                        if (page.worklogSyncService.delete_worklog(sessionIds[j])) {
                                            deleted++;
                                        }
                                    }
                                    console.log("PendingWorklogsPage: %d worklogs filtrados deletados", deleted);
                                    page.reloadWorklogs();
                                } else {
                                    // Deletar todos os worklogs pendentes
                                    var deleted = page.worklogSyncService.delete_all_worklogs();
                                    console.log("PendingWorklogsPage: %d worklogs deletados", deleted);
                                    page.reloadWorklogs();
                                }
                            }
                        }
                    }
                }
            }
        }

        WorklogFiltersBar {
            id: filtersBar
            Layout.fillWidth: true
        }

        // Indicador de filtros ativos
        Controls.Label {
            Layout.fillWidth: true
            visible: page.filterIssueKey !== "" || page.filterDateFrom !== "" || page.filterDateTo !== ""
            text: {
                var parts = [];
                if (page.filterIssueKey !== "") {
                    parts.push(qsTr("Issue Key: %1").arg(page.filterIssueKey));
                }
                if (page.filterDateFrom !== "") {
                    parts.push(qsTr("De: %1").arg(page.filterDateFrom));
                }
                if (page.filterDateTo !== "") {
                    parts.push(qsTr("Até: %1").arg(page.filterDateTo));
                }
                return qsTr("Filtros ativos: %1").arg(parts.join(", "));
            }
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            color: Kirigami.Theme.highlightColor || "#3daee9"
        }

        // Tabela compacta de worklogs
        Controls.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ListView {
                id: worklogsListView
                model: page.filteredWorklogs
                spacing: 2

                // Cabeçalho da tabela (simulado com RowLayout fixo)
                header: Rectangle {
                    id: headerRect
                    width: worklogsListView.width
                    height: 40
                    color: Kirigami.Theme.alternateBackgroundColor || "#e0e0e0"

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.smallSpacing
                        spacing: Kirigami.Units.smallSpacing

                        Controls.Label {
                            Layout.preferredWidth: 120
                            text: qsTr("Issue Key")
                            font.bold: true
                        }

                        Controls.Label {
                            Layout.fillWidth: true
                            text: qsTr("Summary")
                            font.bold: true
                        }

                        Controls.Label {
                            Layout.preferredWidth: 140
                            text: qsTr("Data Início")
                            font.bold: true
                        }

                        Controls.Label {
                            Layout.preferredWidth: 140
                            text: qsTr("Data Fim")
                            font.bold: true
                        }

                        Controls.Label {
                            Layout.preferredWidth: 100
                            text: qsTr("Duração")
                            font.bold: true
                        }

                        Controls.Label {
                            Layout.preferredWidth: 80
                            text: qsTr("Ações")
                            font.bold: true
                        }
                    }
                }

                delegate: Rectangle {
                    id: delegateRect
                    required property int index
                    required property var modelData
                    width: worklogsListView.width
                    height: 45
                    color: delegateRect.index % 2 === 0 ? Kirigami.Theme.backgroundColor : (Kirigami.Theme.alternateBackgroundColor || "#f5f5f5")

                    property var worklogData: page.filteredWorklogs[delegateRect.index] || {}

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.smallSpacing
                        spacing: Kirigami.Units.smallSpacing

                        // Issue Key
                        Controls.Label {
                            Layout.preferredWidth: 120
                            text: delegateRect.worklogData.issue_key || ""
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                            elide: Text.ElideRight
                        }

                        // Summary
                        Controls.Label {
                            Layout.fillWidth: true
                            text: page.issueSummaries[delegateRect.worklogData.issue_key] || ""
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                            elide: Text.ElideRight
                        }

                        // Data Início
                        Controls.Label {
                            Layout.preferredWidth: 140
                            text: {
                                if (delegateRect.worklogData.start_time) {
                                    var date = new Date(delegateRect.worklogData.start_time);
                                    return Qt.formatDateTime(date, "dd/MM/yyyy HH:mm");
                                }
                                return "";
                            }
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                        }

                        // Data Fim
                        Controls.Label {
                            Layout.preferredWidth: 140
                            text: {
                                if (delegateRect.worklogData.end_time) {
                                    var date = new Date(delegateRect.worklogData.end_time);
                                    return Qt.formatDateTime(date, "dd/MM/yyyy HH:mm");
                                }
                                return "";
                            }
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                        }

                        // Duração
                        Controls.Label {
                            Layout.preferredWidth: 100
                            text: {
                                var duration = delegateRect.worklogData.duration_seconds || 0;
                                var hours = Math.floor(duration / 3600);
                                var minutes = Math.floor((duration % 3600) / 60);
                                return qsTr("%1h %2m").arg(hours).arg(minutes);
                            }
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                            font.bold: true
                            color: Kirigami.Theme.highlightColor || "#3daee9"
                        }

                        // Ações
                        RowLayout {
                            Layout.preferredWidth: 80
                            spacing: Kirigami.Units.smallSpacing

                            Controls.ToolButton {
                                icon.name: "document-send"
                                enabled: page.worklogSyncService && delegateRect.worklogData.id
                                Layout.preferredWidth: 30
                                Layout.preferredHeight: 30
                                onClicked: {
                                    if (page.worklogSyncService && delegateRect.worklogData.id) {
                                        var sessionIds = [delegateRect.worklogData.id];
                                        console.log("PendingWorklogsPage: Sincronizando worklog:", delegateRect.worklogData.id);
                                        page.worklogSyncService.sync_pending_worklogs(sessionIds);
                                    }
                                }
                            }

                            Controls.ToolButton {
                                icon.name: "edit-delete"
                                enabled: page.worklogSyncService && delegateRect.worklogData.id
                                Layout.preferredWidth: 30
                                Layout.preferredHeight: 30
                                onClicked: {
                                    if (page.worklogSyncService && delegateRect.worklogData.id) {
                                        console.log("PendingWorklogsPage: Deletando worklog:", delegateRect.worklogData.id);
                                        if (page.worklogSyncService.delete_worklog(delegateRect.worklogData.id)) {
                                            page.reloadWorklogs();
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Mensagem quando não há worklogs
        Controls.Label {
            text: qsTr("Nenhum worklog pendente")
            Layout.fillWidth: true
            Layout.fillHeight: true
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            color: Kirigami.Theme.disabledTextColor || "#808080"
            font.pointSize: Kirigami.Theme.defaultFont.pointSize + 1
            visible: !page.worklogSyncService || (page.filteredWorklogs.length === 0)
        }
    }
}
