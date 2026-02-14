/**
 * DevelopmentPanelSettingsBlock.qml
 *
 * Bloco de configuração do painel de Development em Minhas Issues:
 * enabled (mostrar branches/PRs nos detalhes), github_enrichment (enriquecer PRs com checks/aprovações).
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

    ColumnLayout {
        id: blockColumn
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Heading {
            text: qsTr("Painel de Development (Minhas Issues)")
            level: 3
            Layout.fillWidth: true
        }

        Controls.CheckBox {
            id: developmentPanelEnabledCheckbox
            text: qsTr("Mostrar painel de Development (branches e PRs) nos detalhes da issue")
            Layout.fillWidth: true
            checked: true
            onCheckedChanged: {
                if (root.settingsModel) {
                    root.settingsModel.developmentPanelEnabled = checked;
                }
                developmentPanelGitHubEnrichmentCheckbox.enabled = checked;
            }
        }

        Controls.CheckBox {
            id: developmentPanelGitHubEnrichmentCheckbox
            text: qsTr("Enriquecer PRs e branches com dados do GitHub (checks, aprovações, ahead/behind)")
            Layout.fillWidth: true
            checked: false
            onCheckedChanged: {
                if (root.settingsModel) {
                    root.settingsModel.developmentPanelGitHubEnrichment = checked;
                }
            }
        }

        Controls.Label {
            Layout.topMargin: Kirigami.Units.largeSpacing
            text: qsTr("Org ou usuário padrão (para busca de repositórios)")
            Layout.fillWidth: true
        }
        Controls.TextField {
            id: developmentPanelDefaultOrgField
            placeholderText: qsTr("ex.: minha-org ou meu-usuario")
            Layout.fillWidth: true
            onTextChanged: {
                if (root.settingsModel) {
                    root.settingsModel.developmentPanelDefaultOrg = text;
                }
            }
        }
    }

    Component.onCompleted: {
        if (root.settingsModel) {
            developmentPanelEnabledCheckbox.checked = root.settingsModel.developmentPanelEnabled;
            developmentPanelGitHubEnrichmentCheckbox.checked = root.settingsModel.developmentPanelGitHubEnrichment;
            developmentPanelGitHubEnrichmentCheckbox.enabled = root.settingsModel.developmentPanelEnabled;
            developmentPanelDefaultOrgField.text = root.settingsModel.developmentPanelDefaultOrg;
        }
    }
}
