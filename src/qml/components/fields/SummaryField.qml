/**
 * SummaryField.qml
 *
 * Campo de linha única para o summary do work item (spec summary-description-ai-voice).
 * Reutilizável em criação e edição; limite 255 caracteres.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: root

    property string text: ""
    property bool enabled: true
    property string labelText: qsTr("Summary:")
    property string placeholderText: ""
    property int maximumLength: 255
    property bool required: true
    property bool requestFocusOnLoad: false
    property bool showLabel: true

    signal fieldTextChanged(string newText)

    spacing: Kirigami.Units.smallSpacing

    Controls.Label {
        visible: root.showLabel && root.labelText.length > 0
        text: root.labelText
        font.bold: true
        Layout.fillWidth: true
    }

    Controls.TextField {
        id: textField
        Layout.fillWidth: true
        enabled: root.enabled
        text: root.text
        placeholderText: root.placeholderText
        maximumLength: root.maximumLength
        onTextChanged: function () {
            root.fieldTextChanged(text);
        }
        Component.onCompleted: {
            if (root.requestFocusOnLoad) {
                forceActiveFocus();
            }
        }
    }
}
