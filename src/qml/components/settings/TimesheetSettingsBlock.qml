/**
 * TimesheetSettingsBlock.qml
 *
 * Bloco de configurações do Timesheet: enabled, cache_ttl_minutes,
 * default_period, max_results.
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

    ListModel {
        id: periodModel
        ListElement { value: "today"; label: "Today" }
        ListElement { value: "this_week"; label: "This Week" }
        ListElement { value: "last_week"; label: "Last Week" }
        ListElement { value: "last_7_days"; label: "Last 7 Days" }
        ListElement { value: "this_month"; label: "This Month" }
        ListElement { value: "last_month"; label: "Last Month" }
    }

    function indexForPeriod(period) {
        for (var i = 0; i < periodModel.count; i++) {
            if (periodModel.get(i).value === period) return i;
        }
        return 3; // last_7_days default
    }

    ColumnLayout {
        id: blockColumn
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Heading {
            text: qsTr("Configurações do Timesheet")
            level: 3
            Layout.fillWidth: true
        }

        Controls.CheckBox {
            id: timesheetEnabledCheckbox
            text: qsTr("Habilitar Timesheet")
            Layout.fillWidth: true
            checked: true
            onCheckedChanged: {
                if (root.settingsModel) {
                    root.settingsModel.timesheetEnabled = checked;
                }
                cacheTtlSpinBox.enabled = checked;
                defaultPeriodCombo.enabled = checked;
                maxResultsSpinBox.enabled = checked;
            }
        }

        Controls.Label {
            Layout.topMargin: Kirigami.Units.largeSpacing
            text: qsTr("TTL do cache (minutos):")
            font.bold: true
            Layout.fillWidth: true
        }

        Controls.SpinBox {
            id: cacheTtlSpinBox
            from: 1
            to: 10080
            value: 1440
            stepSize: 60
            onValueChanged: {
                if (root.settingsModel) {
                    root.settingsModel.timesheetCacheTtlMinutes = value;
                }
            }
        }

        Controls.Label {
            text: qsTr("Período padrão:")
            font.bold: true
            Layout.fillWidth: true
        }

        Controls.ComboBox {
            id: defaultPeriodCombo
            model: periodModel
            textRole: "label"
            Layout.fillWidth: true
            onActivated: {
                if (root.settingsModel && currentIndex >= 0) {
                    root.settingsModel.timesheetDefaultPeriod = periodModel.get(currentIndex).value;
                }
            }
        }

        Controls.Label {
            text: qsTr("Máximo de issues por busca:")
            font.bold: true
            Layout.fillWidth: true
        }

        Controls.SpinBox {
            id: maxResultsSpinBox
            from: 50
            to: 1000
            value: 500
            stepSize: 50
            onValueChanged: {
                if (root.settingsModel) {
                    root.settingsModel.timesheetMaxResults = value;
                }
            }
        }
    }

    Component.onCompleted: {
        if (root.settingsModel) {
            timesheetEnabledCheckbox.checked = root.settingsModel.timesheetEnabled;
            cacheTtlSpinBox.value = root.settingsModel.timesheetCacheTtlMinutes;
            defaultPeriodCombo.currentIndex = root.indexForPeriod(root.settingsModel.timesheetDefaultPeriod);
            maxResultsSpinBox.value = root.settingsModel.timesheetMaxResults;
            cacheTtlSpinBox.enabled = root.settingsModel.timesheetEnabled;
            defaultPeriodCombo.enabled = root.settingsModel.timesheetEnabled;
            maxResultsSpinBox.enabled = root.settingsModel.timesheetEnabled;
        }
    }
}
