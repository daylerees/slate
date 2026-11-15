import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import ".."

// A font choice: a dropdown of the installed fonts with a search box, as Settings' other
// long lists are (the time zone, keyboard layouts). key = Config.s property; monoOnly:
// only monospaced ones
DropdownSetting {
    id: fontSetting
    property string key
    property bool monoOnly: false
    // Monospaced fonts, from fontconfig, plus anything named like one
    property var monoFonts: []
    Process {
        running: fontSetting.monoOnly
        command: ["fc-list", ":spacing=mono", "family"]
        stdout: StdioCollector {
            onStreamFinished: fontSetting.monoFonts = text.split("\n").map(l => l.split(",")[0].trim()).filter(f => f)
        }
    }
    readonly property var all: Qt.fontFamilies().filter(f => f && !f.startsWith(".")
        && !/icon|emoji|symbol|tabler|awesome|powerline|signwriting|\.pcf$/i.test(f)
        && (!monoOnly || monoFonts.includes(f) || /mono|code|console|courier|terminal|fixed/i.test(f)))
        .sort((x, y) => x.localeCompare(y))
    settingKey: key
    searchable: true
    // (each written in its own typeface, in the list and on the button)
    options: all.map(f => ({ value: f, label: f, font: f }))
    value: Config.s[key]
    onPicked: v => Config.s[fontSetting.key] = v
}
