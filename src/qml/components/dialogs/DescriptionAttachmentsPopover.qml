pragma ComponentBehavior: Bound
/**
 * DescriptionAttachmentsPopover.qml
 *
 * Popover que lista anexos referenciados na descrição (pending ou anexos da issue)
 * e permite excluí-las. Create: remove do pendingAttachments e do texto; Edit: chama API DELETE e atualiza descrição.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami
import "../../utils/FormatUtils.js" as FormatUtils

Controls.Popup {
    id: root

    property string mode: "create"   // "create" | "edit"
    property var pendingAttachments: []   // create: list from issueModel.pendingAttachments
    property var issueModel: null          // create: model with description + pendingAttachments
    property var attachmentsList: []       // edit: details.attachments + newUploadsThisSession
    property string issueKey: ""           // edit: for context
    property var jiraService: null         // edit: to call deleteAttachment
    /** Create: called after removing pending (placeholderId). Edit: called after API delete (attachmentId); parent should update description and call updateIssue. */
    property var onAttachmentDeleted: null
    /** Edit only: called when delete failed (attachmentId, errorMessage). */
    property var onAttachmentDeleteFailed: null
    /** When true, onOpened positions x so the popover opens to the left of the button (right edge of popover = right edge of parent). */
    property bool positionLeftOfButton: false
    /** Em modo edit: referência ao painel para listSource reativo (_currentAttachmentsList). */
    property var editModePane: null

    modal: false
    closePolicy: Controls.Popup.CloseOnEscape | Controls.Popup.CloseOnPressOutside
    padding: Kirigami.Units.smallSpacing * 2

    readonly property bool isCreate: root.mode === "create"
    readonly property var listSource: root._getListSource()
    readonly property int listCount: Array.isArray(root.listSource) ? root.listSource.length : 0

    function _getListSource() {
        if (!root.isCreate) return (root.editModePane ? root.editModePane._currentAttachmentsList : (root.attachmentsList || []))
        var fromModel = root.issueModel ? (root.issueModel.pendingAttachments || []) : []
        var fromDesc = root.issueModel ? FormatUtils.getPendingPlaceholdersFromDescription(root.issueModel.description || "") : []
        var seen = {}
        for (var i = 0; i < fromModel.length; i++) {
            var pid = fromModel[i] && (fromModel[i].placeholderId !== undefined) ? String(fromModel[i].placeholderId) : ""
            if (pid) seen[pid] = true
        }
        var merged = fromModel.slice()
        for (var j = 0; j < fromDesc.length; j++) {
            if (!seen[fromDesc[j].placeholderId]) {
                seen[fromDesc[j].placeholderId] = true
                merged.push(fromDesc[j])
            }
        }
        return merged
    }

    ListModel {
        id: listModel
    }

    function _syncListModel() {
        listModel.clear()
        var src = root.listSource || []
        for (var i = 0; i < src.length; i++) {
            var it = src[i]
            var displayName = ""
            var itemId = ""
            if (it && typeof it === "object") {
                if (it.filename) displayName = it.filename
                else if (it.placeholderId !== undefined) displayName = it.filename || ("pending:" + it.placeholderId)
                else if (it.contentUrl) displayName = it.filename || (String(it.contentUrl).split("/").pop() || "") || qsTr("Anexo")
                else displayName = qsTr("Anexo")
                itemId = root.isCreate ? (it.placeholderId !== undefined ? String(it.placeholderId) : "") : (it.id !== undefined ? String(it.id) : "")
            }
            listModel.append({ "displayName": displayName, "itemId": itemId })
        }
    }

    onListSourceChanged: _syncListModel()

    contentWidth: Math.min(contentColumn.implicitWidth + root.padding * 2, Kirigami.Units.gridUnit * 22)
    contentHeight: Math.min(contentColumn.implicitHeight + root.padding * 2, Kirigami.Units.gridUnit * 18)

    onOpened: {
        _syncListModel()
        if (root.positionLeftOfButton && parent && root.contentWidth > 0) {
            x = parent.width - root.contentWidth
        }
    }

    background: Rectangle {
        color: Kirigami.Theme.backgroundColor
        border.color: Kirigami.Theme.disabledTextColor
        border.width: 1
        radius: Kirigami.Units.smallSpacing
    }

    Connections {
        target: root.isCreate ? null : root.jiraService
        function onAttachmentDeleted(attachmentId) {
            if (typeof root.onAttachmentDeleted === "function") {
                // qmllint disable use-proper-function
                root.onAttachmentDeleted(attachmentId)
                // qmllint enable use-proper-function
            }
        }
        function onAttachmentDeleteFailed(attachmentId, errorMessage) {
            if (typeof root.onAttachmentDeleteFailed === "function") {
                // qmllint disable use-proper-function
                root.onAttachmentDeleteFailed(attachmentId, errorMessage)
                // qmllint enable use-proper-function
            }
        }
    }

    ColumnLayout {
        id: contentColumn
        spacing: Kirigami.Units.smallSpacing

        Controls.Label {
            Layout.fillWidth: true
            text: qsTr("Anexos na descrição")
            font.bold: true
        }

        Controls.Label {
            visible: root.listCount === 0
            Layout.fillWidth: true
            text: qsTr("Nenhum anexo na descrição.")
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            color: Kirigami.Theme.disabledTextColor
            wrapMode: Text.WordWrap
        }

        Controls.ScrollView {
            visible: root.listCount > 0
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(listContent.implicitHeight, Kirigami.Units.gridUnit * 12)
            clip: true
            contentWidth: listContent.implicitWidth
            contentHeight: listContent.implicitHeight

            ColumnLayout {
                id: listContent
                width: root.contentWidth - root.padding * 2
                spacing: Kirigami.Units.smallSpacing

                Repeater {
                    model: listModel
                    delegate: RowLayout {
                        id: attachmentRow
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        required property string displayName
                        required property string itemId

                        Controls.Label {
                            Layout.fillWidth: true
                            text: attachmentRow.displayName
                            elide: Text.ElideMiddle
                            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        }
                        Controls.Button {
                            text: qsTr("Excluir")
                            icon.name: "edit-delete"
                            flat: true
                            Layout.alignment: Qt.AlignRight
                            onClicked: {
                                var pid = attachmentRow.itemId
                                if (!pid) return
                                if (root.isCreate) {
                                    if (!root.issueModel) return
                                    var currentDesc = root.issueModel.description || ""
                                    var newDesc = FormatUtils.removePendingAttachmentFromDescription(currentDesc, pid)
                                    root.issueModel.description = newDesc
                                    var list = root.issueModel.pendingAttachments || []
                                    var filtered = []
                                    for (var i = 0; i < list.length; i++) {
                                        if (String(list[i].placeholderId) !== pid) filtered.push(list[i])
                                    }
                                    root.issueModel.pendingAttachments = filtered
                                    if (typeof root.onAttachmentDeleted === "function") {
                                        // qmllint disable use-proper-function
                                        root.onAttachmentDeleted(pid)
                                        // qmllint enable use-proper-function
                                    }
                                } else {
                                    if (typeof root.onAttachmentDeleted === "function") {
                                        // qmllint disable use-proper-function
                                        root.onAttachmentDeleted(pid)
                                        // qmllint enable use-proper-function
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
