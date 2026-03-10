/**
 * TimesheetPage.qml
 *
 * Página para visualizar worklogs por issue e dia da semana.
 * Seletor de período, tabela com células clicáveis para detalhes.
 */
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

Kirigami.Page {
    id: page

    title: qsTr("Timesheet")
    focus: true

    property var timesheetViewModel: null

    // Conectar sinal de detalhes para abrir modal
    Connections {
        target: page.timesheetViewModel || null
        function onWorklogDetailsRequested(details) {
            if (details && worklogDetailsDialog) {
                worklogDetailsDialog.details = details;
                worklogDetailsDialog.open();
            }
        }
    }

    // Diálogo de detalhes de worklog
    Controls.Popup {
        id: worklogDetailsDialog
        property var details: null
        anchors.centerIn: parent
        width: Math.min(parent.width - Kirigami.Units.gridUnit * 4, 400)
        modal: true
        closePolicy: Controls.Popup.CloseOnEscape | Controls.Popup.CloseOnPressOutside

        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing

            Controls.Label {
                Layout.fillWidth: true
                text: worklogDetailsDialog.details ? (worklogDetailsDialog.details.issueKey + " - " + worklogDetailsDialog.details.date) : ""
                font.bold: true
                wrapMode: Text.WordWrap
            }

            Repeater {
                model: worklogDetailsDialog.details ? worklogDetailsDialog.details.worklogs : []
                delegate: ColumnLayout {
                    id: worklogDelegate
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 2
                    Controls.Label {
                        Layout.fillWidth: true
                        text: (worklogDelegate.modelData.timeSpent || "") + " - " + (worklogDelegate.modelData.started || "")
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    }
                    Controls.Label {
                        Layout.fillWidth: true
                        text: worklogDelegate.modelData.comment || ""
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        color: Kirigami.Theme.disabledTextColor
                        wrapMode: Text.WordWrap
                    }
                }
            }

            Controls.Label {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                text: worklogDetailsDialog.details ? (qsTr("Total: ") + (worklogDetailsDialog.details.total || "00:00")) : ""
                font.bold: true
            }

            Controls.Button {
                Layout.alignment: Qt.AlignRight
                text: qsTr("Fechar")
                onClicked: worklogDetailsDialog.close()
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        visible: !page.timesheetViewModel || !page.timesheetViewModel.loading

        // Seletor de período
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Controls.ToolButton {
                icon.name: "go-previous"
                Controls.ToolTip.text: qsTr("Período anterior")
                Controls.ToolTip.visible: hovered
                enabled: page.timesheetViewModel && !page.timesheetViewModel.loading
                onClicked: page.timesheetViewModel && page.timesheetViewModel.navigatePrevious()
            }

            Controls.ToolButton {
                icon.name: "go-next"
                Controls.ToolTip.text: qsTr("Próximo período")
                Controls.ToolTip.visible: hovered
                enabled: page.timesheetViewModel && !page.timesheetViewModel.loading
                onClicked: page.timesheetViewModel && page.timesheetViewModel.navigateNext()
            }

            Controls.Label {
                text: page.timesheetViewModel ? page.timesheetViewModel.periodDateRange : ""
                font.bold: true
                Layout.minimumWidth: 140
            }

            Item {
                Layout.fillWidth: true
            }

            Controls.Button {
                text: qsTr("Hoje")
                enabled: page.timesheetViewModel && !page.timesheetViewModel.loading
                onClicked: page.timesheetViewModel && page.timesheetViewModel.setPeriod("today")
            }
            Controls.Button {
                text: qsTr("Esta semana")
                enabled: page.timesheetViewModel && !page.timesheetViewModel.loading
                onClicked: page.timesheetViewModel && page.timesheetViewModel.setPeriod("this_week")
            }
            Controls.Button {
                text: qsTr("Semana passada")
                enabled: page.timesheetViewModel && !page.timesheetViewModel.loading
                onClicked: page.timesheetViewModel && page.timesheetViewModel.setPeriod("last_week")
            }
            Controls.Button {
                text: qsTr("Últimos 7 dias")
                enabled: page.timesheetViewModel && !page.timesheetViewModel.loading
                onClicked: page.timesheetViewModel && page.timesheetViewModel.setPeriod("last_7_days")
            }
            Controls.Button {
                text: qsTr("Este mês")
                enabled: page.timesheetViewModel && !page.timesheetViewModel.loading
                onClicked: page.timesheetViewModel && page.timesheetViewModel.setPeriod("this_month")
            }
            Controls.Button {
                text: qsTr("Mês passado")
                enabled: page.timesheetViewModel && !page.timesheetViewModel.loading
                onClicked: page.timesheetViewModel && page.timesheetViewModel.setPeriod("last_month")
            }
        }

        // Erro
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 60
            visible: page.timesheetViewModel && page.timesheetViewModel.error !== ""
            color: Kirigami.Theme.negativeBackgroundColor
            radius: 4

            RowLayout {
                anchors.fill: parent
                anchors.margins: Kirigami.Units.smallSpacing

                Controls.Label {
                    Layout.fillWidth: true
                    text: page.timesheetViewModel ? page.timesheetViewModel.error : ""
                    wrapMode: Text.WordWrap
                    color: Kirigami.Theme.negativeTextColor
                }
                Controls.Button {
                    text: qsTr("Tentar Novamente")
                    onClicked: page.timesheetViewModel && page.timesheetViewModel.refresh()
                }
            }
        }

        // Tabela
        Controls.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ColumnLayout {
                width: parent ? parent.width - 40 : 800
                spacing: 0

                // Header: Issue | Total | dias
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Layout.bottomMargin: 4

                    Controls.Label {
                        Layout.preferredWidth: 200
                        text: qsTr("Issue")
                        font.bold: true
                    }
                    Controls.Label {
                        Layout.preferredWidth: 60
                        text: qsTr("Total")
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Repeater {
                        model: page.timesheetViewModel ? page.timesheetViewModel.dateHeaders : []
                        delegate: Controls.Label {
                            id: dateHeaderDelegate
                            required property var modelData
                            Layout.preferredWidth: 56
                            text: dateHeaderDelegate.modelData.weekday + "\n" + dateHeaderDelegate.modelData.day
                            font.bold: true
                            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                // Linhas de issues
                Repeater {
                    model: page.timesheetViewModel ? page.timesheetViewModel.issueRows : []

                    delegate: RowLayout {
                        id: rowDelegate
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 2
                        Layout.preferredHeight: 32
                        property string rowIssueKey: modelData ? (modelData.issueKey || "") : ""

                        Controls.Label {
                            Layout.preferredWidth: 200
                            text: (rowDelegate.modelData.issueKey || "") + " " + (rowDelegate.modelData.summary || "").substring(0, 30)
                            elide: Text.ElideRight
                            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        }
                        Controls.Label {
                            Layout.preferredWidth: 60
                            text: rowDelegate.modelData.total || "00:00"
                            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                            horizontalAlignment: Text.AlignHCenter
                        }
                        Repeater {
                            model: rowDelegate.modelData.timeCells || []
                            delegate: MouseArea {
                                id: cellDelegate
                                required property var modelData
                                required property int index
                                Layout.preferredWidth: 56
                                Layout.preferredHeight: 28
                                hoverEnabled: true
                                property string cellTime: cellDelegate.modelData || "00:00"
                                cursorShape: (cellTime !== "00:00" && cellTime !== "") ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: {
                                    if (cellTime === "00:00" || cellTime === "")
                                        return;
                                    var dateHeaders = page.timesheetViewModel ? page.timesheetViewModel.dateHeaders : [];
                                    var dateStr = dateHeaders[index] ? dateHeaders[index].date : "";
                                    var issueKey = rowDelegate ? rowDelegate.rowIssueKey : "";
                                    if (dateStr && issueKey && page.timesheetViewModel) {
                                        page.timesheetViewModel.showWorklogDetails(issueKey, dateStr);
                                    }
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    color: parent.containsMouse && (parent.cellTime !== "00:00" && parent.cellTime !== "") ? Kirigami.Theme.highlightColor : "transparent"
                                    radius: 2
                                }
                                Controls.Label {
                                    anchors.centerIn: parent
                                    text: parent.cellTime || "00:00"
                                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                    color: (parent.cellTime !== "00:00" && parent.cellTime !== "") ? Kirigami.Theme.textColor : Kirigami.Theme.disabledTextColor
                                    horizontalAlignment: Text.AlignHCenter
                                }
                            }
                        }
                    }
                }

                // Linha de totais
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    spacing: 2
                    Layout.preferredHeight: 28

                    Controls.Label {
                        Layout.preferredWidth: 200
                        text: qsTr("Total")
                        font.bold: true
                    }
                    Controls.Label {
                        Layout.preferredWidth: 60
                        text: page.timesheetViewModel ? page.timesheetViewModel.grandTotal : "00:00"
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Repeater {
                        model: page.timesheetViewModel ? page.timesheetViewModel.totalRow : []
                        delegate: Controls.Label {
                            id: totalCellDelegate
                            required property var modelData
                            Layout.preferredWidth: 56
                            text: totalCellDelegate.modelData || "00:00"
                            font.bold: true
                            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }
            }
        }
    }

    // Loading indicator (apenas ícone, sem overlay branco — igual às demais páginas)
    Controls.BusyIndicator {
        anchors.centerIn: parent
        running: page.timesheetViewModel && page.timesheetViewModel.loading
        visible: page.timesheetViewModel && page.timesheetViewModel.loading
    }

    // Placeholder quando timesheetViewModel não está disponível
    Controls.Label {
        anchors.centerIn: parent
        visible: !page.timesheetViewModel
        text: qsTr("Configure o Jira para usar o Timesheet.")
        color: Kirigami.Theme.disabledTextColor
    }
}
