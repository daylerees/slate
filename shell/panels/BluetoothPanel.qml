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

// ---- Bluetooth --------------------------------------------------------
// On/off, then paired devices (click one to connect or disconnect), then Settings for
// finding and pairing new ones
Column {
    required property var pop
    id: btView
    width: 300
    spacing: 10
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool on: !!adapter && adapter.enabled
    readonly property var devices: on ? adapter.devices.values.filter(d => d.paired || d.bonded || d.connected).slice()
        .sort((a, b) => (b.connected - a.connected) || (a.name || "").localeCompare(b.name || "")) : []
    function iconFor(d) {
        const i = (d.icon || "").toLowerCase();
        if (i.includes("headset") || i.includes("headphone") || i.includes("audio")) return 0xEABD;
        if (i.includes("gam") || i.includes("joystick")) return 0xF1D2;
        if (i.includes("mouse")) return 0xEAF9;
        if (i.includes("keyboard")) return 0xEBD6;
        if (i.includes("phone")) return 0xEA8A;
        return 0xEA37;
    }

    PanelTitle {
        text: "Bluetooth"
        Switch {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            visible: !!btView.adapter
            checked: btView.on
            onToggled: if (btView.adapter) btView.adapter.enabled = !btView.adapter.enabled
        }
    }

    Label {
        visible: !btView.on || btView.devices.length === 0
        width: parent.width
        wrapMode: Text.Wrap
        color: pop.dim
        font.pixelSize: 12
        font.weight: Font.Normal
        text: !btView.adapter ? "This computer has no Bluetooth" : !btView.on ? "Bluetooth is off"
            : "No paired devices yet. You can pair one in Bluetooth settings"
    }
    Column {
        visible: btView.on && btView.devices.length > 0
        width: parent.width
        spacing: 6
        Repeater {
            // (a row for each device, kept while it's there and moved when the order changes)
            model: ScriptModel { values: btView.devices }
            delegate: RowButton {
                id: devRow
                required property var modelData
                readonly property var d: modelData
                readonly property bool busy: d.state === BluetoothDeviceState.Connecting || d.state === BluetoothDeviceState.Disconnecting
                width: parent.width
                height: 44
                toggles: true
                selected: d.connected
                onClicked: d.connected ? d.disconnect() : d.connect()
                Icon {
                    id: devIcon
                    code: btView.iconFor(devRow.d)
                    color: devRow.fg
                    Behavior on color { ColorAnimation { duration: Config.ms(120) } }
                    font.pixelSize: 17
                    anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                }
                Column {
                    anchors { left: devIcon.right; leftMargin: 10; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    spacing: 1
                    Label {
                        width: parent.width
                        text: devRow.d.name || devRow.d.deviceName || devRow.d.address
                        color: devRow.fg
                        Behavior on color { ColorAnimation { duration: Config.ms(120) } }
                    }
                    Label {
                        width: parent.width
                        font.pixelSize: 11; font.weight: Font.Normal
                        color: devRow.fgDim
                        Behavior on color { ColorAnimation { duration: Config.ms(120) } }
                        opacity: devRow.selected ? 0.8 : 1
                        text: devRow.busy ? (devRow.d.connected ? "Disconnecting…" : "Connecting…")
                            : devRow.d.connected ? "Connected" + (devRow.d.batteryAvailable ? " · " + Math.round(devRow.d.battery * 100) + "% battery" : "")
                            : "Not connected"
                    }
                }
            }
        }
    }

    Divider {}
    LinkRow {
        code: 0xEB20; text: "Bluetooth settings"
        onClicked: pop.openSettingsPage("bluetooth")
    }
}
