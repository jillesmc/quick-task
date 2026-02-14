/**
 * GooglePage.qml
 *
 * Aba unificada Google: coluna esquerda = Calendar (eventos do dia);
 * coluna direita = Tasks (tarefas todo). Layout SplitView como GitHub.
 * Importar evento/tarefa para Jira mantido.
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

    title: qsTr("Google")

    focus: true

    property var googleCalendarService: null
    property var googleTasksService: null
    property var googleAuthService: null
    property var jiraService: null
    property var issueModel: null
    property var tabBar: null

    property var events: []
    property var tasks: []
    property bool isLoadingCalendar: false
    property bool isLoadingTasks: false
    property string errorMessageCalendar: ""
    property string errorMessageTasks: ""
    property string currentDateStr: ""
    property bool hasCachedData: false

    property bool isLoading: isLoadingCalendar || isLoadingTasks

    function formatDate(d) {
        var y = d.getFullYear()
        var m = String(d.getMonth() + 1).padStart(2, "0")
        var day = String(d.getDate()).padStart(2, "0")
        return y + "-" + m + "-" + day
    }

    function setDateFromStr(s) {
        var parts = (s || "").split("-")
        if (parts.length >= 3) {
            var d = new Date(parseInt(parts[0]), parseInt(parts[1]) - 1, parseInt(parts[2]))
            if (!isNaN(d.getTime())) {
                page._currentDate = d
                page.currentDateStr = formatDate(d)
                return
            }
        }
        var today = new Date()
        page._currentDate = today
        page.currentDateStr = formatDate(today)
    }

    property var _currentDate: new Date()

    function reloadCalendar() {
        if (!page.googleCalendarService) return
        if (!page.currentDateStr) {
            var today = new Date()
            page._currentDate = today
            page.currentDateStr = formatDate(today)
        }
        page.isLoadingCalendar = true
        page.googleCalendarService.loadEventsForDate(page.currentDateStr)
    }

    function reloadTasks() {
        if (!page.googleTasksService) return
        page.isLoadingTasks = true
        page.googleTasksService.loadTasks()
    }

    function reload() {
        page.errorMessageCalendar = ""
        page.errorMessageTasks = ""
        page.reloadCalendar()
        page.reloadTasks()
    }

    function prevDay() {
        var d = new Date(page._currentDate)
        d.setDate(d.getDate() - 1)
        page._currentDate = d
        page.currentDateStr = formatDate(d)
        page.reloadCalendar()
    }

    function nextDay() {
        var d = new Date(page._currentDate)
        d.setDate(d.getDate() + 1)
        page._currentDate = d
        page.currentDateStr = formatDate(d)
        page.reloadCalendar()
    }

    function formatDueDate(rfc3339Str) {
        if (!rfc3339Str || typeof rfc3339Str !== "string") return ""
        var s = rfc3339Str.trim()
        if (s.indexOf("T") >= 0) return s.split("T")[0] || ""
        return s.split(" ")[0] || s
    }

    function formatWorklogStart(isoStart) {
        if (!isoStart || typeof isoStart !== "string") return ""
        var s = isoStart.trim()
        if (!s) return ""
        var d = new Date(s)
        if (isNaN(d.getTime())) return ""
        var y = d.getFullYear()
        var m = String(d.getMonth() + 1).padStart(2, "0")
        var day = String(d.getDate()).padStart(2, "0")
        var h = String(d.getHours()).padStart(2, "0")
        var min = String(d.getMinutes()).padStart(2, "0")
        var sec = String(d.getSeconds()).padStart(2, "0")
        return y + "-" + m + "-" + day + " " + h + ":" + min + ":" + sec
    }

    function importEventToJira(event) {
        if (!page.issueModel || !page.tabBar || !event) return
        page.issueModel.summary = event.summary || ""
        page.issueModel.description = event.description || ""
        page.issueModel.worklogInicio = page.formatWorklogStart(event.start)
        page.issueModel.worklogDuracao = event.duration_minutes || 30
        page.issueModel.statusInicial = "IN DEVELOPMENT"
        page.issueModel.registrarWorklog = true
        page.tabBar.currentIndex = 0
    }

    function importTaskToJira(task) {
        if (!page.issueModel || !page.tabBar || !task) return
        var desc = task.notes || ""
        if (task.list_title) desc = (desc ? desc + "\n\n" : "") + qsTr("Lista: %1").arg(task.list_title)
        if (task.due) desc = (desc ? desc + "\n" : "") + qsTr("Vencimento: %1").arg(page.formatDueDate(task.due))
        var src = task.assignment_source || ""
        if (src === "SPACE") {
            desc = (desc ? desc + "\n\n" : "") + qsTr("Origem: Google Chat Space")
            if (task.assignment_link) desc = desc + "\n" + qsTr("Link: %1").arg(task.assignment_link)
        } else if (src === "DOCUMENT") {
            desc = (desc ? desc + "\n\n" : "") + qsTr("Origem: Google Docs")
            if (task.assignment_link) desc = desc + "\n" + qsTr("Link: %1").arg(task.assignment_link)
        }
        var links = task.links || []
        if (links.length > 0) {
            desc = (desc ? desc + "\n\n" : "") + qsTr("Links:")
            for (var i = 0; i < links.length; i++) {
                var lnk = links[i]
                if (lnk && lnk.link) desc = desc + "\n- " + lnk.link
            }
        }
        page.issueModel.summary = task.title || ""
        page.issueModel.description = desc
        page.tabBar.currentIndex = 0
    }

    Component.onCompleted: {
        if (!page.currentDateStr) {
            var today = new Date()
            page._currentDate = today
            page.currentDateStr = formatDate(today)
        }
    }

    actions: [
        Kirigami.Action {
            text: qsTr("Atualizar")
            icon.name: "view-refresh"
            enabled: page.googleCalendarService && page.googleTasksService && page.googleAuthService
                && page.googleAuthService.isAuthorized && !page.isLoading
            onTriggered: page.reload()
        }
    ]

    Connections {
        target: page.googleCalendarService || null

        function onEventsReady(list) {
            page.events = list || []
            page.isLoadingCalendar = false
            page.errorMessageCalendar = ""
            page.hasCachedData = true
        }

        function onErrorOccurred(msg) {
            page.isLoadingCalendar = false
            page.errorMessageCalendar = msg || qsTr("Erro ao carregar eventos.")
            page.hasCachedData = true
        }

        function onAuthRequired() {
            page.isLoadingCalendar = false
            page.errorMessageCalendar = qsTr("Autorize o acesso ao Google nas Configurações.")
        }
    }

    Connections {
        target: page.googleTasksService || null

        function onTasksReady(list) {
            page.tasks = list || []
            page.isLoadingTasks = false
            page.errorMessageTasks = ""
            page.hasCachedData = true
        }

        function onErrorOccurred(msg) {
            page.isLoadingTasks = false
            page.errorMessageTasks = msg || qsTr("Erro ao carregar tarefas.")
            page.hasCachedData = true
        }

        function onAuthRequired() {
            page.isLoadingTasks = false
            page.errorMessageTasks = qsTr("Autorize o acesso ao Google nas Configurações.")
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.mediumSpacing

        Controls.Label {
            Layout.fillWidth: true
            visible: !page.googleAuthService || !page.googleAuthService.isAuthorized
            text: qsTr("Configure e autorize o Google OAuth nas Configurações para acessar Calendar e Tasks.")
            color: Kirigami.Theme.disabledTextColor
            wrapMode: Text.WordWrap
        }

        Controls.SplitView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: page.googleAuthService && page.googleAuthService.isAuthorized
            handle: SplitViewHandle { }

            // Coluna esquerda: Google Calendar
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
                        running: page.isLoadingCalendar
                        visible: page.isLoadingCalendar
                    }

                    Controls.Label {
                        Layout.fillWidth: true
                        visible: !page.isLoadingCalendar && page.errorMessageCalendar.length > 0
                        text: page.errorMessageCalendar
                        color: Kirigami.Theme.negativeTextColor
                        wrapMode: Text.WordWrap
                    }

                    Kirigami.Heading {
                        level: 4
                        text: qsTr("Calendar — Eventos do dia")
                        Layout.fillWidth: true
                        visible: !page.isLoadingCalendar
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        visible: !page.isLoadingCalendar

                        Controls.Button {
                            icon.name: "arrow-left"
                            onClicked: page.prevDay()
                        }
                        Controls.TextField {
                            id: dateField
                            text: page.currentDateStr
                            placeholderText: "YYYY-MM-DD"
                            Layout.fillWidth: true
                            onAccepted: {
                                page.setDateFromStr(text)
                                page.reloadCalendar()
                            }
                        }
                        Controls.Button {
                            icon.name: "arrow-right"
                            onClicked: page.nextDay()
                        }
                    }

                    Repeater {
                        model: page.events
                        visible: !page.isLoadingCalendar
                        delegate: Item {
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: eventDelegate.height
                            GoogleCalendarEventDelegate {
                                id: eventDelegate
                                itemData: parent.modelData
                                width: parent.width - Kirigami.Units.smallSpacing * 2
                                onImportRequested: (item) => page.importEventToJira(item)
                            }
                        }
                    }

                    Controls.Label {
                        text: qsTr("Nenhum evento neste dia.")
                        color: Kirigami.Theme.disabledTextColor
                        visible: !page.isLoadingCalendar && page.events.length === 0
                        Layout.fillWidth: true
                    }
                }
            }

            // Coluna direita: Google Tasks
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
                        running: page.isLoadingTasks
                        visible: page.isLoadingTasks
                    }

                    Controls.Label {
                        Layout.fillWidth: true
                        visible: !page.isLoadingTasks && page.errorMessageTasks.length > 0
                        text: page.errorMessageTasks
                        color: Kirigami.Theme.negativeTextColor
                        wrapMode: Text.WordWrap
                    }

                    Kirigami.Heading {
                        level: 4
                        text: qsTr("Tasks — Tarefas pendentes")
                        Layout.fillWidth: true
                        visible: !page.isLoadingTasks
                    }

                    Repeater {
                        model: page.tasks
                        visible: !page.isLoadingTasks
                        delegate: Item {
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: taskDelegate.height
                            GoogleTaskItemDelegate {
                                id: taskDelegate
                                itemData: parent.modelData
                                width: parent.width - Kirigami.Units.smallSpacing * 2
                                onImportRequested: (item) => page.importTaskToJira(item)
                            }
                        }
                    }

                    Controls.Label {
                        text: qsTr("Nenhuma tarefa pendente.")
                        color: Kirigami.Theme.disabledTextColor
                        visible: !page.isLoadingTasks && page.tasks.length === 0
                        Layout.fillWidth: true
                    }
                }
            }
        }
    }

}
