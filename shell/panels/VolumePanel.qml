import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs

// ---- Volume ------------------------------------------------------------
Column {
    required property var pop
    id: vol
    width: 300
    spacing: 12
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property var sinks: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream && n.audio)
    PwObjectTracker { objects: [vol.sink, vol.source].concat(vol.sinks) }

    // Nothing to play through or record with (a computer with no sound card, or none
    // found yet): say so, and what brings it back
    PanelTitle { visible: !vol.sink && !vol.source; text: "Sound" }
    Label {
        visible: !vol.sink && !vol.source
        width: parent.width
        wrapMode: Text.Wrap
        font.weight: Font.Normal
        color: pop.dim
        text: "Slate can't find any speakers or a microphone. Plug in speakers, headphones or a headset and they'll show up here"
    }

    Repeater {
        model: [
            { node: vol.sink, title: "Output", on: 0xEB51, off: 0xF1C3 },
            { node: vol.source, title: "Input", on: 0xEAF0, off: 0xED16 }
        ]
        delegate: Column {
            id: audioChannel
            required property var modelData
            readonly property var a: modelData.node && modelData.node.audio ? modelData.node.audio : null
            visible: a !== null
            width: vol.width
            spacing: 6
            Item {
                width: parent.width; height: 22
                Icon {
                    id: muteIcon
                    code: audioChannel.a && audioChannel.a.muted ? audioChannel.modelData.off : audioChannel.modelData.on
                    color: audioChannel.a && audioChannel.a.muted ? pop.danger : pop.text
                    anchors.verticalCenter: parent.verticalCenter
                    function toggle() { const a = audioChannel.a; if (a) a.muted = !a.muted; }
                    ClickTap { onTapped: muteIcon.toggle() }
                    // (the keyboard and a screen reader: a switch, on while it's muted)
                    Accessible.role: Accessible.CheckBox
                    Accessible.name: audioChannel.modelData.title === "Output" ? "Mute the sound" : "Mute the microphone"
                    Accessible.checkable: true
                    Accessible.checked: !!audioChannel.a && audioChannel.a.muted
                    Accessible.onToggleAction: muteIcon.toggle()
                    Accessible.onPressAction: muteIcon.toggle()
                    activeFocusOnTab: visible
                    Keys.onPressed: e => {
                        if (e.key !== Qt.Key_Return && e.key !== Qt.Key_Enter && e.key !== Qt.Key_Space) return;
                        muteIcon.toggle();
                        e.accepted = true;
                    }
                    FocusRing { round: 6 }
                }
                Label {
                    anchors { left: muteIcon.right; leftMargin: 8; verticalCenter: parent.verticalCenter }
                    text: audioChannel.modelData.title
                }
                Label {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    text: audioChannel.a ? Math.round(audioChannel.a.volume * 100) + "%" : ""
                    color: pop.dim
                }
            }
            Slider {
                width: parent.width
                value: parent.a ? parent.a.volume : 0
                muted: parent.a ? parent.a.muted : false
                busy: !!audioChannel.modelData.node && pop.audioBusy[audioChannel.modelData.node.name] === true
                Accessible.name: audioChannel.modelData.title === "Output" ? "Volume" : "Microphone volume"
                onMoved: v => { const a = parent.a; if (a) { a.muted = false; a.volume = v; } }
            }
        }
    }

    Divider { visible: vol.sinks.length > 1 }
    Heading { visible: vol.sinks.length > 1; text: "Output device" }
    Column {
        visible: vol.sinks.length > 1
        width: parent.width
        spacing: 6
        Repeater {
            // (a row for each device, kept while it's there: handed the list itself, every
            // row was made again whenever anything started or stopped playing)
            model: ScriptModel { values: vol.sinks }
            delegate: RowButton {
                required property var modelData
                width: parent.width
                selected: vol.sink && vol.sink.id === modelData.id
                // Short name ("Speaker", "Headphones") rather than the sound card's long one
                readonly property string shortName: (modelData.properties && modelData.properties["device.profile.description"])
                    || modelData.nickname || modelData.description || modelData.name
                onClicked: Pipewire.preferredDefaultAudioSink = modelData
                Icon {
                    id: devIcon
                    code: parent.shortName.toLowerCase().includes("head") ? 0xEABD : 0xEA8B
                    color: parent.fg
                    Behavior on color { ColorAnimation { duration: Config.ms(120) } }
                    font.pixelSize: 16
                    anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                }
                Label {
                    anchors { left: devIcon.right; leftMargin: 10; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    text: parent.shortName
                    color: parent.fg
                    Behavior on color { ColorAnimation { duration: Config.ms(120) } }
                }
            }
        }
    }
}
