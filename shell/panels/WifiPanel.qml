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

// ---- Wi-Fi -------------------------------------------------------------
Column {
    required property var pop
    id: wifiView
    width: 320
    spacing: 10
    readonly property var dev: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
    // (tests: pretend ones, where there's no Wi-Fi)
    readonly property var found: pop.pretendNets ?? (dev ? dev.networks.values : [])
    readonly property bool wifiOn: Networking.wifiEnabled || pop.pretendNets !== null
    readonly property var nets: {
        const seen = new Set();
        return found
            .filter(n => n.name && !seen.has(n.name) && seen.add(n.name))
            .sort((a, b) => (b.connected - a.connected) || (b.signalStrength - a.signalStrength));
    }
    property string askingFor: ""      // network waiting for a password
    Connections { target: pop; function onAskForPassword(name) { wifiView.askingFor = name; } }
    readonly property var testList: netList
    function testOrder() { return nets.map(n => n.name); }
    // (the password field that's open, if one is)
    function testField() {
        for (let i = 0; i < netList.count; i++) {
            const row = netList.itemAtIndex(i);
            if (row && row.modelData.name === askingFor) return row.field;
        }
        return null;
    }
    // On a cable, connected: the panel says so first, and its details are the cable's
    readonly property bool onWire: Networking.devices.values.some(d => d.type === DeviceType.Wired && d.connected)
    // Scan while the panel is open
    Binding { target: wifiView.dev; property: "scannerEnabled"; value: true; when: wifiView.dev !== null && pop.shown }

    PanelTitle {
        text: wifiView.dev ? "Wi-Fi" : "Network"
        Switch {
            visible: !!wifiView.dev
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            checked: Networking.wifiEnabled
            onToggled: Networking.wifiEnabled = !Networking.wifiEnabled
        }
    }
    // (a computer with no Wi-Fi: say so. The bar's Wi-Fi button isn't shown there, but
    // the panel can still be asked for)
    // Wired: its own line, above whatever Wi-Fi there is
    Item {
        visible: wifiView.onWire
        width: parent.width; height: 36
        Icon {
            id: wireIcon
            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
            code: 0xF09F; font.pixelSize: 16
            color: Config.statusColour("wifi", pop.text)
        }
        Label {
            anchors { left: wireIcon.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
            text: "Wired"
        }
        Label {
            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
            text: "Connected"
            color: pop.dim; font.pixelSize: 12
        }
    }
    Divider { visible: wifiView.onWire && !!wifiView.dev }
    Label {
        visible: !wifiView.dev && !wifiView.onWire
        width: parent.width
        wrapMode: Text.Wrap
        font.weight: Font.Normal
        color: pop.dim
        text: "This computer has no Wi-Fi, and no cable is connected. Plug one in and it connects by itself"
    }

    // ---- Connection details (scripts/netinfo.sh), refreshed while the panel is open
    property var info: ({})
    readonly property var connected: nets.find(n => n.connected) ?? null
    Process {
        id: netInfo
        command: [Quickshell.shellPath("scripts/netinfo.sh")]
        stdout: StdioCollector {
            onStreamFinished: {
                const o = {};
                for (const line of text.split("\n")) {
                    const i = line.indexOf("=");
                    if (i > 0) o[line.slice(0, i)] = line.slice(i + 1);
                }
                // (the same as last time, as it nearly always is: nothing to do)
                if (JSON.stringify(o) !== JSON.stringify(wifiView.info)) wifiView.info = o;
            }
        }
    }
    Timer {
        interval: 5000; repeat: true; triggeredOnStart: true
        running: pop.shown && pop.displayed === "wifi"
        onTriggered: if (!netInfo.running) netInfo.running = true
    }
    function band(freq) {
        const mhz = parseInt(freq);
        return isNaN(mhz) ? "" : mhz >= 5925 ? "6 GHz" : mhz >= 4900 ? "5 GHz" : "2.4 GHz";
    }

    Label {
        visible: !!wifiView.dev && (!wifiView.wifiOn || wifiView.nets.length === 0)
        text: Networking.wifiEnabled ? "Searching…" : "Wi-Fi is off"
        color: pop.dim
    }

    ListView {
        id: netList
        visible: wifiView.wifiOn && wifiView.nets.length > 0
        width: parent.width
        // At most 320, less on a short screen (with room for the rest of the panel: its
        // title, the connection's details), so the panel never runs off the screen
        height: Math.min(contentHeight, 320, Math.max(120, pop.height - 360))
        clip: true
        spacing: 6
        boundsBehavior: Flickable.StopAtBounds
        // A row for each network, kept while the network's in range and moved when the
        // order changes (ScriptModel). Handed the list itself, every row was made again
        // each time any network's signal changed, which is every few seconds while the
        // panel scans: a password half typed went with its row
        model: ScriptModel { values: wifiView.nets }
        readonly property bool overflowing: contentHeight > height
        SmoothWheel { flick: netList }
        // Shades and scrollbar, parented to the list itself so they stay put
        ScrollShade { parent: netList; z: 3; width: netList.width; cornerRadius: 8; distance: netList.contentY - netList.originY }
        ScrollShade { parent: netList; z: 3; atBottom: true; y: netList.height - height; width: netList.width; cornerRadius: 8
                      distance: netList.originY + netList.contentHeight - netList.height - netList.contentY }
        ThinScrollbar { parent: netList; z: 3; flick: netList; color: pop.text; anchors { top: parent.top; bottom: parent.bottom; right: parent.right } }
        delegate: Column {
            id: netRow
            required property var modelData
            Component.onCompleted: pop.rowMade("wifi")
            readonly property alias field: psk.input
            readonly property bool secure: modelData.security !== undefined && modelData.security !== WifiSecurityType.Open
            width: netList.width - (netList.overflowing ? 18 : 0)   // room for the scrollbar and a gap before it
            spacing: 4
            RowButton {
                width: parent.width
                selected: netRow.modelData.connected
                onClicked: {
                    const n = netRow.modelData;
                    if (n.connected) return;
                    if (n.known || !netRow.secure) { n.connect(); wifiView.askingFor = ""; }
                    else wifiView.askingFor = (wifiView.askingFor === n.name ? "" : n.name);
                }
                Icon {
                    id: signalIcon
                    readonly property real s: netRow.modelData.signalStrength
                    code: s > 0.66 ? 0xEB52 : s > 0.33 ? 0xEBA5 : 0xEBA4
                    color: parent.fg
                    Behavior on color { ColorAnimation { duration: Config.ms(120) } }
                    font.pixelSize: 16
                    anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                }
                Label {
                    anchors { left: signalIcon.right; leftMargin: 10; right: netStatus.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    text: netRow.modelData.name
                    color: parent.fg
                    Behavior on color { ColorAnimation { duration: Config.ms(120) } }
                }
                Row {
                    id: netStatus
                    anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    spacing: 6
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: netRow.modelData.connected ? "Connected"
                            : netRow.modelData.stateChanging ? "Connecting…"
                            : netRow.modelData.known ? "Saved" : ""
                        color: netRow.modelData.connected ? pop.accentText : pop.dim
                        font.pixelSize: 12
                    }
                    Icon {
                        visible: netRow.secure
                        code: 0xEAE2
                        font.pixelSize: 13
                        color: netRow.modelData.connected ? pop.accentText : pop.dim
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
            // Password entry for a new secured network
            PanelField {
                id: psk
                visible: wifiView.askingFor === netRow.modelData.name
                secret: true; keepFocus: true
                hint: "Password, then Enter"; hintWeight: Font.Medium
                onOpened: { text = ""; input.forceActiveFocus(); }
                onAccepted: { netRow.modelData.connectWithPsk(text); wifiView.askingFor = ""; }
                onEscaped: wifiView.askingFor = ""
            }
        }
    }

    // ---- Connection: signal, then details as small tiles (click to copy) ----
    // (the cable's while on one: netinfo.sh reports it then, with wired=…)
    readonly property bool wiredInfo: wifiView.info.wired !== undefined
    readonly property bool showInfo: wifiView.info.ip !== undefined && (wiredInfo || (Networking.wifiEnabled && wifiView.connected !== null))
    Divider { visible: wifiView.showInfo }
    Heading { visible: wifiView.showInfo; text: "Connection" }
    // Signal strength, as a meter like the battery panel's
    Column {
        id: signalInfo
        visible: wifiView.showInfo && !wifiView.wiredInfo
        width: parent.width
        spacing: 5
        // Glides between readings (the bar and the number together)
        property real sig: wifiView.connected ? wifiView.connected.signalStrength : 0
        Behavior on sig { NumberAnimation { duration: Config.ms(900); easing.type: Easing.InOutCubic } }
        Item {
            width: parent.width; height: sigLabel.height
            Label { id: sigLabel; text: "Signal"; font.pixelSize: 12 }
            Label {
                anchors.right: parent.right
                text: Math.round(signalInfo.sig * 100) + "%" + (wifiView.info.security ? " · " + wifiView.info.security : "")
                color: pop.dim; font.pixelSize: 12
            }
        }
        Meter {
            width: parent.width
            value: signalInfo.sig
            trackColour: pop.card
            colour: signalInfo.sig < 0.2 ? pop.danger : pop.accent   // red below 20%
            colourMs: 300
        }
    }
    // Details: two columns of tiles
    Grid {
        visible: wifiView.showInfo
        width: parent.width
        columns: 2
        spacing: 6
        // (a tile for each detail there is, by its name, so a tile stays while its detail
        // does: "Copied" isn't lost when another detail changes)
        id: detailGrid
        readonly property var details: {
                const ip = (wifiView.info.ip || "").split("/")[0];
                const t = [
                    { k: "Band", v: [wifiView.band(wifiView.info.freq), wifiView.info.channel ? "ch " + wifiView.info.channel : ""].filter(x => x).join(" · "), copy: false },
                    { k: "Link speed", v: wifiView.info.rate || "", copy: false },
                    { k: "IP address", v: ip, copy: true },
                    { k: "Gateway", v: wifiView.info.gateway || "", copy: true }
                ];
                if (wifiView.info.dns && wifiView.info.dns !== wifiView.info.gateway) t.push({ k: "DNS", v: wifiView.info.dns, copy: true });
                return t.filter(x => x.v);
        }
        Repeater {
            model: ScriptModel { values: detailGrid.details.map(x => x.k) }
            delegate: Rectangle {
                id: tile
                required property var modelData     // its detail's name
                readonly property var detail: detailGrid.details.find(x => x.k === modelData) ?? ({ k: modelData, v: "", copy: false })
                width: (wifiView.width - 6) / 2
                height: 46
                radius: Config.corner(9)
                color: "transparent"
                HoverFill { base: pop.card; hovered: tileHover.hovered && tile.detail.copy; radius: parent.radius }
                property bool copied: false
                Timer { id: copiedTimer; interval: 1200; onTriggered: tile.copied = false }
                Column {
                    anchors { left: parent.left; leftMargin: 10; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    spacing: 2
                    Label { text: tile.detail.k; color: pop.dim; font.pixelSize: 11 }
                    Label {
                        width: parent.width
                        text: tile.copied ? "Copied" : tile.detail.v
                        color: tile.copied ? pop.accent : pop.text
                        font.pixelSize: 13
                    }
                }
                HoverHandler { id: tileHover }
                ClickTap {
                    enabled: tile.detail.copy
                    onTapped: { Quickshell.execDetached(["wl-copy", "--", tile.detail.v]); tile.copied = true; copiedTimer.restart(); }
                }
            }
        }
    }
    // VPN, when one is active
    Rectangle {
        visible: wifiView.showInfo && !!wifiView.info.vpn
        width: parent.width; height: 36; radius: Config.corner(9)
        color: Qt.rgba(pop.accent.r, pop.accent.g, pop.accent.b, 0.14)
        Row {
            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
            spacing: 8
            Icon { anchors.verticalCenter: parent.verticalCenter; code: 0xED58; color: pop.accent; font.pixelSize: 16 }
            Label { anchors.verticalCenter: parent.verticalCenter; text: "VPN"; color: pop.accent; font.pixelSize: 12 }
            Label { anchors.verticalCenter: parent.verticalCenter; text: wifiView.info.vpn || ""; font.pixelSize: 12 }
        }
    }

    // Disconnect from the current network
    RowButton {
        visible: wifiView.connected !== null
        width: parent.width
        onClicked: if (wifiView.connected) wifiView.connected.disconnect()
        Label {
            anchors.centerIn: parent
            text: "Disconnect"
            color: pop.dim
        }
    }
}
