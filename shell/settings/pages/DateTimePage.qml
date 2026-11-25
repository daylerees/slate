import QtQuick
import Quickshell
import Quickshell.Io
import "../.."
import ".."

// ---- Region (once "Date & Time"; bin/slate-init timedate: timedatectl with systemd, the same D-Bus service
// without it where something provides it; changing them may ask for your password) --------
Column {
    readonly property var win: SettingsHost.win
    id: dateTimePane
    spacing: 4
    PageTitle { text: "Region" }
    property string zone: ""
    property bool ntp: false
    property bool canNtp: true
    property bool canSet: true            // something here can change the zone
    readonly property var zones: SettingsLookups.zones
    property date now: new Date()
    // The day alone, for the date examples below: it changes at midnight, where `now`
    // changes every second and rebuilt them each time
    property date today: now
    readonly property string dayKey: Qt.formatDate(now, "yyyyMMdd")
    onDayKeyChanged: today = now
    // The clock on this page; only ticks while Settings is showing (and catches up at once)
    Timer { interval: 1000; running: win.visible; repeat: true; triggeredOnStart: true; onTriggered: dateTimePane.now = Config.clockDate(new Date()) }
    function refresh() { stateProc.running = false; stateProc.running = true; }
    Timer { id: reread; interval: 1500; onTriggered: dateTimePane.refresh() }
    Process {
        id: stateProc
        running: true
        command: [Quickshell.shellPath("bin/slate-init"), "timedate", "show"]
        stdout: StdioCollector {
            onStreamFinished: {
                for (const line of text.split("\n")) {
                    const i = line.indexOf("="), k = line.slice(0, i), v = line.slice(i + 1);
                    if (k === "Timezone") dateTimePane.zone = v;
                    else if (k === "NTP") dateTimePane.ntp = v === "yes";
                    else if (k === "CanNTP") dateTimePane.canNtp = v === "yes";
                    else if (k === "CanSet") dateTimePane.canSet = v === "yes";
                }
            }
        }
    }
    // (SettingsLookups.qml: read once, kept for the next time the page opens)
    Component.onCompleted: SettingsLookups.wantZones()
    GroupLabel { text: "Clock" }
    Group {
        SettingRow {
            label: Config.dateText(dateTimePane.now, "long")
            detail: Config.timeText(dateTimePane.now, { seconds: true })
        }
        Separator {}
        // Every zone in one dropdown, opening at the current one, with a search box to filter it
        DropdownSetting {
            label: "Time zone"
            // Without systemd, changing it needs a service that provides the same thing
            // (openrc-settingsd does). Without one it's shown, greyed, with why
            needsMet: dateTimePane.canSet
            needs: "Needs a time service, like openrc-settingsd"
            detail: dateTimePane.canSet ? "Where you are, for the clock; type to search"
                : "Slate can't change this here: your clock follows the system's own setting"
            searchable: true
            options: dateTimePane.zones
            value: dateTimePane.zone
            onPicked: v => { if (v !== dateTimePane.zone) { Quickshell.execDetached([Quickshell.shellPath("bin/slate-init"), "timedate", "set-zone", v]); reread.restart(); } }
        }
        Separator { visible: dateTimePane.canNtp }
        SettingRow {
            visible: dateTimePane.canNtp
            label: "Set the time automatically"
            detail: "Keeps your clock right, using a time server on the internet"
            SettingToggle {
                checked: dateTimePane.ntp
                onToggled: v => { dateTimePane.ntp = v; Quickshell.execDetached([Quickshell.shellPath("bin/slate-init"), "timedate", "set-ntp", v ? "true" : "false"]); reread.restart(); }
            }
        }
    }
    Footnote { text: "How the clock looks is under Menu Bar. Changing these may ask for your password." }
    // How dates, the week and temperatures are written, everywhere Slate shows them
    GroupLabel { text: "Formats" }
    Group {
        DropdownSetting {
            label: "Date format"
            settingKey: "dateFormat"
            detail: "On the menu bar's clock, the calendar, notifications and everywhere else Slate shows a date"
            options: [{ value: "dmy", label: Qt.formatDate(dateTimePane.today, "ddd d MMM") },
                      { value: "mdy", label: Qt.formatDate(dateTimePane.today, "ddd, MMM d") },
                      { value: "ymd", label: Qt.formatDate(dateTimePane.today, "yyyy-MM-dd") }]
            value: Config.s.dateFormat
            onPicked: v => Config.s.dateFormat = v
        }
        Separator {}
        DropdownSetting {
            label: "Week starts on"
            settingKey: "weekStart"
            detail: "The first day of the week in the clock's calendar"
            options: [{ value: "monday", label: "Monday" }, { value: "sunday", label: "Sunday" }, { value: "saturday", label: "Saturday" }]
            value: Config.s.weekStart
            onPicked: v => Config.s.weekStart = v
        }
        Separator {}
        DropdownSetting {
            label: "Temperature"
            settingKey: "temperatureUnit"
            detail: "For the weather in the clock's panel and the control center"
            options: [{ value: "celsius", label: "Celsius (°C)" }, { value: "fahrenheit", label: "Fahrenheit (°F)" }]
            value: Config.s.temperatureUnit
            onPicked: v => Config.s.temperatureUnit = v
        }
    }
}
