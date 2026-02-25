/**
 * ProcessDialog.qml
 *
 * Diálogo unificado de processo com estados: confirm, progress, success, error.
 * Uma única janela que muda de conteúdo conforme o estado; fechamento apenas por botão ou Escape.
 */
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

import "../../utils/FormatUtils.js" as FormatUtils

Controls.Dialog {
    id: root

    modal: true
    closePolicy: Controls.Popup.CloseOnEscape
    standardButtons: Controls.Dialog.NoButton

    // Documentação Qt: Popup usa contentWidth/contentHeight para calcular tamanho (doc.qt.io/qt-6/qml-qtquick-controls-popup.html#popup-sizing)
    contentWidth: 480
    contentHeight: contentColumn.implicitHeight + 2 * (Kirigami.Units.largeSpacing * 1.5)

    // Margens do conteúdo como em SuccessDialog/ErrorDialog (IssueFormPage): padding pelas bordas
    topPadding: 0
    bottomPadding: 0
    leftPadding: 0
    rightPadding: 0

    /** "confirm" | "progress" | "success" | "error" */
    property string state: "progress"
    property var applicationWindow: null

    // ---- Confirm (worklogs pendentes) ----
    property var worklogInfo: []
    property string totalFormatted: ""
    property string targetStatus: ""
    property bool blockTransitionIfPending: false

    signal cancelClicked()
    signal skipSyncClicked()
    signal syncClicked()

    // ---- Progress ----
    property string progressMessage: ""
    property int progressValue: 0

    // ---- Success ----
    property string successIssueKey: ""
    property string successIssueUrl: ""
    property bool successIsUpdate: false
    property var timerService: null
    property var timerModel: null
    property var jiraService: null
    property bool _waitingForInProgress: false

    // ---- Error ----
    property string errorMessage: ""

    function _updateTitle() {
        if (root.state === "confirm") title = qsTr("Worklogs pendentes")
        else if (root.state === "progress") title = qsTr("Progresso")
        else if (root.state === "success") title = root.successIsUpdate ? qsTr("Task Atualizada") : qsTr("Issue Criada")
        else if (root.state === "error") title = qsTr("Erro")
    }

    onStateChanged: _updateTitle()

    function openInConfirm(worklogs, totalFormattedStr, targetStatusStr, blockIfPending) {
        if (typeof console !== "undefined" && console.log) {
            console.log("[ProcessDialog] openInConfirm: parent=", root.parent ? "set" : "null", "worklogs=", (worklogs || []).length);
        }
        root.worklogInfo = worklogs || []
        root.totalFormatted = totalFormattedStr || ""
        root.targetStatus = targetStatusStr || ""
        root.blockTransitionIfPending = blockIfPending || false
        root.state = "confirm"
        root.open()
        if (typeof console !== "undefined" && console.log) {
            console.log("[ProcessDialog] openInConfirm: open() called, opened=", root.opened);
        }
        Qt.callLater(centerDialog)
    }

    /** Transição para estado confirm (ex.: já aberto em progress, aparece worklogs). */
    function transitionToConfirm(worklogs, totalFormattedStr, targetStatusStr, blockIfPending) {
        root.worklogInfo = worklogs || []
        root.totalFormatted = totalFormattedStr || ""
        root.targetStatus = targetStatusStr || ""
        root.blockTransitionIfPending = blockIfPending || false
        root.state = "confirm"
        Qt.callLater(centerDialog)
    }

    function openInProgress(message) {
        root.progressMessage = message || qsTr("Processando...")
        root.progressValue = 0
        root.state = "progress"
        root.open()
        Qt.callLater(centerDialog)
    }

    function transitionToProgress(message) {
        root.progressMessage = message || root.progressMessage
        root.progressValue = 0
        root.state = "progress"
        Qt.callLater(centerDialog)
    }

    function updateProgress(percentage, message) {
        root.progressValue = percentage
        if (message) root.progressMessage = message
    }

    function transitionToSuccess(issueKey, issueUrl, isUpdate) {
        root.successIssueKey = issueKey || ""
        root.successIssueUrl = issueUrl || ""
        root.successIsUpdate = !!isUpdate
        root._waitingForInProgress = false
        root.state = "success"
        if (!root.opened) root.open()
        Qt.callLater(centerDialog)
    }

    function transitionToError(message) {
        if (typeof console !== "undefined" && console.log) {
            console.log("[ProcessDialog.transitionToError] Mostrando erro no ProcessDialog (botão Fechar). message(primeiros 80)=", (message || "").slice(0, 80));
        }
        root.errorMessage = message || ""
        root.state = "error"
        if (!root.opened) root.open()
        Qt.callLater(centerDialog)
    }

    function centerDialog() {
        var cw = (applicationWindow && applicationWindow.width > 0) ? applicationWindow.width : (parent ? parent.width : 0)
        var ch = (applicationWindow && applicationWindow.height > 0) ? applicationWindow.height : (parent ? parent.height : 0)
        if (width > 0 && height > 0 && cw > 0 && ch > 0) {
            x = Math.max(0, (cw - width) / 2)
            y = Math.max(0, (ch - height) / 2)
        }
    }

    function formatDurationSeconds(seconds) {
        if (seconds == null || isNaN(seconds)) return ""
        return FormatUtils.formatDuration(Math.floor(Number(seconds) / 60))
    }

    Component.onCompleted: {
        _updateTitle()
        Qt.callLater(centerDialog)
    }
    onWidthChanged: Qt.callLater(centerDialog)
    onHeightChanged: Qt.callLater(centerDialog)

    contentItem: Item {
        implicitWidth: root.contentWidth
        implicitHeight: root.contentHeight

        ColumnLayout {
            id: contentColumn
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing * 1.5
            spacing: Kirigami.Units.mediumSpacing

            // ---------- Confirm (worklogs) ----------
            ColumnLayout {
                visible: root.state === "confirm"
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing

                Controls.Label {
                    text: root.targetStatus
                        ? qsTr("Esta issue tem worklogs pendentes (%1). É recomendado sincronizar antes de transitar para %2.").arg(root.totalFormatted).arg(root.targetStatus)
                        : qsTr("Esta issue tem worklogs pendentes (%1). É recomendado sincronizar antes de continuar.").arg(root.totalFormatted)
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.smallSpacing
                    Layout.rightMargin: Kirigami.Units.smallSpacing
                }

                Controls.ScrollView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(100, worklogList.implicitHeight)
                    clip: true
                    contentWidth: availableWidth
                    ListView {
                        id: worklogList
                        model: root.worklogInfo
                        spacing: Kirigami.Units.smallSpacing
                        delegate: Controls.ItemDelegate {
                            id: worklogDelegate
                            required property var modelData
                            width: worklogList.width
                            leftPadding: 0
                            topPadding: Kirigami.Units.smallSpacing
                            bottomPadding: Kirigami.Units.smallSpacing
                            contentItem: RowLayout {
                                spacing: Kirigami.Units.mediumSpacing
                                Controls.Label {
                                    text: worklogDelegate.modelData.start_time || ""
                                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                    Layout.preferredWidth: 100
                                }
                                Controls.Label {
                                    text: root.formatDurationSeconds(worklogDelegate.modelData.duration_seconds)
                                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                    Layout.preferredWidth: 56
                                }
                                Controls.Label {
                                    text: (worklogDelegate.modelData.description || "").slice(0, 40) + ((worklogDelegate.modelData.description || "").length > 40 ? "…" : "")
                                    elide: Text.ElideRight
                                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignRight
                    spacing: Kirigami.Units.smallSpacing
                    Item { Layout.fillWidth: true }
                    Controls.Button {
                        text: qsTr("Cancelar")
                        onClicked: {
                            root.cancelClicked()
                            root.close()
                        }
                    }
                    Controls.Button {
                        visible: !root.blockTransitionIfPending
                        text: qsTr("Continuar sem sincronizar")
                        onClicked: {
                            root.skipSyncClicked()
                            // Não fechar: a página faz transição para progresso no mesmo dialog (fluxo unificado)
                        }
                    }
                    Controls.Button {
                        text: qsTr("Sincronizar")
                        highlighted: true
                        onClicked: {
                            root.syncClicked()
                            root.transitionToProgress(qsTr("Sincronizando worklogs..."))
                        }
                    }
                }
            }

            // ---------- Progress ----------
            ColumnLayout {
                visible: root.state === "progress"
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing

                Controls.Label {
                    text: root.progressMessage
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.smallSpacing
                    Layout.rightMargin: Kirigami.Units.smallSpacing
                    wrapMode: Text.Wrap
                }
                Item {
                    Layout.fillWidth: true
                    implicitHeight: Kirigami.Units.smallSpacing * 2
                    Rectangle {
                        anchors.fill: parent
                        color: Kirigami.Theme.backgroundColor
                        border.color: Kirigami.Theme.disabledTextColor
                        radius: Kirigami.Units.smallSpacing
                    }
                    Rectangle {
                        width: Math.min(1, Math.max(0, root.progressValue / 100)) * parent.width
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        radius: Kirigami.Units.smallSpacing
                        color: Kirigami.Theme.highlightColor
                    }
                }
            }

            // ---------- Success ----------
            ColumnLayout {
                visible: root.state === "success"
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing

                Controls.Label {
                    text: root.successIsUpdate ? qsTr("Task atualizada com sucesso!") : qsTr("Issue criada com sucesso!")
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.smallSpacing
                    Layout.rightMargin: Kirigami.Units.smallSpacing
                    wrapMode: Text.Wrap
                }
                Controls.Label {
                    text: "Issue: " + root.successIssueKey
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.smallSpacing
                    Layout.rightMargin: Kirigami.Units.smallSpacing
                    wrapMode: Text.Wrap
                    font.bold: true
                }
                Controls.Label {
                    text: root.successIssueUrl
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.smallSpacing
                    Layout.rightMargin: Kirigami.Units.smallSpacing
                    visible: root.successIssueUrl !== ""
                    color: Kirigami.Theme.linkColor
                    wrapMode: Text.Wrap
                    elide: Text.ElideMiddle
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.successIssueUrl) Qt.openUrlExternally(root.successIssueUrl)
                        }
                    }
                }
                RowLayout {
                    visible: root._waitingForInProgress
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    Controls.BusyIndicator {
                        running: root._waitingForInProgress
                        Layout.preferredWidth: Kirigami.Units.iconSizes.small
                        Layout.preferredHeight: Kirigami.Units.iconSizes.small
                    }
                    Controls.Label {
                        text: qsTr("Transicionando para IN PROGRESS...")
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }
                }

                Controls.Button {
                    text: qsTr("Iniciar Timer")
                    icon.name: "chronometer"
                    Layout.fillWidth: true
                    visible: !root.successIsUpdate && root.successIssueKey !== "" && root.timerService && root.timerModel
                    enabled: root.timerService && root.timerModel && !root._waitingForInProgress
                    onClicked: {
                        if (!root.timerService || !root.successIssueKey) return
                        if (root.jiraService && root.jiraService.transitionToInProgressIfNeeded && root.jiraService.transitionToInProgressIfNeeded(root.successIssueKey)) {
                            root._waitingForInProgress = true
                        } else {
                            root.timerService.start(root.successIssueKey)
                            root.close()
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignHCenter
                    Item { Layout.fillWidth: true }
                    Controls.Button {
                        text: (!root.successIsUpdate && root.successIssueUrl !== "") ? qsTr("Abrir") : qsTr("OK")
                        Layout.preferredWidth: 120
                        onClicked: {
                            if (!root.successIsUpdate && root.successIssueUrl) Qt.openUrlExternally(root.successIssueUrl)
                            root.close()
                        }
                    }
                    Item { Layout.fillWidth: true }
                }
            }

            // ---------- Error ----------
            ColumnLayout {
                visible: root.state === "error"
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing

                Controls.Label {
                    text: root.errorMessage
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.smallSpacing
                    Layout.rightMargin: Kirigami.Units.smallSpacing
                    wrapMode: Text.Wrap
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignRight
                    Item { Layout.fillWidth: true }
                    Controls.Button {
                        text: qsTr("Fechar")
                        onClicked: root.close()
                    }
                }
            }
        }
    }

    Connections {
        target: root.jiraService || null
        function onInProgressReady(key) {
            if (root._waitingForInProgress && key === root.successIssueKey) {
                root._waitingForInProgress = false
                if (root.timerService) root.timerService.start(key)
                root.close()
            }
        }
        function onErrorOccurred(message) {
            if (root._waitingForInProgress) root._waitingForInProgress = false
        }
    }
}
