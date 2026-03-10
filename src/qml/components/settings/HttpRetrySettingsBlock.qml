/**
 * HttpRetrySettingsBlock.qml
 *
 * Bloco de configuração para retry com backoff em chamadas HTTP externas
 * (Jira, GitHub, etc.): max_retries, base_delay_seconds, max_delay_seconds.
 * Reduz falhas por rate limit (HTTP 429) e erros transitórios (503, 502).
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
            text: qsTr("Chamadas externas (HTTP)")
            level: 3
            Layout.fillWidth: true
        }

        Controls.Label {
            text: qsTr("Retentativas com backoff exponencial para evitar falhas por rate limit (429) e erros transitórios. O delay entre tentativas segue: base × 2^tentativa, até o máximo.")
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
        }

        Controls.Label {
            Layout.topMargin: Kirigami.Units.smallSpacing
            text: qsTr("Máximo de tentativas:")
            font.bold: true
            Layout.fillWidth: true
            Accessible.name: text
            Accessible.description: qsTr("Número máximo de tentativas por chamada HTTP, incluindo a primeira.")
        }

        Controls.SpinBox {
            id: maxRetriesSpinBox
            from: 1
            to: 20
            value: 3
            stepSize: 1
            Layout.fillWidth: true
            onValueChanged: {
                if (root.settingsModel) {
                    root.settingsModel.httpRetryMaxRetries = value;
                }
            }
            Accessible.name: qsTr("Máximo de tentativas")
            Accessible.description: qsTr("Inclui a primeira chamada; retentativas usam backoff exponencial.")
        }

        Controls.Label {
            Layout.topMargin: Kirigami.Units.largeSpacing
            text: qsTr("Delay base (segundos):")
            font.bold: true
            Layout.fillWidth: true
            Accessible.name: text
            Accessible.description: qsTr("Delay na primeira retentativa; nas seguintes o delay dobra até o máximo.")
        }

        Controls.SpinBox {
            id: baseDelaySpinBox
            from: 1
            to: 300
            value: 1
            stepSize: 1
            Layout.fillWidth: true
            onValueChanged: {
                if (root.settingsModel) {
                    root.settingsModel.httpRetryBaseDelaySeconds = value;
                }
            }
            Accessible.name: qsTr("Delay base em segundos")
            Accessible.description: qsTr("Usado na primeira retentativa; backoff exponencial nas seguintes.")
        }

        Controls.Label {
            Layout.topMargin: Kirigami.Units.largeSpacing
            text: qsTr("Delay máximo (segundos):")
            font.bold: true
            Layout.fillWidth: true
            Accessible.name: text
            Accessible.description: qsTr("Teto do delay entre tentativas; em 429 o servidor pode indicar Retry-After.")
        }

        Controls.SpinBox {
            id: maxDelaySpinBox
            from: 1
            to: 600
            value: 60
            stepSize: 5
            Layout.fillWidth: true
            onValueChanged: {
                if (root.settingsModel) {
                    root.settingsModel.httpRetryMaxDelaySeconds = value;
                }
            }
            Accessible.name: qsTr("Delay máximo em segundos")
            Accessible.description: qsTr("Nenhuma espera entre tentativas será maior que este valor.")
        }
    }

    Component.onCompleted: {
        if (root.settingsModel) {
            maxRetriesSpinBox.value = root.settingsModel.httpRetryMaxRetries;
            baseDelaySpinBox.value = Math.round(root.settingsModel.httpRetryBaseDelaySeconds);
            maxDelaySpinBox.value = Math.round(root.settingsModel.httpRetryMaxDelaySeconds);
        }
    }
}
