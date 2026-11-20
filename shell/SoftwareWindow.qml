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
    property var look: null                   // Quick Look (shell.qml's lookAt): screenshots, large
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
    property var checkedAt: null              // when updates were last looked for
    // (the tests: what the engine would say, by what: { status, catalogue: { apps }, lists,
    // installed: { apps }, updates }, in place of running it)
    property var pretend: ({})
    function refresh() {
        Config.rereadFlathubColours();
        fetchTried = false;
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
    Process {
        id: statusRun; command: [sw.script, "status"]
        stdout: StdioCollector {
            onStreamFinished: sw.take("status", text, v => {
                sw.status = v;
                if (v.flatpak && v.flathub && !v.catalogue && !sw.fetchTried) sw.fetchCatalogue();
            })
        }
    }
    // Flathub set up, but no catalogue yet: Flatpak only gets it on its first update or install,
    // so on a new computer Software was empty with nothing said. It's got now, once each time
    // Software opens (and Try again), then everything's read again.
    // fetching: "" (not now), "busy", or what went wrong, in words
    property string fetching: ""
    property bool fetchTried: false
    function fetchCatalogue() { fetchTried = true; fetching = "busy"; load("fetch", fetchRun); }
    function fetched(line) {
        if (line === "ok") {
            fetching = "";
            load("status", statusRun);
            load("catalogue", catalogueRun);
            load("lists", listsRun);
            return;
        }
        const why = line.replace(/^error /, "");
        fetching = why === "canceled" || why === "" ? "Slate couldn't get the list of apps from Flathub." : why;
    }
    Process {
        id: fetchRun; command: [sw.script, "fetch-catalog"]
        stdout: StdioCollector {
            onStreamFinished: sw.fetched(sw.pretend.fetch !== undefined ? sw.pretend.fetch : (text.trim().split("\n").pop() || ""))
        }
    }
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
        stdout: StdioCollector {
            onStreamFinished: {
                sw.take("updates", text, v => sw.updates = v);
                sw.checkingUpdates = false;
                sw.checkedAt = new Date();
                // (so Settings → Updates shows the same, and the daily look needn't look again soon)
                if (sw.pretend.updates === undefined) SoftwareUpdates.tookFromSoftware(sw.updates.apps.length, sw.updates.system.length);
            }
        }
    }
    Process { id: appRun; stdout: StdioCollector { onStreamFinished: sw.take("app", text, v => sw.detail = v) } }

    // ---- Apps' icons, drawn as the dock's are (AppIcon) ------------------------------------
    // Apps not installed: drawn from the catalog's picture into the style's own folder
    // (tiles/<style>/flathub), a batch at a time, by scripts/appicon.py --tile-files
    function flathubTile(id) { return Config.tileDir + "/flathub/" + String(id).replace(/[^A-Za-z0-9._-]/g, "_") + ".png"; }
    property int tilesVersion: 0
    property var tilesAsked: ({})              // style folder + id: asked already
    property var tilesTried: ({})              // ...and its batch has finished (drawn, or it couldn't be)
    function tileTried(id) { return !!tilesTried[Config.tileDir + " " + id]; }
    property var tilesWanted: []                // ["id\tpicture"], for the next batch
    function wantTile(id, picture) {
        if (!id || !picture) return;
        const key = Config.tileDir + " " + id;
        if (tilesAsked[key]) return;
        tilesAsked[key] = true;
        tilesWanted.push(id + "\t" + picture);
        tileBatch.restart();
    }
    Timer {
        id: tileBatch
        interval: 150
        onTriggered: {
            if (tileRun.running) { restart(); return; }
            if (sw.tilesWanted.length === 0) return;
            tileRun.lines = sw.tilesWanted.join("\n") + "\n";
            tileRun.keys = sw.tilesWanted.map(l => Config.tileDir + " " + l.split("\t")[0]);
            sw.tilesWanted = [];
            tileRun.command = [Config.tileScript, "--tile-files", Config.tileDir + "/flathub", "192"];
            tileRun.running = true;
        }
    }
    Process {
        id: tileRun
        property string lines: ""
        property var keys: []
        stdinEnabled: true
        onStarted: { write(lines); stdinEnabled = false; }
        onExited: {
            stdinEnabled = true;
            const t = Object.assign({}, sw.tilesTried);
            for (const k of keys) t[k] = true;
            sw.tilesTried = t;
            Config.rereadFlathubColours();
            sw.tilesVersion++;
            if (sw.tilesWanted.length) tileBatch.restart();
        }
    }

    // ---- Doing: one at a time, in order (SoftwareJobs, which outlives this window) ------------
    readonly property var queue: SoftwareJobs.queue
    readonly property var busy: SoftwareJobs.busy
    readonly property int progress: SoftwareJobs.progress
    readonly property string note: SoftwareJobs.note
    function act(what, id, name) { SoftwareJobs.act(what, id, name); }
    function waiting(what, id) { return SoftwareJobs.waiting(what, id); }
    Connections {
        target: SoftwareJobs
        function onDone() {
            sw.load("installed", installedRun);
            sw.checkUpdates();
            if (sw.app !== "") sw.openApp(sw.app);
        }
    }
    // An app's screenshots, large (Quick Look), starting at one
    function showShots(at) {
        const shots = (detail && detail.screenshots) || [];
        if (!look || shots.length === 0) return;
        const name = detail.name || app;
        look(shots.map(x => x.full || x.thumb), at, "",
             shots.map((x, i) => x.caption || (name + ", screenshot " + (i + 1))));
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
                            Text { text: "Slate"; color: sw.text; font.family: sw.font; font.pixelSize: Config.text(18); font.weight: Font.Medium }
                            Text { text: "Software"; color: sw.dim; font.family: sw.font; font.pixelSize: Config.text(12) }
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
                            // As Settings' sidebar: Colorful, each section its own colour; else dim
                            // (dark like its name on the section you're in)
                            color: parent.current ? sw.accentText : Config.colourful ? Config.pageColour("software-" + parent.modelData.id) : sw.dim
                            Behavior on color { ColorAnimation { duration: Config.ms(100) } }
                            font.family: sw.bar.iconFont; font.pixelSize: 17
                        }
                        Text {
                            visible: !sw.compact
                            anchors { left: navIcon.right; leftMargin: 12; verticalCenter: parent.verticalCenter }
                            text: parent.modelData.label
                            color: parent.current ? sw.accentText : sw.dim
                            Behavior on color { ColorAnimation { duration: Config.ms(100) } }
                            font.family: sw.font; font.pixelSize: Config.text(13); font.weight: Font.Medium
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
                                font.family: sw.font; font.pixelSize: Config.text(11); font.weight: Font.DemiBold
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
            // The header: its empty space moves the window, as a title bar would (on every page,
            // Discover's too, which scrolls beneath it rather than up to the window's top)
            MouseArea {
                anchors { top: parent.top; left: parent.left; right: parent.right }
                height: 59
                z: 1
                onPressed: sw.startSystemMove()
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
                anchors { top: parent.top; topMargin: 59; left: parent.left; right: parent.right; bottom: parent.bottom }
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
                                text: !sw.status.flatpak ? "Flatpak isn't installed, so Software can't install apps yet. Install the flatpak package, then open this again."
                                    : "Flathub isn't set up for Flatpak yet. In a terminal: flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo"
                                color: sw.dim; font.family: sw.font; font.pixelSize: Config.text(13)
                            }
                        }
                    }
                    // ---- Getting the catalogue, the first time ----
                    Group {
                        visible: sw.status.flatpak && sw.status.flathub && (!sw.status.catalogue || sw.fetching !== "")
                        Column {
                            width: parent.width
                            topPadding: 16; bottomPadding: 16; spacing: 12
                            Text {
                                anchors { left: parent.left; right: parent.right; margins: 16 }
                                wrapMode: Text.Wrap
                                textFormat: Text.PlainText        // (it can quote what Flatpak said)
                                text: sw.fetching === "busy" || sw.fetching === ""
                                    ? "Getting the list of apps from Flathub. This takes a few seconds the first time."
                                    : sw.fetching
                                color: sw.dim; font.family: sw.font; font.pixelSize: Config.text(13)
                            }
                            Button {
                                x: 16
                                visible: sw.fetching !== "busy" && sw.fetching !== ""
                                label: "Try again"; icon: 0xEB13
                                onClicked: sw.fetchCatalogue()
                            }
                        }
                    }
                    Text {
                        visible: sw.note !== ""
                        width: parent.width; wrapMode: Text.Wrap; bottomPadding: 6
                        textFormat: Text.PlainText        // (it can quote what Flatpak said)
                        text: sw.note; color: sw.danger; font.family: sw.font; font.pixelSize: Config.text(12)
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
                        topPadding: 2
                        bottomPadding: 22
                        Text {
                            width: parent.width; horizontalAlignment: Text.AlignHCenter
                            text: "Find apps for your computer"
                            color: sw.text; font.family: sw.font; font.pixelSize: Config.text(24); font.weight: Font.Medium
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: Math.min(parent.width, 520); wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter
                            text: "Apps here come from Flathub, where thousands of free apps run safely in a space of their own. "
                                + "What you install here is there for everyone who uses this computer, and its updates show under Updates."
                            color: sw.dim; font.family: sw.font; font.pixelSize: Config.text(13); lineHeight: 1.15
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
                            color: sw.dim; font.family: sw.font; font.pixelSize: Config.text(12)
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
                        // Back to Discover beside its title, as Settings' pages have
                        Item {
                            width: parent.width; height: 48
                            IconButton {
                                id: catBack
                                anchors { left: parent.left; leftMargin: -8; verticalCenter: parent.verticalCenter }
                                icon: 0xEA19
                                onClicked: sw.show("discover")
                            }
                            IconTile { id: catTile; anchors { left: catBack.right; leftMargin: 6; verticalCenter: parent.verticalCenter } size: 36; code: catPage.cat ? catPage.cat.icon : 0xEB1C; colourOf: "software-" + sw.page }
                            Text { anchors { left: catTile.right; leftMargin: 12; verticalCenter: parent.verticalCenter } text: catPage.cat ? catPage.cat.label : ""; color: sw.text; font.family: sw.font; font.pixelSize: Config.text(22); font.weight: Font.Medium }
                        }
                        Group { Repeater { model: catPage.apps.slice(0, 120); delegate: AppRow { required property var modelData; required property int index; entry: modelData; first: index === 0 } } }
                    }

                    // ---- Installed ----
                    Column {
                        width: parent.width
                        visible: sw.app === "" && sw.query.trim() === "" && sw.page === "installed"
                        spacing: 4
                        Text { text: "Installed"; color: sw.text; font.family: sw.font; font.pixelSize: Config.text(22); font.weight: Font.Medium; bottomPadding: 8 }
                        Text {
                            visible: sw.installed.length === 0
                            width: parent.width; wrapMode: Text.Wrap
                            text: "No apps from Flathub yet. Find one in Discover, or search above."
                            color: sw.dim; font.family: sw.font; font.pixelSize: Config.text(13)
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
                        Text { text: "Updates"; color: sw.text; font.family: sw.font; font.pixelSize: Config.text(22); font.weight: Font.Medium; bottomPadding: 8 }
                        // Nothing waiting: said calmly in the middle of the page, with what that
                        // covers, when it was looked at, and a way to look again. (While looking:
                        // Slate's spinner in its place)
                        Column {
                            id: upToDate
                            readonly property bool looking: sw.checkingUpdates && sw.updateCount === 0
                            visible: sw.updateCount === 0 && sw.updates.systemProblem === ""
                            width: parent.width
                            topPadding: 40
                            spacing: 10
                            Item {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 76; height: 76
                                IconTile {
                                    anchors.centerIn: parent
                                    size: 76; code: 0xEA5E; colourOf: "software-updates"
                                    opacity: upToDate.looking ? 0 : 1
                                    Behavior on opacity { NumberAnimation { duration: Config.ms(200) } }
                                }
                                Text {
                                    id: lookingSpinner
                                    anchors.centerIn: parent
                                    opacity: upToDate.looking ? 1 : 0
                                    visible: opacity > 0
                                    Behavior on opacity { NumberAnimation { duration: Config.ms(200) } }
                                    text: sw.glyph(0xF226); color: sw.accent
                                    font.family: sw.bar.iconFont; font.pixelSize: 30
                                    RotationAnimation on rotation { running: lookingSpinner.visible && Config.animate; loops: Animation.Infinite; from: 0; to: 360; duration: 900 }
                                }
                            }
                            Item { width: 1; height: 4 }
                            Text {
                                width: parent.width; horizontalAlignment: Text.AlignHCenter
                                text: upToDate.looking ? "Looking for updates…" : "You're up to date"
                                color: sw.text; font.family: sw.font; font.pixelSize: Config.text(20); font.weight: Font.Medium
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: Math.min(parent.width, 420); wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter
                                text: upToDate.looking ? "Slate's checking your apps and this computer's system."
                                    : sw.installed.length === 0 ? "This computer's system has the latest updates."
                                    : (sw.installed.length === 1 ? "Your app" : "Your " + sw.installed.length + " apps")
                                      + " and this computer's system have the latest updates."
                                color: sw.dim; font.family: sw.font; font.pixelSize: Config.text(13); lineHeight: 1.15
                            }
                            Text {
                                width: parent.width; horizontalAlignment: Text.AlignHCenter
                                visible: !upToDate.looking && !!sw.checkedAt
                                text: sw.checkedAt ? "Checked at " + Qt.formatTime(sw.checkedAt, Config.s.barClockFormat === "24h" ? "HH:mm" : "h:mm AP") : ""
                                color: sw.dim; font.family: sw.font; font.pixelSize: Config.text(12)
                            }
                            Item { width: 1; height: 6 }
                            Button {
                                anchors.horizontalCenter: parent.horizontalCenter
                                label: "Check again"; icon: 0xEB13
                                // (gone while it looks: there's nothing to do until it's done)
                                opacity: upToDate.looking ? 0 : 1
                                visible: opacity > 0
                                Behavior on opacity { NumberAnimation { duration: Config.ms(200) } }
                                onClicked: if (!upToDate.looking) sw.checkUpdates()
                            }
                        }
                        GroupLabel { visible: sw.updates.apps.length > 0; text: sw.updates.apps.length === 1 ? "1 app" : sw.updates.apps.length + " apps" }
                        // Update all of them at once, or each on its own (its row's Update)
                        Group {
                            visible: sw.updates.apps.length > 0
                            Item {
                                width: parent.width; height: 56
                                Text {
                                    anchors { left: parent.left; leftMargin: 16; right: allAction.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                    elide: Text.ElideRight
                                    text: allAction.running ? "Updating your apps… " + sw.progress + "%"
                                        : "Your apps and windows stay open while they update"
                                    color: sw.dim; font.family: sw.font; font.pixelSize: Config.text(12)
                                }
                                // While it runs, a progress bar in the button's place (as an app's row has)
                                ProgressOr {
                                    id: allAction
                                    anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                                    running: !!sw.busy && sw.busy.what === "update-apps" && sw.busy.id === ""
                                    Button {
                                        label: "Update all apps"; primary: true; icon: 0xEB13
                                        opacity: sw.waiting("update-apps", "") ? 0.5 : 1
                                        onClicked: sw.act("update-apps", "", "your apps")
                                    }
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
                                    anchors { left: parent.left; leftMargin: 16; right: sysAction.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                    spacing: 2
                                    Text {
                                        width: parent.width; elide: Text.ElideRight
                                        text: sw.updates.systemProblem !== "" ? "System updates" : sw.updates.system.length === 1 ? "1 system update" : sw.updates.system.length + " system updates"
                                        color: sw.text; font.family: sw.font; font.pixelSize: Config.text(13); font.weight: Font.Medium
                                    }
                                    Text {
                                        width: parent.width; wrapMode: Text.Wrap
                                        textFormat: Text.PlainText
                                        text: sw.updates.systemProblem !== "" ? sw.updates.systemProblem
                                            : sysAction.running ? "Updating the system… " + sw.progress + "%"
                                            : "They update together. Asks for an administrator's password; restart afterwards if it says to"
                                        color: sw.dim; font.family: sw.font; font.pixelSize: Config.text(12)
                                    }
                                }
                                ProgressOr {
                                    id: sysAction
                                    visible: sw.updates.system.length > 0
                                    anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                                    running: !!sw.busy && sw.busy.what === "update-system"
                                    Button {
                                        label: "Update"; icon: 0xEB13
                                        opacity: sw.waiting("update-system", "") ? 0.5 : 1
                                        onClicked: sw.act("update-system", "", "the system")
                                    }
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
                                        color: sw.text; font.family: sw.font; font.pixelSize: Config.text(13)
                                    }
                                    Text {
                                        id: pkgVersion
                                        anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                                        width: Math.min(implicitWidth, parent.width * 0.55)
                                        elide: Text.ElideMiddle; textFormat: Text.PlainText
                                        text: (parent.modelData.from ? parent.modelData.from + "  →  " : "") + parent.modelData.to
                                        color: sw.dim; font.family: sw.font; font.pixelSize: Config.text(12)
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
                anchors { top: scroller.top; bottom: parent.bottom; right: parent.right; rightMargin: 4; bottomMargin: 8 }
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
        AppIcon { id: rowIcon; anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter } size: 40; appId: row.entry.id || ""; path: row.entry.icon || "" }
        Column {
            anchors { left: rowIcon.right; leftMargin: 12; right: rowAction.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
            spacing: 2
            Text { width: parent.width; elide: Text.ElideRight; textFormat: Text.PlainText; text: row.entry.name || row.entry.id; color: sw.text; font.family: sw.font; font.pixelSize: Config.text(13); font.weight: Font.Medium }
            Text {
                width: parent.width; elide: Text.ElideRight; textFormat: Text.PlainText
                text: row.updating ? (row.newVersion ? "Version " + row.newVersion : "An update is waiting") : (row.entry.summary || "")
                color: sw.dim; font.family: sw.font; font.pixelSize: Config.text(12)
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
                    id: rowButton
                    label: row.updating ? (sw.waiting("update-apps", row.entry.id) ? "Waiting…" : "Update")
                        : sw.waiting("install", row.entry.id) ? "Waiting…" : row.isInstalled ? "Open" : "Install"
                    primary: !row.updating && !row.isInstalled
                    onClicked: row.updating ? sw.act("update-apps", row.entry.id, row.entry.name)
                        : row.isInstalled ? sw.launch(row.entry.id) : sw.act("install", row.entry.id, row.entry.name)
                }
                Button {
                    visible: row.removable && row.isInstalled
                    label: "Remove"; destructive: true; icon: 0xEB41
                    onClicked: sw.askRemove(row.entry)
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
        property string appId: ""
        property string path: ""                  // the catalog's picture of it
        property real size: 40
        // Drawn as the dock draws apps (Settings → Icons: shape, fill, theme, tint, glass):
        // installed, the dock's own tile of it; else its catalog picture drawn the same way
        // (sw.wantTile). Nothing shows until it's ready, then it fades in (showing the picture first
        // and swapping flickered); the picture itself only if it couldn't be drawn
        readonly property bool installedApp: !!sw.installedIds[appId]
        readonly property real density: sw.screen ? sw.screen.devicePixelRatio : 1
        property bool noDockTile: false
        property bool gaveUp: false
        onAppIdChanged: { noDockTile = false; gaveUp = false; slowIcon.restart(); }
        readonly property string tile: !appId ? "" : installedApp && !noDockTile ? Config.tilePath(appId) : sw.flathubTile(appId)
        width: size; height: size
        // Until it's ready: a soft shape where it'll be (the icons' own shape, Settings → Icons),
        // with Slate's spinner once it's taking a while; the icon then fades in over it
        Timer { id: slowIcon; interval: 350; running: true }
        Rectangle {
            id: aiPlace
            anchors.fill: parent
            radius: Config.iconCornerFor(ai.size)
            color: sw.faint
            opacity: aiTile.status === Image.Ready || ai.gaveUp ? 0 : 1
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: Config.ms(200) } }
            Text {
                id: aiSpinner
                anchors.centerIn: parent
                opacity: aiPlace.opacity === 1 && !slowIcon.running ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: Config.ms(150) } }
                text: sw.glyph(0xF226); color: sw.accent
                font.family: sw.bar.iconFont; font.pixelSize: Math.round(ai.size * 0.38)
                RotationAnimation on rotation { running: aiSpinner.visible && Config.animate; loops: Animation.Infinite; from: 0; to: 360; duration: 900 }
            }
        }
        Image {
            id: aiTile
            anchors.fill: parent
            visible: status === Image.Ready
            opacity: status === Image.Ready ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Config.ms(200) } }
            source: ai.tile ? "file://" + ai.tile + "?v=" + Config.tileVersion + "." + sw.tilesVersion : ""
            // Shrunk once to exactly the pixels it's drawn at (as the launcher's are): mipmapped
            // from a larger picture, it came out soft on a 2× screen
            sourceSize: Qt.size(Math.ceil(ai.size * ai.density), Math.ceil(ai.size * ai.density))
            smooth: true
            asynchronous: true
            onStatusChanged: {
                if (status !== Image.Error) return;
                if (ai.installedApp && !ai.noDockTile) ai.noDockTile = true;
                else if (sw.tileTried(ai.appId) || !ai.path) ai.gaveUp = true;
                else sw.wantTile(ai.appId, ai.path);
            }
            layer.enabled: Config.iconTint > 0
            layer.effect: IconTint {}
            IconPlate { anchors.fill: parent; z: -1; visible: parent.status === Image.Ready && !Config.s.iconFill && Config.s.iconShape !== "original" }
            IconGloss { visible: parent.status === Image.Ready && Config.glassGloss && Config.s.iconShape !== "original" }
        }
        Image {
            id: aiImg
            anchors.fill: parent
            visible: ai.gaveUp && ai.path !== "" && status === Image.Ready
            source: ai.gaveUp && ai.path ? "file://" + ai.path : ""
            sourceSize: Qt.size(ai.size * 2, ai.size * 2)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
        }
        Rectangle {
            visible: ai.gaveUp && !aiImg.visible
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
            color: sw.text; font.family: sw.font; font.pixelSize: Config.text(field.big ? 15 : 13)
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
        // (whole pixels: a card a fraction of one wide puts the next between pixels, and blurs it)
        readonly property real cardWidth: Math.floor((width - gap * (perPage - 1)) / perPage)
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
                IconTile { anchors.verticalCenter: parent.verticalCenter; code: strip.cat.icon || 0xEB1C; colourOf: "software-" + strip.cat.id }
                Text { anchors.verticalCenter: parent.verticalCenter; text: strip.cat.label || ""; color: sw.text; font.family: sw.font; font.pixelSize: Config.text(15); font.weight: Font.Medium }
            }
            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 4
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    rightPadding: 8
                    text: "See all"
                    color: seeAllHover.hovered ? sw.text : sw.accent; font.family: sw.font; font.pixelSize: Config.text(12); font.weight: Font.Medium
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

    // A button, or while what it started runs, a progress bar in its place
    component ProgressOr: Item {
        id: po
        property bool running: false
        default property alias button: slot.data
        width: running ? 160 : slot.childrenRect.width
        height: 30
        Item { id: slot; anchors.verticalCenter: parent.verticalCenter; visible: !po.running; width: childrenRect.width; height: childrenRect.height }
        Meter {
            visible: po.running
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width; height: 6
            value: sw.progress / 100
            colour: sw.accent; trackColour: sw.faint
        }
    }

    // A category's icon on a soft square of its own colour, as All Settings' page icons are (its
    // pastel when Colorful, else the accent)
    component IconTile: Rectangle {
        property int code: 0
        property string colourOf: ""
        property real size: 30
        readonly property color pc: Config.pageColour(colourOf)
        width: size; height: size; radius: Config.corner(size * 0.3)
        color: Qt.rgba(pc.r, pc.g, pc.b, 0.16)
        Text {
            anchors.centerIn: parent
            text: sw.glyph(parent.code)
            color: parent.pc
            font.family: sw.bar.iconFont; font.pixelSize: Math.round(parent.size * 0.53)
        }
    }

    // An app as a card: its icon, name and what it's for; opens its page
    component AppCard: Rectangle {
        id: card
        property var entry: ({})
        height: 140; radius: Config.corner(12)
        color: sw.card
        HoverFill { hovered: cardHover.hovered; radius: parent.radius }
        AppIcon { id: cardIcon; anchors { left: parent.left; top: parent.top; margins: 14 } size: 52; appId: card.entry.id || ""; path: card.entry.icon || "" }
        Text {
            visible: !!sw.installedIds[card.entry.id]
            anchors { right: parent.right; top: parent.top; margins: 14 }
            text: "Installed"; color: sw.dim; font.family: sw.font; font.pixelSize: Config.text(11)
        }
        Column {
            anchors { left: parent.left; right: parent.right; top: cardIcon.bottom; margins: 14; topMargin: 10 }
            spacing: 3
            Text { width: parent.width; elide: Text.ElideRight; textFormat: Text.PlainText; text: card.entry.name || card.entry.id; color: sw.text; font.family: sw.font; font.pixelSize: Config.text(13); font.weight: Font.Medium }
            Text {
                width: parent.width; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight; textFormat: Text.PlainText
                text: card.entry.summary || ""; color: sw.dim; font.family: sw.font; font.pixelSize: Config.text(12)
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
            // Its name as the page's title, with Back beside it, as Settings' pages have
            Item {
                width: parent.width; height: 40
                IconButton {
                    id: appBack
                    anchors { left: parent.left; leftMargin: -8; verticalCenter: parent.verticalCenter }
                    icon: 0xEA19
                    onClicked: sw.app = ""
                }
                Text {
                    anchors { left: appBack.right; leftMargin: 6; right: parent.right; verticalCenter: parent.verticalCenter }
                    elide: Text.ElideRight; textFormat: Text.PlainText
                    text: pg.d.name || sw.app
                    color: sw.text; font.family: sw.font; font.pixelSize: Config.text(22); font.weight: Font.Medium
                }
            }
            Item {
                // (as tall as what's beside the icon, at least the icon's height)
                width: parent.width; height: Math.max(96, pageInfo.implicitHeight)
                AppIcon { id: bigIcon; anchors.verticalCenter: parent.verticalCenter; size: 96; appId: sw.app; path: pg.d.icon || "" }
                // What it is, who makes it, and what you can do with it, beside its icon
                Column {
                    id: pageInfo
                    anchors { left: bigIcon.right; leftMargin: 18; right: parent.right; verticalCenter: parent.verticalCenter }
                    spacing: 4
                    Text { width: parent.width; wrapMode: Text.Wrap; textFormat: Text.PlainText; text: pg.d.summary || ""; color: sw.text; font.family: sw.font; font.pixelSize: Config.text(15) }
                    Text {
                        width: parent.width; elide: Text.ElideRight; textFormat: Text.PlainText
                        text: [pg.d.developer, pg.d.latest ? "Version " + pg.d.latest : "", pg.d.license].filter(x => !!x).join(" · ")
                        color: sw.dim; font.family: sw.font; font.pixelSize: Config.text(12)
                    }
                    Item { width: 1; height: 6 }
                    Row {
                        id: pageActions
                        spacing: 8
                        height: 32
                        Meter {
                            visible: pg.busyHere
                            anchors.verticalCenter: parent.verticalCenter
                            width: 160; height: 6
                            value: sw.progress / 100
                            colour: sw.accent; trackColour: sw.faint
                        }
                        Button {
                            visible: !pg.busyHere
                            label: pg.isInstalled ? "Open" : sw.waiting("install", sw.app) ? "Waiting…" : "Install"
                            primary: true
                            onClicked: pg.isInstalled ? sw.launch(sw.app) : sw.act("install", sw.app, pg.d.name)
                        }
                        Button {
                            visible: !pg.busyHere && pg.isInstalled
                            label: "Remove"; destructive: true; icon: 0xEB41
                            onClicked: sw.askRemove(pg.d)
                        }
                    }
                }
            }
            // Screenshots, in a row you can scroll sideways, with shades at the ends while there's
            // more that way (as everything that scrolls has)
            Item {
                visible: !!pg.d.screenshots && pg.d.screenshots.length > 0
                width: parent.width; height: visible ? 240 : 0
                Flickable {
                    id: shotFlick
                    anchors.fill: parent
                    contentWidth: shotRow.implicitWidth
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.HorizontalFlick
                    Row {
                        id: shotRow
                        spacing: 12
                        Repeater {
                            model: pg.d.screenshots || []
                            // Clicked: large, in Quick Look (the dimmed screen, Left and Right through
                            // the rest, Escape or a click outside to close)
                            delegate: Rectangle {
                                id: shot
                                required property var modelData
                                required property int index
                                width: 426; height: 240; radius: Config.corner(10)
                                color: sw.faint
                                clip: true
                                // Fades in once it's loaded, with Slate's spinner until then
                                Image {
                                    id: shotImg
                                    anchors.fill: parent
                                    source: shot.modelData.thumb
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    sourceSize: Qt.size(852, 480)
                                    opacity: status === Image.Ready ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: Config.ms(220) } }
                                    // (the spinner only once it's taking a while: one already kept
                                    // loads in a moment, and just fades in)
                                    onStatusChanged: if (status === Image.Loading) slowShot.restart(); else slowShot.stop()
                                    Component.onCompleted: if (status === Image.Loading) slowShot.restart()
                                    Timer { id: slowShot; interval: 350 }
                                }
                                Text {
                                    id: shotSpinner
                                    anchors.centerIn: parent
                                    opacity: shotImg.status === Image.Loading && !slowShot.running ? 1 : 0
                                    visible: opacity > 0
                                    Behavior on opacity { NumberAnimation { duration: Config.ms(150) } }
                                    text: sw.glyph(0xF226)
                                    color: sw.accent
                                    font.family: sw.bar.iconFont; font.pixelSize: 22
                                    RotationAnimation on rotation { running: shotSpinner.visible && Config.animate; loops: Animation.Infinite; from: 0; to: 360; duration: 900 }
                                }
                                ClickTap { onTapped: sw.showShots(shot.index) }
                            }
                        }
                    }
                }
                ScrollShade {
                    sideways: true
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                    distance: shotFlick.contentX
                }
                ScrollShade {
                    sideways: true; atBottom: true
                    anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                    distance: shotFlick.contentWidth - shotFlick.width - shotFlick.contentX
                }
            }
            Repeater {
                model: pg.d.description || []
                delegate: Text {
                    required property var modelData
                    width: parent.width; wrapMode: Text.Wrap; textFormat: Text.PlainText
                    text: modelData; color: sw.text; font.family: sw.font; font.pixelSize: Config.text(13); lineHeight: 1.15
                }
            }
            Text {
                visible: !!pg.d.homepage
                textFormat: Text.PlainText
                text: "Website: " + (pg.d.homepage || "")
                color: linkHover.hovered ? sw.text : sw.accent; font.family: sw.font; font.pixelSize: Config.text(12)
                HoverHandler { id: linkHover }
                ClickTap { onTapped: Qt.openUrlExternally(pg.d.homepage) }
            }
        }
    }
}
