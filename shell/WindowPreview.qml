// A window, live: every live window preview in Slate (the overview, the window switcher, the dock's
// previews, New Space) is one of these. Use it in place of a ScreencopyView:
//   WindowPreview { window: toplevel.wayland; address: toplevel.address; running: panel.shown }
// window: the window's Wayland handle (a HyprlandToplevel's .wayland, or a Toplevel); address:
// its Hyprland address (with or without "0x"), so it's never captured again once Hyprland says
// it's closing; running: keep it moving (otherwise it holds its last frame).
//
// Frames are asked for by Slate, one at a time, not with Quickshell's live mode, and nothing is
// captured for a moment after any window closes (PreviewHold.qml): a capture of a window Hyprland
// had just closed killed Slate ("The Wayland connection experienced a fatal error: Invalid
// argument"; closing several windows at once while New Space, the overview, the switcher or the
// dock's previews showed them). It's Quickshell's and Hyprland's (quickshell-mirror/quickshell#1481,
// and #1123; docs/ARCHITECTURE.md, "Workarounds for bugs elsewhere", says how to check a new
// Quickshell and go back to live mode).

import QtQuick
import Quickshell.Wayland

ScreencopyView {
    id: wp
    property var window: null
    property string address: ""
    property bool running: false
    // Frames a second while running (the windows' own rate is far more than a preview needs)
    property int rate: 30
    // Closing: its Toplevel said closed (just before Quickshell deletes it), or Hyprland's
    // closewindow named it (PreviewHold.closing). Kept for this window (closedWindow) once its
    // address is forgotten or can't be looked up any more.
    readonly property string addr: String(address).replace(/^0x/, "")
    readonly property bool closingNow: addr !== "" && PreviewHold.closing[addr] === true
    property var closedWindow: null
    readonly property bool closing: closingNow || (!!window && window === closedWindow)
    onClosingNowChanged: if (closingNow) closedWindow = window
    Component.onCompleted: { if (closingNow) closedWindow = window; pickSource(); }
    Connections {
        target: wp.window
        ignoreUnknownSignals: true
        function onClosed() { wp.closedWindow = wp.window; }
    }
    onClosingChanged: { if (closing && window) PreviewHold.testStopped++; pickSource(); }
    // A capture starts only outside the moment after a window closes; one already started keeps
    // its source (it asks for nothing until the Timer does). Set here rather than bound: what
    // it depends on changes as the source is set (a binding loop).
    property var startedFor: null
    function pickSource() {
        const want = !closing && window && (window === startedFor || !PreviewHold.held) ? window : null;
        if (want) startedFor = want;
        if (captureSource !== want) captureSource = want;
    }
    onWindowChanged: pickSource()
    Connections { target: PreviewHold; function onHeldChanged() { wp.pickSource(); } }
    live: false
    // The first frame comes by itself as the capture starts; the next are asked for once it's
    // here (asked for sooner, each request started the first over, and on a real graphics card,
    // where the first takes longest, it was half a second coming)
    Timer {
        interval: Math.round(1000 / Math.max(1, wp.rate))
        repeat: true
        running: wp.running && !wp.closing && !PreviewHold.held && !!wp.captureSource && wp.hasContent
        // (checked again right before asking: a window may have started closing since)
        onTriggered: if (!wp.closing && !PreviewHold.held && wp.window && wp.captureSource === wp.window) wp.captureFrame()
    }
}
