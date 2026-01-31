/**
 * Botão de preset de duração para WorklogForm.
 * Recebe duration (bind automático da role do ListModel) e formRoot; ao clicar define formRoot.duration e emite worklogChanged.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import "../../utils/FormatUtils.js" as FormatUtils

Controls.Button {
    id: presetButton

    required property int duration
    required property var formRoot

    text: FormatUtils.formatDuration(duration)
    Layout.preferredWidth: implicitWidth
    onClicked: {
        if (formRoot) {
            formRoot.duration = duration
            formRoot.worklogChanged()
        }
    }
}
