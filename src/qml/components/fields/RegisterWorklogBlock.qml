/**
 * RegisterWorklogBlock.qml
 *
 * Bloco reutilizável: checkbox "Registrar worklog" + WorklogForm com bindings ao model (workItemModel).
 * Usado em CreateWorkItemPage e WorkItemDetailPane (abas 7 e 8).
 * Expõe getWorklogData() e reset().
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami
import "../forms"

ColumnLayout {
    id: root

    property var model: null
    property bool enabled: true
    property bool registrarWorklogEnabled: true
    property var service: null

    spacing: Kirigami.Units.smallSpacing
    Layout.fillWidth: true

    Controls.CheckBox {
        id: registrarCheckbox
        text: qsTr("Registrar worklog")
        Layout.fillWidth: true
        enabled: root.enabled && root.registrarWorklogEnabled
        checked: root.model ? root.model.registrarWorklog : false
        onCheckedChanged: {
            if (root.model) {
                root.model.registrarWorklog = checked;
            }
        }
    }

    Binding {
        target: root.model
        property: "registrarWorklog"
        value: false
        when: root.model && !root.registrarWorklogEnabled
    }

    WorklogForm {
        id: worklogForm
        jiraService: root.service
        Layout.fillWidth: true
        enabled: root.enabled && registrarCheckbox.checked
        visible: registrarCheckbox.checked
        showCheckbox: false

        Binding {
            target: root.model
            property: "worklogInicio"
            value: worklogForm.date && worklogForm.time ? worklogForm.date + " " + worklogForm.time : ""
            when: root.model && worklogForm.date && worklogForm.time
        }

        Binding {
            target: root.model
            property: "worklogDuracao"
            value: Math.round(worklogForm.duration)
            when: root.model
        }

        Binding {
            target: root.model
            property: "worklogComment"
            value: worklogForm.comment
            when: root.model
        }

        Component.onCompleted: {
            if (root.model && root.model.worklogInicio) {
                var parts = root.model.worklogInicio.split(" ");
                if (parts.length >= 2) {
                    worklogForm.setWorklogData({
                        date: parts[0],
                        time: parts[1],
                        duration: root.model.worklogDuracao || 30,
                        comment: root.model.worklogComment || ""
                    });
                } else {
                    worklogForm.setWorklogData({
                        duration: root.model.worklogDuracao || 30,
                        comment: root.model.worklogComment || ""
                    });
                }
            } else if (root.model) {
                worklogForm.setWorklogData({
                    duration: root.model.worklogDuracao || 30,
                    comment: root.model.worklogComment || ""
                });
            }
        }

        Connections {
            target: root.model || null
            function onWorklogInicioChanged() {
                if (!root.model || !worklogForm)
                    return;
                var inicio = root.model.worklogInicio || "";
                if (!inicio)
                    return;
                var parts = inicio.split(" ");
                if (parts.length >= 2) {
                    worklogForm.setWorklogData({
                        date: parts[0],
                        time: parts[1],
                        duration: root.model.worklogDuracao || 30,
                        comment: root.model.worklogComment || ""
                    });
                }
            }
            function onWorklogDuracaoChanged() {
                if (!root.model || !worklogForm)
                    return;
                worklogForm.setWorklogData({
                    duration: root.model.worklogDuracao || 30
                });
            }
        }
    }

    function getWorklogData() {
        if (registrarCheckbox.checked && worklogForm) {
            var data = worklogForm.getWorklogData();
            data.shouldRegister = true;
            return data;
        }
        return {};
    }

    function reset() {
        if (root.model) {
            root.model.registrarWorklog = false;
            var now = new Date();
            var dateStr = Qt.formatDateTime(now, "yyyy-MM-dd");
            var timeStr = Qt.formatDateTime(now, "HH:mm:ss");
            root.model.worklogInicio = dateStr + " " + timeStr;
            root.model.worklogDuracao = 30;
            root.model.worklogComment = "";
        }
        if (worklogForm) {
            worklogForm.reset();
        }
    }
}
