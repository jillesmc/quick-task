import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

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

        // Tipo de issue como ícone (primeira coluna)
        Controls.Label {
            text: {
                // Converter tipo de issue em ícone
                if (issueType && issueType.toLowerCase().includes("task")) {
                    return "✓"  // Ícone de tarefa/check
                } else if (issueType && issueType.toLowerCase().includes("bug")) {
                    return "🐛"
                } else if (issueType && issueType.toLowerCase().includes("story")) {
                    return "📖"
                } else if (issueType && issueType.toLowerCase().includes("epic")) {
                    return "📋"
                }
                return "○"  // Ícone genérico
            }
            font.pointSize: Kirigami.Theme.defaultFont.pointSize + 2
            Layout.preferredWidth: 30
            horizontalAlignment: Text.AlignHCenter
        }

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
        
        // Indicador de timer ativo e botão rápido de iniciar timer (juntos)
        RowLayout {
            spacing: Kirigami.Units.smallSpacing
            Layout.preferredWidth: 70
            
            // Indicador de timer ativo para esta issue
            Controls.Label {
                text: "⏱"
                visible: timerModel && timerModel.issueKey === issueKey && 
                         (timerModel.state === "running" || timerModel.state === "paused")
                color: timerModel && timerModel.state === "running" ? "#3daee9" : "#808080"
                Layout.preferredWidth: 30
                horizontalAlignment: Text.AlignHCenter
            }
            
            // Botão rápido de iniciar timer
            Controls.ToolButton {
                icon.name: {
                    if (timerModel && timerModel.issueKey === issueKey && timerModel.state === "running") {
                        return "media-playback-stop"
                    } else if (timerModel && timerModel.issueKey === issueKey && timerModel.state === "paused") {
                        return "media-playback-start"
                    } else if (timerModel && timerModel.isOnBreak) {
                        return "media-playback-start"
                    }
                    return "chronometer"
                }
                Layout.preferredWidth: 40
                enabled: timerService && timerModel
                
                onClicked: {
                    if (!timerService || !timerModel || !issueKey) {
                        return
                    }
                    
                    // Se está em pausa, cancelar pausa e iniciar timer
                    if (timerModel && timerModel.isOnBreak) {
                        timerService.cancelBreak()
                        Qt.callLater(function() {
                            if (timerService && issueKey) {
                                timerService.start(issueKey)
                            }
                        })
                        return
                    }
                    
                    // Se timer já está ativo para esta issue
                    if (timerModel.issueKey === issueKey && timerModel.state !== "idle") {
                        if (timerModel.state === "running") {
                            timerService.stop()
                        } else if (timerModel.state === "paused") {
                            timerService.resume()
                        }
                    }
                    // Se há timer ativo para outra issue, parar e iniciar novo
                    else if (timerModel.state !== "idle" && timerModel.issueKey !== issueKey) {
                        timerService.stop()
                        Qt.callLater(function() {
                            if (timerService && issueKey) {
                                timerService.start(issueKey)
                            }
                        })
                    }
                    // Iniciar novo timer
                    else {
                        timerService.start(issueKey)
                    }
                }
            }
        }
    }
}

