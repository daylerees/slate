import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import "../.."
import ".."

Column {
    readonly property var win: SettingsHost.win
    id: wifiPane
    spacing: 4
    readonly property var dev: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var nets: {
        if (!dev) return [];
        const seen = new Set();
        return dev.networks.values
            .filter(n => n.name && !seen.has(n.name) && seen.add(n.name))
            .sort((a, b) => (b.connected - a.connected) || (b.known - a.known) || (b.signalStrength - a.signalStrength));
    }
    readonly property var current: nets.find(n => n.connected) ?? null
    property string askingFor: ""
    // Look for networks while this page is open
    Binding { target: wifiPane.dev; property: "scannerEnabled"; value: true; when: wifiPane.dev !== null && win.visible }

    // Wired: every network socket this computer has, and whether a cable's connected.
    // A cable carries the connection whenever there is one, Wi-Fi or not
    readonly property var wires: Networking.devices.values.filter(d => d.type === DeviceType.Wired)
    readonly property bool onWire: wires.some(d => d.connected)
    // The connection's details (scripts/netinfo.sh: the cable's while on one, the Wi-Fi's
    // otherwise), refreshed while the page is open
    property var info: ({})
    property string infoText: "\n"      // what netinfo.sh last said, as it said it
    Process {
        id: netDetails
        command: [Quickshell.shellPath("scripts/netinfo.sh")]
        stdout: StdioCollector {
            onStreamFinished: {
                // The same as last time, as it nearly always is: nothing to do
                const said = win.pretendPolls.network ?? text;
                win.rowMade("networkLooks");
                if (said === wifiPane.infoText) return;
                wifiPane.infoText = said;
                const o = {};
                for (const line of said.split("\n")) {
                    const i = line.indexOf("=");
                    if (i > 0) o[line.slice(0, i)] = line.slice(i + 1);
                }
                wifiPane.info = o;
            }
        }
    }
    Timer {
        interval: 5000; repeat: true; triggeredOnStart: true
        running: win.visible
        onTriggered: if (!netDetails.running) netDetails.running = true
    }
    function band(freq) {
        const mhz = parseInt(freq);
        return isNaN(mhz) ? "" : mhz >= 5925 ? "6 GHz" : mhz >= 4900 ? "5 GHz" : "2.4 GHz";
    }
    // What there is to say about the connection, as rows: only the ones that are known
    readonly property var facts: {
        const i = info, wired = i.wired !== undefined;
        if (i.ip === undefined) return [];
        const t = [
            { k: "IP address", v: (i.ip || "").split("/")[0] },
            { k: "Gateway", v: i.gateway || "" },
            { k: "DNS", v: i.dns && i.dns !== i.gateway ? i.dns : "" },
            { k: "Link speed", v: i.rate || "" },
            { k: "Band", v: wired ? "" : [band(i.freq), i.channel ? "channel " + i.channel : ""].filter(x => x).join(" · ") },
            { k: "Security", v: wired ? "" : (i.security || "") },
            { k: "VPN", v: i.vpn || "" }
        ];
        return t.filter(x => x.v);
    }

    PageTitle { text: "Network" }
    GroupLabel { visible: wifiPane.wires.length > 0; text: "Wired" }
    Group {
        visible: wifiPane.wires.length > 0
        Repeater {
            model: wifiPane.wires
            delegate: Column {
                id: wireRow
                required property var modelData
                required property int index
                width: parent.width
                Separator { visible: wireRow.index > 0 }
                Item {
                    width: parent.width; height: 60
                    Rectangle {
                        id: wireIcon
                        anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                        width: 34; height: 34; radius: Config.corner(9)
                        color: wireRow.modelData.connected ? win.accent : win.outline
                        Text {
                            anchors.centerIn: parent
                            text: Config.glyph(wireRow.modelData.connected ? 0xF09F : 0xF0A0)
                            color: wireRow.modelData.connected ? win.accentText : win.text
                            font.family: win.bar.iconFont; font.pixelSize: 17
                        }
                    }
                    Column {
                        anchors { left: wireIcon.right; leftMargin: 12; right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                        spacing: 2
                        Text {
                            width: parent.width; elide: Text.ElideRight
                            textFormat: Text.PlainText        // never markup
                            text: wifiPane.wires.length > 1 ? "Ethernet (" + wireRow.modelData.name + ")" : "Ethernet"
                            color: win.text; font.family: win.font; font.pixelSize: Config.text(13); font.weight: Font.Medium
                        }
                        Text {
                            width: parent.width; elide: Text.ElideRight
                            text: wireRow.modelData.connected
                                    ? "Connected" + (wifiPane.info.wired === wireRow.modelData.name && wifiPane.info.rate ? " · " + wifiPane.info.rate : "")
                                : wireRow.modelData.state === ConnectionState.Connecting ? "Connecting…"
                                : "No cable connected"
                            color: wireRow.modelData.connected ? win.accent : win.dim
                            font.family: win.font; font.pixelSize: Config.text(12)
                        }
                    }
                }
            }
        }
    }
    GroupLabel { text: "Wi-Fi" }
    Group {
        SettingRow {
            label: "Wi-Fi"
            detail: !wifiPane.dev ? "This computer has no Wi-Fi"
                : !Networking.wifiEnabled ? "Off"
                : wifiPane.current ? "Connected to " + wifiPane.current.name : "Not connected"
            SettingToggle { visible: !!wifiPane.dev; checked: Networking.wifiEnabled; onToggled: v => Networking.wifiEnabled = v }
        }
    }
    GroupLabel { visible: Networking.wifiEnabled && !!wifiPane.dev; text: wifiPane.nets.length ? "Networks" : "Searching for networks…" }
    Group {
        visible: Networking.wifiEnabled && wifiPane.nets.length > 0
        Repeater {
            // A row for each network, kept while the network's in range and moved when
            // the order changes (ScriptModel). Handed the list itself, every row was made
            // again each time any network's signal changed, which is every few seconds
            // while the page scans: a password half typed went with its row
            model: ScriptModel { values: wifiPane.nets }
            delegate: Column {
                id: netRow
                required property var modelData
                required property int index
                readonly property var n: modelData
                readonly property bool secure: n.security !== undefined && n.security !== WifiSecurityType.Open
                width: parent.width
                Separator { visible: netRow.index > 0 }
                Item {
                    width: parent.width; height: 60
                    Rectangle {
                        id: netIcon
                        anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                        width: 34; height: 34; radius: Config.corner(9)
                        color: netRow.n.connected ? win.accent : win.outline
                        Text {
                            anchors.centerIn: parent
                            readonly property real s: netRow.n.signalStrength
                            text: Config.glyph(s > 0.66 ? 0xEB52 : s > 0.33 ? 0xEBA5 : 0xEBA4)
                            color: netRow.n.connected ? win.accentText : win.text
                            font.family: win.bar.iconFont; font.pixelSize: 17
                        }
                    }
                    Column {
                        id: netLabels
                        anchors { left: netIcon.right; leftMargin: 12; right: netButtons.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        spacing: 2
                        Row {
                            spacing: 6
                            // A long name stops short of the buttons (… at the end), leaving
                            // room for the lock beside it
                            Text {
                                width: Math.min(implicitWidth, netLabels.width - (netLock.visible ? netLock.width + 6 : 0))
                                elide: Text.ElideRight
                                textFormat: Text.PlainText
                                text: netRow.n.name; color: win.text; font.family: win.font; font.pixelSize: Config.text(13); font.weight: Font.Medium
                            }
                            Text { id: netLock; visible: netRow.secure; anchors.verticalCenter: parent.verticalCenter; text: Config.glyph(0xEAE2); color: win.dim; font.family: win.bar.iconFont; font.pixelSize: 12 }
                        }
                        Text {
                            text: (netRow.n.connected ? "Connected" : netRow.n.stateChanging ? "Connecting…" : netRow.n.known ? "Saved" : netRow.secure ? "Secured" : "Open")
                                + " · " + Math.round(netRow.n.signalStrength * 100) + "% signal"
                            color: netRow.n.connected ? win.accent : win.dim
                            font.family: win.font; font.pixelSize: Config.text(12)
                        }
                    }
                    Row {
                        id: netButtons
                        anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                        spacing: 8
                        Button {
                            label: netRow.n.connected ? "Disconnect" : "Connect"
                            primary: !netRow.n.connected
                            onClicked: {
                                const n = netRow.n;
                                if (n.connected) n.disconnect();
                                else if (n.known || !netRow.secure) { n.connect(); wifiPane.askingFor = ""; }
                                else wifiPane.askingFor = (wifiPane.askingFor === n.name ? "" : n.name);
                            }
                        }
                        Button {
                            visible: netRow.n.known
                            label: "Forget"
                            destructive: true
                            onClicked: netRow.n.forget()
                        }
                    }
                }
                // Password for a new secured network
                Item {
                    visible: wifiPane.askingFor === netRow.n.name
                    width: parent.width; height: 48
                    TextField {
                        id: psk
                        anchors { left: parent.left; right: parent.right; leftMargin: 60; rightMargin: 14; top: parent.top }
                        height: 36; textSize: 13; padding: 12
                        secret: true
                        hintWhileTyping: true
                        hint: "Password for " + netRow.n.name + ", then Enter"      // (plain text: the network's own name)
                        onVisibleChanged: if (visible) { text = ""; input.forceActiveFocus(); }
                        onAccepted: { netRow.n.connectWithPsk(text); wifiPane.askingFor = ""; }
                        Keys.onEscapePressed: wifiPane.askingFor = ""
                    }
                }
            }
        }
    }
    GroupLabel { text: "Connection" }
    Group {
        SettingRow {
            label: wifiPane.onWire ? "Connected by cable"
                : wifiPane.current ? "Connected to " + wifiPane.current.name
                : "Not connected"
            detail: wifiPane.onWire ? (wifiPane.current ? "Wired, with " + wifiPane.current.name + " on Wi-Fi as well" : "Wired")
                : wifiPane.current ? "Wi-Fi"
                : !wifiPane.dev && wifiPane.wires.length === 0 ? "Slate can't find a network socket or Wi-Fi on this computer"
                : !wifiPane.dev ? "Plug in a cable and it connects by itself"
                : !Networking.wifiEnabled ? "Wi-Fi is off. Switch it on below, or plug in a cable"
                : "Choose a network below, or plug in a cable"
        }
        Repeater {
            // (a row for each fact there is, by its name, so a row stays while its fact does)
            model: ScriptModel { values: wifiPane.facts.map(f => f.k) }
            delegate: Column {
                id: factRow
                required property var modelData      // its fact's name
                Component.onCompleted: win.rowMade("facts")
                width: parent.width
                Separator {}
                SettingRow {
                    label: factRow.modelData
                    Text {
                        textFormat: Text.PlainText        // never markup: the network's own details
                        text: (wifiPane.facts.find(f => f.k === factRow.modelData) ?? { v: "" }).v
                        color: win.dim; font.family: win.font; font.pixelSize: Config.text(13)
                    }
                }
            }
        }
    }
}
