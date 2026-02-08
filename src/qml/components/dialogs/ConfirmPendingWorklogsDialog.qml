/**
 * ConfirmPendingWorklogsDialog.qml
 * Diálogo para confirmar sincronização de worklogs pendentes antes de transitar status.
 * Mostra total e lista de worklogs; ações: Cancelar, Continuar sem sincronizar (se permitido), Sincronizar.
 * Emite cancelClicked(), skipSyncClicked(), syncClicked().
 */
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

import "../../utils/FormatUtils.js" as FormatUtils

Controls.Dialog {
    id: dialog

    title: qsTr("Worklogs pendentes")
    modal: true
    closePolicy: Controls.Popup.CloseOnEscape
    standardButtons: Controls.Dialog.NoButton

    width: 460
    implicitWidth: 460
    implicitHeight: 280
    height: implicitHeight

    /** Janela da aplicação (para centralizar o diálogo); definir antes de abrir. */
    property var applicationWindow: null

    /** Lista de entradas: [{ id, issue_key, start_time, duration_seconds, description }, ...] */
    property var worklogInfo: []
    /** Duração total formatada (ex.: "2h 30m") */
    property string totalFormatted: ""
    /** Status alvo para a mensagem (ex.: "CODE REVIEW") */
    property string targetStatus: ""
    /** Se true, não mostrar / desativar "Continuar sem sincronizar" */
    property bool blockTransitionIfPending: false

    signal cancelClicked()
    signal skipSyncClicked()
    signal syncClicked()

    function openWith(worklogs, totalFormattedStr, targetStatusStr, blockIfPending) {
        worklogInfo = worklogs || []
        totalFormatted = totalFormattedStr || ""
        targetStatus = targetStatusStr || ""
        blockTransitionIfPending = blockIfPending || false
        open()
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

    Component.onCompleted: Qt.callLater(centerDialog)
    onWidthChanged: Qt.callLater(centerDialog)
    onHeightChanged: Qt.callLater(centerDialog)

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.mediumSpacing

        Controls.Label {
            text: dialog.targetStatus
                ? qsTr("Esta issue tem worklogs pendentes (%1). É recomendado sincronizar antes de transitar para %2.").arg(dialog.totalFormatted).arg(dialog.targetStatus)
                : qsTr("Esta issue tem worklogs pendentes (%1). É recomendado sincronizar antes de continuar.").arg(dialog.totalFormatted)
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }

        Controls.ScrollView {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(100, worklogList.implicitHeight)
            clip: true
            contentWidth: availableWidth

            ListView {
                id: worklogList
                model: dialog.worklogInfo
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
                            text: dialog.formatDurationSeconds(worklogDelegate.modelData.duration_seconds)
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
            Layout.topMargin: Kirigami.Units.largeSpacing
            Layout.bottomMargin: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing

            Item { Layout.fillWidth: true }

            Controls.Button {
                text: qsTr("Cancelar")
                onClicked: {
                    dialog.cancelClicked()
                    dialog.close()
                }
            }
            Controls.Button {
                visible: !dialog.blockTransitionIfPending
                text: qsTr("Continuar sem sincronizar")
                onClicked: {
                    dialog.skipSyncClicked()
                    dialog.close()
                }
            }
            Controls.Button {
                text: qsTr("Sincronizar")
                highlighted: true
                onClicked: {
                    dialog.syncClicked()
                    dialog.close()
                }
            }
        }
    }
}
