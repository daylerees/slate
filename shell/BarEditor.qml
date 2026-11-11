// Arranging the menu bar (Settings → Menu Bar → Edit layout): a panel that sits just off the
// bar for as long as the bar is being arranged (Config.barArranging). The dragging itself
// happens on the bar (Bar.qml); here are the things that go with it:
//   - Done, which ends it (every change is saved as it's made);
//   - the pool: what isn't on the bar, drawn as it would be there, and the three things there
//     are always more of (a container, a flexible space). A chip is clicked,
//     or dragged onto the bar, which is another window: this one works out where the pointer
//     is on the desktop (where this window is, from one look at Hyprland's pointer position as
//     the chip is pressed, then the pointer's place in the window) and tells the bar
//     (Config.barCarry, barCarryAt), which shows where it would land;
//   - the options of whatever is picked on the bar (Config.barSelected, barSelectedItem):
//     a container (its collapse button too), one thing in it, a flexible space, the active window.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: root
    required property var bar
    property var confirmer: null           // PowerConfirm: asks before putting the defaults back

    readonly property bool shown: Config.barArranging
    property real fade: shown ? 1 : 0
    Behavior on fade { NumberAnimation { duration: Config.ms(180); easing.type: Easing.OutCubic } }
    // Menu item priority (Set priority): this panel gives way to a window of its own, and comes
    // back after
    readonly property bool prioritising: shown && Config.barPrioritising
    property real turn: prioritising ? 1 : 0
    Behavior on turn { NumberAnimation { duration: Config.ms(160); easing.type: Easing.OutCubic } }

    // ---- Look: the bar's own colours, as Settings uses them ----------------------
    readonly property color text: bar.textColor
    readonly property color dim: Config.tint("#8b94a3")
    readonly property color accent: bar.accent
    readonly property color accentText: Config.tint("#12151a")
    readonly property color danger: bar.errorColor
    readonly property color control: Config.raised(Config.tint("#2a313c"))
    // (under the pointer: a button, and a switch's track, as in Settings)
    readonly property color controlLit: Config.hover
    readonly property color knobLit: Config.hover
    readonly property color divider: Config.tint("#262c35")
    function glyph(code) { return String.fromCodePoint(code); }

    // ---- Where: just off the bar, on its screen ------------------------------------
    screen: bar.screen
    readonly property string side: bar.side
    readonly property bool vert: side === "left" || side === "right"
    readonly property int pad: 30                      // room round the panel for its shadow
    // (a little further off while the bar has its scroll handle under it)
    readonly property real off: bar.barHeight + (bar.scrollMax > 0 ? 24 : 10) - pad
    visible: shown || fade > 0
    anchors { top: side !== "bottom"; bottom: side === "bottom"; left: side === "left"; right: side === "right" }
    margins.top: side === "top" ? off : vert ? 40 : 0
    margins.bottom: side === "bottom" ? off : 0
    margins.left: side === "left" ? off : 0
    margins.right: side === "right" ? off : 0
    implicitWidth: Math.max(panel.width, prio.width) + pad * 2
    implicitHeight: Math.max(panel.visible ? panel.height : 0, prio.visible ? prio.height : 0) + pad * 2
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "slate-bar-editor"
    WlrLayershell.layer: WlrLayer.Overlay
    // The keyboard is this panel's while the bar's arranged. Nothing typed reaches a window out
    // of sight under the wallpaper, and it's what lets a drag leave the bar: Hyprland only
    // keeps a pressed pointer with the surface it was pressed on while something has the
    // keyboard, and with no window focused nothing did, so the drag ended at the bar's edge
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    mask: Region { item: root.prioritising ? prio : panel }

    // ---- What's picked on the bar ---------------------------------------------------
    readonly property var picked: Config.barSelected >= 0 ? (Config.barLayout[Config.barSelected] || null) : null
    readonly property string pickedItem: Config.barSelectedItem
    readonly property string kind: !picked ? "none" : picked === "space" ? "space"
        : pickedItem !== "" ? "item" : "box"
    readonly property var pickedThings: picked && typeof picked !== "string" ? picked.items.filter(id => id !== "tuck") : []
    // (how the picked container collapses: "never", "always" or "needed"; and whether it has a
    // collapse button at all, to set up)
    readonly property string pickedCollapse: !!picked && typeof picked !== "string" ? (picked.collapse || "needed") : ""
    readonly property bool pickedTuck: pickedCollapse === "always" || pickedCollapse === "needed"
    function nameOf(id) { const it = Config.barItem(id); return it ? it.label : id; }
    readonly property string textKey: kind === "item" ? (Config.barTextKeys[pickedItem] || "") : ""

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
                try {
                    const p = JSON.parse(text);
                    root.origin = Qt.point(p.x - root.pointer.x, p.y - root.pointer.y);
                    root.placed = true;
                } catch (e) {}
            }
        }
    }
    function pressed(x, y) { pointer = Qt.point(x, y); placed = false; whereAmI.running = true; }
    function carryTo(chip, x, y) {
        pointer = Qt.point(x, y);
        if (!carrying) {
            carrying = chip;
            Config.barCarryAt = Qt.point(-100000, -100000);
            Config.barFloatAt = Qt.point(-100000, -100000);
            Config.barFloat = { kind: chip.carry.kind, label: "",
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
    component Heading: Text {
        color: root.dim
        font.family: root.bar.fontFamily; font.pixelSize: 11; font.weight: Font.Medium
    }
    component Line: Rectangle { width: parent ? parent.width : 0; height: 1; color: root.divider }
    // (a button and a switch as Settings draws them: SettingsWindow.qml's Button and Toggle)
    component PanelButton: Rectangle {
        id: btn
        property string label
        property int icon: 0
        property bool primary: false
        property bool destructive: false
        signal clicked()
        width: btnRow.implicitWidth + 28; height: 32; radius: 8
        color: primary ? root.accent
            : btnHover.hovered ? root.controlLit : root.control
        Behavior on color { ColorAnimation { duration: Config.ms(100) } }
        readonly property color fg: primary ? root.accentText : destructive ? root.danger : root.text
        Row {
            id: btnRow
            anchors.centerIn: parent
            spacing: 6
            Text {
                visible: btn.icon !== 0
                anchors.verticalCenter: parent.verticalCenter
                text: btn.icon ? root.glyph(btn.icon) : ""
                color: btn.fg
                font.family: root.bar.iconFont; font.pixelSize: 15
            }
            Text {
                visible: btn.label !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: btn.label
                color: btn.fg
                font.family: root.bar.fontFamily; font.pixelSize: 12; font.weight: Font.Medium
            }
        }
        HoverHandler { id: btnHover }
        ClickTap { onTapped: btn.clicked() }
    }
    // A switch with its name before it
    component Switch: Row {
        id: sw
        property string label
        property bool checked: false
        signal toggled(bool value)
        spacing: 10
        height: 32
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: sw.label
            color: root.text
            font.family: root.bar.fontFamily; font.pixelSize: 12; font.weight: Font.Medium
        }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 42; height: 24; radius: 12
            color: sw.checked ? root.accent
                : (swHover.hovered ? root.knobLit : root.control)
            Behavior on color { ColorAnimation { duration: Config.ms(120) } }
            // Hover: a soft accent ring around the switch
            Rectangle {
                anchors { fill: parent; margins: -3 }
                radius: height / 2
                color: "transparent"
                border.width: 2; border.color: root.accent
                opacity: swHover.hovered ? 0.35 : 0
                Behavior on opacity { NumberAnimation { duration: Config.ms(120) } }
            }
            Gloss { radius: parent.radius }   // glass: a sheen
            Rectangle {
                width: 18; height: 18; radius: 9
                anchors.verticalCenter: parent.verticalCenter
                x: sw.checked ? parent.width - width - 3 : 3
                color: sw.checked ? root.accentText : root.text
                Behavior on x { NumberAnimation { duration: Config.ms(140); easing.type: Easing.OutCubic } }
            }
            HoverHandler { id: swHover }
            ClickTap { onTapped: sw.toggled(!sw.checked) }
        }
    }
    // A paragraph of explanation
    component Para: Text {
        width: parent ? parent.width : 0
        wrapMode: Text.WordWrap
        lineHeight: 1.2
        color: root.text
        font.family: root.bar.fontFamily; font.pixelSize: 12
    }
    // The bar tried shorter, to see what slims down and what leaves
    component Shorter: Flow {
        spacing: 6
        Text {
            height: 32
            verticalAlignment: Text.AlignVCenter
            rightPadding: 4
            text: "Try it shorter"
            color: root.text
            font.family: root.bar.fontFamily; font.pixelSize: 12; font.weight: Font.Medium
        }
        Repeater {
            model: [{ value: 0, label: "Full length" }, { value: 0.25, label: "Three quarters" }, { value: 0.5, label: "Half" }, { value: 0.67, label: "A third" }]
            PanelButton {
                required property var modelData
                label: modelData.label
                primary: Math.abs(Config.barPreview - modelData.value) < 0.01
                onClicked: Config.barPreview = modelData.value
            }
        }
    }
    // The workspace dots as a picture of themselves: four, the first the one you're on, the
    // next with windows on it (for the pool's chip and what's carried, in place of an icon)
    component WorkspaceDots: Row {
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
        readonly property color iconColour: item === "power" ? root.bar.errorColor
            : item === "chalk" ? (Config.colourful ? Config.pageColour("assistant") : root.text)
            : item === "apps" ? Config.partColour(Config.appsPastels, 0, root.text)
            : item === "spaces" ? Config.partColour(Config.spacesPastels, 0, root.text)
            : Config.statusColour(item, root.text)
        width: chipRow.implicitWidth + (grip ? 16 : 24); height: root.bar.capsuleHeight
        radius: root.bar.capsuleRadius
        color: root.bar.capsuleColor
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: root.bar.hoverFill
            opacity: barChip.lit ? root.bar.hoverStrength : 0
            Behavior on opacity { NumberAnimation { duration: Config.ms(120) } }
        }
        Gloss { radius: parent.radius }   // glass: a sheen, as on the bar's containers
        Row {
            id: chipRow
            anchors.centerIn: parent
            // (with a gripper: nearer the chip's start, where the bar's containers have theirs)
            anchors.horizontalCenterOffset: barChip.grip ? -3 : 0
            spacing: 7
            // (as on the bar's containers while it's arranged: pick it up here, or anywhere on it)
            Text {
                visible: barChip.grip
                anchors.verticalCenter: parent.verticalCenter
                text: root.glyph(0xEC01)
                color: barChip.lit ? root.text : root.dim
                font.family: root.bar.iconFont; font.pixelSize: 13
            }
            Image {
                visible: barChip.item === "control"
                anchors.verticalCenter: parent.verticalCenter
                width: 16; height: 16
                sourceSize: Qt.size(32, 32)
                source: visible ? "file://" + Quickshell.shellPath("assets/icon/icon-64.png") : ""
            }
            WorkspaceDots { visible: barChip.item === "workspaces"; anchors.verticalCenter: parent.verticalCenter }
            Text {
                visible: barChip.item !== "control" && barChip.item !== "workspaces"
                anchors.verticalCenter: parent.verticalCenter
                text: barChip.icon ? root.glyph(barChip.icon) : ""
                color: barChip.iconColour
                font.family: root.bar.iconFont; font.pixelSize: 16
                ChalkFace {}
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: barChip.label !== ""
                text: barChip.label
                color: root.text
                font.family: root.bar.fontFamily; font.pixelSize: root.bar.fontSize; font.weight: Font.Medium
            }
        }
    }
    // A chip in the pool: clicked, or dragged onto the bar. Silent while dragged, a click when
    // it lands, as everywhere
    component PoolChip: BarChip {
        id: chip
        property var carry: null             // what the bar is told is coming: { kind, id }
        signal clicked()
        grip: true
        item: carry && carry.kind === "item" ? carry.id : ""
        lit: chipHover.hovered
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
    Rectangle {
        id: panel
        x: root.pad; y: root.pad
        width: root.vert ? 380 : Math.min(860, (root.screen ? root.screen.width : 900) - 2 * root.pad - 16)
        height: body.implicitHeight + 24
        radius: 16
        color: root.bar.barColor
        opacity: root.fade * (1 - root.turn)
        visible: opacity > 0
        border.width: Config.glassShine ? 1 : 0
        border.color: Config.glassEdge
        Shadow { blur: 22; dropY: 4 }      // raised: Slate's shadow, with glass too
        Gloss { radius: parent.radius; strength: 0.6 }     // glass: a sheen, as on Slate's panels
        MouseArea { anchors.fill: parent }       // (a click on the panel itself does nothing)
        // (Escape ends the arranging, as Done does)
        focus: root.shown && !root.prioritising
        Keys.onEscapePressed: Config.barArranging = false

        Column {
            id: body
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: 12; leftMargin: 14; rightMargin: 14 }
            spacing: 10

            // Title and Done
            Item {
                width: parent.width; height: 36
                Column {
                    anchors { left: parent.left; right: defaults.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    spacing: 1
                    Text {
                        text: "Arranging the menu bar"
                        color: root.text
                        font.family: root.bar.fontFamily; font.pixelSize: 15
                    }
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: "Drag things along the bar, into and out of containers, or to and from here. Click one for its options"
                        color: root.dim
                        font.family: root.bar.fontFamily; font.pixelSize: 11
                    }
                }
                PanelButton {
                    id: defaults
                    anchors { right: done.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    visible: !Config.barIsDefault
                    label: "Defaults"
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
                    id: done
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    primary: true
                    label: "Done"
                    onClicked: Config.barArranging = false
                }
            }
            Line {}

            // The pool
            Heading {
                text: Config.barLeaving ? "Let go to take it off the bar. It waits here, and keeps its place"
                    : root.pool.length === 0 ? "Everything's on the bar. Drag something off it and it waits here"
                    : "Not on the bar"
                color: Config.barLeaving ? root.accent : root.dim
            }
            Flow {
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
            }
            Line {}

            // If it doesn't fit (plans/menubar-length.md): menu item priority, which has a window
            // of its own (below), and a way to see it happen: the bar tried shorter
            Item {
                width: parent.width; height: 32
                Heading {
                    anchors { left: parent.left; right: priorityButton.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    elide: Text.ElideRight
                    text: "When the bar runs short of room, things slim down, then leave for More, lowest priority first"
                }
                PanelButton {
                    id: priorityButton
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    label: "Set priority"
                    onClicked: Config.barPrioritising = true
                }
            }
            Shorter { width: parent.width }
            Line {}

            // What's picked, and its options
            Heading {
                width: parent.width
                elide: Text.ElideRight
                text: root.kind === "none" ? "Nothing picked. Click something on the bar to see its options"
                    : root.kind === "space" ? "A flexible space: it takes up the spare room, pushing what's either side of it apart"
                        + (Config.barSpaces < 2 ? ". The bar always keeps one" : "")
                    : root.kind === "item" && root.pickedItem === "more" ? "More: what there isn't room for on the bar waits behind it. It shows when something does, and stays on the bar"
                    : root.kind === "item" ? root.nameOf(root.pickedItem)
                    : "A container: " + (root.pickedThings.length > 0 ? root.pickedThings.map(root.nameOf).join(", ") : "nothing in it yet. Drag things into it")
            }
            Flow {
                width: parent.width
                spacing: 14
                visible: root.kind !== "none"

                // One thing
                Switch {
                    visible: root.textKey !== ""
                    label: "Show its text"
                    checked: root.textKey !== "" && !!Config.s[root.textKey]
                    onToggled: v => Config.s[root.textKey] = v
                }
                Switch {
                    visible: root.kind === "item" && root.pickedItem !== "more"
                    label: "Always keep on the bar"
                    checked: Config.barStays(root.pickedItem)
                    onToggled: v => Config.barSetStay(root.pickedItem, v)
                }
                Switch {
                    visible: root.kind === "item" && root.pickedItem === "tray"
                    label: "Tuck its icons away"
                    checked: Config.s.barTrayCollapsed
                    onToggled: v => Config.s.barTrayCollapsed = v
                }
                Row {
                    visible: root.kind === "item" && root.pickedItem === "clock"
                    spacing: 6
                    PanelButton {
                        label: "12-hour"
                        primary: Config.s.barClockFormat !== "24h"
                        onClicked: Config.s.barClockFormat = "12h"
                    }
                    PanelButton {
                        label: "24-hour"
                        primary: Config.s.barClockFormat === "24h"
                        onClicked: Config.s.barClockFormat = "24h"
                    }
                }
                Switch {
                    visible: root.kind === "item" && root.pickedItem === "clock"
                    label: "Date"
                    checked: Config.s.barClockDate
                    onToggled: v => Config.s.barClockDate = v
                }
                Switch {
                    visible: root.kind === "item" && root.pickedItem === "clock"
                    label: "Seconds"
                    checked: Config.s.barClockSeconds
                    onToggled: v => Config.s.barClockSeconds = v
                }

                // A container
                // How it collapses: tucked behind a button always, only when the bar's short of
                // room, or never (with one thing in it there's nothing to tuck)
                Row {
                    visible: root.kind === "box" && root.pickedThings.length > 1
                    spacing: 6
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        rightPadding: 4
                        text: "Collapse"
                        color: root.text
                        font.family: root.bar.fontFamily; font.pixelSize: 12; font.weight: Font.Medium
                    }
                    Repeater {
                        model: [{ value: "never", label: "Never" }, { value: "needed", label: "When needed" }, { value: "always", label: "Always" }]
                        PanelButton {
                            required property var modelData
                            label: modelData.label
                            primary: root.pickedCollapse === modelData.value
                            onClicked: Config.barSetCollapse(Config.barSelected, modelData.value)
                        }
                    }
                }
                // ...its button's icon, and which end it sits at
                Row {
                    visible: root.kind === "box" && root.pickedThings.length > 1 && root.pickedTuck
                    spacing: 6
                    Repeater {
                        model: [0xEC38, 0xEA95, 0xEA94, 0xEA60, 0xEA61, 0xEC42, 0xEB0B, 0xEA9A]
                        PanelButton {
                            required property int modelData
                            icon: modelData
                            primary: root.pickedTuck && (parseInt(root.picked.tuckIcon, 16) || 0xEC38) === modelData
                            onClicked: Config.barSetTuck(Config.barSelected, undefined, modelData === 0xEC38 ? "" : modelData.toString(16))
                        }
                    }
                }
                Row {
                    visible: root.kind === "box" && root.pickedThings.length > 1 && root.pickedTuck
                    spacing: 6
                    PanelButton {
                        label: "At the start"
                        primary: root.pickedTuck && root.picked.tuckFrom === "start"
                        onClicked: Config.barSetTuck(Config.barSelected, undefined, undefined, "start")
                    }
                    PanelButton {
                        label: "At the end"
                        primary: root.pickedTuck && root.picked.tuckFrom !== "start"
                        onClicked: Config.barSetTuck(Config.barSelected, undefined, undefined, "end")
                    }
                }

                PanelButton {
                    visible: root.kind === "box" && root.pickedThings.length > 1
                    label: "Split up"
                    onClicked: Config.barSplit(Config.barSelected)
                }

                // Off the bar
                PanelButton {
                    // (the last flexible space stays: something has to take up the spare room. And
                    // More, which holds what doesn't fit, is never off the bar)
                    visible: root.kind !== "none" && !(root.kind === "space" && Config.barSpaces < 2)
                        && !(root.kind === "item" && root.pickedItem === "more")
                    destructive: true
                    label: root.kind === "space" ? "Take away" : "Take off the bar"
                    onClicked: {
                        if (root.kind === "item") Config.barSetShown(root.pickedItem, false);
                        else Config.barRemoveEntry(Config.barSelected);
                        Config.barSelected = -1;
                    }
                }
            }
        }
    }

    // ---- Menu item priority -------------------------------------------------------------
    // What the bar does when it's short of room (plans/menubar-length.md), explained, beside the
    // one part of it that's yours to set: the order things leave for More. Shown highest
    // priority first (the last to leave), so it's Config.barOverflowOrder backwards, without
    // what always stays, which never leaves and so has no place in it
    readonly property var priority: Config.barOverflowOrder.filter(id => !Config.barStays(id)).reverse()
    readonly property var priorityState: ({ open: prioritising, list: priority })
    function priorityMove(id, slot) {          // (tests: as a row dragged to a place and let go)
        if (priority.indexOf(id) < 0) return;
        prioList.held = id; prioList.moving = priority.slice();
        prioList.moveTo(slot);
        prioList.drop();
    }
    Rectangle {
        id: prio
        x: root.pad; y: root.pad
        width: panel.width
        height: prioBody.y + prioBody.height + 14
        radius: 16
        color: root.bar.barColor
        opacity: root.fade * root.turn
        visible: opacity > 0
        border.width: Config.glassShine ? 1 : 0
        border.color: Config.glassEdge
        Shadow { blur: 22; dropY: 4 }
        Gloss { radius: parent.radius; strength: 0.6 }
        MouseArea { anchors.fill: parent }
        // (Escape goes back to the arranging)
        focus: root.prioritising
        Keys.onEscapePressed: Config.barPrioritising = false

        Item {
            id: prioTop
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: 12; leftMargin: 14; rightMargin: 14 }
            height: 36
            Column {
                anchors { left: parent.left; right: prioBack.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                spacing: 1
                Text {
                    text: "Menu item priority"
                    color: root.text
                    font.family: root.bar.fontFamily; font.pixelSize: 15
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: "What stays on the bar longest when there isn't room for everything"
                    color: root.dim
                    font.family: root.bar.fontFamily; font.pixelSize: 11
                }
            }
            PanelButton {
                id: prioBack
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                primary: true
                icon: 0xEA60
                label: "Back"
                onClicked: Config.barPrioritising = false
            }
        }
        Rectangle {
            id: prioLine
            anchors { top: prioTop.bottom; topMargin: 10; left: prioTop.left; right: prioTop.right }
            height: 1; color: root.divider
        }

        // The explanation on one side, the list on the other (one above the other by a bar
        // that's down a side of the screen, where the window's narrow)
        Item {
            id: prioBody
            anchors { top: prioLine.bottom; topMargin: 12; left: prioTop.left; right: prioTop.right }
            readonly property real room: Math.max(260, (root.screen ? root.screen.height : 800) - root.bar.barHeight - 190)
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
                           : names.slice(0, -1).join(", ") + " and " + names[names.length - 1] + " always stay, so they aren't listed.")
                        + " To change that, go back, click something on the bar and use Always keep on the bar."
                }
                Item { width: 1; height: 4 }
                Shorter { width: parent.width }
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
                            radius: 8
                            y: isHeld ? prioList.heldY : prioList.shown.indexOf(modelData) * prioList.step
                            z: isHeld ? 2 : 0
                            // (the others step out of the way of the one being dragged)
                            Behavior on y {
                                enabled: prioList.held !== "" && !prioRow.isHeld
                                NumberAnimation { duration: Config.ms(140); easing.type: Easing.OutCubic }
                            }
                            color: isHeld ? root.bar.capsuleSolid : root.control
                            border.width: isHeld ? 1 : 0
                            border.color: root.accent
                            Rectangle {
                                anchors.fill: parent
                                radius: parent.radius
                                color: root.controlLit
                                opacity: prioRow.lit && !prioRow.isHeld ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: Config.ms(100) } }
                            }
                            Shadow { visible: prioRow.isHeld; blur: 14; dropY: 3 }
                            Row {
                                anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                                spacing: 10
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.glyph(0xEC01)
                                    color: prioRow.lit ? root.text : root.dim
                                    font.family: root.bar.iconFont; font.pixelSize: 14
                                }
                                BarChip {
                                    anchors.verticalCenter: parent.verticalCenter
                                    item: prioRow.modelData
                                    icon: prioRow.it ? prioRow.it.icon : 0
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: prioRow.it ? prioRow.it.label : prioRow.modelData
                                    color: root.text
                                    font.family: root.bar.fontFamily; font.pixelSize: 12; font.weight: Font.Medium
                                }
                            }
                            Text {
                                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                visible: !Config.barShown(prioRow.modelData)
                                text: "Not on the bar"
                                color: root.dim
                                font.family: root.bar.fontFamily; font.pixelSize: 11
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
                ThinScrollbar {
                    flick: prioFlick
                    color: root.text
                    anchors { top: prioFlick.top; bottom: prioFlick.bottom; left: prioFlick.right; leftMargin: 8 }
                }
            }
        }
    }

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
    // container; a flexible space and an empty container as their outlines
    function iconColour(item) {
        return item === "power" ? bar.errorColor
            : item === "chalk" ? (Config.colourful ? Config.pageColour("assistant") : root.text)
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
            readonly property bool hollow: !!f && (f.kind === "space" || (f.kind === "box" && f.icons.length === 0))
            x: Config.barFloatAt.x - (root.screen ? root.screen.x : 0) - width / 2
            y: Config.barFloatAt.y - (root.screen ? root.screen.y : 0) - height / 2
            width: Math.max(root.bar.capsuleHeight + 8, floatRow.implicitWidth + 18)
            height: root.bar.capsuleHeight
            radius: root.bar.capsuleRadius
            color: hollow ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.14) : root.bar.capsuleSolid
            border.width: 1
            border.color: root.accent
            // (pulled well off the bar: fading, as it's about to go back to the pool)
            opacity: Config.barLeaving ? 0.45 : 0.95
            Behavior on opacity { NumberAnimation { duration: Config.ms(120) } }
            Shadow { blur: 14; dropY: 3 }
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
                        WorkspaceDots { visible: parent.modelData.item === "workspaces"; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            visible: parent.modelData.item !== "workspaces"
                            anchors.verticalCenter: parent.verticalCenter
                            text: parent.modelData.code ? root.glyph(parent.modelData.code) : ""
                            color: root.iconColour(parent.modelData.item)
                            font.family: root.bar.iconFont; font.pixelSize: 16
                            ChalkFace {}
                        }
                        // (its text, as on the bar)
                        Text {
                            visible: text !== ""
                            anchors.verticalCenter: parent.verticalCenter
                            text: parent.modelData.text || ""
                            color: root.text
                            font.family: root.bar.fontFamily; font.pixelSize: root.bar.fontSize; font.weight: Font.Medium
                        }
                    }
                }
                Text {
                    visible: text !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: floater.f ? floater.f.label : ""
                    color: root.text
                    font.family: root.bar.fontFamily; font.pixelSize: root.bar.fontSize; font.weight: Font.Medium
                }
            }
        }
    }
}
