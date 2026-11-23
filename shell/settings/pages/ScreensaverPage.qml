import QtQuick
import Quickshell
import Quickshell.Io
import "../.."
import ".."

Column {
    readonly property var win: SettingsHost.win
    id: ssCol
    spacing: 4
    readonly property var minutes: win.minuteOptions([0, 1, 2, 3, 5, 10, 15, 20, 30])
    PageTitle { text: "Screensaver" }
    IntroText { text: "Covers the screen while you're away, before the lock and screen-off times in Security. Any key, click or move of the pointer puts it away." }
    GroupLabel { text: "Style & timing" }
    Group {
        DropdownSetting {
            label: "Start after"
            settingKey: "screensaverMinutes"
            detail: Config.s.idleLockMinutes > 0 && Config.s.screensaverMinutes >= Config.s.idleLockMinutes
                ? "The screen locks at " + Config.s.idleLockMinutes + " minutes (in Security), so it won't show"
                : "Of no input. Video and apps that keep the screen awake hold it off"
            options: ssCol.minutes
            value: Config.s.screensaverMinutes
            onPicked: v => Config.s.screensaverMinutes = v
        }
        Separator {}
        DropdownSetting {
            // The background; whether there's a clock on it is Show the clock, below
            label: "Style"
            settingKey: "screensaverStyle"
            options: [{ value: "drift", label: "Your wallpaper" },
                      { value: "slideshow", label: "Wallpaper slideshow" },
                      { value: "videos", label: "Videos" },
                      { value: "black", label: "Black" }]
            value: Config.s.screensaverStyle
            onPicked: v => Config.s.screensaverStyle = v
            detail: Config.s.screensaverStyle === "drift" ? "Your wallpaper, dimmed and slowly drifting"
                : Config.s.screensaverStyle === "slideshow" ? "The pictures in your wallpaper folder, fading from one to the next"
                : Config.s.screensaverStyle === "videos" ? (Config.multimediaAvailable ? "The videos in a folder, silent, fading from one to the next"
                    : "The videos in a folder, silent. Needs Qt Multimedia" + Packages.named("qtmultimedia") + ", which isn't installed")
                : "Plain black; best for OLED screens"
        }
        Separator { visible: Config.s.screensaverStyle === "videos" }
        SettingRow {
            id: vidRow
            visible: Config.s.screensaverStyle === "videos"
            label: "Videos folder"
            // Get scenery videos: twelve free clips (Earth from the ISS, an aurora, lakes,
            // coasts, mountains, penguins…) from Wikimedia Commons (scripts/screensaver-videos.py)
            property string status: ""
            property real progress: 0          // the whole download, 0 to 1
            detail: status !== "" ? status
                : Config.screensaverVideoFolder.replace(Quickshell.env("HOME"), "~") + ": MP4, WebM, MKV or MOV, played in a shuffled order. "
                  + "Get scenery videos adds twelve free clips (credits in the folder's CREDITS.txt)"
            Process {
                id: sceneryRun
                command: [Quickshell.shellPath("scripts/screensaver-videos.py"), Config.screensaverVideoFolder, Config.sceneryQuality]
                stdout: SplitParser {
                    onRead: line => {
                        if (line.startsWith("progress ")) { vidRow.progress = Number(line.slice(9)) || 0; return; }
                        const m = line.match(/^(\d+)\/(\d+) (.*)$/);
                        if (m) vidRow.status = "Downloading " + m[1] + " of " + m[2] + ": " + m[3] + "…";
                        else if (line.startsWith("done ")) vidRow.status = line.slice(5) === "0" ? "Slate couldn't download any videos. Are you online?"
                            : "Got " + line.slice(5) + " scenery videos, in " + Config.screensaverVideoFolder.replace(Quickshell.env("HOME"), "~");
                    }
                }
                onExited: code => { if (code !== 0 && !vidRow.status.startsWith("Got")) vidRow.status = "Slate couldn't download the videos this time"; }
            }
            // How far the download's got: a thin bar along the bottom of the row while it runs
            Rectangle {
                parent: vidRow
                visible: sceneryRun.running
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 16; rightMargin: 16; bottomMargin: 6 }
                height: 4; radius: Config.corner(2)
                color: win.control
                Rectangle {
                    width: Math.max(height, parent.width * vidRow.progress); height: parent.height; radius: Config.corner(2)
                    color: win.accent
                    Behavior on width { NumberAnimation { duration: Config.ms(200) } }
                }
            }
            Row {
                spacing: 8
                Button {
                    icon: 0xEA96; label: sceneryRun.running ? "Downloading…" : "Get scenery videos"
                    opacity: sceneryRun.running ? 0.5 : 1
                    onClicked: if (!sceneryRun.running) { vidRow.status = "Starting…"; vidRow.progress = 0; sceneryRun.running = true; }
                }
                Button {
                    icon: 0xEAAD; label: "Open folder"
                    onClicked: Quickshell.execDetached(["sh", "-c", "mkdir -p \"$0\" && exec xdg-open \"$0\"", Config.screensaverVideoFolder])
                }
            }
        }
        Separator { visible: Config.s.screensaverStyle === "videos" }
        // The size Get scenery videos downloads in (clips without that size come in their
        // largest). Raising it later fetches again only the clips that get sharper
        DropdownSetting {
            visible: Config.s.screensaverStyle === "videos"
            readonly property var names: ({ "2160p": "4K", "1440p": "1440p", "1080p": "1080p" })
            label: "Scenery quality"
            settingKey: "screensaverVideoQuality"
            detail: "For Get scenery videos: sharper is bigger (4K is about 1.1 GB in all, 1440p about 780 MB, 1080p about 410 MB). Choosing a higher one and getting them again replaces only the clips that get sharper"
            options: [{ value: "auto", label: "Automatic (" + names[Config.screenSceneryQuality] + " for this screen)" },
                      { value: "2160p", label: "4K" }, { value: "1440p", label: "1440p" }, { value: "1080p", label: "1080p" }]
            value: Config.s.screensaverVideoQuality || "auto"
            onPicked: v => Config.s.screensaverVideoQuality = v
        }
        Separator {}
        SettingRow {
            label: "Show the clock"
            settingKey: "screensaverClock"
            detail: Config.s.screensaverStyle === "black" ? "The time and date, moving now and then so nothing burns in"
                : "The time and date in the middle"
            SettingToggle { checked: Config.s.screensaverClock; onToggled: v => Config.s.screensaverClock = v }
        }
        Separator { visible: Config.s.screensaverStyle === "slideshow" }
        DropdownSetting {
            visible: Config.s.screensaverStyle === "slideshow"
            label: "Change picture every"
            settingKey: "screensaverSlideSeconds"
            options: [10, 20, 30, 60, 120, 300].map(s => ({ value: s, label: s < 60 ? s + " seconds" : (s / 60) + (s === 60 ? " minute" : " minutes") }))
            value: Config.s.screensaverSlideSeconds
            onPicked: v => Config.s.screensaverSlideSeconds = v
        }
        Separator {}
        ToggleSetting {
            label: "Lock on wake"
            detail: "Waking it shows the lock screen, so you'll need your password to get back in"
            key: "screensaverLock"
        }
        Separator {}
        SettingRow {
            label: "Preview"
            detail: "Shows it now; any key, click or pointer move puts it away (it doesn't lock)"
            // Settings stays open beneath it (the screensaver covers every window), so it's
            // still here when the preview ends
            Button { label: "Preview"; onClicked: Config.slateCall("screensaver", "start") }
        }
    }
}
