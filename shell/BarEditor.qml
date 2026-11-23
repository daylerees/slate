// Arranging the menu bar (Settings → Menu Bar → Edit layout): a panel that sits just off the
// bar for as long as the bar is being arranged (Config.barArranging). The dragging itself
// happens on the bar (Bar.qml); here are the things that go with it, drawn as the bar's own
// panels are (panels/: PanelTitle, Label, Heading, Divider, RowButton, LinkRow, Switch):
//   - Done, which ends it (every change is saved as it's made), and Restore defaults;
//   - what isn't on the bar, drawn as it would be there, and the two things there are always
//     more of (a container, a flexible space). A chip is clicked, or dragged onto the bar,
//     which is another window: this one works out where the pointer is on the desktop (where
//     this window is, from one look at Hyprland's pointer position as the chip is pressed,
//     then the pointer's place in the window) and tells the bar (Config.barCarry,
//     barCarryAt), which shows where it would land;
//   - the options of whatever is picked on the bar (Config.barSelected, barSelectedItem):
//     a container (its collapse button too), one thing in it, a flexible space, the active window;
//   - when there isn't room: Set priority (a view of its own in the same panel, sliding across)
//     and Try it shorter.
// It comes out with the bar's panels' motion: easing in from the bar's side as it fades in, once
// its first frames are drawn, and back again as the arranging ends.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "panels"

