import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.UPower
import Quickshell.Services.Pipewire
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.Mpris
import QtQuick.Effects
import qs

// ---- Game mode: costly effects off while you play (Config.gameMode) ------------------
// ---- Window mode (the button before the workspace dots) ------------------------------
// The window mode of the workspace you're on (this one only: the others keep theirs). The
// default for the rest is in Settings → Windows (its footer link)
Column {
    required property var pop
    id: wmView
    width: 300
    spacing: 10
    readonly property int ws: Config.focusedWorkspaceId
    readonly property string own: Config.workspaceModes[String(ws)] || ""
    readonly property var modes: Config.windowModes

    // Its name (or "Workspace 3"), with a pencil to rename it: asked in Slate's
    // confirmation window, which has a field for it. An empty name: the number again
    PanelTitle {
        text: Config.workspaceLabel(wmView.ws)
        editCode: wmView.ws > 0 ? 0xEA98 : 0
        editName: "Rename this workspace"
        onEditClicked: pop.renameWorkspace(wmView.ws)
    }
    Label {
        width: parent.width
        wrapMode: Text.Wrap
        color: pop.dim; font.pixelSize: Config.text(12); font.weight: Font.Normal
        text: (wmView.own ? "This workspace has a window mode of its own." : "This workspace follows the default.")
            + " A mode picked here is for this workspace only; the others keep theirs"
    }
    Column {
        width: parent.width
        spacing: 6
        Repeater {
            model: wmView.modes
            delegate: RowButton {
                id: modeRow
                required property var modelData
                readonly property bool isDefault: modelData.value === Config.windowMode
                width: parent.width
                selected: Config.focusedMode === modelData.value
                // (the default's mode: back to following the default)
                onClicked: Config.setWorkspaceMode(wmView.ws, modelData.value)
                Icon {
                    id: modeIcon
                    code: modeRow.modelData.icon; font.pixelSize: 16
                    color: modeRow.fgDim
                    Behavior on color { ColorAnimation { duration: Config.ms(120) } }
                    anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                }
                Label {
                    anchors { left: modeIcon.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
                    text: modeRow.modelData.label
                    color: modeRow.fg
                    Behavior on color { ColorAnimation { duration: Config.ms(120) } }
                    font.weight: Font.Normal
                }
                Label {
                    visible: modeRow.isDefault
                    anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    text: "Default"
                    color: modeRow.fgDim
                    Behavior on color { ColorAnimation { duration: Config.ms(120) } }
                    font.pixelSize: Config.text(12); font.weight: Font.Normal
                }
            }
        }
    }
    Divider {}
    LinkRow {
        code: 0xEB20; text: "Window settings"
        onClicked: pop.openSettingsPage("windows")
    }
}
