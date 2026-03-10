/**
 * WorklogForm.qml
 *
 * Componente reutilizável para formulário de worklog
 * Segue Single Responsibility Principle - apenas gerencia campos de worklog
 * Segue Open/Closed Principle - pode ser estendido sem modificar
 *
 * Propriedades:
 * - enabled: controla se o formulário está habilitado
 * - showCheckbox: se true, mostra checkbox para registrar worklog
 * - shouldRegister: alias para checkbox checked
 * - date: alias para campo de data
 * - time: alias para campo de hora
 * - duration: alias para slider de duração
 * - comment: alias para campo de comentário
 *
 * Signals:
 * - worklogChanged(): emitido quando qualquer campo muda
 *
 * Métodos:
 * - reset(): reseta todos os campos para valores padrão
 * - getWorklogData(): retorna objeto com dados do worklog
 * - setWorklogData(data): define dados do worklog
 */

// Componente WorklogForm - tipo raiz com nome correto
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami
import "../../utils/FormatUtils.js" as FormatUtils

ColumnLayout {
    id: root

    property bool enabled: true
    property var jiraService: null
    property bool showCheckbox: true
    property alias shouldRegister: registrarCheckbox.checked
    property alias date: dateField.text
    property alias time: timeField.text
    property alias duration: durationSlider.value
    property alias comment: commentField.text

    // Propriedades para cálculo retroativo
    property int retroactiveMaxHours: 24
    property var defaultDurations: [30, 60, 120, 240, 480]

    signal worklogChanged

    spacing: Kirigami.Units.smallSpacing

    // Checkbox para registrar worklog
    Controls.CheckBox {
        id: registrarCheckbox
        visible: root.showCheckbox
        text: qsTr("Registrar worklog")
        Layout.fillWidth: true
        enabled: root.enabled
        onCheckedChanged: root.worklogChanged()
    }

    // Campos de worklog (sempre visíveis, mas podem estar desabilitados)
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.mediumSpacing
        enabled: root.enabled && (!root.showCheckbox || registrarCheckbox.checked)

        // Campo Data/hora
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Controls.Label {
                text: qsTr("Data/hora:")
                Layout.fillWidth: true
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Controls.TextField {
                    id: dateField
                    Layout.fillWidth: true
                    placeholderText: qsTr("YYYY-MM-DD")
                    inputMethodHints: Qt.ImhDigitsOnly

                    property bool updatingFromModel: false

                    Keys.onPressed: function (event) {
                        if (event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete || event.key === Qt.Key_Left || event.key === Qt.Key_Right || event.key === Qt.Key_Home || event.key === Qt.Key_End || (event.modifiers & Qt.ControlModifier)) {
                            return;
                        }
                        var keyChar = String.fromCharCode(event.key);
                        if (keyChar < '0' || keyChar > '9') {
                            event.accepted = true;
                        }
                    }

                    Keys.onTabPressed: function (event) {
                        event.accepted = true;
                        var nextItem = nextItemInFocusChain(true);
                        if (nextItem) {
                            nextItem.forceActiveFocus();
                        }
                    }

                    Keys.onBacktabPressed: function (event) {
                        event.accepted = true;
                        var prevItem = nextItemInFocusChain(false);
                        if (prevItem) {
                            prevItem.forceActiveFocus();
                        }
                    }

                    onTextChanged: {
                        if (updatingFromModel)
                            return;
                        var formatted = FormatUtils.formatDateInput(text);
                        if (formatted !== text) {
                            var oldCursor = cursorPosition;
                            var oldLength = text.length;
                            var newText = formatted;
                            Qt.callLater(function () {
                                if (dateField.updatingFromModel)
                                    return;
                                dateField.updatingFromModel = true;
                                dateField.text = newText;
                                var cursorOffset = newText.length - oldLength;
                                dateField.cursorPosition = Math.max(0, Math.min(oldCursor + cursorOffset, newText.length));
                                dateField.updatingFromModel = false;
                            });
                            return;
                        }
                        root.worklogChanged();
                    }
                }

                Controls.TextField {
                    id: timeField
                    Layout.preferredWidth: 100
                    placeholderText: qsTr("HH:MM:SS")
                    inputMethodHints: Qt.ImhDigitsOnly

                    property bool updatingFromModel: false

                    Keys.onPressed: function (event) {
                        if (event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete || event.key === Qt.Key_Left || event.key === Qt.Key_Right || event.key === Qt.Key_Home || event.key === Qt.Key_End || (event.modifiers & Qt.ControlModifier)) {
                            return;
                        }
                        var keyChar = String.fromCharCode(event.key);
                        if (keyChar < '0' || keyChar > '9') {
                            event.accepted = true;
                        }
                    }

                    Keys.onTabPressed: function (event) {
                        event.accepted = true;
                        var nextItem = nextItemInFocusChain(true);
                        if (nextItem) {
                            nextItem.forceActiveFocus();
                        }
                    }

                    Keys.onBacktabPressed: function (event) {
                        event.accepted = true;
                        var prevItem = nextItemInFocusChain(false);
                        if (prevItem) {
                            prevItem.forceActiveFocus();
                        }
                    }

                    onTextChanged: {
                        if (updatingFromModel)
                            return;
                        var formatted = FormatUtils.formatTimeInput(text);
                        if (formatted !== text) {
                            var oldCursor = cursorPosition;
                            var oldLength = text.length;
                            var newText = formatted;
                            Qt.callLater(function () {
                                if (timeField.updatingFromModel)
                                    return;
                                timeField.updatingFromModel = true;
                                timeField.text = newText;
                                var cursorOffset = newText.length - oldLength;
                                timeField.cursorPosition = Math.max(0, Math.min(oldCursor + cursorOffset, newText.length));
                                timeField.updatingFromModel = false;
                            });
                            return;
                        }
                        root.worklogChanged();
                    }
                }

                // Botão de cálculo automático ao lado do campo de hora
                Controls.Button {
                    icon.name: "media-seek-backward"
                    enabled: root.enabled
                    onClicked: {
                        root.calculateAndSetRetroactiveTime();
                    }
                }
            }
        }

        // Campo Duração
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Controls.Label {
                text: qsTr("Duração:")
                Layout.fillWidth: true
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Controls.Slider {
                    id: durationSlider
                    Layout.fillWidth: true
                    from: 15
                    to: 480
                    stepSize: 15
                    value: 30
                    onValueChanged: root.worklogChanged()
                }

                Controls.Label {
                    text: FormatUtils.formatDuration(Math.round(durationSlider.value))
                    font.bold: true
                }

                // Presets rápidos
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    visible: root.defaultDurations && typeof root.defaultDurations.length !== "undefined" && root.defaultDurations.length > 0

                    Controls.Label {
                        text: qsTr("Presets:")
                        Layout.preferredWidth: implicitWidth
                    }

                    ListModel {
                        id: presetDurationsModel
                    }
                    Repeater {
                        model: presetDurationsModel
                        delegate: WorklogPresetButton {
                            formRoot: root
                        }
                    }
                }
            }
        }

        // Campo Comentário
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Controls.Label {
                text: qsTr("Comentário:")
                Layout.fillWidth: true
            }

            // Scroll vertical para comentários longos
            Controls.ScrollView {
                id: commentScrollView
                Layout.fillWidth: true
                Layout.preferredHeight: 80
                clip: true

                Controls.TextArea {
                    id: commentField
                    width: commentScrollView.availableWidth
                    placeholderText: qsTr("Comentário opcional para o worklog")
                    wrapMode: Controls.TextArea.Wrap
                    onTextChanged: root.worklogChanged()
                }
            }
        }
    }

    /**
     * Sincroniza presetDurationsModel com root.defaultDurations (para delegate com model.duration qualificado).
     */
    function syncPresetDurations() {
        presetDurationsModel.clear();
        if (root.defaultDurations && root.defaultDurations.length) {
            for (var i = 0; i < root.defaultDurations.length; i++) {
                presetDurationsModel.append({
                    duration: root.defaultDurations[i]
                });
            }
        }
    }

    Connections {
        target: root
        function onDefaultDurationsChanged() {
            root.syncPresetDurations();
        }
    }

    /**
     * Inicializa campos com valores padrão
     */
    function initializeDefaults() {
        var now = FormatUtils.getCurrentDateTime(false, false);
        date = now.date;
        time = now.time;
        duration = 30;
        comment = "";
        if (registrarCheckbox.visible) {
            registrarCheckbox.checked = false;
        }
    }

    /**
     * Reseta todos os campos para valores padrão
     */
    function reset() {
        initializeDefaults();
    }

    /**
     * Retorna objeto com dados do worklog
     * @returns {object} Objeto com shouldRegister, date, time, duration, comment
     */
    function getWorklogData() {
        return {
            shouldRegister: shouldRegister,
            date: date,
            time: time,
            duration: Math.round(duration),
            comment: comment,
            inicioStr: date && time ? date + " " + time : ""
        };
    }

    /**
     * Define dados do worklog
     * @param {object} data - Objeto com shouldRegister, date, time, duration, comment
     */
    function setWorklogData(data) {
        if (!data)
            return;
        dateField.updatingFromModel = true;
        timeField.updatingFromModel = true;

        if (data.shouldRegister !== undefined) {
            registrarCheckbox.checked = data.shouldRegister;
        }
        if (data.date !== undefined) {
            dateField.text = data.date;
        }
        if (data.time !== undefined) {
            timeField.text = data.time;
        }
        if (data.duration !== undefined) {
            durationSlider.value = data.duration;
        }
        if (data.comment !== undefined) {
            commentField.text = data.comment;
        }

        dateField.updatingFromModel = false;
        timeField.updatingFromModel = false;
    }

    /**
     * Calcula e preenche campos automaticamente baseado na duração
     */
    function calculateAndSetRetroactiveTime() {
        var durationMinutes = Math.round(durationSlider.value);
        var calculated = FormatUtils.calculateRetroactiveStartTime(durationMinutes);

        // Preencher campos de data/hora
        dateField.updatingFromModel = true;
        timeField.updatingFromModel = true;
        dateField.text = calculated.date;
        timeField.text = calculated.time;
        dateField.updatingFromModel = false;
        timeField.updatingFromModel = false;

        // Validação básica (sem usar Validators.js para evitar problemas de import)
        if (durationMinutes > retroactiveMaxHours * 60) {
            console.warn("Duração excede o máximo permitido de", retroactiveMaxHours, "horas");
        }

        root.worklogChanged();
    }

    Component.onCompleted: {
        initializeDefaults();
        root.syncPresetDurations();
        // Carregar configurações de worklog retroativo se jiraService estiver disponível
        Qt.callLater(function () {
            if (root.jiraService) {
                try {
                    if (typeof root.jiraService.getRetroactiveMaxHours === "function") {
                        var maxHours = root.jiraService.getRetroactiveMaxHours();
                        if (maxHours > 0) {
                            root.retroactiveMaxHours = maxHours;
                        }
                    }
                    if (typeof root.jiraService.getDefaultDurations === "function") {
                        var durations = root.jiraService.getDefaultDurations();
                        if (durations && Array.isArray(durations) && durations.length > 0) {
                            root.defaultDurations = durations;
                        }
                    }
                } catch (e) {
                    console.warn("Erro ao carregar configurações de worklog retroativo:", e);
                }
            }
            root.syncPresetDurations();
        });
    }
}
