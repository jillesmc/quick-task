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
    
    // Função para recarregar worklogs (pode ser chamada externamente)
    function reloadWorklogs() {
        if (worklogSyncService) {
            pendingWorklogs = worklogSyncService.get_pending_worklogs()
            console.log("PendingWorklogsPage: Worklogs pendentes carregados:", pendingWorklogs.length)
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
                loadIssueSummaries()
            }
        }
        
        function onSessionSynced(sessionId, jiraWorklogId) {
            console.log("PendingWorklogsPage: Worklog sincronizado ou deletado:", sessionId, "->", jiraWorklogId)
            if (worklogSyncService) {
                pendingWorklogs = worklogSyncService.get_pending_worklogs()
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
                        icon.name: "document-send"
                        enabled: worklogSyncService && pendingWorklogs.length > 0
                        Layout.preferredWidth: 40
                        onClicked: {
                            if (worklogSyncService && pendingWorklogs.length > 0) {
                                var sessionIds = []
                                for (var i = 0; i < pendingWorklogs.length; i++) {
                                    if (pendingWorklogs[i].id) {
                                        sessionIds.push(pendingWorklogs[i].id)
                                    }
                                }
                                console.log("PendingWorklogsPage: Sincronizando", sessionIds.length, "worklogs")
                                worklogSyncService.sync_pending_worklogs(sessionIds)
                            }
                        }
                    }
                }
            }
        }

        // Lista de worklogs pendentes
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
                id: worklogsListView
                model: pendingWorklogs
                spacing: Kirigami.Units.smallSpacing
                
                delegate: Rectangle {
                    width: worklogsListView.width
                    height: 120
                    color: Kirigami.Theme.backgroundColor || "#f0f0f0"
                    border.color: Kirigami.Theme.separatorColor || "#d0d0d0"
                    border.width: 1
                    radius: Kirigami.Units.smallSpacing
                    
                    property var worklogData: pendingWorklogs[index] || {}
                    
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.largeSpacing
                        spacing: Kirigami.Units.largeSpacing
                        
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing
                            
                            Controls.Label {
                                text: worklogData.issue_key || ""
                                font.bold: true
                                font.pointSize: Kirigami.Theme.defaultFont.pointSize + 1
                                Layout.fillWidth: true
                            }
                            
                            Controls.Label {
                                text: issueSummaries[worklogData.issue_key] || ""
                                font.pointSize: Kirigami.Theme.defaultFont.pointSize
                                color: Kirigami.Theme.textColor || "#000000"
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                visible: issueSummaries[worklogData.issue_key] !== undefined
                            }
                            
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
                                        // Atualizar lista após deleção bem-sucedida
                                        pendingWorklogs = worklogSyncService.get_pending_worklogs()
                                        loadIssueSummaries()
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
