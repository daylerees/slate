import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Qt.labs.folderlistmodel
import "../.."
import ".."

// ---- Webcam ----------------------------------------------------------------
// The camera's picture settings, through scripts/webcam.py (v4l2-ctl). Changes apply at
// once; cameras forget them when unplugged or restarted, so they're remembered and put
// back at login (Config: webcam.py apply)
Column {
    readonly property var win: SettingsHost.win
    id: camPane
    spacing: 4
    readonly property string script: Quickshell.shellPath("scripts/webcam.py")
    property var cams: []
    property string error: ""
    property bool looked: false
    property string chosen: ""
    readonly property var cam: cams.find(c => c.device === chosen) || cams[0] || null
    property bool preview: false          // the camera (and its light) only on when asked
    property var usedBy: []
    // (the tests: what it shows, and the cameras handed to it, as the container has none)
    readonly property var testState: ({ cams: cams.length, preview: preview,
                                        previewLoaded: previewLoader.status === Loader.Ready,
                                        previewFailed: previewLoader.status === Loader.Error })
    function testPretend(d) { if (d.cams) { cams = d.cams; looked = true; } if (d.preview !== undefined) preview = d.preview; }
    // Plain words for the camera's own names for its settings: [label, detail]
    readonly property var words: ({
        brightness: ["Brightness", ""],
        contrast: ["Contrast", ""],
        saturation: ["Color", "How vivid colors are"],
        sharpness: ["Sharpness", ""],
        gain: ["Gain", "Brightens a dim picture, at the cost of more grain"],
        gamma: ["Gamma", "Brightens or darkens the middle tones"],
        white_balance_temperature: ["Color temperature", "Lower is warmer, higher is cooler"],
        exposure_time_absolute: ["Exposure", "How long each frame gathers light: longer is brighter, but blurs movement"],
        backlight_compensation: ["Backlight compensation", "Brightens you when there's a bright light behind you"]
    })

    function refresh() { listProc.running = false; listProc.running = true; }
    function ctrl(name) { return cam ? cam.controls.find(c => c.name === name) || null : null; }
    // Change a setting: shown at once, sent a moment later (a slider moves many times)
    property var pending: ({})
    function setCtrl(name, value) {
        const copy = JSON.parse(JSON.stringify(cams));
        const c = copy.find(x => x.device === cam.device);
        const k = c ? c.controls.find(x => x.name === name) : null;
        if (k) k.value = Math.round(value);
        cams = copy;
        const p = Object.assign({}, pending);
        p[name] = Math.round(value);
        pending = p;
        sendSoon.restart();
    }
    Timer {
        id: sendSoon
        interval: 120
        onTriggered: {
            for (const n in camPane.pending)
                Quickshell.execDetached([camPane.script, "set", camPane.cam.device, n, String(camPane.pending[n])]);
            camPane.pending = {};
            readBack.restart();
        }
    }
    // (switching automatic white balance or exposure off makes their manual setting usable)
    Timer { id: readBack; interval: 500; onTriggered: camPane.refresh() }
    FirstLook {
        id: listProc
        running: true
        command: [camPane.script, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    if (Array.isArray(d)) { camPane.cams = d; camPane.error = ""; } else camPane.error = d.error || "";
                } catch (e) { camPane.error = "Slate couldn't read the webcams"; }
                camPane.looked = true;
            }
        }
    }
    Process {
        id: resetProc
        onExited: camPane.refresh()
    }
    // Who's using a camera, looked at again now and then while the page shows
    Process {
        id: usersProc
        running: true
        command: [camPane.script, "users"]
        stdout: StdioCollector { onStreamFinished: { try { camPane.usedBy = JSON.parse(text); } catch (e) {} } }
    }
    Timer { interval: 3000; repeat: true; running: win.visible; onTriggered: { usersProc.running = false; usersProc.running = true; } }
    // Restore defaults (the page title's): the camera's own defaults
    readonly property bool changed: !!cam && cam.controls.some(c => c.default !== undefined && c.value !== c.default)
    function reset() { if (cam) { resetProc.command = [script, "reset", cam.device]; resetProc.running = true; } }
    Binding { target: win; property: "pageResetChanged"; value: camPane.changed }
    Component.onCompleted: win.pageResetRun = () => camPane.reset()
    Component.onDestruction: win.pageResetRun = null

    PageTitle { text: "Webcam" }
    IntroText { text: "Your camera's picture. Changes apply straight away, to every app that uses the camera, and are kept when it's unplugged or the computer restarts." }

    // Private Mode turns the camera off for every app, this page included (PrivateMode.qml):
    // said instead of the camera's settings, which can't be reached until it's off. Looked
    // at again once it's turned off (the camera takes a moment to come back)
    readonly property bool privateOn: Config.s.privateMode
    onPrivateOnChanged: { if (!privateOn) lookAgain.restart(); else preview = false; }
    Timer { id: lookAgain; interval: 1500; onTriggered: camPane.refresh() }
    GroupLabel { visible: camPane.privateOn; text: "Private Mode" }
    Group {
        visible: camPane.privateOn
        SettingRow {
            label: "Private Mode is on"
            detail: "Your camera is off for every app until you turn it off, so its picture and settings aren't here for now."
            Button { label: "Turn off"; icon: 0xF227; onClicked: Config.setPrivateMode(false) }
        }
    }

    GroupLabel { visible: camPane.looked && !camPane.privateOn; text: "Camera" }
    // Nothing to show
    Group {
        visible: camPane.looked && !camPane.privateOn && (camPane.error !== "" || camPane.cams.length === 0)
        SettingRow {
            label: camPane.error !== "" ? "Slate can't reach the camera" : "No webcam found"
            detail: camPane.error !== "" ? camPane.error : "Plug one in, or check it isn't switched off (some laptops have a key or a slider for it)"
            Button { label: "Look again"; icon: 0xEB13; onClicked: camPane.refresh() }
        }
    }

    // ---- Preview -------------------------------------------------------------
    Group {
        visible: !!camPane.cam && !camPane.privateOn
        Item {
            width: parent.width
            height: Math.round(Math.min(width * 9 / 16, 320)) + 16
            Rectangle {
                id: previewBox
                anchors { fill: parent; margins: 8 }
                radius: Config.corner(10)
                color: Qt.rgba(0, 0, 0, 0.35)
                clip: true
                Loader {
                    id: previewLoader
                    anchors.fill: parent
                    active: camPane.preview && win.visible && !!camPane.cam
                    source: Quickshell.shellPath("WebcamPreview.qml")    // (in Slate's own folder, not this page's)
                    onLoaded: item.device = Qt.binding(() => camPane.cam ? camPane.cam.device : "")
                }
                Text {
                    anchors.centerIn: parent
                    width: parent.width - 40
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    visible: !(previewLoader.item && previewLoader.item.showing)
                    color: win.dim
                    font.family: win.font; font.pixelSize: Config.text(13)
                    text: !camPane.preview ? "The preview is off, so the camera isn't on"
                        : previewLoader.status === Loader.Error ? "The preview needs Qt Multimedia" + Packages.named("qtmultimedia")
                        : previewLoader.item && previewLoader.item.problem !== "" ? "No picture: " + previewLoader.item.problem
                        : "Starting the camera…"
                }
            }
        }
        SettingRow {
            label: "Preview"
            detail: "Shows the camera here. Its light comes on while it's shown"
            SettingToggle { checked: camPane.preview; onToggled: v => camPane.preview = v }
        }
        Separator { visible: camPane.cams.length > 1 }
        DropdownSetting {
            visible: camPane.cams.length > 1
            label: "Camera"
            options: camPane.cams.map(c => ({ value: c.device, label: c.name }))
            value: camPane.cam ? camPane.cam.device : ""
            onPicked: v => camPane.chosen = v
        }
        Separator {}
        SettingRow {
            label: "In use by"
            detail: camPane.usedBy.length === 0 ? "No app is using the camera"
                : camPane.usedBy.map(u => u.name).filter((n, i, a) => a.indexOf(n) === i).join(", ")
        }
    }

    // ---- Picture -------------------------------------------------------------
    GroupLabel { visible: !!camPane.cam && !camPane.privateOn; text: "Picture" }
    Group {
        visible: !!camPane.cam && !camPane.privateOn
        Repeater {
            model: ["brightness", "contrast", "saturation", "sharpness", "gain", "gamma"].filter(n => !!camPane.ctrl(n))
            delegate: Column {
                required property string modelData
                required property int index
                width: parent.width
                readonly property var c: camPane.ctrl(modelData)
                Separator { visible: index > 0 }
                SettingRow {
                    label: camPane.words[modelData][0]
                    detail: camPane.words[modelData][1]
                    ValueSlider {
                        from: c ? c.min : 0; to: c ? c.max : 1; stepSize: c ? c.step : 1
                        value: c ? c.value : 0
                        onMoved: v => camPane.setCtrl(modelData, v)
                    }
                }
            }
        }
    }

    // ---- Light -------------------------------------------------------------
    GroupLabel { visible: !!camPane.cam && !camPane.privateOn; text: "Light" }
    Group {
        visible: !!camPane.cam && !camPane.privateOn
        SettingRow {
            visible: !!camPane.ctrl("white_balance_automatic")
            label: "Automatic white balance"
            detail: "Adjusts the colors to the light in the room. Off: set the color temperature yourself"
            SettingToggle {
                checked: camPane.ctrl("white_balance_automatic") ? camPane.ctrl("white_balance_automatic").value === 1 : true
                onToggled: v => camPane.setCtrl("white_balance_automatic", v ? 1 : 0)
            }
        }
        Separator { visible: !!camPane.ctrl("white_balance_temperature") && !!camPane.ctrl("white_balance_automatic") && camPane.ctrl("white_balance_automatic").value === 0 }
        SettingRow {
            readonly property var c: camPane.ctrl("white_balance_temperature")
            visible: !!c && !!camPane.ctrl("white_balance_automatic") && camPane.ctrl("white_balance_automatic").value === 0
            label: camPane.words.white_balance_temperature[0]
            detail: camPane.words.white_balance_temperature[1]
            ValueSlider {
                from: parent.c ? parent.c.min : 0; to: parent.c ? parent.c.max : 1; stepSize: parent.c ? parent.c.step : 1
                suffix: " K"; value: parent.c ? parent.c.value : 0
                onMoved: v => camPane.setCtrl("white_balance_temperature", v)
            }
        }
        Separator { visible: !!camPane.ctrl("auto_exposure") }
        SettingRow {
            readonly property var c: camPane.ctrl("auto_exposure")
            visible: !!c
            label: "Automatic exposure"
            detail: "Adjusts how bright the picture is to the light. Off: set the exposure yourself"
            SettingToggle {
                // (1 is manual on every camera; the automatic one varies: the camera's default)
                checked: parent.c ? parent.c.value !== 1 : true
                onToggled: v => camPane.setCtrl("auto_exposure", v ? (parent.c.default !== 1 ? parent.c.default : 3) : 1)
            }
        }
        Separator { visible: !!camPane.ctrl("exposure_time_absolute") && !!camPane.ctrl("auto_exposure") && camPane.ctrl("auto_exposure").value === 1 }
        SettingRow {
            readonly property var c: camPane.ctrl("exposure_time_absolute")
            visible: !!c && !!camPane.ctrl("auto_exposure") && camPane.ctrl("auto_exposure").value === 1
            label: camPane.words.exposure_time_absolute[0]
            detail: camPane.words.exposure_time_absolute[1]
            ValueSlider {
                from: parent.c ? parent.c.min : 0; to: parent.c ? parent.c.max : 1; stepSize: parent.c ? parent.c.step : 1
                value: parent.c ? parent.c.value : 0
                onMoved: v => camPane.setCtrl("exposure_time_absolute", v)
            }
        }
        Separator { visible: !!camPane.ctrl("power_line_frequency") }
        DropdownSetting {
            readonly property var c: camPane.ctrl("power_line_frequency")
            visible: !!c
            label: "Anti-flicker"
            detail: "Match your mains electricity to stop lights flickering in the picture: 50 Hz in the UK, Europe and most of the world, 60 Hz in North America"
            options: c ? c.options.map(o => ({ value: o[0], label: o[1] === "Disabled" ? "Off" : o[1] })) : []
            value: c ? c.value : 0
            onPicked: v => camPane.setCtrl("power_line_frequency", v)
        }
        Separator { visible: !!camPane.ctrl("backlight_compensation") }
        SettingRow {
            readonly property var c: camPane.ctrl("backlight_compensation")
            visible: !!c
            label: camPane.words.backlight_compensation[0]
            detail: camPane.words.backlight_compensation[1]
            ValueSlider {
                from: parent.c ? parent.c.min : 0; to: parent.c ? parent.c.max : 1; stepSize: parent.c ? parent.c.step : 1
                zeroText: "Off"; value: parent.c ? parent.c.value : 0
                onMoved: v => camPane.setCtrl("backlight_compensation", v)
            }
        }
    }
}
