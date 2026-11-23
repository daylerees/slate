import QtQuick
import Quickshell
import Quickshell.Bluetooth
import "../.."
import ".."

Column {
    readonly property var win: SettingsHost.win
    id: bluetoothPane
    spacing: 4
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var devices: adapter ? adapter.devices.values.slice().sort((a, b) =>
        (b.connected - a.connected) || (b.paired - a.paired) || (a.name || "").localeCompare(b.name || "")) : []
    function deviceIcon(d) {
        const i = (d.icon || "").toLowerCase();
        if (i.includes("headset") || i.includes("headphone") || i.includes("audio")) return 0xEABD;
        if (i.includes("gam") || i.includes("joystick")) return 0xF1D2;
        if (i.includes("mouse")) return 0xEAF9;
        if (i.includes("keyboard")) return 0xEBD6;
        if (i.includes("phone")) return 0xEA8A;
        return 0xEA37;
    }

    PageTitle { text: "Bluetooth" }
    GroupLabel { text: "Status" }
    Group {
        SettingRow {
            label: "Bluetooth"
            detail: bluetoothPane.adapter ? (bluetoothPane.adapter.enabled ? "On" : "Off") : "This computer has no Bluetooth"
            SettingToggle { visible: !!bluetoothPane.adapter; checked: bluetoothPane.adapter ? bluetoothPane.adapter.enabled : false; onToggled: v => { if (bluetoothPane.adapter) bluetoothPane.adapter.enabled = v; } }
        }
        Separator { visible: bluetoothPane.adapter && bluetoothPane.adapter.enabled }
        SettingRow {
            visible: bluetoothPane.adapter && bluetoothPane.adapter.enabled
            label: "New devices"
            detail: bluetoothPane.adapter && bluetoothPane.adapter.discovering ? "Searching… put your device in pairing mode" : "Find nearby devices to pair"
            Row {
                spacing: 10
                Spinner {
                    visible: bluetoothPane.adapter && bluetoothPane.adapter.discovering
                    anchors.verticalCenter: parent.verticalCenter
                    colour: win.accent
                }
                Button {
                    icon: 0xEA37
                    label: bluetoothPane.adapter && bluetoothPane.adapter.discovering ? "Stop" : "Search"
                    primary: !(bluetoothPane.adapter && bluetoothPane.adapter.discovering)
                    onClicked: if (bluetoothPane.adapter) bluetoothPane.adapter.discovering = !bluetoothPane.adapter.discovering
                }
            }
        }
    }
    GroupLabel { visible: bluetoothPane.adapter && bluetoothPane.adapter.enabled; text: "Devices" }
    Group {
        visible: bluetoothPane.adapter && bluetoothPane.adapter.enabled
        Text {
            visible: bluetoothPane.devices.length === 0
            x: 16; height: 48; verticalAlignment: Text.AlignVCenter
            text: "No devices just yet"
            color: win.dim; font.family: win.font; font.pixelSize: Config.text(13)
        }
        Repeater {
            // (a row for each device, kept while it's there and moved when the order changes)
            model: ScriptModel { values: bluetoothPane.devices }
            delegate: Item {
                required property var modelData
                required property int index
                readonly property var d: modelData
                width: parent.width
                height: 60
                Separator { visible: index > 0 }
                Rectangle {
                    id: devIcon
                    anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                    width: 34; height: 34; radius: Config.corner(9)
                    color: d.connected ? win.accent : win.outline
                    Text {
                        anchors.centerIn: parent
                        text: Config.glyph(bluetoothPane.deviceIcon(d))
                        color: d.connected ? win.accentText : win.text
                        font.family: win.bar.iconFont; font.pixelSize: 17
                    }
                }
                Column {
                    anchors { left: devIcon.right; leftMargin: 12; right: devButtons.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    spacing: 2
                    Text { width: parent.width; textFormat: Text.PlainText; text: d.name || d.deviceName || d.address; color: win.text; font.family: win.font; font.pixelSize: Config.text(13); font.weight: Font.Medium; elide: Text.ElideRight }
                    Text {
                        width: parent.width
                        text: d.pairing ? "Pairing…"
                            : d.connected ? "Connected" + (d.batteryAvailable ? " · " + Math.round(d.battery * 100) + "% battery" : "")
                            : d.paired ? "Paired" : "Not paired"
                        color: d.connected ? win.accent : win.dim
                        font.family: win.font; font.pixelSize: Config.text(12)
                    }
                }
                Row {
                    id: devButtons
                    anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    spacing: 8
                    Button {
                        visible: d.paired || d.bonded
                        label: d.connected ? "Disconnect" : "Connect"
                        primary: !d.connected
                        onClicked: d.connected ? d.disconnect() : d.connect()
                    }
                    Button {
                        visible: !(d.paired || d.bonded)
                        label: d.pairing ? "Cancel" : "Pair"
                        primary: !d.pairing
                        onClicked: d.pairing ? d.cancelPair() : d.pair()
                    }
                    Button {
                        visible: d.paired || d.bonded
                        label: "Forget"
                        destructive: true
                        onClicked: d.forget()
                    }
                }
            }
        }
    }
}
