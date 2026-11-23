import QtQuick
import Quickshell.Services.Pipewire
import "../.."
import ".."

// ---- Sound ------------------------------------------------------------------
Column {
    readonly property var win: SettingsHost.win
    id: soundPane
    spacing: 4
    PageTitle { text: "Sound" }
    readonly property var sinks: Pipewire.nodes.values.filter(n => n.audio && n.isSink && !n.isStream)
    readonly property var sources: Pipewire.nodes.values.filter(n => n.audio && !n.isSink && !n.isStream)
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    PwObjectTracker { objects: [soundPane.sink, soundPane.source] }
    function nodeName(n) { return n ? (n.description || n.nickname || n.name) : ""; }

    // Private Mode keeps every microphone muted (PrivateMode.qml): said here, so the
    // microphone's mute staying on makes sense
    GroupLabel { visible: Config.s.privateMode; text: "Private Mode" }
    Group {
        visible: Config.s.privateMode
        SettingRow {
            label: "Private Mode is on"
            detail: "Your microphones are muted and stay that way until you turn it off. Your speakers and Slate's sounds work as usual."
            Button { label: "Turn off"; icon: 0xF227; onClicked: Config.setPrivateMode(false) }
        }
    }

    GroupLabel { text: "Output" }
    Group {
        DropdownSetting {
            label: "Play sound through"
            noneLabel: "None found"          // (no speakers or headphones: not "-1")
            options: soundPane.sinks.map(n => ({ value: n.id, label: soundPane.nodeName(n) }))
            value: soundPane.sink ? soundPane.sink.id : -1
            onPicked: v => { const n = soundPane.sinks.find(x => x.id === v); if (n) Pipewire.preferredDefaultAudioSink = n; }
        }
        Separator {}
        SettingRow {
            label: "Volume"
            ValueSlider {
                from: 0; to: 100; stepSize: 1; suffix: "%"
                value: soundPane.sink && soundPane.sink.audio ? Math.round(soundPane.sink.audio.volume * 100) : 0
                onMoved: v => { if (soundPane.sink && soundPane.sink.audio) soundPane.sink.audio.volume = v / 100; }
            }
        }
        Separator {}
        SettingRow {
            label: "Mute"
            SettingToggle {
                checked: !!(soundPane.sink && soundPane.sink.audio && soundPane.sink.audio.muted)
                onToggled: v => { if (soundPane.sink && soundPane.sink.audio) soundPane.sink.audio.muted = v; }
            }
        }
    }
    GroupLabel { text: "Input" }
    Group {
        DropdownSetting {
            label: "Microphone"
            noneLabel: "None found"
            options: soundPane.sources.map(n => ({ value: n.id, label: soundPane.nodeName(n) }))
            value: soundPane.source ? soundPane.source.id : -1
            onPicked: v => { const n = soundPane.sources.find(x => x.id === v); if (n) Pipewire.preferredDefaultAudioSource = n; }
        }
        Separator {}
        SettingRow {
            label: "Input level"
            ValueSlider {
                from: 0; to: 100; stepSize: 1; suffix: "%"
                value: soundPane.source && soundPane.source.audio ? Math.round(soundPane.source.audio.volume * 100) : 0
                onMoved: v => { if (soundPane.source && soundPane.source.audio) soundPane.source.audio.volume = v / 100; }
            }
        }
        Separator {}
        SettingRow {
            label: "Mute the microphone"
            // (Private Mode keeps it muted: its own row, at the top of this page, turns it off)
            needsMet: !Config.s.privateMode
            needs: "Muted while Private Mode is on"
            needsPage: "sound"; needsLabel: "Private Mode is on"
            SettingToggle {
                checked: !!(soundPane.source && soundPane.source.audio && soundPane.source.audio.muted)
                onToggled: v => { if (soundPane.source && soundPane.source.audio) soundPane.source.audio.muted = v; }
            }
        }
    }
    GroupLabel { text: "Sound effects" }
    Group {
        SoundSetting {
            label: "Volume keys"
            detail: "A short tick at the new volume when you press the volume keys"
            which: "tick"; sample: "volume-tick"
        }
        Separator {}
        SoundSetting {
            label: "Notifications"
            detail: "A soft chime when a notification pops up (silent during Do Not Disturb)"
            which: "notification"; sample: "notification"
        }
        Separator {}
        SoundSetting {
            label: "Questions and warnings"
            detail: "A soft, questioning sound when Slate asks you to confirm something, an app asks for your password, or a notification is urgent"
            which: "attention"; sample: "attention"
        }
        Separator {}
        SoundSetting {
            label: "Nova's answer"
            detail: "A soft, warm tone when an answer arrives while Nova's window is open (if you've closed it, a notification tells you instead)"
            which: "answered"; sample: "answered"
        }
        Separator {}
        SoundSetting {
            label: "Clicks"
            detail: Config.clickAvailable ? "A barely-there tap when you press Slate's buttons, menus and switches"
                                          : "Needs Qt Multimedia" + Packages.named("qtmultimedia") + ", so the click is on time"
            which: "click"; sample: "click"; available: Config.clickAvailable
        }
        Separator {}
        SoundSetting {
            label: "Switching"
            detail: "A soft swish when you change workspace or move through the window switcher and overview, drifting the way you're going"
            which: "swish"; sample: "swish-right"
        }
        Separator {}
        SoundSetting {
            label: "Welcome"
            detail: "A gentle, warm swell when you log in (not when Slate reloads)"
            which: "welcome"; sample: "welcome"
        }
        Separator {}
        SoundSetting {
            label: "Goodbye"
            detail: "A gentle closing sound when you log out, restart or shut down (it plays first, so they take a moment longer)"
            which: "goodbye"; sample: "goodbye"
        }
    }
}
