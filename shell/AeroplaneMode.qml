// Aeroplane mode: Wi-Fi, Bluetooth and mobile broadband off together, and back as they were
// when it's turned off. On/off from the control centre and the launcher (Config.s.aeroplaneMode).
//   slate ipc call aeroplane toggle | on | off
//
// What was on is remembered (Config.s.aeroplaneRestore), so only those come back: Bluetooth
// that was already off stays off. Turning Wi-Fi or Bluetooth on by hand while it's on is
// allowed, as on a phone; aeroplane mode stays on until you turn it off.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Networking

Scope {
    id: root
    readonly property bool on: Config.s.aeroplaneMode
    // (mobile broadband goes through NetworkManager, where there is one; whether Slate turned
    // it off is kept beside Slate's other state, as it's a fact about this session's radios)
    readonly property string wwanMark: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/slate/aeroplane-wwan"

    IpcHandler {
        target: "aeroplane"
        function toggle(): void { Config.s.aeroplaneMode = !Config.s.aeroplaneMode; }
        function on(): void { Config.s.aeroplaneMode = true; }
        function off(): void { Config.s.aeroplaneMode = false; }
    }

    onOnChanged: on ? root.radiosOff() : root.radiosBack()

    function radiosOff() {
        // What's on now is turned off, and added to what's remembered: when Slate starts with
        // aeroplane mode already on (after a restart, say, where Bluetooth came back by itself
        // and Wi-Fi didn't), what was remembered before is kept
        const was = [];
        if (Networking.wifiEnabled) was.push("wifi");
        if (Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled) was.push("bt");
        const kept = Config.s.aeroplaneRestore && Config.s.aeroplaneRestore.length !== undefined ? Array.from(Config.s.aeroplaneRestore) : [];
        if (was.some(r => kept.indexOf(r) < 0)) Config.s.aeroplaneRestore = kept.concat(was.filter(r => kept.indexOf(r) < 0));
        if (was.indexOf("wifi") >= 0) Networking.wifiEnabled = false;
        if (was.indexOf("bt") >= 0) Bluetooth.defaultAdapter.enabled = false;
        if (!Config.testMode)
            Quickshell.execDetached(["sh", "-c", '[ "$(nmcli radio wwan 2>/dev/null)" = enabled ] && nmcli radio wwan off && mkdir -p "${0%/*}" && : > "$0"', wwanMark]);
    }
    function radiosBack() {
        const was = Config.s.aeroplaneRestore && Config.s.aeroplaneRestore.length !== undefined ? Array.from(Config.s.aeroplaneRestore) : [];
        if (was.indexOf("wifi") >= 0) Networking.wifiEnabled = true;
        if (was.indexOf("bt") >= 0 && Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.enabled = true;
        if (was.length > 0) Config.s.aeroplaneRestore = [];
        if (!Config.testMode)
            Quickshell.execDetached(["sh", "-c", '[ -e "$0" ] && { nmcli radio wwan on; rm -f "$0"; }', wwanMark]);
    }
}
