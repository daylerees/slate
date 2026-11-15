// The dock's window previews: resting on an app's icon shows its windows beside it, as live
// pictures or as titles (Settings → Dock → Window previews), with a "+N" card for any that
// don't fit. Click one to go to it. Dock.qml places it (atX, atY) and says whose windows to
// show (dock.previewApp); this draws them.

import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: previews
    required property var dock          // the dock (Dock.qml)
    // The pointer has left the previews (the dock waits a moment, then closes them)
    signal left()
    screen: dock.screen
    property real atX: 0          // by the icon, just off the dock (screen coordinates)
    property real atY: 0
    // Open for this app; fading in and out (the last app's windows stay on it while it fades)
    readonly property bool wanted: !!dock.previewApp && dock.previewApp.windows.length > 0 && dock.dragKey === ""
    property var shownApp: null
    onWantedChanged: if (wanted) shownApp = dock.previewApp
    Connections { target: previews.dock; function onPreviewAppChanged() { if (previews.wanted) previews.shownApp = dock.previewApp; } }
    readonly property var wins: shownApp ? shownApp.windows : []
    property real fade: wanted ? 1 : 0
    Behavior on fade { NumberAnimation { duration: Config.ms(180); easing.type: Easing.OutCubic } }
    onFadeChanged: if (fade === 0 && !wanted) shownApp = null
    visible: wanted || fade > 0
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "slate-dock-previews"
    WlrLayershell.layer: WlrLayer.Overlay
    // Only the panel takes the pointer, and nothing once it's going
    mask: wanted ? boxRegion : noRegion
    Region { id: boxRegion; item: previewBox }
    Region { id: noRegion }
    // The panel (for the dock's test state)
    readonly property Item box: previewBox

    // A card's size: live pictures are wider than title-only cards
    readonly property real cardW: dock.previewMode === "live" ? 220 : 200
    readonly property real cardH: dock.previewMode === "live" ? 160 : 48
    // At most six cards, and never more than fit beside the icon (along the screen for
    // live pictures, from the icon to the screen's far side when the dock's on one; down
    // the screen for titles). An app with more windows than that shows as many as fit
    // with room for one more card, which says how many it has besides and opens the
    // app's menu, where every one of its windows is listed
    readonly property int cap: 6
    readonly property real moreW: 110            // the live "+N" card: narrower than a picture
    readonly property bool live: dock.previewMode === "live"
    readonly property real room: live
        ? (dock.edge === "left" ? width - atX - 8 : dock.edge === "right" ? atX - 8 : width - 16) - 16
        : height - 16 - 12
    readonly property bool capped: wins.length > cap
        || (live ? wins.length * (cardW + 8) - 8 : wins.length * (cardH + 4) - 4) > room
    // How many windows get a card, the "+N" card standing in for the rest
    readonly property int fitCount: !capped ? wins.length
        : Math.max(1, Math.min(cap - 1, live ? Math.floor((room - moreW) / (cardW + 8))
                                             : Math.floor((room + 4) / (cardH + 4)) - 1))
    // The first ones, in the dock's order, the window you're in always among them
    readonly property var shownWins: {
        if (!capped) return wins;
        const s = wins.slice(0, fitCount);
        const now = wins.find(w => w.activated);
        if (now && !s.includes(now)) s[s.length - 1] = now;
        return s;
    }
    readonly property int moreCount: wins.length - shownWins.length

    Rectangle {
        id: previewBox
        width: previews.live ? previewRow.implicitWidth + 16 : previews.cardW + 16
        height: previews.live ? previews.cardH + 16 : titleCol.implicitHeight + 12
        x: Math.max(8, Math.min(previews.width - width - 8,
            dock.edge === "left" ? previews.atX : dock.edge === "right" ? previews.atX - width : previews.atX - width / 2))
        y: Math.max(8, Math.min(previews.height - height - 8,
            dock.edge === "bottom" ? previews.atY - height : dock.edge === "top" ? previews.atY : previews.atY - height / 2))
        radius: Config.corner(12)
        color: dock.bgColor
        opacity: previews.fade
        Shadow {}                // raised: Slate's shadow, with glass too
        // Grows out of the icon as it fades in, and back into it as it fades out
        transform: Scale {
            origin.x: Math.max(0, Math.min(previewBox.width, previews.atX - previewBox.x))
            origin.y: Math.max(0, Math.min(previewBox.height, previews.atY - previewBox.y))
            xScale: 0.82 + 0.18 * previews.fade
            yScale: xScale
        }
        Gloss { radius: parent.radius }   // glass: a sheen
        HoverHandler {
            onHoveredChanged: { dock.previewHeld = hovered; if (!hovered) previews.left(); }
        }

        // Live: the windows side by side, then "+N" for the rest
        Row {
            id: previewRow
            visible: previews.live
            x: 8; y: 8
            spacing: 8
            Repeater {
                model: previews.live ? previews.shownWins : []
                delegate: Rectangle {
                    id: liveCard
                    required property var modelData
                    width: previews.cardW; height: previews.cardH
                    radius: Config.corner(8)
                    color: liveHover.hovered ? Config.hover : "transparent"
                    Behavior on color { ColorAnimation { duration: Config.ms(90) } }
                    Gloss { radius: parent.radius; opacity: liveHover.hovered ? 1 : 0 }
                    WindowPreview {
                        id: liveShot
                        readonly property real ratio: sourceSize.height > 0 ? sourceSize.width / sourceSize.height : 16 / 10
                        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 6 }
                        width: Math.min(parent.width - 12, (parent.height - 34) * ratio)
                        height: width / ratio
                        window: previews.visible ? liveCard.modelData : null
                        running: previews.wanted          // (still while it fades out)
                        // Rounded, and brightened back if Hyprland dims it (it isn't focused)
                        layer.enabled: true
                        layer.effect: PreviewShape { radius: Config.corner(6); gain: Config.undimGain(liveCard.modelData.activated, liveCard.modelData.appId) }
                    }
                    Text {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 8; bottomMargin: 6 }
                        horizontalAlignment: Text.AlignHCenter
                        textFormat: Text.PlainText        // never markup: the window's title is the app's to choose
                        text: liveCard.modelData.title || ""
                        elide: Text.ElideRight
                        color: liveCard.modelData.activated ? dock.activeDotColor : dock.textColor
                        font.family: Config.s.fontFamily; font.pixelSize: 12; font.weight: Font.Medium
                    }
                    HoverHandler { id: liveHover }
                    ClickTap { hand: false; onTapped: { liveCard.modelData.activate(); dock.previewApp = null; } }
                }
            }
            // The rest: a card of the same shape (no sheen), "+N" where the picture would
            // be, on the dock's own tile colour, and its caption below. Only says how many:
            // not something to click (the app's right-click menu lists every window)
            Rectangle {
                id: moreCard
                visible: previews.moreCount > 0
                width: previews.moreW; height: previews.cardH
                radius: Config.corner(8)
                color: "transparent"
                Rectangle {
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
                    height: parent.height - 34
                    radius: Config.corner(6)
                    color: dock.tileColor
                    Text {
                        anchors.centerIn: parent
                        text: "+" + previews.moreCount
                        color: dock.textColor
                        font.family: Config.s.fontFamily; font.pixelSize: 22; font.weight: Font.Medium
                    }
                }
                Text {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 8; bottomMargin: 6 }
                    horizontalAlignment: Text.AlignHCenter
                    text: "More windows"
                    elide: Text.ElideRight
                    color: dock.textColor
                    font.family: Config.s.fontFamily; font.pixelSize: 12; font.weight: Font.Medium
                }
            }
        }

        // Titles: the windows one above another, each with the app's icon, then a row
        // for the rest in the same way
        Column {
            id: titleCol
            visible: !previews.live
            x: 6; y: 6
            width: previewBox.width - 12
            spacing: 4
            Repeater {
                model: !previews.live ? previews.shownWins : []
                delegate: Rectangle {
                    id: titleCard
                    required property var modelData
                    width: titleCol.width; height: previews.cardH
                    radius: Config.corner(8)
                    color: titleHover.hovered ? Config.hover : "transparent"
                    Behavior on color { ColorAnimation { duration: Config.ms(90) } }
                    Gloss { radius: parent.radius; opacity: titleHover.hovered ? 1 : 0 }
                    AppTile {
                        id: titleIcon
                        anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                        width: 28; height: 28
                        app: dock.previewApp ? (dock.previewApp.entry ? dock.previewApp.entry.id : dock.previewApp.key) : ""
                    }
                    Text {
                        anchors { left: titleIcon.right; leftMargin: 10; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        textFormat: Text.PlainText        // never markup: the window's title is the app's to choose
                        text: titleCard.modelData.title || ""
                        elide: Text.ElideRight
                        color: titleCard.modelData.activated ? dock.activeDotColor : dock.textColor
                        font.family: Config.s.fontFamily; font.pixelSize: 13; font.weight: Font.Medium
                    }
                    HoverHandler { id: titleHover }
                    ClickTap { hand: false; onTapped: { titleCard.modelData.activate(); dock.previewApp = null; } }
                }
            }
            Rectangle {
                id: moreRow
                visible: !previews.live && previews.moreCount > 0
                width: titleCol.width; height: previews.cardH
                radius: Config.corner(8)
                color: "transparent"
                Rectangle {
                    id: moreRowTile
                    anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                    width: 28; height: 28
                    radius: Config.corner(6)
                    color: dock.tileColor
                    Text {
                        anchors.centerIn: parent
                        text: "+" + previews.moreCount
                        color: dock.textColor
                        font.family: Config.s.fontFamily; font.pixelSize: 12; font.weight: Font.Medium
                    }
                }
                Text {
                    anchors { left: moreRowTile.right; leftMargin: 10; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    text: "More windows"
                    elide: Text.ElideRight
                    color: dock.textColor
                    font.family: Config.s.fontFamily; font.pixelSize: 13; font.weight: Font.Medium
                }
            }
        }
    }
}
