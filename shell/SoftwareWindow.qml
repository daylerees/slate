// Slate Software: install, open, remove and update apps from Flathub, and update the system.
// A window like Settings (its sidebar, search box, groups and buttons, in Settings' colours,
// which are the theme's: it uses Settings' own building blocks, through SettingsHost), but an app
// of its own: its title tells it apart (Config.appIdOf), so it has its own place in the dock and
// the switcher, with its own icon.
// Everything it shows and does comes from scripts/software.py: the Flathub catalog on this
// computer (search happens here, in it), Flathub's popular, new and trending lists, installed
// apps, and app and system updates. Installs, removals and updates run one at a time, as Flatpak
// allows, with their progress on the app's row.
//   slate ipc call software open | close | page <discover|installed|updates> | app <id> | search <text>
// (handled in shell.qml, which builds the window the first time it's wanted)

import QtQuick
import Quickshell
import Quickshell.Io
import "settings"

FloatingWindow {
    id: sw
    required property var bar
    title: Config.softwareTitle
    visible: false
    color: bar.barColor
    readonly property var fitScreen: Config.focusedScreen
    function fitSize(scr) { return Qt.size(Math.min(960, scr.width * 0.9), Math.min(660, (scr.height - 60) * 0.9)); }
    implicitWidth: Math.round(fitScreen ? fitSize(fitScreen).width : 960)
    implicitHeight: Math.round(fitScreen ? fitSize(fitScreen).height : 660)
    minimumSize: Qt.size(Math.min(560, implicitWidth), Math.min(400, implicitHeight))
    readonly property bool compact: width < 780

    property var confirmer: null              // Slate's confirmation window (removing an app)
    // ---- Look: Settings' own (the theme's), so its building blocks (Group, Button…) fit. They
    // read these from SettingsHost.win: Settings when it's built, else this window, which has the
    // same colours under the same names
    Component.onCompleted: if (!SettingsHost.win) SettingsHost.win = sw
    readonly property color card: bar.capsuleColor
    readonly property color control: Config.raised(Config.tint("#2a313c"))
    readonly property color divider: Config.tint("#262c35")
    readonly property color outline: Config.tint("#2a313c")
    readonly property color text: bar.textColor
    readonly property color dim: Config.tint("#8b94a3")
    readonly property color accent: bar.accent
    readonly property color accentText: Config.tint("#12151a")
    readonly property color well: Config.tint("#151920")
    readonly property color faint: Qt.rgba(text.r, text.g, text.b, 0.06)
    readonly property color danger: bar.errorColor
    readonly property string font: bar.fontFamily
    function glyph(code) { return String.fromCodePoint(code); }

    // ---- Where you are ---------------------------------------------------------------------
    // "discover", "installed", "updates", or a category's name; `app` is the app page over it
    property string page: "discover"
    property string app: ""
    property string query: ""
    readonly property bool searchFocused: searchBox.input.activeFocus || heroSearch.input.activeFocus      // (the tests)
    // The keyboard to whichever search box shows
    function focusSearch() {
        const f = onHome ? heroSearch.input : searchBox.input;
        f.focus = true;
        Qt.callLater(() => f.forceActiveFocus());
    }
    // (opens on Discover each time, as Settings opens on All Settings: reset here rather than when
    // it shows, which can come after a page, an app or a search asked for with it)
    function open() {
        const opening = !visible;
        if (opening) { app = ""; query = ""; page = "discover"; }
        visible = true;
        // (the search box takes the keyboard, so you can type straight away)
        if (opening) focusSearch();
        refresh();
    }
    function show(p) { app = ""; page = p; query = ""; scroller.contentY = 0; }
    // Discover's own page (its search box in the middle), rather than an app or a category
    readonly property bool onHome: page === "discover" && app === ""
    function openApp(id) { app = id; detail = null; appRun.command = [script, "app", id]; load("app", appRun); scroller.contentY = 0; }

    // ---- What the engine says (scripts/software.py) ---------------------------------------------
    readonly property string script: Quickshell.shellPath("scripts/software.py")
    property var status: ({ flatpak: true, flathub: true, catalogue: true })
    property var catalogue: []
    property var byId: ({})
    property var lists: ({})
    property var installed: []
    readonly property var installedIds: { const o = {}; for (const a of installed) o[a.id] = a; return o; }
    property var updates: ({ apps: [], system: [], systemTool: "", systemProblem: "" })
    readonly property int updateCount: updates.apps.length + updates.system.length
    property var detail: null                 // the app page's: software.py app <id>
    property bool checkingUpdates: false
    // (the tests: what the engine would say, by what: { status, catalogue: { apps }, lists,
    // installed: { apps }, updates }, in place of running it)
    property var pretend: ({})
    function refresh() {
        load("status", statusRun);
        if (catalogue.length === 0) load("catalogue", catalogueRun);
        load("lists", listsRun);
        load("installed", installedRun);
        checkUpdates();
    }
    function checkUpdates() { checkingUpdates = true; load("updates", updatesRun); }
    // Runs the engine for one thing, or (the tests) takes what it'd say from `pretend` without
    // running anything
    function load(what, run) {
        if (pretend[what] === undefined) { run.running = false; run.running = true; return; }
        run.stdout.streamFinished();
    }
    function take(what, text, then) {
        const p = pretend[what];
        try { then(p !== undefined ? p : JSON.parse(text)); } catch (e) {}
    }
    Process { id: statusRun; command: [sw.script, "status"]; stdout: StdioCollector { onStreamFinished: sw.take("status", text, v => sw.status = v) } }
    Process {
        id: catalogueRun
        command: [sw.script, "catalogue"]
        stdout: StdioCollector {
            onStreamFinished: sw.take("catalogue", text, v => {
                const apps = Array.isArray(v) ? v : (v.apps || []);
                const o = {};
                for (const a of apps) o[a.id] = a;
                sw.byId = o;
                sw.catalogue = apps;
            })
        }
    }
    Process { id: listsRun; command: [sw.script, "discover"]; stdout: StdioCollector { onStreamFinished: sw.take("lists", text, v => sw.lists = v) } }
    Process { id: installedRun; command: [sw.script, "installed"]; stdout: StdioCollector { onStreamFinished: sw.take("installed", text, v => sw.installed = Array.isArray(v) ? v : (v.apps || [])) } }
    Process {
        id: updatesRun
        command: [sw.script, "updates"]
        stdout: StdioCollector { onStreamFinished: { sw.take("updates", text, v => sw.updates = v); sw.checkingUpdates = false; } }
    }
    Process { id: appRun; stdout: StdioCollector { onStreamFinished: sw.take("app", text, v => sw.detail = v) } }

    // ---- Doing: one at a time, in order ------------------------------------------------------
    // queue: [{ what: "install"|"remove"|"update-apps"|"update-system", id, name }]; busy: the
    // one running (and its progress, 0–100); note: how the last one went, when it didn't
    property var queue: []
    property var busy: null
    property int progress: 0
    property string note: ""
    function act(what, id, name) {
        if (busy && busy.what === what && busy.id === id) return;
        if (queue.some(q => q.what === what && q.id === id)) return;
        queue = queue.concat([{ what: what, id: id || "", name: name || "" }]);
        next();
    }
    function next() {
        if (busy || queue.length === 0) return;
        busy = queue[0];
        queue = queue.slice(1);
        progress = 0;
        note = "";
        actRun.command = [script, busy.what].concat(busy.id ? [busy.id] : []);
        if (pretend.act === undefined) { actRun.running = true; return; }
        // (the tests: how it went, after a moment at half way)
        progress = 50;
        pretendAct.restart();
    }
    Timer { id: pretendAct; interval: 600; onTriggered: { if (sw.pretend.act !== "ok") sw.note = sw.pretend.act; sw.finished(); } }
    function waiting(what, id) { return (busy && busy.what === what && busy.id === id) || queue.some(q => q.what === what && q.id === id); }
    Process {
        id: actRun
        stdout: SplitParser {
            onRead: line => {
                if (line.startsWith("progress ")) { sw.progress = parseInt(line.slice(9)) || 0; return; }
                if (line === "ok" || line === "error canceled") return;
                if (line.startsWith("error ")) sw.note = line.slice(6);
            }
        }
        onExited: sw.finished()
    }
    function finished() {
        busy = null;
        load("installed", installedRun);
        checkUpdates();
        if (app !== "") openApp(app);
        next();
    }
    function launch(id) { Quickshell.execDetached(["flatpak", "run", "--", id]); }
    function askRemove(a) {
        if (!confirmer) return;
        confirmer.confirmWith({ title: "Remove " + a.name + "?",
                                body: a.name + " is removed for everyone on this computer. Your own files from it stay where they are, and you can install it again any time.",
                                button: "Remove", code: 0xEB41, danger: true },
                              () => sw.act("remove", a.id, a.name));
    }

    // ---- What a page lists ------------------------------------------------------------------
    // Flathub's main categories, in plain words
    readonly property var categories: [
        { id: "Game", label: "Games", icon: 0xEA3B }, { id: "Graphics", label: "Graphics & Photos", icon: 0xEB0A },
        { id: "AudioVideo", label: "Music & Video", icon: 0xEB51 }, { id: "Office", label: "Productivity", icon: 0xEA7A },
        { id: "Network", label: "Internet", icon: 0xEB54 }, { id: "Development", label: "Developer Tools", icon: 0xEA77 },
        { id: "Education", label: "Learning", icon: 0xEB30 }, { id: "Science", label: "Science", icon: 0xEB06 },
        { id: "Utility", label: "Utilities", icon: 0xEB11 }, { id: "System", label: "System", icon: 0xEB20 }
    ]
    function found(text) {
        const q = text.trim().toLowerCase();
        if (q === "") return [];
        const words = q.split(/\s+/);
        const scored = [];
        for (const a of catalogue) {
            const name = a.name.toLowerCase();
            const hay = name + " " + (a.summary || "").toLowerCase() + " " + (a.keywords || "") + " " + a.id.toLowerCase();
            if (!words.every(w => hay.indexOf(w) >= 0)) continue;
            scored.push({ a: a, s: name === q ? 0 : name.startsWith(q) ? 1 : name.indexOf(q) >= 0 ? 2 : 3 });
        }
        scored.sort((x, y) => x.s - y.s || x.a.name.localeCompare(y.a.name));
        return scored.slice(0, 60).map(x => x.a);
    }
    // A category's apps: its most installed on Flathub first (when we've heard), then the rest by
    // name; `many` of them (0: all)
    function inCategory(cat, many) {
        const top = ((lists.categories || {})[cat] || []).map(id => byId[id]).filter(a => !!a);
        const seen = {};
        for (const a of top) seen[a.id] = true;
        const all = top.concat(catalogue.filter(a => !seen[a.id] && (a.categories || []).indexOf(cat) >= 0));
        return many > 0 ? all.slice(0, many) : all;
    }
    // An installed app as a row: from the catalog when it's in it, else as Flatpak names it
    function asApp(i) { return byId[i.id] || { id: i.id, name: i.name, summary: "", icon: "" }; }

    // ---- Layout -----------------------------------------------------------------------------
    readonly property var sections: [
        { id: "discover", label: "Discover", icon: 0xEB1C },
        { id: "installed", label: "Installed", icon: 0xEA96 },
        { id: "updates", label: "Updates", icon: 0xEB13 }
    ]
    // (a focus scope with the search box in it focused: whenever the window is active, the
    // search box has the keyboard)
    FocusScope {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: { if (sw.app !== "") sw.app = ""; else if (sw.query !== "") sw.query = ""; else sw.visible = false; }

        // Sidebar, as Settings'
        Rectangle {
            id: sidebar
            width: sw.compact ? 66 : 210
            anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
            color: sw.bar.barColor
            Column {
                anchors { fill: parent; margins: 14 }
                spacing: 4
                Item {
                    width: parent.width; height: logoRow.implicitHeight
                    Row {
                        id: logoRow
                        leftPadding: 4; topPadding: 4; bottomPadding: 14
                        spacing: 8
                        SlateLogo { size: sw.compact ? 30 : 40; showText: false; anchors.verticalCenter: parent.verticalCenter }
                        Column {
                            visible: !sw.compact
                            anchors.verticalCenter: parent.verticalCenter
                            Text { text: "Slate"; color: sw.text; font.family: sw.font; font.pixelSize: 18; font.weight: Font.Medium }
                            Text { text: "Software"; color: sw.dim; font.family: sw.font; font.pixelSize: 12 }
                        }
                    }
                    MouseArea { anchors.fill: parent; onPressed: sw.startSystemMove() }
                }
                Repeater {
                    model: sw.sections
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool current: sw.page === modelData.id || (modelData.id === "discover" && sw.categories.some(c => c.id === sw.page))
                        width: parent.width; height: 38; radius: Config.corner(9)
                        color: current ? sw.accent : Qt.rgba(sw.accent.r, sw.accent.g, sw.accent.b, 0)
                        Behavior on color { ColorAnimation { duration: Config.ms(100) } }
                        HoverFill { hovered: navHover.hovered; gone: parent.current; radius: parent.radius }
                        Text {
                            id: navIcon
                            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                            text: sw.glyph(parent.modelData.icon)
                            color: parent.current ? sw.accentText : Config.colourful ? Config.pageColour("updates") : sw.dim
                            font.family: sw.bar.iconFont; font.pixelSize: 17
                        }
                        Text {
                            visible: !sw.compact
                            anchors { left: navIcon.right; leftMargin: 12; verticalCenter: parent.verticalCenter }
                            text: parent.modelData.label
                            color: parent.current ? sw.accentText : sw.dim
                            font.family: sw.font; font.pixelSize: 13; font.weight: Font.Medium
                        }
                        // How many updates are waiting
                        Rectangle {
                            visible: parent.modelData.id === "updates" && sw.updateCount > 0 && !sw.compact
                            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            width: Math.max(height, countShape.tightBoundingRect.width + 12); height: 20; radius: Config.corner(10)
                            color: parent.current ? Qt.rgba(sw.accentText.r, sw.accentText.g, sw.accentText.b, 0.15) : sw.accent
                            // Centred by the number's own shape rather than its line of text
                            // (which has room above for capitals and below for descenders, and
                            // left the digits sitting high)
                            TextMetrics { id: countShape; font: countText.font; text: countText.text }
                            Text {
                                id: countText
                                x: Math.round((parent.width - countShape.tightBoundingRect.width) / 2 - countShape.tightBoundingRect.x)
                                y: Math.round((parent.height - countShape.tightBoundingRect.height) / 2 - countText.baselineOffset - countShape.tightBoundingRect.y)
                                text: sw.updateCount; color: sw.accentText
                                font.family: sw.font; font.pixelSize: 11; font.weight: Font.DemiBold
                            }
                        }
                        HoverHandler { id: navHover }
                        ClickTap { onTapped: sw.show(parent.modelData.id) }
                    }
                }
            }
        }

        // Content
        Rectangle {
            id: contentPane
            anchors { top: parent.top; bottom: parent.bottom; left: sidebar.right; right: parent.right }
            color: sw.well
            // Search all of Flathub, from any page but Discover (which has its own, larger, in
            // the middle of the page)
            SearchField {
                id: searchBox
                z: 2
                visible: !sw.onHome
                // (clear of the close button, as Settings' search is)
                anchors { top: parent.top; topMargin: 15; left: parent.left; leftMargin: 22; right: parent.right; rightMargin: 58 }
            }
            // Close, top right, where Settings has it
            IconButton {
                z: 3
                anchors { right: parent.right; rightMargin: 14; top: parent.top; topMargin: 16 }
                icon: 0xEB55
                onClicked: sw.visible = false
            }
            Flickable {
                id: scroller
                anchors { top: parent.top; topMargin: searchBox.visible ? 59 : 0; left: parent.left; right: parent.right; bottom: parent.bottom }
                contentHeight: pageCol.implicitHeight + 40
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                SmoothWheel { flick: scroller }
                Column {
                    id: pageCol
                    x: 22; width: scroller.width - 44
                    spacing: 4
                    topPadding: 10

                    // ---- Nothing to work with ----
                    Group {
                        visible: !sw.status.flatpak || !sw.status.flathub
                        Item {
                            width: parent.width; height: 64
                            Text {
                                anchors { left: parent.left; right: parent.right; margins: 16; verticalCenter: parent.verticalCenter }
                                wrapMode: Text.Wrap
                                text: !sw.status.flatpak ? "Flatpak isn't installed, so Slate Software can't install apps yet. Install the flatpak package, then open this again."
                                    : "Flathub isn't set up for Flatpak yet. In a terminal: flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo"
                                color: sw.dim; font.family: sw.font; font.pixelSize: 13
                            }
                        }
                    }
                    Text {
                        visible: sw.note !== ""
                        width: parent.width; wrapMode: Text.Wrap; bottomPadding: 6
                        textFormat: Text.PlainText        // (it can quote what Flatpak said)
                        text: sw.note; color: sw.danger; font.family: sw.font; font.pixelSize: 12
                    }

                    // ---- An app's own page ----
                    Loader {
                        width: parent.width
                        active: sw.app !== ""
                        visible: active
                        sourceComponent: appPage
                    }

                    // ---- Discover: what this is, a search box, and each category's popular apps ----
                    Column {
                        id: hero
                        width: parent.width
                        visible: sw.onHome
                        spacing: 10
                        topPadding: 34
                        bottomPadding: 22
                        Text {
                            width: parent.width; horizontalAlignment: Text.AlignHCenter
                            text: "Find apps for your computer"
                            color: sw.text; font.family: sw.font; font.pixelSize: 24; font.weight: Font.Medium
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: Math.min(parent.width, 520); wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter
                            text: "Slate Software installs apps from Flathub, where thousands of free apps run safely in a space of their own. "
                                + "What you install here is there for everyone who uses this computer, and its updates show under Updates."
                            color: sw.dim; font.family: sw.font; font.pixelSize: 13; lineHeight: 1.15
                        }
                        Item { width: 1; height: 6 }
                        SearchField {
                            id: heroSearch
                            big: true
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: Math.min(parent.width, 560)
                        }
                    }

                    // ---- Search ----
                    Column {
                        id: searchPage
                        width: parent.width
                        visible: sw.app === "" && sw.query.trim() !== ""
                        readonly property var hits: visible ? sw.found(sw.query) : []
                        spacing: 4
                        GroupLabel { text: searchPage.hits.length ? "On Flathub" : "Nothing on Flathub matches that" }
                        Group {
                            visible: searchPage.hits.length > 0
                            Repeater { model: searchPage.hits; delegate: AppRow { required property var modelData; required property int index; entry: modelData; first: index === 0 } }
                        }
                    }

                    Column {
                        width: parent.width
                        visible: sw.onHome && sw.query.trim() === ""
                        spacing: 26
                        Repeater {
                            model: sw.categories
                            delegate: CategoryStrip { required property var modelData; cat: modelData }
                        }
                        Text {
                            visible: !!sw.lists.offline && !sw.lists.categories
                            width: parent.width; wrapMode: Text.Wrap
                            text: "Each category's most popular apps show here when you're online. Until then, they're in alphabetical order, and search works as usual."
                            color: sw.dim; font.family: sw.font; font.pixelSize: 12
                        }
                    }

                    // ---- A category ----
                    Column {
                        id: catPage
                        width: parent.width
                        readonly property var cat: sw.categories.find(c => c.id === sw.page)
                        visible: sw.app === "" && sw.query.trim() === "" && !!cat
                        readonly property var apps: visible ? sw.inCategory(sw.page, 0) : []
                        spacing: 4
                        Text { text: catPage.cat ? catPage.cat.label : ""; color: sw.text; font.family: sw.font; font.pixelSize: 22; font.weight: Font.Medium; bottomPadding: 8 }
                        Group { Repeater { model: catPage.apps.slice(0, 120); delegate: AppRow { required property var modelData; required property int index; entry: modelData; first: index === 0 } } }
                    }

                    // ---- Installed ----
                    Column {
                        width: parent.width
                        visible: sw.app === "" && sw.query.trim() === "" && sw.page === "installed"
                        spacing: 4
                        Text { text: "Installed"; color: sw.text; font.family: sw.font; font.pixelSize: 22; font.weight: Font.Medium; bottomPadding: 8 }
                        Text {
                            visible: sw.installed.length === 0
                            width: parent.width; wrapMode: Text.Wrap
                            text: "No apps from Flathub yet. Find one in Discover, or search above."
                            color: sw.dim; font.family: sw.font; font.pixelSize: 13
                        }
                        Group {
                            visible: sw.installed.length > 0
                            Repeater { model: sw.installed; delegate: AppRow { required property var modelData; required property int index; entry: sw.asApp(modelData); first: index === 0; removable: true } }
                        }
                    }

                    // ---- Updates ----
                    Column {
                        width: parent.width
                        visible: sw.app === "" && sw.query.trim() === "" && sw.page === "updates"
                        spacing: 4
                        Text { text: "Updates"; color: sw.text; font.family: sw.font; font.pixelSize: 22; font.weight: Font.Medium; bottomPadding: 8 }
                        Text {
                            visible: sw.checkingUpdates && sw.updateCount === 0
                            text: "Looking for updates…"; color: sw.dim; font.family: sw.font; font.pixelSize: 13
                        }
                        Text {
                            visible: !sw.checkingUpdates && sw.updateCount === 0 && sw.updates.systemProblem === ""
                            text: "Everything's up to date."; color: sw.dim; font.family: sw.font; font.pixelSize: 13
                        }
                        GroupLabel { visible: sw.updates.apps.length > 0; text: sw.updates.apps.length === 1 ? "1 app" : sw.updates.apps.length + " apps" }
                        // Update all of them at once, or each on its own (its row's Update)
                        Group {
                            visible: sw.updates.apps.length > 0
                            Item {
                                width: parent.width; height: 56
                                Text {
                                    anchors { left: parent.left; leftMargin: 16; right: allButton.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                    elide: Text.ElideRight
                                    text: sw.busy && sw.busy.what === "update-apps" && sw.busy.id === "" ? "Updating your apps… (" + sw.progress + "%)"
                                        : "Your apps and windows stay open while they update"
                                    color: sw.dim; font.family: sw.font; font.pixelSize: 12
                                }
                                Button {
                                    id: allButton
                                    anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                                    label: "Update all apps"; primary: true; icon: 0xEB13
                                    opacity: sw.waiting("update-apps", "") ? 0.5 : 1
                                    onClicked: sw.act("update-apps", "", "your apps")
                                }
                            }
                            Repeater {
                                model: sw.updates.apps
                                delegate: AppRow { required property var modelData; entry: sw.asApp(modelData); updating: true; newVersion: modelData.version || "" }
                            }
                        }
                        GroupLabel { visible: sw.updates.system.length > 0 || sw.updates.systemProblem !== ""; text: "This computer's system" }
                        Group {
                            visible: sw.updates.system.length > 0 || sw.updates.systemProblem !== ""
                            Item {
                                width: parent.width; height: 64
                                Column {
                                    anchors { left: parent.left; leftMargin: 16; right: sysButton.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                    spacing: 2
                                    Text {
                                        width: parent.width; elide: Text.ElideRight
                                        text: sw.updates.systemProblem !== "" ? "System updates" : sw.updates.system.length === 1 ? "1 system update" : sw.updates.system.length + " system updates"
                                        color: sw.text; font.family: sw.font; font.pixelSize: 13; font.weight: Font.Medium
                                    }
                                    Text {
                                        width: parent.width; wrapMode: Text.Wrap
                                        textFormat: Text.PlainText
                                        text: sw.updates.systemProblem !== "" ? sw.updates.systemProblem
                                            : sw.waiting("update-system", "") ? "Updating the system… (" + sw.progress + "%)"
                                            : "They update together. Asks for an administrator's password; restart afterwards if it says to"
                                        color: sw.dim; font.family: sw.font; font.pixelSize: 12
                                    }
                                }
                                Button {
                                    id: sysButton
                                    visible: sw.updates.system.length > 0
                                    anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                                    label: "Update"; icon: 0xEB13
                                    opacity: sw.waiting("update-system", "") ? 0.5 : 1
                                    onClicked: sw.act("update-system", "", "the system")
                                }
                            }
                            // Each package, with the version it goes to. (They update together: one
                            // on its own is a partial upgrade, which some systems, Arch among them,
                            // don't support)
                            Repeater {
                                model: sw.updates.system
                                delegate: Item {
                                    required property var modelData
                                    width: parent.width; height: 40
                                    Separator {}
                                    Text {
                                        anchors { left: parent.left; leftMargin: 16; right: pkgVersion.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                        elide: Text.ElideRight; textFormat: Text.PlainText
                                        text: parent.modelData.name
                                        color: sw.text; font.family: sw.font; font.pixelSize: 13
                                    }
                                    Text {
                                        id: pkgVersion
                                        anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                                        width: Math.min(implicitWidth, parent.width * 0.55)
                                        elide: Text.ElideMiddle; textFormat: Text.PlainText
                                        text: (parent.modelData.from ? parent.modelData.from + "  →  " : "") + parent.modelData.to
                                        color: sw.dim; font.family: sw.font; font.pixelSize: 12
                                    }
                                }
                            }
                        }
                    }
                }
            }
            ThinScrollbar {
                z: 3
                flick: scroller
                color: sw.text
                // (below the close button)
                anchors { top: scroller.top; topMargin: searchBox.visible ? 0 : 56; bottom: parent.bottom; right: parent.right; rightMargin: 4; bottomMargin: 8 }
            }
            ScrollShade { z: 3; anchors { top: scroller.top; left: parent.left; right: parent.right } distance: scroller.contentY }
            ScrollShade { z: 3; atBottom: true; anchors { bottom: parent.bottom; left: parent.left; right: parent.right } distance: scroller.contentHeight - scroller.height - scroller.contentY }
        }
    }

    // ---- An app, as a row: its icon, name and summary, and what you can do ----------------------
    component AppRow: Item {
        id: row
        property var entry: ({})
        property bool first: false
        property bool updating: false             // (on Updates: the new version, and Update)
        property string newVersion: ""
        property bool removable: false            // (on Installed: Remove beside Open, asking first)
        readonly property bool isInstalled: !!sw.installedIds[entry.id]
        readonly property bool busyHere: !!sw.busy && sw.busy.id === entry.id
        width: parent ? parent.width : 0
        height: 64
        Separator { visible: !row.first }
        // (rounded to sit inside its group's card: the card's corner less the room round its rows)
        HoverFill { anchors.fill: parent; hovered: rowHover.hovered; radius: Config.corner(8) }
        AppIcon { id: rowIcon; anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter } size: 40; path: row.entry.icon || "" }
        Column {
            anchors { left: rowIcon.right; leftMargin: 12; right: rowAction.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
            spacing: 2
            Text { width: parent.width; elide: Text.ElideRight; textFormat: Text.PlainText; text: row.entry.name || row.entry.id; color: sw.text; font.family: sw.font; font.pixelSize: 13; font.weight: Font.Medium }
            Text {
                width: parent.width; elide: Text.ElideRight; textFormat: Text.PlainText
                text: row.updating ? (row.newVersion ? "Version " + row.newVersion : "An update is waiting") : (row.entry.summary || "")
                color: sw.dim; font.family: sw.font; font.pixelSize: 12
            }
        }
        Item {
            id: rowAction
            anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
            width: row.busyHere ? 120 : rowButtons.width; height: 30
            Meter {
                visible: row.busyHere
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width; height: 6
                value: sw.progress / 100
                colour: sw.accent; trackColour: sw.faint
            }
            Row {
                id: rowButtons
                spacing: 8
                visible: !row.busyHere
                Button {
                    visible: row.removable && row.isInstalled
                    label: "Remove"; destructive: true
                    onClicked: sw.askRemove(row.entry)
                }
                Button {
                    id: rowButton
                    label: row.updating ? (sw.waiting("update-apps", row.entry.id) ? "Waiting…" : "Update")
                        : sw.waiting("install", row.entry.id) ? "Waiting…" : row.isInstalled ? "Open" : "Install"
                    primary: !row.updating && !row.isInstalled
                    onClicked: row.updating ? sw.act("update-apps", row.entry.id, row.entry.name)
                        : row.isInstalled ? sw.launch(row.entry.id) : sw.act("install", row.entry.id, row.entry.name)
                }
            }
        }
        HoverHandler { id: rowHover }
        // (the row, not its button: the app's own page)
        ClickTap { onTapped: sw.openApp(row.entry.id) }
    }

    // An app's icon from the catalog, or a plain stand-in
    component AppIcon: Item {
        id: ai
        property string path: ""
        property real size: 40
        width: size; height: size
        Image {
            id: aiImg
            anchors.fill: parent
            visible: ai.path !== "" && status === Image.Ready
            source: ai.path ? "file://" + ai.path : ""
            sourceSize: Qt.size(ai.size * 2, ai.size * 2)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
        }
        Rectangle {
            visible: !aiImg.visible
            anchors.fill: parent; radius: Config.corner(ai.size * 0.22)
            color: sw.faint
            Text { anchors.centerIn: parent; text: sw.glyph(0xEB75); color: sw.dim; font.family: sw.bar.iconFont; font.pixelSize: ai.size * 0.5 }
        }
    }

    // ---- A search box: in the header, or (big) in the middle of Discover ------------------------
    // Both show and change the same search (sw.query)
    component SearchField: Rectangle {
        id: field
        property bool big: false
        readonly property alias input: fieldInput
        height: big ? 48 : 36; radius: Config.corner(big ? 12 : 10)
        color: big ? sw.card : sw.faint
        border.width: fieldInput.activeFocus ? 1 : 0; border.color: sw.accent
        Text {
            id: fieldIcon
            anchors { left: parent.left; leftMargin: field.big ? 16 : 12; verticalCenter: parent.verticalCenter }
            text: sw.glyph(0xEB1C); color: sw.dim; font.family: sw.bar.iconFont; font.pixelSize: field.big ? 19 : 16
        }
        TextInput {
            id: fieldInput
            activeFocusOnTab: true
            anchors { left: fieldIcon.right; leftMargin: field.big ? 10 : 8; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
            color: sw.text; font.family: sw.font; font.pixelSize: field.big ? 15 : 13
            selectionColor: sw.accent; selectedTextColor: sw.accentText
            clip: true
            text: sw.query
            onTextEdited: { sw.query = text; sw.app = ""; if (!field.big) scroller.contentY = 0; }
            // Escape: clears the search, then leaves an app's page, then closes the window
            Keys.onEscapePressed: {
                if (text !== "") sw.query = "";
                else if (sw.app !== "") sw.app = "";
                else sw.visible = false;
            }
            Text {
                visible: fieldInput.text === ""
                anchors.verticalCenter: parent.verticalCenter
                text: field.big ? "Search thousands of apps" : "Search Flathub"
                color: sw.dim; font: fieldInput.font
            }
        }
        HoverHandler { cursorShape: Qt.IBeamCursor }
        TapHandler { onTapped: fieldInput.forceActiveFocus() }
    }

    // ---- A category on Discover: its name, See all, and its most popular apps as cards in a row,
    // a page at a time (the arrows). Paged rather than scrolled sideways, so the wheel always
    // scrolls the page
    component CategoryStrip: Column {
        id: strip
        property var cat: ({})
        readonly property var apps: sw.inCategory(cat.id, 16)
        readonly property int gap: 12
        readonly property int perPage: Math.max(2, Math.floor((width + gap) / (180 + gap)))
        readonly property real cardWidth: (width - gap * (perPage - 1)) / perPage
        property int first: 0
        onPerPageChanged: first = Math.floor(first / perPage) * perPage
        width: parent ? parent.width : 0
        visible: apps.length > 0
        spacing: 10
        Item {
            width: parent.width; height: 30
            Row {
                anchors { left: parent.left; leftMargin: 2; verticalCenter: parent.verticalCenter }
                spacing: 8
                Text { anchors.verticalCenter: parent.verticalCenter; text: sw.glyph(strip.cat.icon || 0xEB1C); color: Config.colourful ? Config.pageColour("updates") : sw.accent; font.family: sw.bar.iconFont; font.pixelSize: 17 }
                Text { anchors.verticalCenter: parent.verticalCenter; text: strip.cat.label || ""; color: sw.text; font.family: sw.font; font.pixelSize: 15; font.weight: Font.Medium }
            }
            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 4
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    rightPadding: 8
                    text: "See all"
                    color: seeAllHover.hovered ? sw.text : sw.accent; font.family: sw.font; font.pixelSize: 12; font.weight: Font.Medium
                    HoverHandler { id: seeAllHover }
                    ClickTap { onTapped: sw.show(strip.cat.id) }
                }
                IconButton {
                    icon: 0xEA60
                    opacity: strip.first > 0 ? 1 : 0.35
                    onClicked: strip.first = Math.max(0, strip.first - strip.perPage)
                }
                IconButton {
                    icon: 0xEA61
                    opacity: strip.first + strip.perPage < strip.apps.length ? 1 : 0.35
                    onClicked: if (strip.first + strip.perPage < strip.apps.length) strip.first += strip.perPage
                }
            }
        }
        Row {
            spacing: strip.gap
            Repeater {
                model: strip.apps.slice(strip.first, strip.first + strip.perPage)
                delegate: AppCard { required property var modelData; entry: modelData; width: strip.cardWidth }
            }
        }
    }

    // An app as a card: its icon, name and what it's for; opens its page
    component AppCard: Rectangle {
        id: card
        property var entry: ({})
        height: 140; radius: Config.corner(12)
        color: sw.card
        HoverFill { hovered: cardHover.hovered; radius: parent.radius }
        AppIcon { id: cardIcon; anchors { left: parent.left; top: parent.top; margins: 14 } size: 52; path: card.entry.icon || "" }
        Text {
            visible: !!sw.installedIds[card.entry.id]
            anchors { right: parent.right; top: parent.top; margins: 14 }
            text: "Installed"; color: sw.dim; font.family: sw.font; font.pixelSize: 11
        }
        Column {
            anchors { left: parent.left; right: parent.right; top: cardIcon.bottom; margins: 14; topMargin: 10 }
            spacing: 3
            Text { width: parent.width; elide: Text.ElideRight; textFormat: Text.PlainText; text: card.entry.name || card.entry.id; color: sw.text; font.family: sw.font; font.pixelSize: 13; font.weight: Font.Medium }
            Text {
                width: parent.width; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight; textFormat: Text.PlainText
                text: card.entry.summary || ""; color: sw.dim; font.family: sw.font; font.pixelSize: 12
            }
        }
        HoverHandler { id: cardHover }
        ClickTap { onTapped: sw.openApp(card.entry.id) }
    }

    // ---- An app's own page ----------------------------------------------------------------------
    Component {
        id: appPage
        Column {
            id: pg
            readonly property var d: sw.detail || sw.byId[sw.app] || { id: sw.app, name: "", summary: "" }
            readonly property bool isInstalled: !!sw.installedIds[sw.app]
            readonly property bool busyHere: !!sw.busy && sw.busy.id === sw.app
            spacing: 14
            Row {
                spacing: 10
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: sw.glyph(0xEA60); color: backHover.hovered ? sw.text : sw.dim; font.family: sw.bar.iconFont; font.pixelSize: 18
                    HoverHandler { id: backHover }
                    ClickTap { onTapped: sw.app = "" }
                }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Back"; color: sw.dim; font.family: sw.font; font.pixelSize: 13 }
            }
            Item {
                width: parent.width; height: 96
                AppIcon { id: bigIcon; size: 96; path: pg.d.icon || "" }
                Column {
                    anchors { left: bigIcon.right; leftMargin: 18; right: pageActions.left; rightMargin: 18; verticalCenter: parent.verticalCenter }
                    spacing: 4
                    Text { width: parent.width; elide: Text.ElideRight; textFormat: Text.PlainText; text: pg.d.name || sw.app; color: sw.text; font.family: sw.font; font.pixelSize: 22; font.weight: Font.Medium }
                    Text { width: parent.width; wrapMode: Text.Wrap; textFormat: Text.PlainText; text: pg.d.summary || ""; color: sw.dim; font.family: sw.font; font.pixelSize: 13 }
                    Text {
                        width: parent.width; elide: Text.ElideRight; textFormat: Text.PlainText
                        text: [pg.d.developer, pg.d.latest ? "Version " + pg.d.latest : "", pg.d.license].filter(x => !!x).join(" · ")
                        color: sw.dim; font.family: sw.font; font.pixelSize: 12
                    }
                }
                Row {
                    id: pageActions
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    spacing: 8
                    Meter {
                        visible: pg.busyHere
                        anchors.verticalCenter: parent.verticalCenter
                        width: 140; height: 6
                        value: sw.progress / 100
                        colour: sw.accent; trackColour: sw.faint
                    }
                    Button {
                        visible: !pg.busyHere && pg.isInstalled
                        label: "Remove"; destructive: true
                        onClicked: sw.askRemove(pg.d)
                    }
                    Button {
                        visible: !pg.busyHere
                        label: pg.isInstalled ? "Open" : sw.waiting("install", sw.app) ? "Waiting…" : "Install"
                        primary: true
                        onClicked: pg.isInstalled ? sw.launch(sw.app) : sw.act("install", sw.app, pg.d.name)
                    }
                }
            }
            // Screenshots, in a row you can scroll sideways
            Flickable {
                visible: !!pg.d.screenshots && pg.d.screenshots.length > 0
                width: parent.width; height: visible ? 240 : 0
                contentWidth: shotRow.implicitWidth
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.HorizontalFlick
                Row {
                    id: shotRow
                    spacing: 12
                    Repeater {
                        model: pg.d.screenshots || []
                        delegate: Rectangle {
                            required property var modelData
                            width: 426; height: 240; radius: Config.corner(10)
                            color: sw.faint
                            clip: true
                            Image {
                                anchors.fill: parent
                                source: parent.modelData.thumb
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                sourceSize: Qt.size(852, 480)
                            }
                        }
                    }
                }
            }
            Repeater {
                model: pg.d.description || []
                delegate: Text {
                    required property var modelData
                    width: parent.width; wrapMode: Text.Wrap; textFormat: Text.PlainText
                    text: modelData; color: sw.text; font.family: sw.font; font.pixelSize: 13; lineHeight: 1.15
                }
            }
            Text {
                visible: !!pg.d.homepage
                textFormat: Text.PlainText
                text: "Website: " + (pg.d.homepage || "")
                color: linkHover.hovered ? sw.text : sw.accent; font.family: sw.font; font.pixelSize: 12
                HoverHandler { id: linkHover }
                ClickTap { onTapped: Qt.openUrlExternally(pg.d.homepage) }
            }
        }
    }
}
