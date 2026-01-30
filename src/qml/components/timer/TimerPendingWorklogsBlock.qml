/**
 * TimerPendingWorklogsBlock.qml
 *
 * Bloco de worklogs pendentes na TimerPage: lista e botão Atualizar.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: root

    property var pendingWorklogs: []
    property var worklogSyncService: null
    signal refreshRequested()

    Controls.Label {
        text: qsTr("Worklogs Pendentes")
        font.bold: true
        font.pointSize: Kirigami.Theme.defaultFont.pointSize + 1
        Layout.fillWidth: true
    }

    Repeater {
        id: pendingWorklogsRepeater
        model: root.pendingWorklogs

        delegate: Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 80
            color: Kirigami.Theme.backgroundColor || "#f0f0f0"
            border.color: Kirigami.Theme.separatorColor || "#d0d0d0"
            border.width: 1
            radius: Kirigami.Units.smallSpacing

            property var worklogData: root.pendingWorklogs[index] || {}

            RowLayout {
                anchors.fill: parent
                anchors.margins: Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.mediumSpacing

                ColumnLayout {
                    Layout.fillWidth: true

                    Controls.Label {
                        text: worklogData.issue_key || ""
                        font.bold: true
                        Layout.fillWidth: true
                    }

                    Controls.Label {
                        text: {
                            var duration = worklogData.duration_seconds || 0;
                            var hours = Math.floor(duration / 3600);
                            var minutes = Math.floor((duration % 3600) / 60);
                            return qsTr("%1h %2m").arg(hours).arg(minutes);
                        }
                        Layout.fillWidth: true
                        color: Kirigami.Theme.disabledTextColor || "#808080"
                    }

                    Controls.Label {
                        text: {
                            if (worklogData.start_time) {
                                var date = new Date(worklogData.start_time);
                                return Qt.formatDateTime(date, "dd/MM/yyyy HH:mm");
                            }
                            return "";
                        }
                        Layout.fillWidth: true
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        color: Kirigami.Theme.disabledTextColor || "#808080"
                    }
                }

                Controls.Button {
                    text: qsTr("Sincronizar")
                    icon.name: "network-upload"
                    enabled: root.worklogSyncService !== null && root.worklogSyncService !== undefined
                    onClicked: {
                        if (root.worklogSyncService && worklogData.id) {
                            root.worklogSyncService.sync_pending_worklogs([worklogData.id]);
                        }
                    }
                }
            }
        }
    }

    Controls.Label {
        text: qsTr("Nenhum worklog pendente")
        Layout.fillWidth: true
        color: Kirigami.Theme.disabledTextColor || "#808080"
        visible: !root.worklogSyncService || (root.pendingWorklogs.length === 0)
    }

    Controls.Button {
        text: qsTr("Atualizar Lista")
        icon.name: "view-refresh"
        Layout.fillWidth: true
        enabled: root.worklogSyncService !== null && root.worklogSyncService !== undefined
        onClicked: {
            root.refreshRequested();
        }
    }
}
