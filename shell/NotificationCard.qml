// One notification: app tile (or the notification's own image), app name and time,
// title, message and action buttons. Used by the pop-ups and the bell panel.

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io

Rectangle {
    id: card
    required property var bar
    property var entry: null           // saved history item
    property var notif: null           // live notification, if the app is still listening
    property bool critical: false
    property bool inPanel: false       // in the bell panel: flatter look
    property real progress: -1         // pop-ups: time left (1 → 0) for the timeout bar; -1 = none
    property bool fresh: false         // pop-ups: just arrived (accent dot by the app name)
    signal activated()
    signal closed()
    signal action(string id)

    readonly property color textColor: bar.textColor
    readonly property color dim: Config.tint("#8b94a3")
    readonly property string tileDir: Config.tileDir
    readonly property string tilePath: entry && entry.entryId ? tileDir + "/" + entry.entryId.replace(/[^A-Za-z0-9._-]/g, "_") + ".png" : ""
    readonly property var actions: notif ? notif.actions.filter(a => a.identifier !== "default" && a.text) : []
    readonly property color accent: bar.accent
    // A picture from a file (screenshots, album art…) gets a large preview under the text, with
    // the app's icon beside it; other images (chat avatars) stay as the icon
    readonly property string image: entry && entry.image ? entry.image : ""
    // A file path, however the app passed it ("file://…", "/…", or Quickshell's "image://icon//…")
    readonly property string imageFile: image.startsWith("file://") ? image.slice(7)
        : image.startsWith("image://icon//") ? image.slice(13)
        : image.startsWith("/") ? image : ""
    // …if it's big enough to be a picture: a small one (an icon given as a file, like
    // notify-send --icon=/path) stays the small icon rather than stretched into a preview
    readonly property bool preview: imageFile !== "" && sizeProbe.status === Image.Ready
        && Math.max(sizeProbe.implicitWidth, sizeProbe.implicitHeight) >= 200
    Image {
        id: sizeProbe
        visible: false
        asynchronous: true
        sourceSize: Qt.size(256, 256)   // enough to tell (small icons aren't scaled up)
        source: card.imageFile !== "" ? "file://" + card.imageFile : ""
    }

    readonly property real band: critical && !inPanel ? 3.5 : 0   // red band across the top (urgent pop-ups only)
    readonly property bool hasTimer: progress >= 0
    implicitHeight: band + content.height + 24 + (hasTimer ? 14 : 0)
    height: implicitHeight
    radius: 9
    color: inPanel ? (cardHover.hovered ? Config.hoverOn(bar.capsuleColor) : bar.capsuleColor) : bar.barColor
    Gloss { radius: parent.radius }   // glass: a sheen
    Behavior on color { ColorAnimation { duration: 100 } }
    // Pop-ups float a little: a light drop shadow, drawn as a rounded shape behind the card.
    // (A blur effect on the card took a frame or two to blur, showing a hard square-looking
    // shadow first, as the pop-up faded in.)
    RectangularShadow {
        visible: !card.inPanel && !Config.glass
        z: -1
        anchors.fill: parent
        radius: card.radius
        blur: 14
        offset.y: 4
        color: Qt.rgba(0, 0, 0, 0.38)
    }

    // A thick band across the top that wraps round the corners and tapers down the sides:
    // the space between the card's outline and its rounded content area, set `band` lower.
    // Shown on urgent notifications only, in red.
    Item {
        visible: card.band > 0
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: card.band + card.radius
        clip: true
        // The red shape with the content area cut out of it (not covered in the card's colour,
        // which glass makes see-through, so the red showed through)
        Rectangle {
            width: parent.width; height: card.height
            radius: card.radius
            color: card.critical ? card.bar.errorColor : card.accent
            layer.enabled: true
            layer.effect: MultiEffect { maskEnabled: true; maskInverted: true; maskSource: bandCut; maskThresholdMin: 0.5; maskSpreadAtMin: 1 }
        }
        Item {
            id: bandCut
            width: parent.width; height: card.height
            visible: false
            layer.enabled: true
            Rectangle {
                y: card.band
                width: parent.width; height: card.height
                radius: card.radius
            }
        }
    }

    // Timeout bar: a rounded line on a faint track under the content, shrinking as time runs out
    Rectangle {
        id: timerTrack
        visible: card.hasTimer
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 12; rightMargin: 12; bottomMargin: 12 }
        height: 4; radius: 2
        color: Qt.rgba(card.accent.r, card.accent.g, card.accent.b, 0.14)
        Rectangle {
            width: Math.max(height, parent.width * Math.max(0, card.progress))
            height: parent.height; radius: 2
            color: card.accent
            opacity: card.progress > 0 ? 0.85 : 0
        }
    }

    HoverHandler { id: cardHover }
    ClickTap { onTapped: card.activated() }

    // Refresh "2 min ago" text
    property int tick: 0
    Timer { interval: 30000; running: true; repeat: true; onTriggered: card.tick++ }
    function ago(t) {
        tick;
        const s = Math.max(0, (Date.now() - t) / 1000);
        if (s < 60) return "now";
        if (s < 3600) return Math.floor(s / 60) + " min ago";
        if (s < 86400) return Math.floor(s / 3600) + " h ago";
        return Qt.formatDate(new Date(t), "d MMM");
    }

    Item {
        id: content
        x: 12; y: card.band + 12
        width: parent.width - 24
        height: Math.max(icon.height, textCol.height)

        // Icon: Slate's own notices get its mark; others the notification's image, else the
        // app's tile, else a bell
        Item {
            id: icon
            width: 40; height: 40
            property int version: 0
            property string tried: ""          // drawn once per icon file
            // From Slate itself: its mark on the accent-tinted tile, like the glyph icons (a
            // screenshot's picture still shows below, as the preview)
            readonly property bool fromSlate: !!card.entry && card.entry.appName === "Slate"
            // Its colour: in Colourful mode, Slate's notices take the colour of the Settings page
            // they're about, and other apps' bell the Notifications page's; else the accent
            readonly property color tint: Config.pageColour(fromSlate ? ((card.entry && card.entry.page) || "about") : "notifications")
            RoundImage {
                id: picture
                anchors.fill: parent
                radius: 9
                visible: !icon.fromSlate && card.image !== "" && !card.preview
                source: visible ? card.image : ""
            }
            Image {
                id: tile
                anchors.fill: parent
                visible: !icon.fromSlate && !picture.visible && card.tilePath !== "" && status === Image.Ready
                source: card.tilePath ? "file://" + card.tilePath + "?v=" + icon.version + "." + Config.tileVersion : ""
                sourceSize: Qt.size(96, 96)
                smooth: true; mipmap: true
                layer.enabled: Config.iconTint > 0; layer.effect: IconTint {}
                onStatusChanged: if (status === Image.Error && !gen.running && icon.tried !== card.tilePath) { icon.tried = card.tilePath; gen.running = true; }
                IconPlate { anchors.fill: parent; z: -1 }       // the tile behind, in the theme's colour
            }
            Process {
                id: gen
                command: Config.tileCommand(card.entry ? card.entry.entryId : "", card.tilePath)
                onExited: icon.version++
            }
            Rectangle {
                anchors.fill: parent
                visible: !picture.visible && !tile.visible
                radius: 9
                // No icon: the bell on an accent-tinted tile (Slate's mark for Slate's notices)
                color: Qt.rgba(icon.tint.r, icon.tint.g, icon.tint.b, 0.16)
                SlateMark {
                    visible: icon.fromSlate
                    anchors.centerIn: parent
                    size: 24
                    accent: icon.tint
                    body: Qt.rgba(icon.tint.r, icon.tint.g, icon.tint.b, 0.55)
                }
                Text {
                    visible: !icon.fromSlate
                    anchors.centerIn: parent
                    text: String.fromCodePoint(0xEA35)
                    color: icon.tint
                    font.family: card.bar.iconFont
                    font.pixelSize: 20
                }
            }
        }

        Column {
            id: textCol
            anchors { left: icon.right; leftMargin: 12; right: parent.right }
            spacing: 3

            Item {
                width: parent.width; height: appLabel.height
                // New: a small accent dot before the app name
                Rectangle {
                    id: freshDot
                    visible: card.fresh
                    width: 6; height: 6; radius: 3
                    color: card.accent
                    anchors { left: parent.left; verticalCenter: appLabel.verticalCenter }
                }
                Text {
                    id: appLabel
                    anchors { left: freshDot.visible ? freshDot.right : parent.left; leftMargin: freshDot.visible ? 6 : 0; right: timeLabel.left; rightMargin: 8 }
                    text: card.entry ? card.entry.appName : ""
                    color: card.dim
                    font.family: card.bar.fontFamily; font.pixelSize: 11; font.weight: Font.Medium
                    elide: Text.ElideRight
                }
                Text {
                    id: timeLabel
                    anchors.right: closeBtn.visible ? closeBtn.left : parent.right
                    anchors.rightMargin: closeBtn.visible ? 6 : 0
                    text: card.entry ? card.ago(card.entry.time) : ""
                    color: card.dim
                    font.family: card.bar.fontFamily; font.pixelSize: 11
                }
                // Close button, shown on hover: the icon on a small rounded square, lit in the
                // accent when pointed at. (Overhangs the row a little rather than making it taller.)
                Rectangle {
                    id: closeBtn
                    visible: cardHover.hovered
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    width: 20; height: 20
                    radius: 5
                    color: closeHover.hovered ? Config.hover : Qt.rgba(card.textColor.r, card.textColor.g, card.textColor.b, 0.08)
                    Gloss { radius: parent.radius }   // glass: a sheen
                    Behavior on color { ColorAnimation { duration: 100 } }
                    Text {
                        anchors.centerIn: parent
                        text: String.fromCodePoint(0xEB55)
                        color: closeHover.hovered ? card.textColor : card.dim
                        font.family: card.bar.iconFont; font.pixelSize: 13
                    }
                    HoverHandler { id: closeHover }
                    ClickTap { onTapped: card.closed() }
                }
            }
            Text {
                width: parent.width
                text: card.entry ? card.entry.summary : ""
                visible: text !== ""
                color: card.textColor
                font.family: card.bar.fontFamily; font.pixelSize: 13; font.weight: Font.Medium
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: card.entry ? card.entry.body : ""
                visible: text !== ""
                textFormat: Text.StyledText
                color: card.dim
                linkColor: card.bar.accent
                font.family: card.bar.fontFamily; font.pixelSize: 12
                wrapMode: Text.Wrap
                maximumLineCount: card.inPanel ? 3 : 4
                elide: Text.ElideRight
                onLinkActivated: link => Qt.openUrlExternally(link)
            }
            // Picture preview (screenshots, album art…)
            RoundImage {
                visible: card.preview
                width: parent.width
                height: visible ? Math.min(170, width * 0.56) : 0
                radius: 10
                source: card.preview ? "file://" + card.imageFile : ""
            }
            // Action buttons
            Row {
                visible: card.actions.length > 0
                spacing: 6
                topPadding: 4
                Repeater {
                    model: card.actions
                    delegate: Rectangle {
                        required property var modelData
                        height: 28
                        width: actText.implicitWidth + 20
                        radius: 8
                        // Accent-tinted; solid accent on hover
                        color: actHover.hovered ? card.accent : Qt.rgba(card.accent.r, card.accent.g, card.accent.b, 0.16)
                        Gloss { radius: parent.radius }   // glass: a sheen
                        Behavior on color { ColorAnimation { duration: 100 } }
                        Text {
                            id: actText
                            anchors.centerIn: parent
                            text: modelData.text
                            color: actHover.hovered ? Config.tint("#12151a") : card.accent
                            font.family: card.bar.fontFamily; font.pixelSize: 12; font.weight: Font.Medium
                        }
                        HoverHandler { id: actHover }
                        ClickTap { onTapped: card.action(modelData.identifier) }
                    }
                }
            }
        }
    }
}
