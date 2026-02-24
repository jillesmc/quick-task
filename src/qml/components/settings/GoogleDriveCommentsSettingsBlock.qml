/**
 * GoogleDriveCommentsSettingsBlock.qml
 *
 * Bloco de configuração para comentários do Google Drive (Issue #18):
 * habilitar coluna, máximo de comentários, apenas não resolvidos.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

Rectangle {
    id: root

    property var settingsModel: null
    implicitHeight: contentColumn.implicitHeight + (Kirigami.Units.largeSpacing * 2)

    color: Kirigami.Theme.backgroundColor || "#f0f0f0"
    border.color: Kirigami.Theme.textColor || "#d0d0d0"
    border.width: 1
    radius: Kirigami.Units.smallSpacing

    ColumnLayout {
        id: contentColumn
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Heading {
            text: qsTr("Comentários do Google Drive")
            level: 3
            Layout.fillWidth: true
        }

        Controls.Label {
            text: qsTr("Exibe na aba Google os comentários do Drive onde você foi mencionado. Permite importar para o formulário de task ou marcar como resolvido.")
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            color: Kirigami.Theme.disabledTextColor
        }

        Controls.CheckBox {
            id: driveCommentsEnabledCheckbox
            text: qsTr("Habilitar coluna de comentários do Drive")
            Layout.fillWidth: true
            checked: true
            onCheckedChanged: {
                if (root.settingsModel) {
                    root.settingsModel.driveCommentsEnabled = checked;
                }
                maxCommentsSpinBox.enabled = checked;
                unresolvedOnlyCheckbox.enabled = checked;
            }
        }

        Controls.Label {
            text: qsTr("Máximo de comentários a carregar:")
            font.bold: true
            Layout.fillWidth: true
        }

        Controls.SpinBox {
            id: maxCommentsSpinBox
            from: 10
            to: 100
            value: 50
            onValueChanged: {
                if (root.settingsModel) {
                    root.settingsModel.driveCommentsMaxComments = value;
                }
            }
        }

        Controls.CheckBox {
            id: unresolvedOnlyCheckbox
            text: qsTr("Apenas comentários não resolvidos")
            Layout.fillWidth: true
            checked: true
            onCheckedChanged: {
                if (root.settingsModel) {
                    root.settingsModel.driveCommentsUnresolvedOnly = checked;
                }
            }
        }
    }

    Component.onCompleted: {
        if (root.settingsModel) {
            driveCommentsEnabledCheckbox.checked = root.settingsModel.driveCommentsEnabled;
            maxCommentsSpinBox.value = root.settingsModel.driveCommentsMaxComments;
            unresolvedOnlyCheckbox.checked = root.settingsModel.driveCommentsUnresolvedOnly;
            maxCommentsSpinBox.enabled = root.settingsModel.driveCommentsEnabled;
            unresolvedOnlyCheckbox.enabled = root.settingsModel.driveCommentsEnabled;
        }
    }
}
