/**
 * WorklogFiltersBar.qml
 *
 * Barra de filtros para worklogs pendentes: issue key, data de, data até,
 * botões rápidos (Hoje, Últimos 7 dias, Últimos 30 dias) e Limpar Filtros.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

RowLayout {
    id: root

    property string filterIssueKey: ""
    property string filterDateFrom: ""
    property string filterDateTo: ""

    spacing: Kirigami.Units.mediumSpacing

    Controls.Label {
        text: qsTr("Filtrar por Issue Key:")
    }

    Controls.TextField {
        id: filterIssueKeyField
        Layout.preferredWidth: 150
        placeholderText: qsTr("Ex: PLATFORM-123")
        text: root.filterIssueKey
        onTextChanged: root.filterIssueKey = text
    }

    Controls.Label {
        text: qsTr("Data Inicial:")
    }

    Controls.TextField {
        id: filterDateFromField
        Layout.preferredWidth: 120
        placeholderText: qsTr("YYYY-MM-DD")
        text: root.filterDateFrom
        onTextChanged: root.filterDateFrom = text
    }

    Controls.Label {
        text: qsTr("Data Final:")
    }

    Controls.TextField {
        id: filterDateToField
        Layout.preferredWidth: 120
        placeholderText: qsTr("YYYY-MM-DD")
        text: root.filterDateTo
        onTextChanged: root.filterDateTo = text
    }

    Controls.Button {
        text: qsTr("Hoje")
        onClicked: {
            var today = new Date();
            var todayStr = Qt.formatDate(today, "yyyy-MM-dd");
            root.filterDateFrom = todayStr;
            root.filterDateTo = todayStr;
        }
    }

    Controls.Button {
        text: qsTr("Últimos 7 dias")
        onClicked: {
            var today = new Date();
            var weekAgo = new Date(today);
            weekAgo.setDate(today.getDate() - 7);
            root.filterDateFrom = Qt.formatDate(weekAgo, "yyyy-MM-dd");
            root.filterDateTo = Qt.formatDate(today, "yyyy-MM-dd");
        }
    }

    Controls.Button {
        text: qsTr("Últimos 30 dias")
        onClicked: {
            var today = new Date();
            var monthAgo = new Date(today);
            monthAgo.setDate(today.getDate() - 30);
            root.filterDateFrom = Qt.formatDate(monthAgo, "yyyy-MM-dd");
            root.filterDateTo = Qt.formatDate(today, "yyyy-MM-dd");
        }
    }

    Item {
        Layout.fillWidth: true
    }

    Controls.Button {
        text: qsTr("Limpar Filtros")
        onClicked: {
            root.filterIssueKey = "";
            root.filterDateFrom = "";
            root.filterDateTo = "";
        }
    }
}
