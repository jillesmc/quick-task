import QtQuick 2.12
import QtQuick.Layouts 1.12
import QtQuick.Controls 2.12 as Controls
import org.kde.kirigami 2.12 as Kirigami

// Delegate para exibir uma issue na lista de "Minhas Issues"

Controls.ItemDelegate {
    id: root

    // Cada item do modelo deve expor pelo menos:
    // - key
    // - summary
    // - status
    // - issueType
    // - assignee (opcional)
    // Nota: Quando o modelo é uma lista de dicts Python exposta via QML Property,
    // o QML pode usar tanto 'model' quanto 'modelData'. Tentamos ambos para compatibilidade.

    property var itemData: modelData || model || {}
    property string issueKey: itemData.key || ""
    property string summary: itemData.summary || ""
    property string status: itemData.status || ""
    property string issueType: itemData.issueType || ""
    property string assignee: itemData.assignee || ""
    property string parentKey: itemData.parentKey || ""
    property string parentDisplay: parentKey || ""

    width: ListView.view ? ListView.view.width : implicitWidth
    
    // Garantir que o background de seleção seja visível
    background: Rectangle {
        color: root.checked ? Kirigami.Theme.highlightColor : "transparent"
        opacity: root.checked ? 0.2 : 1.0
    }

    contentItem: RowLayout {
        spacing: Kirigami.Units.smallSpacing

        Controls.Label {
            text: issueKey
            font.bold: true
            Layout.preferredWidth: 110
        }

        Controls.Label {
            text: summary
            Layout.fillWidth: true
            elide: Text.ElideRight
        }

        Controls.Label {
            text: issueType
            Layout.preferredWidth: 80
            horizontalAlignment: Text.AlignHCenter
        }

        Controls.Label {
            text: status
            Layout.preferredWidth: 120
            horizontalAlignment: Text.AlignHCenter
        }

        Controls.Label {
            text: parentDisplay
            Layout.preferredWidth: 150
            horizontalAlignment: Text.AlignLeft
            elide: Text.ElideRight
        }
    }
}

