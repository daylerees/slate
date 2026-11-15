import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.UPower
import Quickshell.Services.Pipewire
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.Mpris
import QtQuick.Effects
import qs

// ---- Spaces -----------------------------------------------------------
// Saved sets of workspaces (Spaces.qml, scripts/spaces.py): click one to bring it back on
// new workspaces, or save the workspaces you have now as a new one
Column {
    required property var pop
    id: spacesView
    width: 440
    spacing: 10
    property string mode: "list"          // list, or new (saving the workspaces now)
    // New Space
    property var picked: []               // workspace ids
    property string name: ""
    property int icon: Spaces.icons[0]
    property color colour: Spaces.colours[0]
    property bool custom: false           // a colour of your own (hue strip and hex)
    readonly property var sameName: Spaces.list.find(s => s.name.toLowerCase() === name.trim().toLowerCase()) ?? null
    readonly property bool canSave: name.trim() !== "" && picked.length > 0
    readonly property color inkColour: "#1b1f26"      // icons on a pastel

    // The workspace you're on starts picked, once the list of workspaces with apps is in,
    // and only if it's on it (an empty one has nothing to save)
    property int autoPick: -1
    Connections {
        target: Spaces
        function onLiveChanged() {
            if (spacesView.autoPick < 0) return;
            spacesView.picked = Spaces.live.some(w => w.id === spacesView.autoPick) ? [spacesView.autoPick] : [];
            spacesView.autoPick = -1;
        }
    }
    Connections { target: pop; function onNewSpaceAsked() { spacesView.startNew(); } }
    function startNew() {
        const ws = Hyprland.focusedWorkspace;
        picked = [];
        autoPick = ws ? ws.id : -1;
        Spaces.refreshLive();
        name = "";
        custom = false;
        // A colour and icon no saved space uses yet
        const used = Spaces.list.map(s => String(s.colour).toLowerCase());
        colour = Spaces.colours.find(c => !used.includes(c)) ?? Spaces.colours[0];
        const usedIcons = Spaces.list.map(s => Spaces.iconOf(s));
        icon = Spaces.icons.find(i => !usedIcons.includes(i)) ?? Spaces.icons[0];
        mode = "new";
    }
    function toggle(id) { picked = picked.includes(id) ? picked.filter(x => x !== id) : picked.concat([id]).sort((a, b) => a - b); }
    function save() {
        if (!canSave) return;
        Spaces.save(name.trim(), colour.toString(), icon, picked);
        mode = "list";
    }
    Connections {
        target: pop
        function onCurrentChanged() { if (pop.current === "spaces") { spacesView.mode = "list"; } }
    }

    // ---- The saved spaces ----
    PanelTitle {
        visible: spacesView.mode === "list"
        text: "Spaces"
        height: 22
        Label {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            visible: Spaces.list.length > 0
            text: Spaces.list.length === 1 ? "1 space" : Spaces.list.length + " spaces"
            color: pop.dim; font.weight: Font.Normal
        }
    }
    Label {
        visible: spacesView.mode === "list" && Spaces.list.length === 0
        width: parent.width
        text: "Set up your apps across workspaces the way you like them, then save them as a space to bring them all back in one click"
        color: pop.dim; font.weight: Font.Normal; wrapMode: Text.Wrap
    }
    // The saved spaces. Past five they scroll (about four and a half show, to say
    // there's more), with a soft shadow at an edge that has more beyond it
    Item {
        id: spListBox
        visible: spacesView.mode === "list" && Spaces.list.length > 0
        width: parent.width
        readonly property real rowH: 52
        readonly property bool overflow: Spaces.list.length > 5
        height: overflow ? Math.round(rowH * 4.5 + 6 * 4) : spListCol.height
        Flickable {
            id: spListFlick
            anchors.fill: parent
            contentHeight: spListCol.height
            clip: true
            interactive: spListBox.overflow
            boundsBehavior: Flickable.StopAtBounds
            SmoothWheel { flick: spListFlick; enabled: spListBox.overflow }
            Column {
                id: spListCol
                width: spListBox.width - (spListBox.overflow ? 18 : 0)
                spacing: 6
                Repeater {
                    model: Spaces.list
                    delegate: RowButton {
                        id: spRow
                        required property var modelData
                        readonly property bool busy: Spaces.restoring === modelData.id
                        readonly property var appIds: Spaces.apps(modelData)
                        width: parent.width
                        height: 52
                        onClicked: { if (Spaces.restoring !== "") return; Spaces.restore(modelData.id); pop.close(); }
                        HoverHandler { id: spRowHover }
                        Rectangle {
                            id: spBadge
                            anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                            width: 34; height: 34; radius: Config.corner(9)
                            color: spRow.modelData.colour
                            Icon { anchors.centerIn: parent; code: Spaces.iconOf(spRow.modelData); color: spacesView.inkColour; font.pixelSize: 19 }
                        }
                        Column {
                            anchors { left: spBadge.right; leftMargin: 10; right: spSide.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                            spacing: 2
                            Label { width: parent.width; text: spRow.modelData.name }
                            Label {
                                width: parent.width
                                readonly property int nWs: (spRow.modelData.workspaces || []).length
                                readonly property int nApps: Spaces.appCount(spRow.modelData)
                                text: spRow.busy ? "Opening…"
                                    : (nWs === 1 ? "1 workspace" : nWs + " workspaces") + " · " + (nApps === 1 ? "1 app" : nApps + " apps")
                                color: pop.dim; font.weight: Font.Normal; font.pixelSize: 12
                            }
                        }
                        // Its apps, or, under the pointer, a delete button (asks first, in
                        // the middle of the screen)
                        Item {
                            id: spSide
                            anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                            width: spRowHover.hovered ? spDel.width : spApps.width
                            height: 28
                            Row {
                                id: spApps
                                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                visible: !spRowHover.hovered
                                spacing: -5
                                Repeater {
                                    model: spRow.appIds.slice(0, 4)
                                    AppTile { required property string modelData; app: modelData; width: 22; height: 22 }
                                }
                                Label {
                                    visible: spRow.appIds.length > 4
                                    anchors.verticalCenter: parent.verticalCenter
                                    leftPadding: 8
                                    text: "+" + (spRow.appIds.length - 4)
                                    color: pop.dim; font.pixelSize: 11
                                }
                            }
                            Rectangle {
                                id: spDel
                                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                visible: !spApps.visible
                                width: 28; height: 28; radius: Config.corner(7)
                                color: spDelHover.hovered ? Config.hoverDanger : "transparent"
                                Icon { anchors.centerIn: parent; code: 0xEB41; font.pixelSize: 16; color: pop.danger }
                                HoverHandler { id: spDelHover }
                                // A MouseArea, so the click stops here rather than also opening the space
                                ClickArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        const sp = spRow.modelData;
                                        pop.close();
                                        if (!pop.powerConfirm) return;
                                        pop.powerConfirm.confirmWith({
                                            title: "Delete \u201c" + sp.name + "\u201d?",
                                            body: "Slate will forget this space. Don't worry about anything that's open: its apps and windows stay just as they are.",
                                            button: "Delete", code: 0xEB41, danger: true
                                        }, () => Spaces.remove(sp.id));
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        // Scroll shades: at the top once scrolled down, and at the bottom while
        // there's more below
        ScrollShade { z: 3; width: spListBox.width - (spListBox.overflow ? 18 : 0); cornerRadius: 8
                      distance: spListFlick.contentY - spListFlick.originY }
        ScrollShade { z: 3; atBottom: true; y: spListBox.height - height; width: spListBox.width - (spListBox.overflow ? 18 : 0); cornerRadius: 8
                      distance: spListFlick.originY + spListFlick.contentHeight - spListFlick.height - spListFlick.contentY }
        ThinScrollbar {
            flick: spListFlick
            color: pop.text
            anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
        }
    }
    Divider { visible: spacesView.mode === "list" }
    LinkRow {
        visible: spacesView.mode === "list"
        code: 0xEB0B; text: "New Space"
        onClicked: spacesView.startNew()
    }
    LinkRow {
        visible: spacesView.mode === "list"
        code: 0xEB20; text: "Spaces settings"
        onClicked: pop.openSettingsPage("spaces")
    }

    // ---- New Space ----
    Item {
        visible: spacesView.mode === "new"
        width: parent.width; height: 26
        Rectangle {
            id: spBack
            width: 26; height: 26; radius: Config.corner(7)
            color: spBackHover.hovered ? Config.hover : "transparent"
            Icon { anchors.centerIn: parent; code: 0xEA60; font.pixelSize: 16; color: pop.dim }
            HoverHandler { id: spBackHover }
            ClickTap { onTapped: spacesView.mode = "list" }
        }
        PanelTitle { x: spBack.width + 6; width: parent.width - x; text: "New Space" }
    }
    Label {
        visible: spacesView.mode === "new"
        text: spacesView.picked.length === 0 ? "Pick the workspaces to save" : spacesView.picked.length === 1 ? "1 workspace" : spacesView.picked.length + " workspaces"
        color: pop.dim; font.weight: Font.Normal; font.pixelSize: 12
    }
    Label {
        visible: spacesView.mode === "new" && Spaces.live.length === 0
        width: parent.width
        text: "There's nothing to save just yet. Open the apps you'd like, arrange them how you like, then come back here"
        color: pop.dim; font.weight: Font.Normal; wrapMode: Text.Wrap
    }
    // Each workspace with apps, drawn small over the wallpaper; click to pick it.
    // Three to a row; past two rows the rest scroll (a little of the third shows,
    // to say there's more)
    Item {
        id: wsBox
        visible: spacesView.mode === "new" && Spaces.live.length > 0
        width: parent.width
        readonly property bool overflow: Math.ceil(Spaces.live.length / 3) > 2
        readonly property real cardW: Math.floor((width - 16 - (overflow ? 18 : 0)) / 3)
        readonly property real rowH: Math.round(cardW / Math.max(1, (Spaces.live[0] || {}).aspect || 1.6)) + 5 + 17 + 8
        height: overflow ? Math.round(rowH * 2.4) : wsFlow.height
        Flickable {
            id: wsFlick
            anchors.fill: parent
            contentHeight: wsFlow.height
            clip: true
            interactive: wsBox.overflow
            boundsBehavior: Flickable.StopAtBounds
            SmoothWheel { flick: wsFlick; enabled: wsBox.overflow }
            Flow {
                id: wsFlow
                width: wsBox.width - (wsBox.overflow ? 18 : 0)
                spacing: 8
                Repeater {
                    model: Spaces.live
                    delegate: Column {
                        id: wsCard
                        required property var modelData
                        readonly property bool on: spacesView.picked.includes(modelData.id)
                        width: wsBox.cardW
                        spacing: 5
                        Rectangle {
                            id: wsShot
                            width: parent.width
                            height: Math.round(width / Math.max(1, wsCard.modelData.aspect || 1.6))
                            radius: Config.corner(8)
                            color: Config.tint("#0b0d10")
                            clip: true
                            Image {
                                anchors.fill: parent
                                source: Config.wallpaper ? "file://" + Config.wallpaper : ""
                                sourceSize: Qt.size(320, 200)
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                opacity: wsCard.on ? 0.75 : 0.4
                                Behavior on opacity { NumberAnimation { duration: Config.ms(150) } }
                            }
                            Repeater {
                                // Tiled first, floating ones on top
                                model: wsCard.modelData.windows.slice().sort((a, b) => a.floating - b.floating)
                                delegate: Rectangle {
                                    id: wsWin
                                    required property var modelData
                                    x: wsShot.width * modelData.x; y: wsShot.height * modelData.y
                                    width: Math.max(6, wsShot.width * modelData.w - 1); height: Math.max(6, wsShot.height * modelData.h - 1)
                                    // The window's own rounding, scaled to the preview (but
                                    // enough to see; a square window stays square)
                                    radius: (modelData.rounding ?? 10) > 0
                                        ? Math.max(2.5, (modelData.rounding ?? 10) * wsShot.width / Math.max(1, wsCard.modelData.width || 1440)) : 0
                                    color: Qt.rgba(pop.card.r, pop.card.g, pop.card.b, 0.92)
                                    border.width: 1
                                    border.color: Qt.rgba(pop.text.r, pop.text.g, pop.text.b, 0.12)
                                    // The window itself, live while New Space is open
                                    // (as in the workspace overview)
                                    readonly property var toplevel: Hyprland.toplevels.values.find(t => "0x" + t.address === modelData.address || t.address === modelData.address) ?? null
                                    // Behind a see-through window: the wallpaper blurred as on
                                    // screen, from where the window sits on this card
                                    WallBlur {
                                        visible: !Config.gameMode           // game mode: no blur
                                        anchors.fill: wsLive
                                        win: Qt.rect(wsWin.modelData.x * wsShot.width, wsWin.modelData.y * wsShot.height,
                                                     wsWin.modelData.w * wsShot.width, wsWin.modelData.h * wsShot.height)
                                        screen: Qt.size(wsShot.width, wsShot.height)
                                        pixelScale: wsShot.width / Math.max(1, wsCard.modelData.width || 1440)
                                        radius: Config.corner(Math.max(0, wsWin.radius - 1))
                                        opacity: wsCard.on ? 1 : 0.6
                                    }
                                    WindowPreview {
                                        id: wsLive
                                        anchors.fill: parent
                                        anchors.margins: 1
                                        // Not in game mode: just the window's outline and app icon
                                        window: !Config.gameMode && pop.shown && spacesView.mode === "new" && wsWin.toplevel && wsWin.toplevel.wayland ? wsWin.toplevel.wayland : null
                                        address: wsWin.modelData.address || ""
                                        running: pop.shown && spacesView.mode === "new"
                                        smooth: true
                                        // Clipped to the window's rounded corners, and brightened
                                        // back if Hyprland dims it (it isn't focused)
                                        layer.enabled: true
                                        layer.effect: PreviewShape {
                                            radius: Config.corner(Math.max(0, wsWin.radius - 1))
                                            gain: wsWin.toplevel ? Config.undimGain(wsWin.toplevel.activated, wsWin.toplevel.lastIpcObject ? wsWin.toplevel.lastIpcObject.class : "") : 1
                                        }
                                    }
                                    // Its app's icon on top, with a soft shadow so it
                                    // reads over whatever the window shows
                                    Item {
                                        anchors.centerIn: parent
                                        width: Math.min(22, wsWin.width * 0.6, wsWin.height * 0.6); height: width
                                        layer.enabled: wsLive.hasContent
                                        layer.effect: MultiEffect {
                                            shadowEnabled: Config.shadowsOn
                                            shadowColor: Config.shadowColour
                                            shadowOpacity: 0.55
                                            shadowBlur: Config.shadowEffectBlur
                                            blurMax: 32
                                            shadowHorizontalOffset: Config.shadowDX
                                            shadowVerticalOffset: Config.shadowDY
                                        }
                                        AppTile {
                                            anchors.fill: parent
                                            app: wsWin.modelData.desktopId || wsWin.modelData["class"]
                                        }
                                    }
                                }
                            }
                            // Picked: an accent ring and a tick
                            Rectangle {
                                anchors.fill: parent
                                radius: parent.radius
                                color: "transparent"
                                border.width: wsCard.on ? 2 : 1
                                border.color: wsCard.on ? pop.accent : wsShotHover.hovered ? pop.dim : Qt.rgba(pop.text.r, pop.text.g, pop.text.b, 0.1)
                                Behavior on border.color { ColorAnimation { duration: Config.ms(120) } }
                            }
                            Rectangle {
                                anchors { top: parent.top; right: parent.right; margins: 5 }
                                width: 18; height: 18; radius: Config.corner(9)
                                color: wsCard.on ? pop.accent : Qt.rgba(0, 0, 0, 0.45)
                                border.width: wsCard.on ? 0 : 1.5
                                border.color: Qt.rgba(1, 1, 1, 0.7)
                                Icon { anchors.centerIn: parent; visible: wsCard.on; code: 0xEA5E; font.pixelSize: 12; color: pop.accentText }
                            }
                            HoverHandler { id: wsShotHover }
                            ClickTap { onTapped: spacesView.toggle(wsCard.modelData.id) }
                        }
                        Label {
                            width: parent.width
                            readonly property int n: wsCard.modelData.windows.length
                            text: Config.workspaceLabel(wsCard.modelData.id) + " · " + (n === 1 ? "1 app" : n + " apps")
                            color: wsCard.on ? pop.text : pop.dim
                            font.weight: Font.Normal; font.pixelSize: 12
                        }
                    }
                }
            }
        }
        ScrollShade { z: 3; width: wsBox.width - (wsBox.overflow ? 18 : 0); cornerRadius: 8
                      distance: wsFlick.contentY - wsFlick.originY }
        ScrollShade { z: 3; atBottom: true; y: wsBox.height - height; width: wsBox.width - (wsBox.overflow ? 18 : 0); cornerRadius: 8
                      distance: wsFlick.originY + wsFlick.contentHeight - wsFlick.height - wsFlick.contentY }
        ThinScrollbar { flick: wsFlick; color: pop.text; anchors { top: parent.top; bottom: parent.bottom; right: parent.right } }
    }

    Label { visible: spacesView.mode === "new"; text: "Name"; color: pop.dim; font.weight: Font.Normal; font.pixelSize: 12 }
    PanelField {
        id: spName
        visible: spacesView.mode === "new"
        outlined: true; selectByMouse: true; maximumLength: 40
        hint: "e.g. Coding, Writing, Gaming"
        text: spacesView.name
        onTextEdited: spacesView.name = text
        onOpened: { text = spacesView.name; input.forceActiveFocus(); }
        onAccepted: spacesView.save()
        onEscaped: spacesView.mode = "list"
    }
    Label {
        visible: spacesView.mode === "new" && spacesView.sameName !== null
        width: parent.width
        text: "Saving replaces the space already called " + (spacesView.sameName ? spacesView.sameName.name : "")
        color: pop.dim; font.weight: Font.Normal; font.pixelSize: 12; wrapMode: Text.Wrap
    }

    Label { visible: spacesView.mode === "new"; text: "Icon"; color: pop.dim; font.weight: Font.Normal; font.pixelSize: 12 }
    Grid {
        visible: spacesView.mode === "new"
        columns: 15
        spacing: 2
        Repeater {
            model: Spaces.icons
            delegate: Rectangle {
                id: icCell
                required property int modelData
                readonly property bool on: spacesView.icon === modelData
                width: (spacesView.width - 28) / 15; height: width; radius: Config.corner(7)
                // The chosen icon fades in, in the space's colour; the muted hover is there at once
                color: on ? spacesView.colour : Qt.rgba(spacesView.colour.r, spacesView.colour.g, spacesView.colour.b, 0)
                Behavior on color { ColorAnimation { duration: Config.ms(100) } }
                HoverFill { hovered: icHover.hovered; gone: icCell.on; radius: icCell.radius }
                Icon { anchors.centerIn: parent; code: icCell.modelData; font.pixelSize: 17; color: icCell.on ? spacesView.inkColour : icHover.hovered ? pop.text : pop.dim }
                HoverHandler { id: icHover }
                ClickTap { onTapped: spacesView.icon = icCell.modelData }
            }
        }
    }

    Label { visible: spacesView.mode === "new"; text: "Color"; color: pop.dim; font.weight: Font.Normal; font.pixelSize: 12 }
    Grid {
        visible: spacesView.mode === "new"
        columns: 9
        readonly property real cell: 28
        columnSpacing: (spacesView.width - cell * 9) / 8
        rowSpacing: 10
        Repeater {
            // The pastels, then your own colour
            model: Spaces.colours.concat(["custom"])
            delegate: Item {
                id: swatch
                required property string modelData
                readonly property bool isCustom: modelData === "custom"
                readonly property bool on: isCustom ? spacesView.custom : !spacesView.custom && Qt.colorEqual(spacesView.colour, modelData)
                width: 28; height: 28
                // A ring around the picked one
                Rectangle {
                    anchors.fill: parent; radius: Config.corner(width / 2)
                    color: "transparent"
                    border.width: 2
                    border.color: swatch.on ? pop.text : "transparent"
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: swatch.on ? 20 : swHover.hovered ? 24 : 22; height: width; radius: Config.corner(width / 2)
                    color: swatch.isCustom ? (spacesView.custom ? spacesView.colour : "transparent") : swatch.modelData
                    Behavior on width { NumberAnimation { duration: Config.ms(100) } }
                    // Your own colour: a colour wheel until one is chosen
                    Canvas {
                        anchors.fill: parent
                        visible: swatch.isCustom && !spacesView.custom
                        onPaint: {
                            const ctx = getContext("2d"), r = width / 2;
                            ctx.reset();
                            for (let i = 0; i < 36; i++) {
                                ctx.beginPath();
                                ctx.moveTo(r, r);
                                ctx.arc(r, r, r, i / 36 * Math.PI * 2, (i + 1.2) / 36 * Math.PI * 2);
                                ctx.closePath();
                                ctx.fillStyle = Qt.hsla(i / 36, 0.65, 0.78, 1);
                                ctx.fill();
                            }
                        }
                        onWidthChanged: requestPaint()
                    }
                    Icon { anchors.centerIn: parent; visible: swatch.isCustom; code: 0xEBE6; font.pixelSize: 12; color: spacesView.inkColour }
                }
                HoverHandler { id: swHover }
                ClickTap {
                    onTapped: {
                        if (swatch.isCustom) {
                            if (!spacesView.custom) { spacesView.custom = true; spHexBox.text = spacesView.colour.toString().slice(0, 7); }
                        } else { spacesView.custom = false; spacesView.colour = swatch.modelData; }
                    }
                }
            }
        }
    }
    // Your own colour: drag along the hues, or type a hex value
    Row {
        visible: spacesView.mode === "new" && spacesView.custom
        width: parent.width
        spacing: 10
        Item {
            id: hueStrip
            width: parent.width - spHexBox.width - 10; height: 30
            Canvas {
                id: hueCanvas
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                height: 14
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const g = ctx.createLinearGradient(0, 0, width, 0);
                    for (let i = 0; i <= 12; i++) g.addColorStop(i / 12, Qt.hsla(i / 12, 0.65, 0.78, 1));
                    ctx.fillStyle = g;
                    ctx.beginPath();
                    ctx.roundedRect(0, 0, width, height, height / 2, height / 2);
                    ctx.fill();
                }
                onWidthChanged: requestPaint()
            }
            Rectangle {
                readonly property real hue: Math.max(0, spacesView.colour.hslHue)
                x: hue * (hueStrip.width - width)
                anchors.verticalCenter: parent.verticalCenter
                width: 20; height: 20; radius: Config.corner(10)
                color: spacesView.colour
                border.width: 2; border.color: pop.text
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor      // (a hand over it, as over what's clicked)
                function set(mx) {
                    const h = Math.max(0, Math.min(0.999, mx / width));
                    spacesView.colour = Qt.hsla(h, 0.65, 0.78, 1);
                    spHexBox.text = spacesView.colour.toString().slice(0, 7);
                }
                onPressed: m => set(m.x)
                onPositionChanged: m => { if (pressed) set(m.x); }
            }
        }
        PanelField {
            id: spHexBox
            width: 92; height: 30
            inset: 10
            outlined: true; selectByMouse: true; maximumLength: 7
            onTextEdited: {
                const t = text.startsWith("#") ? text : "#" + text;
                if (/^#[0-9a-fA-F]{6}$/.test(t)) spacesView.colour = t;
            }
            onEscaped: spacesView.mode = "list"
        }
    }

    Divider { visible: spacesView.mode === "new" }
    Row {
        visible: spacesView.mode === "new"
        anchors.right: parent.right
        spacing: 8
        Rectangle {
            width: spCancel.implicitWidth + 28; height: 32; radius: Config.corner(8)
            color: spCancelHover.hovered ? Config.hover : "transparent"
            Label { id: spCancel; anchors.centerIn: parent; text: "Cancel"; font.weight: Font.Normal }
            HoverHandler { id: spCancelHover }
            ClickTap { onTapped: spacesView.mode = "list" }
        }
        Rectangle {
            width: spSave.implicitWidth + 28; height: 32; radius: Config.corner(8)
            // The lighter accent under the pointer, as the control centre's toggles (nothing
            // to light while it can't save yet)
            color: spacesView.canSave ? (spSaveHover.hovered ? Config.accentLit : pop.accent) : pop.card
            Behavior on color { ColorAnimation { duration: Config.ms(100) } }
            Label { id: spSave; anchors.centerIn: parent; text: spacesView.sameName ? "Replace" : "Save"; color: spacesView.canSave ? pop.accentText : pop.dim }
            HoverHandler { id: spSaveHover }
            ClickTap { onTapped: spacesView.save() }
        }
    }
}
