/**
 * WorkItemStatusField.qml
 *
 * Componente de status para abas 7 e 8: mostra todos os statuses do workflow,
 * habilitando apenas o atual e os alcançáveis por transição (fecho transitivo);
 * os sem caminho possível ficam desabilitados. Layout em duas colunas: coluna
 * principal (initial + directed + done) e coluna de globais. Usa workflow_metadata (StatusReachableLogic).
 */
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami
import "../../utils/StatusReachableLogic.js" as StatusReachableLogic

ColumnLayout {
    id: root

    /** Entrada: { statuses, transitions } do workflow_metadata. Se null, model fica vazio. */
    property var workflowEntry: null
    /** Status atual (nome ou id) para calcular reachable. */
    property string currentStatusName: ""
    /** Quando true (ex.: CreateWorkItemPage), todos os statuses ficam habilitados. */
    property bool allPathsFromInitial: false
    /** Transições disponíveis da API (GET issue/transitions). Quando definido e não vazio, enabled vem da API em vez de reachable. */
    property var availableTransitions: null
    /** Valor selecionado (nome do status). */
    property string selectedValue: ""
    property bool enabled: true

    signal valueChanged(string value)

    /** Opções por coluna: mainColumn e globalColumn. Usado quando workflowEntry existe. */
    readonly property var _statusOptionsWithColumns: {
        if (!workflowEntry)
            return {
                mainColumn: [],
                globalColumn: []
            };
        return StatusReachableLogic.buildStatusOptionsWithColumns(workflowEntry, currentStatusName, allPathsFromInitial);
    }

    /** Lista única (fallback quando não usa duas colunas). */
    readonly property var _statusOptions: {
        if (!workflowEntry)
            return [];
        var useApi = availableTransitions !== undefined && availableTransitions !== null && (typeof availableTransitions.length === "number" && availableTransitions.length > 0);
        if (useApi)
            return StatusReachableLogic.buildStatusOptionsFromApi(workflowEntry, currentStatusName, availableTransitions);
        return StatusReachableLogic.buildStatusOptions(workflowEntry, currentStatusName);
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.largeSpacing

        Column {
            Layout.alignment: Qt.AlignLeft | Qt.AlignTop
            spacing: Kirigami.Units.smallSpacing
            Repeater {
                model: root._statusOptionsWithColumns.mainColumn
                Controls.RadioButton {
                    required property var modelData
                    text: modelData.name || modelData.id
                    enabled: root.enabled && (modelData.enabled === true)
                    checked: (root.selectedValue || "").toUpperCase() === (modelData.name || "").toUpperCase()
                    onCheckedChanged: {
                        if (checked) {
                            root.valueChanged(modelData.name || modelData.id || "");
                        }
                    }
                    Accessible.description: modelData.enabled ? qsTr("Transição permitida para este status.") : qsTr("Sem transição possível a partir do status atual.")
                }
            }
        }
        Column {
            Layout.alignment: Qt.AlignLeft | Qt.AlignTop
            spacing: Kirigami.Units.smallSpacing
            Repeater {
                model: root._statusOptionsWithColumns.globalColumn
                Controls.RadioButton {
                    required property var modelData
                    text: modelData.name || modelData.id
                    enabled: root.enabled && (modelData.enabled === true)
                    checked: (root.selectedValue || "").toUpperCase() === (modelData.name || "").toUpperCase()
                    onCheckedChanged: {
                        if (checked) {
                            root.valueChanged(modelData.name || modelData.id || "");
                        }
                    }
                    Accessible.description: modelData.enabled ? qsTr("Transição permitida para este status.") : qsTr("Sem transição possível a partir do status atual.")
                }
            }
        }
        Item {
            Layout.fillWidth: true
        }
    }
}
