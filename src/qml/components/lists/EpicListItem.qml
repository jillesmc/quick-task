import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

// Delegate para exibir um Epic na lista

Controls.ItemDelegate {
    id: root

    // Cada item do modelo deve expor pelo menos:
    // - key
    // - summary
    // - status
    // Nota: Quando o modelo é uma lista de dicts Python exposta via QML Property,
    // o QML pode usar tanto 'model' quanto 'modelData'. Tentamos ambos para compatibilidade.

    property var itemData: modelData || model || {}
    property string epicKey: itemData.key || ""
    property string summary: itemData.summary || ""
    property string status: itemData.status || ""

    width: ListView.view ? ListView.view.width : implicitWidth
    
    // Garantir que o background de seleção seja visível
    background: Rectangle {
        color: root.checked ? Kirigami.Theme.highlightColor : "transparent"
        opacity: root.checked ? 0.2 : 1.0
    }

    contentItem: RowLayout {
        spacing: Kirigami.Units.smallSpacing

        Controls.Label {
            text: epicKey
            font.bold: true
            Layout.preferredWidth: 110
        }

        Controls.Label {
            text: summary
            Layout.fillWidth: true
            elide: Text.ElideRight
        }

        Controls.Label {
            text: status
            Layout.preferredWidth: 120
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
