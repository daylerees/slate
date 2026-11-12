// Which of the control centre's quick switches this computer can't use: no Wi-Fi card, no
// Bluetooth, nothing to play through or record with, no performance mode, no charging limit.
// Those are left out of the panel and of Settings → Control Centre (Config.controlSwitchMissing),
// and come back by themselves if the hardware turns up (a Bluetooth dongle, a USB microphone).
// Under the tests everything's there: their computer has none of it.

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower

Scope {
    readonly property var missing: {
        if (Config.testMode) return [];
        const out = [];
        if (!Networking.devices.values.some(d => d.type === DeviceType.Wifi)) out.push("wifi");
        if (!Bluetooth.defaultAdapter) out.push("bt");
        if (!Pipewire.defaultAudioSink) out.push("mute");
        if (!Pipewire.defaultAudioSource) out.push("micmute");
        if (!PowerProfiles.hasPerformanceProfile) out.push("perf");
        if (!Config.chargeLimitSupported) out.push("chargelimit");
        return out;
    }
    onMissingChanged: Config.controlSwitchMissing = missing
    Component.onCompleted: Config.controlSwitchMissing = missing
}