PanelWindow {
    id: root
    required property var bar
    property var confirmer: null           // PowerConfirm: asks before putting the defaults back

    readonly property bool shown: Config.barArranging
    // (made as the arranging starts: it slides in once its first two frames are drawn, as the
    // bar's panels do, or the first frames of the slide came late and it jumped)
    property bool ready: false
    property int readyFrames: 0
    Connections {
        target: card.Window.window
        enabled: !root.ready
        function onFrameSwapped() { if (++root.readyFrames >= 2) root.ready = true; }
    }
    Timer { running: !root.ready; interval: 150; onTriggered: root.ready = true }
    property real fade: shown && ready ? 1 : 0
    Behavior on fade { NumberAnimation { duration: Config.ms(220); easing.type: Easing.OutCubic } }
    // Menu item priority (Set priority): a view of its own, sliding in over the arranging one
    readonly property bool prioritising: shown && Config.barPrioritising
    property real turn: prioritising ? 1 : 0
    Behavior on turn { NumberAnimation { duration: Config.ms(200); easing.type: Easing.OutCubic } }

    // ---- Look: the bar's panels' own colours (Popouts.qml) --------------------------
    readonly property var pop: PanelHost.pop
    readonly property color text: bar.textColor
    readonly property color dim: Config.tint("#8b94a3")
    readonly property color accent: bar.accent
    readonly property color accentText: Config.tint("#12151a")
    readonly property color danger: bar.errorColor
    readonly property color card: bar.capsuleColor
    readonly property int pad: 16

    // ---- Where: just off the bar, on its screen --------------------------------------
    // The window covers the screen (it takes the pointer only over the panel: the mask), so the
    // panel slides and grows inside it without the window changing size
    screen: bar.screen
    readonly property string side: bar.side
    readonly property bool vert: side === "left" || side === "right"
    // (a little further off while the bar has its scroll handle under it)
    // (always room for the bar's scroll handle under it: going by whether the bar had anything to
    // scroll, which flips while the bar eases into arranging, the panel juddered as it came in)
    readonly property real off: bar.barHeight + 24
    // (how far it eases in from, towards the bar)
    readonly property real slide: 14 * (1 - fade)
    visible: shown || fade > 0
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "slate-bar-editor"
    WlrLayershell.layer: WlrLayer.Overlay
    // The keyboard is this panel's while the bar's arranged. Nothing typed reaches a window out
    // of sight under the wallpaper, and it's what lets a drag leave the bar: Hyprland only
    // keeps a pressed pointer with the surface it was pressed on while something has the
    // keyboard, and with no window focused nothing did, so the drag ended at the bar's edge
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    mask: Region { item: root.shown ? card : null }

    // ---- What's picked on the bar ---------------------------------------------------
    readonly property var picked: Config.barSelected >= 0 ? (Config.barLayout[Config.barSelected] || null) : null
    readonly property string pickedItem: Config.barSelectedItem
    readonly property string kind: !picked ? "none" : picked === "space" ? "space"
        : Config.barFixed(picked) ? "fixed" : pickedItem !== "" ? "item" : "box"
    // (a picked fixed space's size: { n, unit })
    readonly property var pickedFixed: kind === "fixed" ? Config.barFixed(picked) : null
    readonly property var pickedThings: picked && typeof picked !== "string" ? picked.items.filter(id => id !== "tuck") : []
    // (how the picked container collapses: "never", "always" or "needed"; and whether it has a
    // collapse button at all, to set up)
    readonly property string pickedCollapse: !!picked && typeof picked !== "string" ? (picked.collapse || "needed") : ""
    readonly property bool pickedTuck: pickedCollapse === "always" || pickedCollapse === "needed"
    function nameOf(id) { const it = Config.barItem(id); return it ? it.label : id; }
    readonly property string textKey: kind === "item" ? (Config.barTextKeys[pickedItem] || "") : ""
    // What the options are headed with: the picked thing's name and icon, and a line about it
    readonly property string pickedName: kind === "space" ? "Flexible space" : kind === "fixed" ? "Fixed space" : kind === "box" ? "Container"
        : kind === "item" ? nameOf(pickedItem) : ""
    readonly property int pickedIcon: kind === "space" ? 0xEB59 : kind === "fixed" ? 0xEF54 : kind === "box" ? 0xEAD5
        : kind === "item" ? ((Config.barItem(pickedItem) || { icon: 0 }).icon || 0) : 0
    readonly property string pickedAbout: kind === "space" ? "Takes up the spare room, pushing what's either side of it apart."
            + (Config.barSpaces < 2 ? " The bar always keeps one." : "")
        : kind === "fixed" ? "Keeps a gap of the same size, however much else is on the bar."
        : kind === "item" && pickedItem === "more" ? "What there isn't room for waits behind it. It shows only when something's there, and always stays on the bar."
        : kind === "box" ? (pickedThings.length > 0 ? "Holds " + listOf(pickedThings.map(nameOf)) + "." : "Empty for now. Drag things into it.")
        : ""
    // The sizes a fixed space offers, in each unit (pixels: the bar's own; %: of the screen)
    readonly property var fixedSizes: ({ "px": [8, 16, 32, 48, 64, 128], "%": [1, 2, 5, 10, 15, 25] })
    readonly property real screenLength: Config.barEdge === "left" || Config.barEdge === "right"
        ? (screen ? screen.height : 0) : (screen ? screen.width : 0)
    function listOf(names) { return Config.listText(names); }

    // ---- The pool, and carrying a chip to the bar ------------------------------------
    readonly property var pool: Config.barItems.filter(i => i.key !== "" && !Config.s[i.key])
    property point origin: Qt.point(0, 0)      // this window's corner on the desktop
    property bool placed: false                // ...once it's known
    property point pointer: Qt.point(0, 0)     // the pointer, in this window
    property var carrying: null                // the chip being dragged
    Process {
        id: whereAmI
        command: ["hyprctl", "-j", "cursorpos"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { const p = JSON.parse(text); root.locate(p.x, p.y); } catch (e) {}
            }
        }
    }
    // The pointer's at x, y in Hyprland's pixels: where's this window's corner on the desktop?
    // (On the desktop as the bar counts it: a screen's top-left as Qt keeps it, in Hyprland's
    // pixels, plus Slate's own units across the screen, Interface size: Config.uiScale. So the
    // pointer's made relative to this screen first, then brought to Slate's scale)
    function locate(x, y) {
        const k = Config.uiScale || 1, sx = root.screen ? root.screen.x : 0, sy = root.screen ? root.screen.y : 0;
        root.origin = Qt.point(sx + (x - sx) / k - root.pointer.x, sy + (y - sy) / k - root.pointer.y);
        root.placed = true;
    }
    function pressed(x, y) { pointer = Qt.point(x, y); placed = false; whereAmI.running = true; }
    function carryTo(chip, x, y) {
        pointer = Qt.point(x, y);
        if (!carrying) {
            carrying = chip;
            Config.barCarryAt = Qt.point(-100000, -100000);
            Config.barFloatAt = Qt.point(-100000, -100000);
            Config.barFloat = { kind: chip.carry.kind,
                                icons: [{ code: chip.icon, item: chip.item, text: chip.item !== "" ? root.bar.exampleOf(chip.item) : "" }] };
            Config.barCarry = chip.carry;
        }
        if (placed) { Config.barCarryAt = Qt.point(origin.x + x, origin.y + y); Config.barFloatAt = Config.barCarryAt; }
    }
    function dropped() {
        carrying = null; Config.barFloat = null;
        if (Config.barDrop()) Config.click();
    }
    function letGo() { carrying = null; Config.barFloat = null; Config.barCarry = null; Config.barCarryTarget = null; }
    onShownChanged: if (!shown) letGo()
    onPrioritisingChanged: { prioList.held = ""; prioList.moving = null; }

    // ---- Building blocks --------------------------------------------------------------
    // A button as Settings and the Spaces panel draw them: the card's fill with the muted hover,
    // or the accent (lit under the pointer) for the one that finishes
    component PanelButton: Rectangle {
        id: btn
        property string label
        property int icon: 0
        property bool primary: false
        property bool destructive: false
        signal clicked()
        width: btnRow.implicitWidth + 28; height: 32; radius: Config.corner(8)
        // (the lit accent fades, as everywhere; the muted hover is HoverFill's, there at once)
        color: primary ? Config.accentFor(btnHover.hovered) : "transparent"
        HoverFill { base: root.card; hover: btn.destructive ? Config.hoverDanger : Config.hover; hovered: btnHover.hovered; gone: btn.primary; radius: btn.radius }
        Behavior on color { ColorAnimation { duration: Config.ms(100) } }
        readonly property color fg: primary ? root.accentText : destructive ? root.danger : root.text
        Row {
            id: btnRow
            anchors.centerIn: parent
            spacing: 6
            Icon { visible: btn.icon !== 0; anchors.verticalCenter: parent.verticalCenter; code: btn.icon; color: btn.fg; font.pixelSize: 15 }
            Label { visible: btn.label !== ""; anchors.verticalCenter: parent.verticalCenter; text: btn.label; color: btn.fg; font.pixelSize: Config.text(12) }
        }
        HoverHandler { id: btnHover }
        ClickTap { onTapped: btn.clicked() }
    }
    // A setting that's on or off: its name, and the panels' switch at the end of the row
    component SwitchRow: Item {
        id: sw
        property string label
        property bool checked: false
        signal toggled(bool value)
        width: parent ? parent.width : 0
        height: 30
        Label {
            anchors { left: parent.left; right: swSwitch.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
            text: sw.label
            font.weight: Font.Normal
        }
        Switch {
            id: swSwitch
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            checked: sw.checked
            onToggled: sw.toggled(!sw.checked)
        }
    }
    // One of a few: a row of buttons, the one chosen in the active colour (as the Battery
    // panel's power modes), with a heading over it. Each choice: { value, label } or { value, code }
    component Choices: Column {
        id: ch
        property string title: ""
        property var options: []
        property var current
        signal chose(var value)
        width: parent ? parent.width : 0
        spacing: 6
        Heading { visible: ch.title !== ""; text: ch.title }
        Row {
            spacing: 6
            Repeater {
                model: ch.options
                RowButton {
                    id: choice
                    required property var modelData
                    width: (ch.width - 6 * (ch.options.length - 1)) / ch.options.length
                    height: 32
                    selected: ch.current === modelData.value
                    onClicked: ch.chose(modelData.value)
                    Icon {
                        visible: !!choice.modelData.code
                        anchors.centerIn: parent
                        code: choice.modelData.code || 0
                        font.pixelSize: 16
                        color: choice.fg
                        Behavior on color { ColorAnimation { duration: Config.ms(100) } }
                    }
                    Label {
                        visible: !choice.modelData.code
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, choice.width - 12)
                        text: choice.modelData.label || ""
                        font.pixelSize: Config.text(12)
                        font.weight: Font.Normal
                        color: choice.fg
                        Behavior on color { ColorAnimation { duration: Config.ms(100) } }
                    }
                }
            }
        }
    }
    // A paragraph: what the bar does, in plain words
    component Para: Label {
        width: parent ? parent.width : 0
        wrapMode: Text.WordWrap
        elide: Text.ElideNone
        lineHeight: 1.15
        font.pixelSize: Config.text(12)
        font.weight: Font.Normal
    }
    // The bar tried shorter, to see what slims down and what leaves: a dropdown as Settings
    // draws them (DropdownSetting), its menu in dropLayer below
    readonly property var lengths: [{ value: 0, label: "Full length" }, { value: 0.25, label: "Three quarters" }, { value: 0.5, label: "Half" }, { value: 0.67, label: "A third" }]
    readonly property var length: lengths.find(o => Math.abs(Config.barPreview - o.value) < 0.01) || lengths[0]
    component Shorter: Row {
        id: shorter
        readonly property Item button: shortButton
        spacing: 10
        Label {
            anchors.verticalCenter: parent.verticalCenter
            text: "Try it shorter"
            font.weight: Font.Normal
        }
        Rectangle {
            id: shortButton
            readonly property bool open: dropLayer.owner === shorter
            width: 150; height: 32; radius: Config.corner(8)
            color: "transparent"
            HoverFill { base: root.card; hovered: shortButton.open || shortHover.hovered; radius: shortButton.radius }
            border.width: open ? 1 : 0; border.color: root.accent
            Label {
                anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                text: root.length.label
                font.weight: Font.Normal
            }
            Icon {
                anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                code: 0xEA5F                      // chevron down
                rotation: shortButton.open ? 180 : 0
                Behavior on rotation { NumberAnimation { duration: Config.ms(120) } }
                color: root.dim; font.pixelSize: 16
            }
            HoverHandler { id: shortHover }
            ClickTap { onTapped: { if (!dropLayer.reopening(shorter)) dropLayer.owner = shortButton.open ? null : shorter; } }
        }
    }
    // The workspace dots as a picture of themselves: four, the first the one you're on, the
    // next with windows on it (for the pool's chip and what's carried, in place of an icon)
    component DotsPicture: Row {
        spacing: 5
        Repeater {
            model: 4
            Rectangle {
                required property int index
                anchors.verticalCenter: parent.verticalCenter
                width: 12; height: 12; radius: Config.dotRadius(12)
                color: index === 0 ? root.accent : index === 1 ? Config.tint("#aeb6c2") : Config.tint("#4f5866")
            }
        }
    }
    // Something from the bar, drawn as it is there, with its name beside it: the bar's own
    // container shape, sizes, font and colours (the icon in its Colourful colour, as on the
    // bar). `item`: its name in the arrangement, "" for what isn't an item
    component BarChip: Rectangle {
        id: barChip
        property string item: ""
        property int icon: 0
        property string label: ""
        property bool lit: false             // hovered
        property bool grip: false            // a gripper at its start: it can be dragged
        readonly property color iconColour: root.iconColour(item)
        width: chipRow.implicitWidth + (grip ? 18 : 24); height: Math.max(32, root.bar.capsuleHeight)
        radius: Config.corner(root.bar.capsuleRadius)
        color: root.bar.capsuleColor
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: root.bar.hoverFill
            opacity: barChip.lit ? root.bar.hoverStrength : 0               // (at once: CONVENTIONS, the muted hover)
        }
        Gloss { radius: parent.radius }   // glass: a sheen, as on the bar's containers
        Row {
            id: chipRow
            anchors.centerIn: parent
            // (with a gripper: nearer the chip's start, where the bar's containers have theirs)
            anchors.horizontalCenterOffset: barChip.grip ? -3 : 0
            spacing: 7
            // (as on the bar's containers while it's arranged: pick it up here, or anywhere on it)
            Icon {
                visible: barChip.grip
                anchors.verticalCenter: parent.verticalCenter
                code: 0xEC01
                color: barChip.lit ? root.text : root.dim
                font.pixelSize: 13
            }
            Image {
                visible: barChip.item === "control"
                anchors.verticalCenter: parent.verticalCenter
                width: 16; height: 16
                sourceSize: Qt.size(32, 32)
                source: visible ? "file://" + Quickshell.shellPath("assets/icon/icon-64.png") : ""
            }
            DotsPicture { visible: barChip.item === "workspaces"; anchors.verticalCenter: parent.verticalCenter }
            Icon {
                visible: barChip.item !== "control" && barChip.item !== "workspaces"
                anchors.verticalCenter: parent.verticalCenter
                code: barChip.icon
                color: barChip.iconColour
                font.pixelSize: 16
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: barChip.label !== ""
                textFormat: Text.PlainText        // never markup: a tray icon's name is the app's to choose
                text: barChip.label
                color: root.text
                font.family: root.bar.fontFamily; font.pixelSize: Config.text(root.bar.fontSize); font.weight: Font.Medium
            }
        }
    }
    // A chip in the pool: clicked, or dragged onto the bar. Silent while dragged, a click when
    // it lands, as everywhere. While it's carried, its place here stays, faded
    component PoolChip: BarChip {
        id: chip
        property var carry: null             // what the bar is told is coming: { kind, id }
        signal clicked()
        grip: true
        item: carry && carry.kind === "item" ? carry.id : ""
        lit: chipHover.hovered && root.carrying === null
        opacity: root.carrying === chip ? 0.35 : 1
        HoverHandler { id: chipHover }
        MouseArea {
            anchors.fill: parent
            preventStealing: true
            property point from
            property bool dragged: false
            onPressed: m => {
                from = Qt.point(m.x, m.y); dragged = false;
                const p = mapToItem(null, m.x, m.y);
                root.pressed(p.x, p.y);
            }
            onPositionChanged: m => {
                if (!dragged && Math.abs(m.x - from.x) + Math.abs(m.y - from.y) > 6) dragged = true;
                if (!dragged) return;
                const p = mapToItem(null, m.x, m.y);
                root.carryTo(chip, p.x, p.y);
            }
            onReleased: {
                const was = dragged;
                dragged = false;
                if (!was) { Config.click(); chip.clicked(); }
                else root.dropped();
            }
            onCanceled: { dragged = false; root.letGo(); }
        }
    }

    // ---- The panel ----------------------------------------------------------------------
    // One surface, as the bar's panels are: the arranging view, and menu item priority sliding
    // in over it. Its height eases between them, and as what's picked changes what it shows
    Rectangle {
        id: card
        readonly property real targetHeight: (root.prioritising ? prioView.implicitHeight : mainView.implicitHeight) + root.pad * 2
        width: root.vert ? 380 : Math.min(860, root.width - 64)
        height: targetHeight
        Behavior on height { enabled: root.fade >= 1; NumberAnimation { duration: Config.ms(180); easing.type: Easing.OutCubic } }
        x: root.side === "left" ? root.off - root.slide
            : root.side === "right" ? root.width - root.off - width + root.slide
            : Math.round((root.width - width) / 2)
        y: root.side === "top" ? root.off - root.slide
            : root.side === "bottom" ? root.height - root.off - height + root.slide
            : 40
        radius: Config.corner(14)
        color: root.bar.barColor
        opacity: root.fade
        visible: opacity > 0
        WindowBorder { radius: parent.radius }   // glass: the window border (Config)
        Shadow {}      // raised: Slate's shadow, with glass too
        Gloss { radius: parent.radius; strength: 0.6 }     // glass: a sheen, as on Slate's panels
        MouseArea { anchors.fill: parent }       // (a click on the panel itself does nothing)

        Item {
            id: views
            anchors.fill: parent
            clip: true                           // (while its height eases)

            // ---- Arranging --------------------------------------------------------------
            Column {
                id: mainView
                x: root.pad - 24 * root.turn
                y: root.pad
                width: card.width - root.pad * 2
                spacing: 12
                opacity: 1 - root.turn
                visible: opacity > 0
                // (Escape ends the arranging, as Done does)
                focus: root.shown && !root.prioritising
                Keys.onEscapePressed: Config.barArranging = false

                // Title, Restore defaults and Done
                Item {
                    width: parent.width; height: 32
                    PanelTitle {
                        anchors { left: parent.left; right: titleButtons.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        height: textHeight
                        text: "Arrange the menu bar"
                    }
                    Row {
                        id: titleButtons
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        spacing: 8
                        PanelButton {
                            visible: !Config.barIsDefault
                            label: "Restore defaults"
                            onClicked: {
                                if (!root.confirmer) { Config.barReset(); return; }
                                root.confirmer.confirmWith({
                                    title: "Put the menu bar back as it started?",
                                    body: "Everything goes back to where Slate first had it, and what you took off the bar returns. Your other menu bar settings stay as they are.",
                                    button: "Restore defaults"
                                }, () => Config.barReset());
                            }
                        }
                        PanelButton {
                            primary: true
                            label: "Done"
                            onClicked: Config.barArranging = false
                        }
                    }
                }
                Para {
                    color: root.dim
                    text: "Drag things along the bar to move them, or here to take them off. Click one to change it."
                }
                Divider {}

                // What isn't on the bar, beside (or above, by a bar down a side) what's picked
                Item {
                    id: mainBody
                    width: parent.width
                    readonly property real optWidth: root.vert ? width : 320
                    height: root.vert ? poolCol.height + 25 + optCol.height : Math.max(poolCol.height, optCol.height, 130)

                    Column {
                        id: poolCol
                        width: root.vert ? parent.width : parent.width - mainBody.optWidth - 29
                        spacing: 8
                        Heading {
                            width: parent.width
                            text: Config.barLeaving ? "Let go to take it off the bar"
                                : root.pool.length === 0 ? "Everything's on the bar" : "Not on the bar"
                            color: Config.barLeaving ? root.accent : root.dim
                        }
                        // (where something dragged off the bar lands: lit while it's over here, so
                        // it's clear letting go will put it back)
                        Item {
                            width: parent.width
                            height: Math.max(poolFlow.height, 32) + 16
                            Rectangle {
                                x: -8; y: 0
                                width: parent.width + 16; height: parent.height
                                radius: Config.corner(10)
                                color: Config.barLeaving ? Config.hover : "transparent"
                                border.width: Config.barLeaving ? 1 : 0
                                border.color: root.accent
                            }
                            Flow {
                                id: poolFlow
                                y: 8
                                width: parent.width
                                spacing: 8
                                Repeater {
                                    model: root.pool
                                    PoolChip {
                                        required property var modelData
                                        icon: modelData.icon; label: modelData.label
                                        carry: ({ kind: "item", id: modelData.id })
                                        onClicked: Config.barSetShown(modelData.id, true)
                                    }
                                }
                                // (always more of these)
                                PoolChip {
                                    icon: 0xEAD5; label: "Container"
                                    carry: ({ kind: "box", id: "" })
                                    onClicked: Config.barAddBox(Config.barLayout.length)
                                }
                                PoolChip {
                                    icon: 0xEB59; label: "Flexible space"
                                    carry: ({ kind: "space", id: "" })
                                    onClicked: Config.barAddSpace(Config.barLayout.length)
                                }
                                PoolChip {
                                    icon: 0xEF54; label: "Fixed space"
                                    carry: ({ kind: "fixed", id: "" })
                                    onClicked: Config.barAddFixed(Config.barLayout.length)
                                }
                            }
                        }
                        Para {
                            color: root.dim
                            text: root.pool.length === 0 ? "Drag something off the bar and it waits here, or add a container or a space."
                                : "Drag one onto the bar, or click it to add it at the end."
                        }
                    }
                    // (between the two)
                    Rectangle {
                        visible: !root.vert
                        x: poolCol.width + 14
                        width: 1; height: parent.height
                        color: root.card
                    }
                    Divider {
                        visible: root.vert
                        y: poolCol.height + 12
                    }

                    // What's picked, and its options
                    Column {
                        id: optCol
                        x: root.vert ? 0 : parent.width - width
                        y: root.vert ? poolCol.height + 25 : 0
                        width: mainBody.optWidth
                        spacing: 10

                        // Nothing yet: a nudge
                        Item {
                            visible: root.kind === "none"
                            width: parent.width; height: 130
                            Column {
                                anchors.centerIn: parent
                                width: parent.width
                                spacing: 8
                                Icon { anchors.horizontalCenter: parent.horizontalCenter; code: 0xEF4F; font.pixelSize: 24; color: root.dim }
                                Para {
                                    horizontalAlignment: Text.AlignHCenter
                                    color: root.dim
                                    text: "Click something on the bar to change it"
                                }
                            }
                        }

                        // Its name, and what it is
                        Item {
                            visible: root.kind !== "none"
                            width: parent.width; height: 26
                            Item {
                                id: pickedMark
                                width: 20; height: parent.height
                                Icon {
                                    anchors.centerIn: parent
                                    code: root.pickedIcon
                                    font.pixelSize: 16
                                    color: root.kind === "item" ? root.iconColour(root.pickedItem) : root.dim
                                }
                            }
                            PanelTitle {
                                anchors { left: pickedMark.right; leftMargin: 8; right: parent.right; verticalCenter: parent.verticalCenter }
                                height: textHeight
                                text: root.pickedName
                            }
                        }
                        Para {
                            visible: text !== ""
                            color: root.dim
                            text: root.pickedAbout
                        }

                        // One thing
                        SwitchRow {
                            visible: root.textKey !== ""
                            label: "Show its text"
                            checked: root.textKey !== "" && !!Config.s[root.textKey]
                            onToggled: v => Config.s[root.textKey] = v
                        }
                        SwitchRow {
                            visible: root.kind === "item" && root.pickedItem !== "more"
                            label: "Always keep on the bar"
                            checked: Config.barStays(root.pickedItem)
                            onToggled: v => Config.barSetStay(root.pickedItem, v)
                        }
                        SwitchRow {
                            visible: root.kind === "item" && root.pickedItem === "tray"
                            label: "Tuck its icons away"
                            checked: Config.s.barTrayCollapsed
                            onToggled: v => Config.s.barTrayCollapsed = v
                        }
                        Choices {
                            visible: root.kind === "item" && root.pickedItem === "clock"
                            title: "Clock"
                            options: [{ value: "12h", label: "12-hour" }, { value: "24h", label: "24-hour" }]
                            current: Config.s.barClockFormat === "24h" ? "24h" : "12h"
                            onChose: v => Config.s.barClockFormat = v
                        }
                        SwitchRow {
                            visible: root.kind === "item" && root.pickedItem === "clock"
                            label: "Date"
                            checked: Config.s.barClockDate
                            onToggled: v => Config.s.barClockDate = v
                        }
                        SwitchRow {
                            visible: root.kind === "item" && root.pickedItem === "clock"
                            label: "Seconds"
                            checked: Config.s.barClockSeconds
                            onToggled: v => Config.s.barClockSeconds = v
                        }

                        // A fixed space: its size, in pixels or as a share of the screen
                        Choices {
                            visible: root.kind === "fixed"
                            title: "Size in"
                            options: [{ value: "px", label: "Pixels" }, { value: "%", label: "% of screen" }]
                            current: root.pickedFixed ? root.pickedFixed.unit : ""
                            // (switching keeps it about the same size: the nearest choice in the other unit)
                            onChose: v => {
                                if (!root.pickedFixed || v === root.pickedFixed.unit) return;
                                const sl = root.screenLength > 0 ? root.screenLength : 1920;
                                const now = root.pickedFixed.unit === "%" ? sl * root.pickedFixed.n / 100 : root.pickedFixed.n;
                                const to = v === "%" ? now * 100 / sl : now;
                                const near = root.fixedSizes[v].reduce((a, b) => Math.abs(b - to) < Math.abs(a - to) ? b : a);
                                Config.barSetFixed(Config.barSelected, near, v);
                            }
                        }
                        Choices {
                            visible: root.kind === "fixed"
                            title: "Size"
                            options: root.pickedFixed ? root.fixedSizes[root.pickedFixed.unit].map(n => ({ value: n, label: n + (root.pickedFixed.unit === "%" ? "%" : "") })) : []
                            current: root.pickedFixed ? root.pickedFixed.n : 0
                            onChose: v => Config.barSetFixed(Config.barSelected, v, root.pickedFixed.unit)
                        }

                        // A container
                        // How it collapses: tucked behind a button always, only when the bar's short of
                        // room, or never (with one thing in it there's nothing to tuck)
                        Choices {
                            visible: root.kind === "box" && root.pickedThings.length > 1
                            title: "Collapse"
                            options: [{ value: "never", label: "Never" }, { value: "needed", label: "When needed" }, { value: "always", label: "Always" }]
                            current: root.pickedCollapse
                            onChose: v => Config.barSetCollapse(Config.barSelected, v)
                        }
                        // ...its button's icon, and which end it sits at
                        Choices {
                            visible: root.kind === "box" && root.pickedThings.length > 1 && root.pickedTuck
                            title: "Its button"
                            options: [0xEC38, 0xEA95, 0xEA94, 0xEA60, 0xEA61, 0xEC42, 0xEB0B, 0xEA9A].map(c => ({ value: c, code: c }))
                            current: root.pickedTuck ? (parseInt(root.picked.tuckIcon, 16) || 0xEC38) : 0
                            onChose: v => Config.barSetTuck(Config.barSelected, undefined, v === 0xEC38 ? "" : v.toString(16))
                        }
                        Choices {
                            visible: root.kind === "box" && root.pickedThings.length > 1 && root.pickedTuck
                            options: [{ value: "start", label: "At the start" }, { value: "end", label: "At the end" }]
                            current: root.pickedTuck && root.picked.tuckFrom === "start" ? "start" : "end"
                            onChose: v => Config.barSetTuck(Config.barSelected, undefined, undefined, v)
                        }

                        // (no visible: of its own: it's empty, so no height, when neither shows. Bound
                        // to theirs, it hid itself and them with it, as they're seen only through it)
                        Column {
                            width: parent.width
                            spacing: 2
                            LinkRow {
                                id: splitRow
                                visible: root.kind === "box" && root.pickedThings.length > 1
                                code: 0xEDB5; text: "Split up"
                                onClicked: Config.barSplit(Config.barSelected)
                            }
                            // Off the bar
                            // (the last flexible space stays: something has to take up the spare room. And
                            // More, which holds what doesn't fit, is never off the bar)
                            LinkRow {
                                id: offRow
                                visible: root.kind !== "none" && !(root.kind === "space" && Config.barSpaces < 2)
                                    && !(root.kind === "item" && root.pickedItem === "more")
                                danger: true
                                code: 0xEB41
                                iconColor: root.danger; textColor: root.danger
                                text: root.kind === "space" || root.kind === "fixed" ? "Take away" : "Take off the bar"
                                onClicked: {
                                    if (root.kind === "item") Config.barSetShown(root.pickedItem, false);
                                    else Config.barRemoveEntry(Config.barSelected);
                                    Config.barSelected = -1;
                                }
                            }
                        }
                    }
                }
                Divider {}

                // If it doesn't fit: menu item priority, which has a view of its own (below), and
                // a way to see it happen: the bar tried shorter
                Heading { text: "When there isn't room for everything" }
                Flow {
                    width: parent.width
                    spacing: 12
                    PanelButton {
                        id: priorityButton
                        icon: 0xEF11                      // a numbered list
                        label: "Set priority"
                        onClicked: Config.barPrioritising = true
                    }
                    Shorter { id: panelShorter }
                }
            }

            // ---- Menu item priority -------------------------------------------------------
            // What the bar does when it's short of room, explained, beside the
            // one part of it that's yours to set: the order things leave for More. Shown highest
            // priority first (the last to leave), so it's Config.barOverflowOrder backwards, without
            // what always stays, which never leaves and so has no place in it
            Item {
                id: prioView
                x: root.pad + 24 * (1 - root.turn)
                y: root.pad
                width: card.width - root.pad * 2
                implicitHeight: prioBody.y + prioBody.height
                opacity: root.turn
                visible: opacity > 0
                // (Escape goes back to the arranging)
                focus: root.prioritising
                Keys.onEscapePressed: Config.barPrioritising = false

                Item {
                    id: prioTop
                    width: parent.width; height: 32
                    RowButton {
                        id: prioBack
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                        width: 28; height: 28
                        onClicked: Config.barPrioritising = false
                        Icon { anchors.centerIn: parent; code: 0xEA60; font.pixelSize: 16; color: root.dim }
                    }
                    PanelTitle {
                        anchors { left: prioBack.right; leftMargin: 8; right: parent.right; verticalCenter: parent.verticalCenter }
                        height: textHeight
                        text: "Menu item priority"
                    }
                }
                Para {
                    id: prioAbout
                    anchors { top: prioTop.bottom; topMargin: 12 }
                    color: root.dim
                    text: "What stays on the bar longest when there isn't room for everything."
                }
                Divider { id: prioLine; anchors { top: prioAbout.bottom; topMargin: 12 } }

                // The explanation on one side, the list on the other (one above the other by a bar
                // that's down a side of the screen, where the panel's narrow)
                Item {
                    id: prioBody
                    anchors { top: prioLine.bottom; topMargin: 12; left: parent.left; right: parent.right }
                    readonly property real room: Math.max(260, (root.screen ? root.screen.height : 800) - root.bar.barHeight - 220)
                    height: root.vert ? prioWhy.height + 14 + Math.max(200, Math.min(320, room - prioWhy.height - 14))
                        : Math.min(room, Math.max(prioWhy.height, 340))
                    clip: true

                    Column {
                        id: prioWhy
                        width: root.vert ? parent.width : Math.round(parent.width * 0.42)
                        spacing: 6
                        Heading { text: "When the bar runs short of room" }
                        Para { text: "Slate makes room in two steps, and puts everything back as soon as there's space again." }
                        Item { width: 1; height: 4 }
                        Heading { text: "First, things slim down" }
                        Para { text: "The window's title shortens, text beside icons goes (the longest first), the clock drops its date and seconds, and containers set to collapse When needed tuck behind their button. Nothing leaves the bar." }
                        Item { width: 1; height: 4 }
                        Heading { text: "Then, things leave for More" }
                        Para { text: "If that isn't enough, things move behind More one at a time, lowest priority first. They're still there when you open it." }
                        Item { width: 1; height: 4 }
                        Heading { text: "Your priority" }
                        Para { text: "The list is that order. What's at the top stays on the bar longest, and what's at the bottom leaves first. Drag to change it." }
                        Para {
                            readonly property var names: Config.barStay.map(root.nameOf)
                            color: root.dim
                            text: (names.length === 0 ? "Nothing's set to always stay just now."
                                   : names.length === 1 ? names[0] + " always stays, so it isn't listed."
                                   : root.listOf(names) + " always stay, so they aren't listed.")
                                + " To change that, go back, click something on the bar and use Always keep on the bar."
                        }
                        Item { width: 1; height: 6 }
                        Shorter { id: prioShorter }
                    }

                    Item {
                        id: prioList
                        x: root.vert ? 0 : prioWhy.width + 20
                        y: root.vert ? prioWhy.height + 14 : 0
                        width: parent.width - x
                        height: parent.height - y
                        readonly property int rowHeight: 38
                        readonly property int step: rowHeight + 4
                        // The list as it's shown: while a row's dragged, a copy with it where it would land
                        property var moving: null
                        property string held: ""
                        property real heldY: 0             // the dragged row's place, in the list
                        property real grabOff: 0           // ...and where on it the pointer has it
                        property real viewY: 0             // the pointer, in what's showing of the list
                        readonly property var shown: moving || root.priority
                        readonly property string lit: held === "" && prioArea.containsMouse ? prioArea.idAt(prioArea.mouseY) : ""
                        function moveTo(slot) {
                            const list = moving.filter(id => id !== held);
                            list.splice(Math.max(0, Math.min(list.length, slot)), 0, held);
                            if (list.join() !== moving.join()) moving = list;
                        }
                        function track() {
                            heldY = Math.max(0, Math.min(prioFlick.contentHeight - rowHeight, viewY + prioFlick.contentY - grabOff));
                            moveTo(Math.round(heldY / step));
                        }
                        function drop() {
                            if (held !== "" && moving && moving.join() !== root.priority.join()) {
                                Config.barSetOverflow(moving.slice().reverse(), Config.barStay);
                                Config.click();
                            }
                            held = ""; moving = null;
                        }
                        // (held by the top or bottom of the list: it scrolls under the row)
                        Timer {
                            running: prioList.held !== ""
                            interval: 16; repeat: true
                            onTriggered: {
                                const edge = 34, far = Math.max(0, prioFlick.contentHeight - prioFlick.height);
                                const by = prioList.viewY < edge ? -(edge - prioList.viewY) : prioList.viewY > prioFlick.height - edge ? prioList.viewY - (prioFlick.height - edge) : 0;
                                if (by === 0 || far <= 0) return;
                                prioFlick.contentY = Math.max(0, Math.min(far, prioFlick.contentY + Math.max(-14, Math.min(14, by * 0.4))));
                                prioList.track();
                            }
                        }

                        Heading { id: prioFirst; text: "Highest priority: stays longest" }
                        Heading { id: prioLast; anchors.bottom: parent.bottom; text: "Lowest priority: leaves first" }
                        Flickable {
                            id: prioFlick
                            anchors { top: prioFirst.bottom; topMargin: 8; bottom: prioLast.top; bottomMargin: 8; left: parent.left; right: parent.right
                                      rightMargin: contentHeight <= height ? 0 : 18 }
                            contentWidth: width
                            contentHeight: Math.max(0, prioList.shown.length * prioList.step - 4)
                            interactive: false             // (the wheel and the scrollbar move it: a drag moves a row)
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            SmoothWheel { flick: prioFlick }

                            Repeater {
                                model: root.priority
                                delegate: Rectangle {
                                    id: prioRow
                                    required property string modelData
                                    readonly property var it: Config.barItem(modelData)
                                    readonly property bool isHeld: prioList.held === modelData
                                    readonly property bool lit: isHeld || prioList.lit === modelData
                                    width: prioFlick.width; height: prioList.rowHeight
                                    radius: Config.corner(10)
                                    y: isHeld ? prioList.heldY : prioList.shown.indexOf(modelData) * prioList.step
                                    z: isHeld ? 2 : 0
                                    // (the others step out of the way of the one being dragged)
                                    Behavior on y {
                                        enabled: prioList.held !== "" && !prioRow.isHeld
                                        NumberAnimation { duration: Config.ms(140); easing.type: Easing.OutCubic }
                                    }
                                    // (picked up: lifted, solid and outlined; under the pointer, the muted hover)
                                    color: isHeld ? root.bar.capsuleSolid : "transparent"
                                    border.width: isHeld ? 1 : 0
                                    border.color: root.accent
                                    HoverFill { base: root.card; hovered: prioRow.lit && !prioRow.isHeld; gone: prioRow.isHeld; radius: prioRow.radius }
                                    Shadow { visible: Config.shadowsOn && prioRow.isHeld }
                                    Row {
                                        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                                        spacing: 10
                                        Icon {
                                            anchors.verticalCenter: parent.verticalCenter
                                            code: 0xEC01
                                            color: prioRow.lit ? root.text : root.dim
                                            font.pixelSize: 14
                                        }
                                        Icon {
                                            visible: prioRow.modelData !== "control" && prioRow.modelData !== "workspaces"
                                            anchors.verticalCenter: parent.verticalCenter
                                            code: prioRow.it ? prioRow.it.icon : 0
                                            color: root.iconColour(prioRow.modelData)
                                            font.pixelSize: 16
                                        }
                                        Image {
                                            visible: prioRow.modelData === "control"
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 16; height: 16
                                            sourceSize: Qt.size(32, 32)
                                            source: visible ? "file://" + Quickshell.shellPath("assets/icon/icon-64.png") : ""
                                        }
                                        DotsPicture { visible: prioRow.modelData === "workspaces"; anchors.verticalCenter: parent.verticalCenter }
                                        Label {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: prioRow.it ? prioRow.it.label : prioRow.modelData
                                            font.weight: Font.Normal
                                        }
                                    }
                                    Label {
                                        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                        visible: !Config.barShown(prioRow.modelData)
                                        text: "Not on the bar"
                                        color: root.dim
                                        font.pixelSize: Config.text(12); font.weight: Font.Normal
                                    }
                                }
                            }
                            MouseArea {
                                id: prioArea
                                width: prioFlick.width; height: prioFlick.contentHeight
                                z: 3
                                hoverEnabled: true
                                preventStealing: true
                                property real fromY: 0
                                property string grabbed: ""
                                function idAt(y) {
                                    const i = Math.floor(y / prioList.step), list = prioList.shown;
                                    return i >= 0 && i < list.length && y - i * prioList.step < prioList.rowHeight ? list[i] : "";
                                }
                                onPressed: m => {
                                    grabbed = idAt(m.y); fromY = m.y;
                                    prioList.grabOff = m.y - prioList.shown.indexOf(grabbed) * prioList.step;
                                }
                                onPositionChanged: m => {
                                    if (!pressed || grabbed === "") return;
                                    if (prioList.held === "" && Math.abs(m.y - fromY) > 4) {
                                        prioList.moving = root.priority.slice();
                                        prioList.heldY = prioList.shown.indexOf(grabbed) * prioList.step;
                                        prioList.held = grabbed;
                                    }
                                    if (prioList.held === "") return;
                                    prioList.viewY = m.y - prioFlick.contentY;
                                    prioList.track();
                                }
                                onReleased: { prioList.drop(); grabbed = ""; }
                                onCanceled: { prioList.held = ""; prioList.moving = null; grabbed = ""; }
                            }
                        }
                        // While the list scrolls: a soft shadow at the top once scrolled down, and at the
                        // bottom while there's more below
                        ScrollShade {
                            anchors { top: prioFlick.top; left: prioFlick.left; right: prioFlick.right }
                            cornerRadius: 10
                            distance: prioFlick.contentY
                        }
                        ScrollShade {
                            atBottom: true
                            anchors { bottom: prioFlick.bottom; left: prioFlick.left; right: prioFlick.right }
                            cornerRadius: 10
                            distance: prioFlick.contentHeight - prioFlick.height - prioFlick.contentY
                        }
                        ThinScrollbar {
                            flick: prioFlick
                            color: root.text
                            anchors { top: prioFlick.top; bottom: prioFlick.bottom; left: prioFlick.right; leftMargin: 8 }
                        }
                    }
                }
            }
        }

        // ---- The dropdown's menu --------------------------------------------------------
        // Over the panel, as Settings has its own (dropLayer there): under the button, or above
        // it where there isn't room, so it stays on the panel
        Item {
            id: dropLayer
            anchors.fill: parent
            z: 100
            property var owner: null
            visible: owner !== null
            onVisibleChanged: if (visible) place()
            readonly property real rowH: 34
            readonly property real menuH: root.lengths.length * rowH + 12
            property real menuX: 0
            property real menuY: 0
            function place() {
                const b = owner.button, p = b.mapToItem(dropLayer, 0, 0);
                menuX = Math.max(8, Math.min(width - menu.width - 8, p.x));
                const below = height - 8 - (p.y + b.height + 6);
                menuY = menuH <= below ? p.y + b.height + 6 : Math.max(8, p.y - 6 - menuH);
            }
            Connections {
                target: root
                function onPrioritisingChanged() { dropLayer.owner = null; }
                function onShownChanged() { dropLayer.owner = null; }
            }
            // Click anywhere else to close. A press on the open list's own button closes it too, and
            // the tap that press ends in mustn't open it again (it did: the list popped straight back),
            // so the button asks reopening() first
            property var closedBy: null
            property real closedAt: 0
            function reopening(o) { const r = closedBy === o && Date.now() - closedAt < 800; closedBy = null; return r; }
            MouseArea {
                anchors.fill: parent
                onPressed: mouse => {
                    const o = dropLayer.owner, b = o ? o.button : null;
                    if (b) {
                        const p = b.mapToItem(dropLayer, 0, 0);
                        if (mouse.x >= p.x && mouse.x < p.x + b.width && mouse.y >= p.y && mouse.y < p.y + b.height) {
                            dropLayer.closedBy = o; dropLayer.closedAt = Date.now();
                        }
                    }
                    dropLayer.owner = null;
                }
            }
            Rectangle {
                id: menu
                x: dropLayer.menuX; y: dropLayer.menuY
                width: 200; height: dropLayer.menuH
                radius: Config.corner(12)
                color: Config.tint("#1d222a")
                border.width: 1; border.color: Config.tint("#2a313c")
                Shadow {}
                MouseArea { anchors.fill: parent }     // clicks between rows stay in the menu
                Column {
                    anchors { fill: parent; margins: 6 }
                    Repeater {
                        model: root.lengths
                        Rectangle {
                            id: lengthRow
                            required property var modelData
                            readonly property bool current: modelData.value === root.length.value
                            width: parent.width; height: dropLayer.rowH; radius: Config.corner(8)
                            color: lengthHover.hovered ? Config.hover : "transparent"
                            Label {
                                anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                                text: lengthRow.modelData.label
                                color: lengthRow.current ? root.accent : root.text
                            }
                            Icon {
                                anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                visible: lengthRow.current
                                code: 0xEA5E
                                color: root.accent
                                font.pixelSize: 16
                            }
                            HoverHandler { id: lengthHover }
                            ClickArea { anchors.fill: parent; onClicked: root.lengthPick(lengthRow.modelData.value) }
                        }
                    }
                }
            }
        }
    }

    readonly property var priority: Config.barOverflowOrder.filter(id => !Config.barStays(id)).reverse()
    function priorityScroll(y) { prioFlick.contentY = Math.max(0, Math.min(prioFlick.contentHeight - prioFlick.height, y)); }
    readonly property var priorityState: ({ open: prioritising, list: priority, scroll: prioFlick.contentY, scrollMax: Math.max(0, prioFlick.contentHeight - prioFlick.height), lengthMenu: lengthMenuOpen, length: length.label })
    function priorityMove(id, slot) {          // (tests: as a row dragged to a place and let go)
        if (priority.indexOf(id) < 0) return;
        prioList.held = id; prioList.moving = priority.slice();
        prioList.moveTo(slot);
        prioList.drop();
    }
    function lengthMenu(open) { dropLayer.owner = open ? (prioritising ? prioShorter : panelShorter) : null; }
    function lengthPick(value) { dropLayer.owner = null; Config.barPreview = value; }
    readonly property bool lengthMenuOpen: dropLayer.owner !== null

    // While the bar's being arranged, everything under it is heavily dimmed: every screen's
    // windows and desktop, under a dark wash that also takes the clicks, so nothing beneath is
    // touched. Above the windows and below the bar (which goes up a layer meanwhile) and this panel
    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            visible: root.shown || root.fade > 0
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.namespace: "slate-bar-dim"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            Rectangle {
                anchors.fill: parent
                color: Config.shade(0.94)
                opacity: root.fade
            }
            MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
        }
    }

    // What's being dragged, from the bar or from the pool, under the pointer wherever it goes
    // (Config.barFloat): a window of its own over the whole screen, which the pointer goes
    // straight through. Drawn as it is on the bar while that's being arranged: its icons in a
    // container; a flexible space and an empty container as their outlines. Let go over a gap
    // on the bar, it glides into it (Config.barLanding) before it's moved there
    function iconColour(item) {
        return item === "power" ? bar.errorColor
            : item === "nova" ? (Config.colourful ? Config.pageColour("assistant") : root.text)
            : item === "apps" ? Config.partColour(Config.appsPastels, 0, root.text)
            : item === "spaces" ? Config.partColour(Config.spacesPastels, 0, root.text)
            : Config.statusColour(item, root.text);
    }
    PanelWindow {
        screen: root.screen
        visible: !!Config.barFloat
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.namespace: "slate-bar-drag"
        WlrLayershell.layer: WlrLayer.Overlay
        mask: Region {}
        Rectangle {
            id: floater
            readonly property var f: Config.barFloat
            readonly property bool hollow: !!f && (f.kind === "space" || f.kind === "fixed" || (f.kind === "box" && f.icons.length === 0))
            x: Config.barFloatAt.x - (root.screen ? root.screen.x : 0) - width / 2
            y: Config.barFloatAt.y - (root.screen ? root.screen.y : 0) - height / 2
            Behavior on x { enabled: Config.barLanding; NumberAnimation { duration: Config.ms(120); easing.type: Easing.OutCubic } }
            Behavior on y { enabled: Config.barLanding; NumberAnimation { duration: Config.ms(120); easing.type: Easing.OutCubic } }
            width: Math.max(root.bar.capsuleHeight + 8, floatRow.implicitWidth + 18)
            height: root.bar.capsuleHeight
            radius: Config.corner(root.bar.capsuleRadius)
            color: hollow ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.14) : root.bar.capsuleSolid
            border.width: 1
            border.color: root.accent
            // (pulled well off the bar: fading, as it's about to go back to the pool)
            opacity: Config.barLeaving ? 0.45 : 0.95
            Behavior on opacity { NumberAnimation { duration: Config.ms(120) } }
            Shadow {}
            Row {
                id: floatRow
                anchors.centerIn: parent
                spacing: 12
                Repeater {
                    model: floater.f ? floater.f.icons : []
                    Row {
                        required property var modelData
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        DotsPicture { visible: parent.modelData.item === "workspaces"; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            visible: parent.modelData.item !== "workspaces"
                            anchors.verticalCenter: parent.verticalCenter
                            text: parent.modelData.code ? Config.glyph(parent.modelData.code) : ""
                            color: root.iconColour(parent.modelData.item)
                            font.family: root.bar.iconFont; font.pixelSize: 16
                        }
                        // (its text, as on the bar)
                        Text {
                            visible: text !== ""
                            anchors.verticalCenter: parent.verticalCenter
                            textFormat: Text.PlainText        // never markup
                            text: parent.modelData.text || ""
                            color: root.text
                            font.family: root.bar.fontFamily; font.pixelSize: Config.text(root.bar.fontSize); font.weight: Font.Medium
                        }
                    }
                }
            }
        }
    }
}
