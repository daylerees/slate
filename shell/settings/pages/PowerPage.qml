import QtQuick
import Quickshell.Io
import Quickshell.Services.UPower
import "../.."
import ".."

// ---- Power ------------------------------------------------------------------
Column {
    readonly property var win: SettingsHost.win
    id: powerPane
    spacing: 4
    PageTitle { text: "Power" }
    property bool hasLid: false
    Process {
        running: true
        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector { onStreamFinished: { try { powerPane.hasLid = (JSON.parse(text).switches || []).some(x => /lid/i.test(x.name)); } catch (e) {} } }
    }
    readonly property var profileOptions: [{ value: "", label: "Leave it as it is" }, { value: "power-saver", label: "Power saver" },
        { value: "balanced", label: "Balanced" }].concat(PowerProfiles.hasPerformanceProfile ? [{ value: "performance", label: "Performance" }] : [])

    GroupLabel { text: "Lid and power button" }
    Group {
        DropdownSetting {
            visible: powerPane.hasLid
            label: "Closing the lid"
            settingKey: "lidAction"
            detail: Config.s.lidAction === "" ? "As your computer does it (usually it sleeps)"
                : "With another screen connected, only the laptop's own screen turns off"
            // (holding the system's own handling back needs systemd or elogind: Config.system)
            needsMet: Config.canInhibit
            needs: "Needs systemd or elogind, and neither is running"
            options: [{ value: "", label: "System default" }, { value: "suspend", label: "Suspend" }, { value: "lock", label: "Lock the screen" },
                      { value: "screenoff", label: "Turn the screen off" }, { value: "nothing", label: "Do nothing" }]
                .filter(o => o.value !== "suspend" || Config.canSuspend)
            value: Config.s.lidAction
            onPicked: v => Config.s.lidAction = v
        }
        Separator { visible: powerPane.hasLid }
        DropdownSetting {
            label: "Power button"
            settingKey: "powerKeyAction"
            needsMet: Config.canInhibit
            needs: "Needs systemd or elogind, and neither is running"
            detail: Config.s.powerKeyAction === "" ? "As your computer does it (usually it shuts down)" : ""
            options: [{ value: "", label: "System default" }, { value: "menu", label: "Show the power menu" }, { value: "suspend", label: "Suspend" },
                      { value: "poweroff", label: "Shut down (asks first)" }, { value: "lock", label: "Lock the screen" }, { value: "nothing", label: "Do nothing" }]
                .filter(o => (o.value !== "suspend" || Config.canSuspend) && (o.value !== "poweroff" || Config.canPowerOff))
            value: Config.s.powerKeyAction
            onPicked: v => Config.s.powerKeyAction = v
        }
    }
    // The charging limit: where the laptop can stop charging short of full, which is
    // kinder to a battery that's mostly plugged in. The system's power service (UPower)
    // keeps it, with the level the laptop's maker set, and lets whoever's at the laptop
    // switch it on and off. The row only shows where it's there to switch
    // (Config keeps it, as the control centre's Charging Limit switch uses it too)
    readonly property bool limitSupported: Config.chargeLimitSupported
    readonly property bool limitOn: Config.chargeLimitOn
    readonly property int limitAt: Config.chargeLimitAt
    Component.onCompleted: Config.chargeLimitRefresh()
    function askLimit(on) { Config.askChargeLimit(on, win.confirmer); }
    GroupLabel { text: "Power mode" }
    Group {
        DropdownSetting {
            label: "On battery"
            settingKey: "profileOnBattery"
            detail: "Switched to when you unplug; the control center can still change it any time"
            options: powerPane.profileOptions
            value: Config.s.profileOnBattery
            onPicked: v => { Config.s.profileOnBattery = v; Config.applyPowerProfile(); }
        }
        Separator {}
        DropdownSetting {
            label: "Plugged in"
            settingKey: "profileOnAC"
            detail: "Switched to when you plug in"
            options: powerPane.profileOptions
            value: Config.s.profileOnAC
            onPicked: v => { Config.s.profileOnAC = v; Config.applyPowerProfile(); }
        }
    }
    GroupLabel { visible: powerPane.limitSupported; text: "Battery" }
    Group {
        visible: powerPane.limitSupported
        SettingRow {
            label: "Charging limit"
            detail: powerPane.limitOn ? "Charging stops at " + powerPane.limitAt + "%, which keeps your battery healthy for longer"
                : "Your battery charges to full. Stopping at " + powerPane.limitAt + "% is kinder to it"
            SettingToggle { checked: powerPane.limitOn; onToggled: v => powerPane.askLimit(v) }
        }
    }
}
