// Wi-Fi and Bluetooth through IPC, the way the bar's panels do them (Popouts.qml), for
// assistants (scripts/slate-mcp.py's wifi and bluetooth tools). Through Quickshell's own
// Networking and Bluetooth services, so it works however the distro runs them.
//   slate ipc call wifi list                   {available, on, wired, connected, networks: the saved ones in range}
//   slate ipc call wifi power true|false
//   slate ipc call wifi connect <name>         a saved network only: ok | off | unknown | notsaved
//   slate ipc call wifi disconnect             ok | none
//   slate ipc call bluetooth list              {available, on, devices: the paired ones}
//   slate ipc call bluetooth power true|false  ok | none
//   slate ipc call bluetooth connect <address> a paired device only: ok | off | unknown
//   slate ipc call bluetooth disconnect <address>
//
// Never a new network or a new device: one that needs a password, or pairing, is the
// person's to set up in its panel or in Settings. Networks you haven't saved aren't listed
// either (what's around you says where you are).

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Networking

Scope {
    id: root
    readonly property var wifiDev: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var adapter: Bluetooth.defaultAdapter
    function saved() {
        if (!wifiDev) return [];
        const seen = new Set();
        return wifiDev.networks.values.filter(n => n.name && n.known && !seen.has(n.name) && seen.add(n.name));
    }
    function paired() {
        return adapter ? adapter.devices.values.filter(d => d.paired || d.bonded) : [];
    }

    IpcHandler {
        target: "wifi"
        function list(): string {
            const on = !!root.wifiDev && Networking.wifiEnabled;
            const nets = on ? root.saved() : [];
            const now = nets.find(n => n.connected);
            return JSON.stringify({
                available: !!root.wifiDev, on: on,
                wired: Networking.devices.values.some(d => d.type === DeviceType.Wired && d.connected),
                connected: now ? now.name : "",
                networks: nets.sort((a, b) => b.signalStrength - a.signalStrength)
                    .map(n => ({ name: n.name, connected: n.connected, signal: Math.round(n.signalStrength * 100) }))
            });
        }
        function power(on: bool): string {
            if (!root.wifiDev) return "none";
            Networking.wifiEnabled = on;
            return "ok";
        }
        function connect(name: string): string {
            if (!root.wifiDev || !Networking.wifiEnabled) return "off";
            const n = root.wifiDev.networks.values.find(n => n.name === name && n.known)
                ?? root.wifiDev.networks.values.find(n => n.name === name);
            if (!n) return "unknown";
            if (!n.known) return "notsaved";
            if (!n.connected) n.connect();
            return "ok";
        }
        function disconnect(): string {
            const n = root.wifiDev ? root.wifiDev.networks.values.find(n => n.connected) : null;
            if (!n) return "none";
            n.disconnect();
            return "ok";
        }
    }

    IpcHandler {
        target: "bluetooth"
        function list(): string {
            const on = !!root.adapter && root.adapter.enabled;
            return JSON.stringify({
                available: !!root.adapter, on: on,
                devices: (on ? root.paired() : []).map(d => {
                    const o = { name: d.name || d.deviceName || d.address, address: d.address, connected: d.connected };
                    if (d.connected && d.batteryAvailable) o.battery = Math.round(d.battery * 100);
                    return o;
                })
            });
        }
        function power(on: bool): string {
            if (!root.adapter) return "none";
            root.adapter.enabled = on;
            return "ok";
        }
        function connect(address: string): string { return root.device(address, true); }
        function disconnect(address: string): string { return root.device(address, false); }
    }
    function device(address, on) {
        if (!adapter || !adapter.enabled) return "off";
        const d = paired().find(d => d.address === address);
        if (!d) return "unknown";
        if (on && !d.connected) d.connect();
        else if (!on && d.connected) d.disconnect();
        return "ok";
    }
}
