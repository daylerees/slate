// A window, live: every live window preview in Slate (the overview, the window switcher, the dock's
// previews, New Space) is one of these. Use it in place of a ScreencopyView:
//   WindowPreview { window: toplevel.wayland; running: panel.shown }
// window: the window's Wayland handle (a HyprlandToplevel's .wayland, or a Toplevel); running:
// keep it moving (otherwise it holds its last frame).
//
// Frames are asked for by Slate, one at a time, not with Quickshell's live mode: live captures of
// windows coming and going killed Slate ("The Wayland connection experienced a fatal error:
// Invalid argument"; closing several windows at once while New Space or the overview showed them).
// It's Quickshell's (quickshell-mirror/quickshell#1123; docs/ARCHITECTURE.md, "Workarounds for bugs
// elsewhere", says how to check a new Quickshell and go back to live mode).

import QtQuick
import Quickshell.Wayland

ScreencopyView {
    id: wp
    property var window: null
    property bool running: false
    // Frames a second while running (the windows' own rate is far more than a preview needs)
    property int rate: 30
    captureSource: window ?? null
    live: false
    // The first frame comes by itself as the capture starts; the next are asked for once it's
    // here (asked for sooner, each request started the first over, and on a real graphics card,
    // where the first takes longest, it was half a second coming)
    Timer {
        interval: Math.round(1000 / Math.max(1, wp.rate))
        repeat: true
        running: wp.running && !!wp.captureSource && wp.hasContent
        onTriggered: if (wp.captureSource) wp.captureFrame()
    }
}
