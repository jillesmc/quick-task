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
    property var tabBar: null

    property var events: []
    property var tasks: []
    property bool isLoadingCalendar: false
    property bool isLoadingTasks: false
    property string errorMessage: ""
    property string currentDateStr: ""

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
        page.errorMessage = ""
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

    // qmllint disable missing-property
    function openImportCalendarDialog(event) {
        var item = importCalendarDialogLoader.item
        if (item && typeof item.openWith === "function") {
            item.openWith(event, page.jiraService)
        }
    }

    function openImportTaskDialog(task) {
        var item = importTaskDialogLoader.item
        if (item && typeof item.openWith === "function") {
            item.openWith(task, page.jiraService)
        }
    }
    // qmllint enable missing-property

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
        }

        function onErrorOccurred(msg) {
            page.isLoadingCalendar = false
            page.errorMessage = msg || qsTr("Erro ao carregar eventos.")
        }

        function onAuthRequired() {
            page.isLoadingCalendar = false
            page.errorMessage = qsTr("Autorize o acesso ao Google nas Configurações.")
        }
    }

    Connections {
        target: page.googleTasksService || null

        function onTasksReady(list) {
            page.tasks = list || []
            page.isLoadingTasks = false
        }

        function onErrorOccurred(msg) {
            page.isLoadingTasks = false
            page.errorMessage = msg || qsTr("Erro ao carregar tarefas.")
        }

        function onAuthRequired() {
            page.isLoadingTasks = false
            page.errorMessage = qsTr("Autorize o acesso ao Google nas Configurações.")
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

        Controls.Label {
            Layout.fillWidth: true
            visible: !page.googleAuthService || !page.googleAuthService.isAuthorized
            text: qsTr("Configure e autorize o Google OAuth nas Configurações para acessar Calendar e Tasks.")
            color: Kirigami.Theme.disabledTextColor
            wrapMode: Text.WordWrap
        }

        Controls.BusyIndicator {
            Layout.alignment: Qt.AlignHCenter
            running: page.isLoading
            visible: page.isLoading
        }

        Controls.SplitView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: page.googleAuthService && page.googleAuthService.isAuthorized && !page.isLoading
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

                    Kirigami.Heading {
                        level: 4
                        text: qsTr("Calendar — Eventos do dia")
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

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
                        delegate: Item {
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: eventDelegate.height
                            GoogleCalendarEventDelegate {
                                id: eventDelegate
                                itemData: parent.modelData
                                width: parent.width - Kirigami.Units.smallSpacing * 2
                                onImportRequested: (item) => page.openImportCalendarDialog(item)
                            }
                        }
                    }

                    Controls.Label {
                        text: qsTr("Nenhum evento neste dia.")
                        color: Kirigami.Theme.disabledTextColor
                        visible: page.events.length === 0
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

                    Kirigami.Heading {
                        level: 4
                        text: qsTr("Tasks — Tarefas pendentes")
                        Layout.fillWidth: true
                    }

                    Repeater {
                        model: page.tasks
                        delegate: Item {
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: taskDelegate.height
                            GoogleTaskItemDelegate {
                                id: taskDelegate
                                itemData: parent.modelData
                                width: parent.width - Kirigami.Units.smallSpacing * 2
                                onImportRequested: (item) => page.openImportTaskDialog(item)
                            }
                        }
                    }

                    Controls.Label {
                        text: qsTr("Nenhuma tarefa pendente.")
                        color: Kirigami.Theme.disabledTextColor
                        visible: page.tasks.length === 0
                        Layout.fillWidth: true
                    }
                }
            }
        }
    }

    Loader {
        id: importCalendarDialogLoader
        active: true
        source: "../components/dialogs/ImportCalendarEventDialog.qml"
        onLoaded: {
            if (item) {
                item.jiraService = Qt.binding(function() { return page.jiraService })
            }
        }
    }

    Loader {
        id: importTaskDialogLoader
        active: true
        source: "../components/dialogs/ImportTaskDialog.qml"
    }
}
