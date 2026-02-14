/**
 * StatusTransitionsSettingsBlock.qml
 *
 * Bloco de configurações para verificação de worklogs pendentes ao transitar status:
 * enabled, show_confirmation_dialog, block_transition_if_pending.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

Rectangle {
    id: root

    property var settingsModel: null
    implicitHeight: blockColumn.implicitHeight + (Kirigami.Units.largeSpacing * 2)

    color: Kirigami.Theme.backgroundColor || "#f0f0f0"
    border.color: Kirigami.Theme.textColor || "#d0d0d0"
    border.width: 1
    radius: Kirigami.Units.smallSpacing

    ColumnLayout {
        id: blockColumn
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Heading {
            text: qsTr("Verificação de worklogs ao transitar status")
            level: 3
            Layout.fillWidth: true
        }

        Controls.CheckBox {
            id: worklogCheckEnabledCheckbox
            text: qsTr("Verificar worklogs pendentes antes de transitar")
            Layout.fillWidth: true
            checked: true
            onCheckedChanged: {
                if (root.settingsModel) {
                    root.settingsModel.worklogCheckEnabled = checked;
                }
                worklogCheckShowDialogCheckbox.enabled = checked;
                worklogCheckBlockIfPendingCheckbox.enabled = checked;
            }
        }

        Controls.CheckBox {
            id: worklogCheckShowDialogCheckbox
            Layout.topMargin: Kirigami.Units.largeSpacing
            text: qsTr("Mostrar diálogo de confirmação quando houver pendentes")
            Layout.fillWidth: true
            checked: true
            onCheckedChanged: {
                if (root.settingsModel) {
                    root.settingsModel.worklogCheckShowDialog = checked;
                }
            }
        }

        Controls.CheckBox {
            id: worklogCheckBlockIfPendingCheckbox
            text: qsTr("Bloquear transição se houver pendentes (apenas Sincronizar ou Cancelar)")
            Layout.fillWidth: true
            checked: false
            onCheckedChanged: {
                if (root.settingsModel) {
                    root.settingsModel.worklogCheckBlockIfPending = checked;
                }
            }
        }
    }

    Component.onCompleted: {
        if (root.settingsModel) {
            worklogCheckEnabledCheckbox.checked = root.settingsModel.worklogCheckEnabled;
            worklogCheckShowDialogCheckbox.checked = root.settingsModel.worklogCheckShowDialog;
            worklogCheckBlockIfPendingCheckbox.checked = root.settingsModel.worklogCheckBlockIfPending;
            worklogCheckShowDialogCheckbox.enabled = root.settingsModel.worklogCheckEnabled;
            worklogCheckBlockIfPendingCheckbox.enabled = root.settingsModel.worklogCheckEnabled;
        }
    }
}
