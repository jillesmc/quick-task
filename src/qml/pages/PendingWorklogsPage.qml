/**
 * PendingWorklogsPage.qml
 * 
 * Página para gerenciar worklogs pendentes de sincronização
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

Kirigami.Page {
    id: page

    title: qsTr("Worklogs Pendentes")
    
    focus: true
    
    property var pendingWorklogs: []
    property var issueSummaries: ({})  // Cache de summaries por issue_key
    property var groupedWorklogs: ({})  // Worklogs agrupados por issue_key
    
    // Função para agrupar worklogs por issue_key
    function groupWorklogsByIssue() {
        var grouped = {}
        for (var i = 0; i < pendingWorklogs.length; i++) {
            var worklog = pendingWorklogs[i]
            var issueKey = worklog.issue_key || "Sem Issue"
            if (!grouped[issueKey]) {
                grouped[issueKey] = []
            }
            grouped[issueKey].push(worklog)
        }
        groupedWorklogs = grouped
    }
    
    // Função para recarregar worklogs (pode ser chamada externamente)
    function reloadWorklogs() {
        if (worklogSyncService) {
            pendingWorklogs = worklogSyncService.get_pending_worklogs()
            console.log("PendingWorklogsPage: Worklogs pendentes carregados:", pendingWorklogs.length)
            // Agrupar worklogs por issue_key
            groupWorklogsByIssue()
            // Carregar summaries das issues
            loadIssueSummaries()
        } else {
            console.error("PendingWorklogsPage: worklogSyncService não está disponível!")
        }
    }
    
    // Carregar worklogs pendentes ao carregar a página
    Component.onCompleted: {
        reloadWorklogs()
    }
    
    function loadIssueSummaries() {
        if (!jiraService) {
            return
        }
        
        // Coletar issue_keys únicas
        var uniqueKeys = []
        var keysSet = {}
        for (var i = 0; i < pendingWorklogs.length; i++) {
            var key = pendingWorklogs[i].issue_key
            if (key && !keysSet[key]) {
                uniqueKeys.push(key)
                keysSet[key] = true
            }
        }
        
        // Buscar summary para cada issue_key
        var summaries = {}
        for (var j = 0; j < uniqueKeys.length; j++) {
            var issueKey = uniqueKeys[j]
            try {
                var details = jiraService.getIssueDetails(issueKey)
                if (details && details.summary) {
                    summaries[issueKey] = details.summary
                }
            } catch (e) {
                console.error("PendingWorklogsPage: Erro ao buscar summary para", issueKey, ":", e)
            }
        }
        
        issueSummaries = summaries
    }
    
    // Conectar sinais do worklogSyncService para atualizar lista
    Connections {
        target: worklogSyncService || null
        
        function onSyncCompleted(count) {
            console.log("PendingWorklogsPage: Sincronização concluída, %d worklogs sincronizados", count)
            if (worklogSyncService) {
                pendingWorklogs = worklogSyncService.get_pending_worklogs()
                groupWorklogsByIssue()
                loadIssueSummaries()
            }
        }
        
        function onSessionSynced(sessionId, jiraWorklogId) {
            console.log("PendingWorklogsPage: Worklog sincronizado ou deletado:", sessionId, "->", jiraWorklogId)
            if (worklogSyncService) {
                pendingWorklogs = worklogSyncService.get_pending_worklogs()
                groupWorklogsByIssue()
                loadIssueSummaries()
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.largeSpacing

        // Cabeçalho com estatísticas
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 120
            color: Kirigami.Theme.backgroundColor || "#f0f0f0"
            border.color: Kirigami.Theme.separatorColor || "#d0d0d0"
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
                            text: pendingWorklogs.length
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
                                var totalSeconds = 0
                                for (var i = 0; i < pendingWorklogs.length; i++) {
                                    totalSeconds += pendingWorklogs[i].duration_seconds || 0
                                }
                                var hours = Math.floor(totalSeconds / 3600)
                                var minutes = Math.floor((totalSeconds % 3600) / 60)
                                return qsTr("%1h %2m").arg(hours).arg(minutes)
                            }
                            font.pointSize: Kirigami.Theme.defaultFont.pointSize + 4
                            font.bold: true
                            color: Kirigami.Theme.highlightColor || "#3daee9"
                            Layout.fillWidth: true
                        }
                    }

                    Controls.ToolButton {
                        icon.name: "edit-delete"
                        enabled: worklogSyncService && pendingWorklogs.length > 0
                        Layout.preferredWidth: 40
                        onClicked: {
                            if (worklogSyncService && pendingWorklogs.length > 0) {
                                var deleted = worklogSyncService.delete_all_worklogs()
                                console.log("PendingWorklogsPage: %d worklogs deletados", deleted)
                                reloadWorklogs()
                            }
                        }
                    }
                }
            }
        }

        // Lista de worklogs pendentes agrupados por issue_key
        Controls.Label {
            text: qsTr("Worklogs Pendentes")
            font.bold: true
            font.pointSize: Kirigami.Theme.defaultFont.pointSize + 1
            Layout.fillWidth: true
            visible: pendingWorklogs.length > 0
        }

        // Lista usando ScrollView e ListView para melhor performance
        Controls.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ListView {
                id: groupsListView
                // Converter groupedWorklogs em lista de chaves para o modelo
                model: Object.keys(groupedWorklogs)
                spacing: Kirigami.Units.mediumSpacing
                
                delegate: Rectangle {
                    width: groupsListView.width
                    // Calcular altura: cabeçalho (80) + margens (2 * largeSpacing) + worklogs (100 cada + spacing)
                    height: 80 + (Kirigami.Units.largeSpacing * 2) + (worklogs.length * (100 + Kirigami.Units.mediumSpacing)) + Kirigami.Units.mediumSpacing
                    color: Kirigami.Theme.backgroundColor || "#f0f0f0"
                    border.color: Kirigami.Theme.separatorColor || "#d0d0d0"
                    border.width: 1
                    radius: Kirigami.Units.smallSpacing
                    
                    property string issueKey: modelData
                    property var worklogs: groupedWorklogs[issueKey] || []
                    
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.largeSpacing
                        spacing: Kirigami.Units.mediumSpacing
                        
                        // Cabeçalho do grupo
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 80
                            color: Kirigami.Theme.alternateBackgroundColor || "#e0e0e0"
                            radius: Kirigami.Units.smallSpacing
                            
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: Kirigami.Units.mediumSpacing
                                spacing: Kirigami.Units.mediumSpacing
                                
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: Kirigami.Units.smallSpacing
                                    
                                    Controls.Label {
                                        text: issueKey
                                        font.bold: true
                                        font.pointSize: Kirigami.Theme.defaultFont.pointSize + 2
                                        Layout.fillWidth: true
                                    }
                                    
                                    Controls.Label {
                                        text: issueSummaries[issueKey] || ""
                                        font.pointSize: Kirigami.Theme.defaultFont.pointSize
                                        color: Kirigami.Theme.textColor || "#000000"
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        visible: issueSummaries[issueKey] !== undefined
                                    }
                                    
                                    Controls.Label {
                                        text: {
                                            var totalSeconds = 0
                                            for (var i = 0; i < worklogs.length; i++) {
                                                totalSeconds += worklogs[i].duration_seconds || 0
                                            }
                                            var hours = Math.floor(totalSeconds / 3600)
                                            var minutes = Math.floor((totalSeconds % 3600) / 60)
                                            return qsTr("%1 worklogs • %2h %3m").arg(worklogs.length).arg(hours).arg(minutes)
                                        }
                                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                                        color: Kirigami.Theme.disabledTextColor || "#808080"
                                        Layout.fillWidth: true
                                    }
                                }
                                
                                Controls.ToolButton {
                                    icon.name: "document-send"
                                    enabled: worklogSyncService && worklogs.length > 0
                                    Layout.preferredWidth: 40
                                    onClicked: {
                                        if (worklogSyncService && worklogs.length > 0) {
                                            var sessionIds = []
                                            for (var i = 0; i < worklogs.length; i++) {
                                                if (worklogs[i].id) {
                                                    sessionIds.push(worklogs[i].id)
                                                }
                                            }
                                            console.log("PendingWorklogsPage: Sincronizando %d worklogs da issue %s", sessionIds.length, issueKey)
                                            worklogSyncService.sync_pending_worklogs(sessionIds)
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Lista de worklogs do grupo
                        Repeater {
                            id: worklogsRepeater
                            model: worklogs
                            
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 100
                                color: Kirigami.Theme.backgroundColor || "#f0f0f0"
                                border.color: Kirigami.Theme.separatorColor || "#d0d0d0"
                                border.width: 1
                                radius: Kirigami.Units.smallSpacing
                                
                                property var worklogData: worklogs[index] || {}
                                
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: Kirigami.Units.mediumSpacing
                                    spacing: Kirigami.Units.mediumSpacing
                                    
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: Kirigami.Units.smallSpacing
                                        
                                        // Datas: início e fim lado a lado
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: Kirigami.Units.largeSpacing
                                            
                                            // Data de início
                                            Controls.Label {
                                                text: {
                                                    if (worklogData.start_time) {
                                                        var date = new Date(worklogData.start_time)
                                                        return qsTr("Início: %1").arg(Qt.formatDateTime(date, "dd/MM/yyyy HH:mm"))
                                                    }
                                                    return ""
                                                }
                                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                                                color: Kirigami.Theme.disabledTextColor || "#808080"
                                                visible: worklogData.start_time
                                            }
                                            
                                            // Data de fim
                                            Controls.Label {
                                                text: {
                                                    if (worklogData.end_time) {
                                                        var date = new Date(worklogData.end_time)
                                                        return qsTr("Fim: %1").arg(Qt.formatDateTime(date, "dd/MM/yyyy HH:mm"))
                                                    }
                                                    return ""
                                                }
                                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                                                color: Kirigami.Theme.disabledTextColor || "#808080"
                                                visible: worklogData.end_time
                                            }
                                        }
                                        
                                        // Duração calculada (abaixo das datas)
                                        Controls.Label {
                                            text: {
                                                var duration = worklogData.duration_seconds || 0
                                                var hours = Math.floor(duration / 3600)
                                                var minutes = Math.floor((duration % 3600) / 60)
                                                return qsTr("Duração: %1h %2m").arg(hours).arg(minutes)
                                            }
                                            font.pointSize: Kirigami.Theme.defaultFont.pointSize
                                            font.bold: true
                                            color: Kirigami.Theme.highlightColor || "#3daee9"
                                            Layout.fillWidth: true
                                        }
                                    }
                                    
                                    Controls.ToolButton {
                                        icon.name: "document-send"
                                        enabled: worklogSyncService !== null && worklogSyncService !== undefined && worklogData.id
                                        Layout.preferredWidth: 40
                                        onClicked: {
                                            if (worklogSyncService && worklogData.id) {
                                                var sessionIds = [worklogData.id]
                                                console.log("PendingWorklogsPage: Sincronizando worklog:", worklogData.id)
                                                worklogSyncService.sync_pending_worklogs(sessionIds)
                                            }
                                        }
                                    }
                                    
                                    Controls.ToolButton {
                                        icon.name: "edit-delete"
                                        enabled: worklogSyncService !== null && worklogSyncService !== undefined && worklogData.id
                                        Layout.preferredWidth: 40
                                        onClicked: {
                                            if (worklogSyncService && worklogData.id) {
                                                console.log("PendingWorklogsPage: Deletando worklog:", worklogData.id)
                                                if (worklogSyncService.delete_worklog(worklogData.id)) {
                                                    reloadWorklogs()
                                                }
                                            }
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
            visible: !worklogSyncService || (pendingWorklogs.length === 0)
        }
    }
}
