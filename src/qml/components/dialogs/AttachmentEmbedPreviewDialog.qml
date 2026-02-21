pragma ComponentBehavior: Bound
/**
 * AttachmentEmbedPreviewDialog.qml
 *
 * Diálogo exibido quando o usuário arrasta ou cola uma imagem, antes de inserir
 * na descrição/comentário. Permite escolher layout, posição (create flow) e
 * decidir entre embedar na description ou apenas anexar.
 *
 * Signals:
 *   acceptedEmbed(layout: string, position: string)  // position: "start" | "end"
 *   acceptedAttachOnly()
 *   rejected()
 */
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../../utils/FormatUtils.js" as FormatUtils

Controls.Dialog {
    id: dialog

    title: qsTr("Inserir imagem")
    modal: true
    closePolicy: Controls.Popup.CloseOnEscape
    standardButtons: Controls.Dialog.NoButton
    clip: false

    property string filePath: ""
    /** true = create flow (mostra posição); false = edit/comment (oculta posição) */
    property bool showPositionOptions: true
    /** "description" | "comment" — define o texto do botão e o target do embed */
    property string embedTarget: "description"
    /** Largura máxima de exibição (px); default do config ou 760 */
    property int defaultDisplayWidth: 760
    property var applicationWindow: null
    property var clipboardHelper: null

    signal acceptedEmbed(string layout, string position, int displayWidth)
    signal acceptedAttachOnly()

    width: 460
    implicitHeight: previewColumn.implicitHeight + (implicitHeaderHeight > 0 ? implicitHeaderHeight : Kirigami.Units.gridUnit * 4) + topPadding + bottomPadding
    height: implicitHeight

    onOpened: {
        selectedLayout = "center"
        selectedDisplayWidth = defaultDisplayWidth
        if (filePath) {
            var info = (clipboardHelper && typeof clipboardHelper.getFileInfo === "function")
                ? clipboardHelper.getFileInfo(filePath) : {}
            fileInfoModel.filename = info.filename || ""
            fileInfoModel.fileType = info.fileType || ""
            fileInfoModel.size = info.size !== undefined ? info.size : 0
            fileInfoModel.width = info.width
            fileInfoModel.height = info.height
        }
        Qt.callLater(centerDialog)
    }

    QtObject {
        id: fileInfoModel
        property string filename: ""
        property string fileType: ""
        property int size: 0
        property int width: 0
        property int height: 0
    }

    property string selectedLayout: "center"
    property int selectedDisplayWidth: defaultDisplayWidth

    function centerDialog() {
        var ref = applicationWindow || parent
        if (ref && width > 0 && height > 0 && ref.width > 0 && ref.height > 0) {
            x = Math.max(0, (ref.width - width) / 2)
            y = Math.max(0, (ref.height - height) / 2)
        }
    }

    Component.onCompleted: Qt.callLater(centerDialog)
    onWidthChanged: Qt.callLater(centerDialog)
    onHeightChanged: Qt.callLater(centerDialog)

    ColumnLayout {
        id: previewColumn
        // implicitWidth: 440
        spacing: Kirigami.Units.mediumSpacing

        

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.largeSpacing
        }

        // Image preview
        Item {
            id: previewImageItem
            Layout.fillWidth: true
            Layout.preferredHeight: 200
            Layout.alignment: Qt.AlignHCenter


            Image {
                id: previewImage
                anchors.centerIn: parent
                width: Math.min(400, parent.width - Kirigami.Units.largeSpacing * 2)
                height: width > 0 && sourceSize.width > 0
                    ? Math.min(parent.height - Kirigami.Units.smallSpacing * 2,
                               (sourceSize.height / sourceSize.width) * width)
                    : 0
                fillMode: Image.PreserveAspectFit
                source: dialog.filePath ? "file://" + dialog.filePath : ""
                asynchronous: true
                mipmap: true
            }

            Controls.BusyIndicator {
                anchors.centerIn: parent
                running: previewImage.status === Image.Loading
            }

            
        }

        // File info
        Kirigami.FormLayout {
            id: formLayout
            Layout.fillWidth: true
            Kirigami.FormData.isSection: false

            

            Controls.Label {
                Kirigami.FormData.label: qsTr("Arquivo:")
                text: fileInfoModel.filename || "—"
                elide: Text.ElideMiddle
            }
            Controls.Label {
                Kirigami.FormData.label: qsTr("Tipo:")
                text: fileInfoModel.fileType || "—"
            }
            Controls.Label {
                Kirigami.FormData.label: qsTr("Dimensões:")
                text: (fileInfoModel.width && fileInfoModel.height)
                    ? (fileInfoModel.width + "×" + fileInfoModel.height)
                    : "—"
            }
            Controls.Label {
                Kirigami.FormData.label: qsTr("Tamanho:")
                text: FormatUtils.formatFileSize(fileInfoModel.size) || "—"
            }
        }

        // Display width
        Controls.Label {
            text: qsTr("Largura máxima (px):")
            font.bold: true
            Layout.fillWidth: true
        }
        Controls.SpinBox {
            id: displayWidthSpinBox
            from: 100
            to: 2000
            value: dialog.selectedDisplayWidth
            stepSize: 50
            editable: true
            onValueChanged: dialog.selectedDisplayWidth = value
            Layout.fillWidth: true
        }

        // Layout options
        Controls.Label {
            text: qsTr("Layout:")
            font.bold: true
            Layout.fillWidth: true
        }
        Controls.ButtonGroup {
            id: layoutGroup
        }
        RowLayout {
            id: layoutRow
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            

            Repeater {
                model: [
                    { value: "center", label: qsTr("Center") },
                    { value: "wrap-left", label: qsTr("Wrap Left") },
                    { value: "wrap-right", label: qsTr("Wrap Right") },
                    { value: "wide", label: qsTr("Wide") },
                    { value: "full-width", label: qsTr("Full Width") }
                ]
                Controls.RadioButton {
                    required property var modelData
                    required property int index
                    text: modelData.label
                    checked: index === 0
                    Controls.ButtonGroup.group: layoutGroup
                    onCheckedChanged: if (checked) dialog.selectedLayout = modelData.value
                }
            }
        }

        // Position options (create flow only)
        ColumnLayout {

            id: positionColumn
            visible: dialog.showPositionOptions
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            

            Controls.Label {
                text: qsTr("Posição:")
                font.bold: true
                Layout.fillWidth: true
            }
            Controls.ButtonGroup {
                id: positionGroup
                buttons: [positionStartBtn, positionEndBtn]
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.mediumSpacing
                Controls.RadioButton {
                    id: positionStartBtn
                    text: qsTr("Início da description")
                    checked: true
                    Controls.ButtonGroup.group: positionGroup
                }
                Controls.RadioButton {
                    id: positionEndBtn
                    text: qsTr("Final da description")
                    Controls.ButtonGroup.group: positionGroup
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 3
        }

        // Buttons
        RowLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            spacing: Kirigami.Units.mediumSpacing

            Controls.Button {
                text: qsTr("Cancelar")
                onClicked: {
                    dialog.rejected()
                    dialog.close()
                }
            }
            Controls.Button {
                text: qsTr("Apenas Anexar")
                onClicked: {
                    dialog.acceptedAttachOnly()
                    dialog.close()
                }
            }
            Controls.Button {
                text: dialog.embedTarget === "comment"
                    ? qsTr("Embedar no comentário")
                    : qsTr("Embedar na Description")
                onClicked: {
                    var position = positionStartBtn.checked ? "start" : "end"
                    dialog.acceptedEmbed(dialog.selectedLayout, position, dialog.selectedDisplayWidth)
                    dialog.close()
                }
            }
        }
    }
}
