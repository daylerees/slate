// Nova, Slate's assistant: a small prompt window, like the launcher. Type what you want
// ("turn on glass", "put Firefox on workspace 2") and it's handed to the agent you chose
// (Settings → Assistant), which acts through Slate's own tools (docs/ASSISTANT.md).
//   slate ipc call assistant toggle      (or open / close / stop; Super+K)
//   slate ipc call assistant ask <text>  open and send
// scripts/assistant.py runs the agent and says what comes back, a JSON line at a time. The
// answer's words never reach a text item that reads markup: Qt's Markdown and rich text load
// any picture named in them (from the network or disk), so a misled agent could send what it
// read to someone else's server. The runner reads a small, safe subset of Markdown itself
// (scripts/safe_markdown.py: paragraphs, bold, italic, code, code boxes, lists, headings) and
// sends it as blocks; Slate draws those with its own items, and the only markup any of them
// sees is the few tags rich() writes around words it has escaped. Links are their words and
// their address as text, never clickable; images are their description. An answer without
// blocks (one kept from before, or an error) is plain text, as it always was. "What it did"
// is Slate's own record, sent by Slate's MCP server as each
// tool is used (did(), from AssistantGate's IPC): words Slate wrote, not the agent's.
// It reads as a chat: what you asked on the right in the accent colour, Nova's answers on
// the left in its own, in order. There are no "conversations" to manage: the history just
// runs on (Clear empties it), and what you type within a few minutes of the last answer
// follows on from it. Left longer, Nova quietly starts afresh with the agent (followFor). Closing the
// window lets a run carry on (a notification says when it's done); Stop ends it. Not loaded
// on the lock or login screens, and a run stops when the screen locks.

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

PanelWindow {
    id: root

    // ---- Look: the launcher's ------------------------------------------------
    readonly property real panelWidth: Math.max(300, Math.min(560, width - 32))
    readonly property int fadeMs: 200
    readonly property real dropDistance: 18
    // (at its own opacity with glass: Settings → Assistant → Glass)
    readonly property color barColor: Config.assistantSurface(Config.tint("#0f1216"))
    readonly property color fieldColor: Config.raised(Config.tint("#1d222a"))
    // Nova's side of the conversation: a touch of its own colour over the field's
    readonly property color replyColor: Qt.tint(fieldColor, Qt.rgba(Config.pageColour("assistant").r, Config.pageColour("assistant").g, Config.pageColour("assistant").b, 0.10))
    readonly property color textColor: Config.tint("#eef1f5")
    readonly property color dimTextColor: Config.tint("#8b94a3")
    readonly property color accent: Config.accent
    readonly property color accentText: Config.tint("#12151a")
    readonly property color danger: Config.tint("#f28b8b")
    readonly property string fontFamily: Config.s.fontFamily
    FontLoader { id: tabler; source: "file://" + Quickshell.shellPath("fonts/tabler.ttf") }
    // Code in an answer: the monospaced font (Settings → Appearance), on a plate a step darker
    // than the bubble (solid, so on glass it isn't a lighter patch laid over the bubble)
    readonly property string codeFont: String(Config.s.codeFontFamily || "monospace").replace(/[^\w .-]/g, "")
    readonly property color codePlate: Config.tint("#14181e")

    // ---- An answer's words, as Slate's own markup -------------------------------------
    // The blocks the runner sends (scripts/safe_markdown.py), checked again here as they arrive
    // or are read back from the kept conversation: only the kinds Slate draws, every word a
    // string. Anything else becomes plain words
    function cleanRuns(rs) {
        return (Array.isArray(rs) ? rs : []).slice(0, 4000).map(r => ({
            text: String(r && r.text !== undefined ? r.text : ""), bold: !!(r && r.bold), italic: !!(r && r.italic),
            code: !!(r && r.code), dim: !!(r && r.dim) }));
    }
    function cleanBlocks(bs) {
        return (Array.isArray(bs) ? bs : []).slice(0, 201).filter(b => b && typeof b === "object").map(b => {
            if (b.type === "list")
                return { type: "list", items: (Array.isArray(b.items) ? b.items : []).slice(0, 200).filter(it => it && typeof it === "object")
                    .map(it => ({ level: it.level === 1 ? 1 : 0, marker: String(it.marker || "•").slice(0, 12), runs: cleanRuns(it.runs) })) };
            if (b.type === "code" || b.type === "table")
                return { type: b.type, text: String(b.text || ""), lang: String(b.lang || "").slice(0, 20), open: !!b.open };
            return { type: b.type === "heading" ? "heading" : "paragraph", runs: cleanRuns(b.runs) };
        });
    }
    // Words made safe to show: every character that markup could start with written as itself
    function esc(s) { return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;"); }
    function hex(c) { return "#" + [c.r, c.g, c.b].map(v => Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16).padStart(2, "0")).join(""); }
    // One block's runs as the rich text its TextEdit shows: the words escaped, then wrapped in
    // the only tags Slate uses (b, i, and a span for code or dim words). Spaces and line
    // breaks stay as written. strong: all of it bold (a heading)
    function rich(runs, strong) {
        let h = "";
        for (const r of runs || []) {
            let t = esc(r.text);
            if (r.code) t = "<span style=\"font-family:'" + codeFont + "'; background-color:" + hex(codePlate) + "\"> " + t + " </span>";
            if (r.dim) t = "<span style=\"color:" + hex(dimTextColor) + "\">" + t + "</span>";
            if (r.italic) t = "<i>" + t + "</i>";
            if (r.bold) t = "<b>" + t + "</b>";
            h += t;
        }
        if (strong) h = "<b>" + h + "</b>";
        return "<span style=\"white-space:pre-wrap\">" + h + "</span>";
    }
    // An answer's first line without its marks: for the notification when it arrives out of sight
    function firstLine(t) {
        const b = t && t.blocks && t.blocks.length ? t.blocks[0] : null;
        const words = rs => (rs || []).map(r => r.text).join("");
        const s = !b ? (t ? t.answer : "") : b.runs ? words(b.runs) : b.items ? (b.items.length ? words(b.items[0].runs) : "") : b.text;
        return String(s || "").trim().split("\n")[0].slice(0, 160);
    }

    // ---- State ---------------------------------------------------------------
    property bool shown: false
    property bool working: false
    // The conversation, oldest first: [{ asked, answer, error, actions }] (error: { kind,
    // message, detail } when it went wrong; actions: what it did, [{ id, text, state }], with
    // { key, before, after, undone } on a setting it changed: keptAction).
    // The last one is the exchange in hand
    property var turns: []
    readonly property int maxTurns: 50       // (the last 100 messages: 50 of yours, 50 answers)
    readonly property var cur: turns.length > 0 ? turns[turns.length - 1] : null
    readonly property string asked: cur ? cur.asked : ""
    readonly property string answer: cur ? cur.answer : ""
    readonly property var error: cur ? cur.error : null
    readonly property var actions: cur ? cur.actions : []
    // The conversation is kept on this computer (Settings → Assistant → Keep the conversation),
    // so it's still there after Slate restarts or you log in again:
    // ~/.local/state/slate/assistant/chat.json, in a folder only you can read, never sent
    // anywhere or put in `slate logs`, and emptied by New. The agent's own conversation
    // (session) is kept with it, so a follow-up still follows. Switched off, nothing is
    // written and what was kept is deleted
    readonly property string chatFile: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/slate/assistant/chat.json"
    property bool restored: false
    readonly property bool keepChat: Config.s.assistantKeepChat
    onKeepChatChanged: {
        if (!restored) return;
        if (keepChat) chatSave.restart();
        else Quickshell.execDetached(["rm", "-f", chatFile]);
    }
    FileView {
        id: chatStore
        path: root.keepChat || !root.restored ? root.chatFile : ""
        blockLoading: true
        printErrors: false
        onLoaded: {
            if (root.restored) return;
            if (!Config.s.assistantKeepChat) { root.restored = true; return; }
            try {
                const d = JSON.parse(text());
                const clean = t => ({ asked: String(t.asked || ""), answer: String(t.answer || ""), blocks: root.cleanBlocks(t.blocks), at: Number(t.at) || 0, doneAt: Number(t.doneAt) || 0,
                                      error: t.error && t.error.message ? { kind: String(t.error.kind || "failed"), message: String(t.error.message), detail: String(t.error.detail || "") } : null,
                                      actions: (t.actions || []).filter(a => a && typeof a === "object").map(a => root.keptAction(a)) });
                let list = (d.turns || []).filter(t => t && t.asked).map(clean).slice(-root.maxTurns);
                // (one that was still being answered when Slate stopped)
                list = list.map(t => t.answer === "" && !t.error ? Object.assign(t, { answer: "Stopped." }) : t);
                list.forEach(t => t.actions = t.actions.map(a => a.state === "asking" ? Object.assign(a, { state: "no answer" }) : a));
                root.turns = list;
                root.session = String(d.session || "");
            } catch (e) {}
            root.restored = true;
        }
        onLoadFailed: root.restored = true
    }
    Timer {
        id: chatSave
        interval: 600
        onTriggered: {
            if (!root.keepChat || !root.restored) return;
            chatStore.setText(JSON.stringify({ session: root.session, turns: root.turns }));
            Quickshell.execDetached(["chmod", "600", root.chatFile]);
        }
    }
    onTurnsChanged: chatSave.restart()
    onSessionChanged: chatSave.restart()
    // (at: when you asked; doneAt: when the answer was finished. Shown as "2 min ago")
    // (blocks: the answer as Slate draws it, from the runner; with none, it's plain text)
    function begin(text) { turns = turns.concat([{ asked: text, answer: "", blocks: [], error: null, actions: [], at: Date.now(), doneAt: 0 }]).slice(-maxTurns); }
    // "2 min ago", worded as on notifications, and kept fresh while the window shows
    property int tick: 0
    Timer { interval: 30000; running: root.shown; repeat: true; onTriggered: root.tick++ }
    onShownChanged: if (shown) tick++
    function ago(t) {
        tick;
        if (!t) return "";
        const s = Math.max(0, (Date.now() - t) / 1000);
        if (s < 60) return "now";
        if (s < 3600) return Math.floor(s / 60) + " min ago";
        if (s < 86400) return Math.floor(s / 3600) + " h ago";
        return Config.dateText(new Date(t), "day");
    }
    function patch(change) {
        if (turns.length === 0) return;
        const t = turns.slice();
        t[t.length - 1] = Object.assign({}, t[t.length - 1], change);
        turns = t;
    }
    property string session: ""            // the agent's conversation, for a follow-up
    property string runId: ""
    property real answeredAt: 0
    // Copying a message (the icon that shows in its corner under the pointer): which one was
    // just copied ("3:you", "3:nova"), for a moment, so its icon can say so
    property string copied: ""
    Timer { id: copiedReset; interval: 1400; onTriggered: root.copied = "" }
    function copy(which, text) {
        if (!text) return;
        Quickshell.execDetached(["wl-copy", "--", text]);     // (--: words starting with - are words too)
        copied = which;
        copiedReset.restart();
    }
    // A code box's Copy: just its code (turn and block: where it is in the conversation)
    function copyCode(ti, bi) {
        const b = turns[ti] && turns[ti].blocks ? turns[ti].blocks[bi] : null;
        if (b && b.type === "code") copy(ti + ":code:" + bi, b.text);
    }
    // (for the tests: the markup each words item of the latest answer is given)
    function richNow() {
        const out = [];
        for (const b of (cur && cur.blocks) || []) {
            if (b.runs) out.push(rich(b.runs, b.type === "heading"));
            for (const it of b.items || []) out.push(rich(it.runs));
        }
        return out;
    }
    readonly property bool on: Config.assistantOn
    // The agents there are (scripts/assistant.py detect), looked for when the window first opens
    property var agents: []
    property bool looked: false
    readonly property var agent: {
        const want = Config.s.assistantAgent;
        if (want === "custom") return { id: "custom", label: "Your command", installed: Config.s.assistantCommand !== "", signedIn: true, confined: false, followUps: false };
        // (none until one's chosen in Settings → Assistant: Slate doesn't pick one for you)
        return want === "" ? null : (agents.find(a => a.id === want) || null);
    }
    // What you type follows on from the last answer (the agent keeps its thread, session) for
    // this long after it; then the thread is dropped and the next prompt starts afresh. Nothing
    // on screen changes: it's how long "and a bit bigger" can be expected to make sense, and a
    // long thread costs more with every prompt
    readonly property int followFor: 5 * 60 * 1000
    function lastHeard() { return cur ? (cur.doneAt || cur.at || 0) : 0; }
    readonly property bool canFollowUp: session !== "" && !!agent && agent.followUps !== false

    // Switching workspace closes it, as it does the launcher (a run carries on). Changes
    // right after opening are ignored, so "go to a workspace and ask" still works
    property real openedAt: 0
    property int openedOnWorkspace: -1
    Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() {
            const id = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1;
            if (!root.shown || id === root.openedOnWorkspace) return;
            if (Date.now() - root.openedAt > 400) root.closeWindow();
            else root.openedOnWorkspace = id;
        }
    }
    function openWindow() {
        screen = Config.focusedScreen;
        openedOnWorkspace = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1;
        openedAt = Date.now();
        shown = true;
        if (!looked && on) { looked = true; detect.running = true; }
        Qt.callLater(() => field.forceActiveFocus());
    }
    function closeWindow() { shown = false; }
    function ask(text) { openWindow(); send(text); }
    function fresh() {
        if (working) return;
        turns = []; session = ""; answeredAt = 0; field.text = "";
    }
    function send(text) {
        text = String(text || "").trim();
        if (text === "" || working || !on) return;
        if (!agent) {
            // Not looked for yet (asked by IPC before the window ever opened): sent once they're found
            if (Config.s.assistantAgent !== "" && (!looked || detect.running)) { pending = text; if (!looked) { looked = true; detect.running = true; } return; }
            begin(text);
            patch({ error: noAgent });
            field.text = "";
            return;
        }
        const heard = lastHeard();         // (before this prompt joins the history)
        begin(text);
        field.text = "";
        runId = Date.now().toString(36) + Math.floor(Math.random() * 1e6).toString(36);
        const cmd = ["python3", Quickshell.shellPath("scripts/assistant.py"), "run", "--agent", agent.id, "--run", runId];
        if (Config.s.assistantModel !== "" && agent.id !== "custom") cmd.push("--model", Config.s.assistantModel);
        if (session !== "" && Date.now() - heard > followFor) session = "";       // left a while: afresh
        if (canFollowUp) cmd.push("--session", session);
        if (agent.id === "custom") {
            cmd.push("--command", Config.s.assistantCommand);
            if (Config.s.assistantCommandBare) cmd.push("--bare");
        }
        cmd.push("--accepted", (Config.s.assistantAgentsAccepted || []).join(","));
        runner.command = cmd;
        working = true;
        runner.stdinEnabled = true;
        runner.running = true;
        runner.write(text);
        runner.stdinEnabled = false;       // (closes it: the prompt is the whole of stdin)
    }
    property string pending: ""            // typed before the agents were found: sent once they are
    readonly property var noAgent: ({ kind: "not-installed", message: Config.s.assistantAgent === "" ? "Nova doesn't have an agent to ask yet. Choose one in Settings → Assistant, and ask again." : "There's no assistant set up yet. Slate can use Claude Code or a command of your own." })
    function stop() { if (working) runner.signal(15); }
    readonly property bool stopShown: stopButton.visible && stopButton.opacity === 1    // (for the tests)
    // Try again: the same words, in place of the exchange that went wrong
    function again() {
        const t = asked;
        if (t === "" || working) return;
        turns = turns.slice(0, -1);
        send(t);
    }

    // One line from the runner: {type: start | text | blocks | done | error, …}
    function handle(e) {
        if (!e || !e.type) return;
        if (e.type === "start") { if (e.session) session = e.session; }
        else if (e.type === "text") patch({ answer: e.fresh ? String(e.delta || "") : answer + String(e.delta || "") });
        else if (e.type === "blocks") patch({ blocks: cleanBlocks(e.blocks) });
        else if (e.type === "done") {
            patch({ answer: String(e.text || answer) });
            if (e.session) session = e.session;
            const waited = working && shown && Date.now() - (cur ? cur.at : 0) >= quickAnswer;
            finished();
            if (waited && !Config.gameMode) Config.playSound("answered", "answered");
        } else if (e.type === "error") {
            if (e.kind !== "stopped") patch({ error: { kind: e.kind || "failed", message: String(e.message || ""), detail: String(e.detail || "") } });
            else if (answer === "") patch({ answer: "Stopped." });
            finished();
        }
    }
    // Nova's own sound (Settings → Sound → Nova's answer) is for an answer you were waiting
    // for, with the window showing: once, as the whole answer arrives (not for each piece of
    // it). Not for one that came straight back (you never looked away), not when the window is
    // away (the notification carries it, with its own sound), not for errors or Stop, not for
    // the history, and not in game mode. The window isn't on the lock or login screens
    readonly property int quickAnswer: 1000
    function finished() {
        if (!working) return;
        working = false;
        answeredAt = Date.now();
        patch({ doneAt: answeredAt });
        // Finished out of sight: an ordinary notification, which opens the window again
        if (!shown && !Config.testMode) {
            const line = error ? error.message.split("\n")[0].slice(0, 160) : firstLine(cur);
            if (line !== "") {
                doneNote.command = ["notify-send", "-a", "Slate", "-i", Quickshell.shellPath("assets/icon/icon-64.png"),
                                    "-h", "string:x-slate-page:assistant", "-A", "default=Open", "Nova", line];
                doneNote.running = true;
            }
        }
    }
    Process { id: doneNote; stdout: StdioCollector { onStreamFinished: if (text.trim() === "default") root.openWindow() } }
    // What Slate's server did in this run: { run, id, text, state } (state: asking, done,
    // declined, no answer, refused, failed). Anything from another run is ignored
    function did(json) {
        let d;
        try { d = JSON.parse(json); } catch (e) { return; }
        if (!d || d.run !== runId || runId === "") return;
        const list = actions.slice();
        const i = list.findIndex(a => a.id === d.id);
        const item = keptAction(d);
        if (i >= 0) list[i] = item; else list.push(item);
        patch({ actions: list.slice(-12) });
    }
    readonly property var stateWords: ({ asking: "Waiting for you", declined: "you said no", "no answer": "no answer", refused: "Slate said no", failed: "didn't work" })
    // One row of the list, as kept: { id, text, state }, and for a setting it changed (the
    // server's settings_set) its key, the value before and the value it was given, for Undo;
    // undone once it's been put back
    function keptAction(a) {
        const item = { id: a.id, text: String(a.text || ""), state: String(a.state || "") };
        if (undoKey(a.key) !== "" && a.before !== undefined && a.after !== undefined
                && typeof a.before === typeof Config.s[a.key] && typeof a.after === typeof Config.s[a.key])
            Object.assign(item, { key: a.key, before: a.before, after: a.after, undone: !!a.undone });
        return item;
    }
    // A key Undo may set: one of Slate's settings, never the assistant's own or Private Mode
    // (the server can't change those anyway). "" otherwise
    function undoKey(k) {
        k = String(k || "");
        if (!/^[A-Za-z][A-Za-z0-9]*$/.test(k) || Config.s[k] === undefined || typeof Config.s[k] === "object") return "";
        if (k.startsWith("assistant") || ["barShowAssistant", "privateMode", "privateRestore"].indexOf(k) >= 0) return "";
        return k;
    }
    function sameValue(a, b) { return typeof a === "number" ? Math.abs(a - Number(b)) < 1e-9 : a === b; }
    // Undo shows on a setting it changed, until it's put back, and only while the setting
    // still has the value Nova gave it: changed again since, by you or anyone, there's nothing to undo
    function undoable(a) {
        return !!a && a.state === "done" && !a.undone && a.key !== undefined && undoKey(a.key) !== "" && sameValue(Config.s[a.key], a.after);
    }
    // Put it back as Settings would (the same special cases as the server's settings_set and
    // `config set`), then the row says it's undone (turn: its place in the conversation)
    function undo(ti, ai) {
        const t = turns[ti];
        const a = t && t.actions ? t.actions[ai] : null;
        if (!undoable(a)) return;
        const k = a.key, v = a.before;
        if (k === "windowMode") Config.setDefaultMode(v, false);     // (workspaces in use keep the mode they have)
        else if (k === "barPosition") Config.moveBar(v);
        else if (k === "dockPosition") Config.moveDock(v);
        else {
            Config.s[k] = v;
            if (k === "themeMode" && (v === "dark" || v === "light")) Config.s.lightMode = v === "light";
        }
        const list = t.actions.slice();
        list[ai] = Object.assign({}, a, { undone: true });
        const all = turns.slice();
        all[ti] = Object.assign({}, t, { actions: list });
        turns = all;
    }

    Process {
        id: runner
        stdinEnabled: true
        stdout: SplitParser { onRead: line => { try { root.handle(JSON.parse(line)); } catch (e) {} } }
        onExited: {
            // (gone without a last word: stopped, or it broke)
            if (root.working) root.handle({ type: "error", kind: "stopped" });
        }
    }
    Process {
        id: detect
        command: ["python3", Quickshell.shellPath("scripts/assistant.py"), "detect"]
        stdout: StdioCollector { onStreamFinished: { try { root.agents = JSON.parse(text); } catch (e) {} } }
        onExited: {
            const t = root.pending;
            root.pending = "";
            if (t !== "") root.send(t);
        }
    }
    onWorkingChanged: Config.assistantWorking = working
    // Switched off (or the risks changed) while it works: stopped
    onOnChanged: if (!on) { stop(); looked = false; }

    // ---- Window --------------------------------------------------------------
    property real fade: shown ? 1 : 0
    Behavior on fade { NumberAnimation { duration: Config.ms(root.fadeMs); easing.type: Easing.OutCubic } }
    visible: shown || fade > 0
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "slate-assistant"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // Click outside to close (a run carries on)
    MouseArea { anchors.fill: parent; enabled: root.shown; onClicked: root.closeWindow() }

    Rectangle {
        id: panel
        width: root.panelWidth
        height: body.implicitHeight + 28
        Behavior on height { enabled: root.shown; NumberAnimation { duration: Config.ms(200); easing.type: Easing.OutCubic } }
        x: Math.round((parent.width - width) / 2)
        y: Math.round(Math.max(24, (parent.height - 520) / 2))
        radius: Config.corner(18)
        color: root.barColor
        opacity: root.fade
        scale: 0.98 + 0.02 * root.fade
        border.width: Config.glassShine ? 1 : 0
        border.color: Config.glassEdge
        Shadow { strength: Config.assistantShadowShare }      // raised: Slate's shadow, with glass too
        Gloss { radius: parent.radius; strength: 0.6 }     // glass: a sheen, as on Slate's panels
        transform: Translate { y: -root.dropDistance * (1 - root.fade) }
        MouseArea { anchors.fill: parent }       // swallow clicks inside

        Column {
            id: body
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: 14 }
            spacing: 12

            // ---- Header: its name, and a round close button as on Settings ----
            Item {
                width: parent.width; height: 30
                Row {
                    anchors { left: parent.left; leftMargin: 4; verticalCenter: parent.verticalCenter }
                    spacing: 8
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: String.fromCodePoint(0xF014)
                        color: Config.pageColour("assistant"); font.family: tabler.name; font.pixelSize: 17
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Nova"
                        color: root.textColor; font.family: root.fontFamily; font.pixelSize: 15; font.weight: Font.Medium
                    }
                    // Nova is an experiment still, and says so: a flask and the word, on a soft
                    // green pill (the accent with the Colourful look off). Flat, with glass too
                    Rectangle {
                        id: trial
                        readonly property color ink: Config.colourful ? Config.tint("#9ed6a6") : root.accent
                        anchors.verticalCenter: parent.verticalCenter
                        width: trialRow.implicitWidth + 18; height: 22; radius: Config.corner(11)
                        color: Qt.rgba(ink.r, ink.g, ink.b, 0.16)
                        Row {
                            id: trialRow
                            anchors.centerIn: parent
                            spacing: 5
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: String.fromCodePoint(0xEBD2)
                                color: trial.ink; font.family: tabler.name; font.pixelSize: 13
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Experiment"
                                color: trial.ink; font.family: root.fontFamily; font.pixelSize: 11; font.weight: Font.Medium
                            }
                        }
                    }
                }
                Rectangle {
                    id: closeBtn
                    anchors { right: parent.right; rightMargin: -4; verticalCenter: parent.verticalCenter }
                    width: 34; height: 34; radius: Config.corner(17)      // (Settings' close button)
                    color: closeHover.hovered ? Config.hover : "transparent"
                    Behavior on color { ColorAnimation { duration: Config.ms(100) } }
                    Text {
                        anchors.centerIn: parent
                        text: String.fromCodePoint(0xEB55)
                        color: closeHover.hovered ? root.textColor : root.dimTextColor
                        // (with the fill behind it, not ahead of it)
                        Behavior on color { ColorAnimation { duration: Config.ms(100) } }
                        font.family: tabler.name; font.pixelSize: 18
                    }
                    HoverHandler { id: closeHover }
                    ClickTap { onTapped: root.closeWindow() }
                }
            }

            // ---- Not switched on yet -------------------------------------
            Column {
                visible: !root.on
                width: parent.width
                spacing: 12
                topPadding: 6
                Text {
                    width: parent.width
                    text: Config.s.privateMode ? "Nova is off while Private Mode is on. You can turn Private Mode off in the control centre."
                        : Config.assistantRisksChanged ? "Something's changed about the assistant. Have a look in Settings → Assistant."
                        : "The assistant isn't switched on yet. You can switch it on in Settings, which says what that means first."
                    textFormat: Text.PlainText; wrapMode: Text.WordWrap
                    color: root.textColor; font.family: root.fontFamily; font.pixelSize: 14; font.weight: Font.Medium
                }
                PillButton { visible: !Config.s.privateMode; label: "Open Settings"; primary: true; onPressed: root.openSettings() }
            }

            // ---- The conversation: what you asked, what came back, what it did ----
            // (it scrolls once it's taller than its share of the screen, with Slate's slim
            // scrollbar and a shade at whichever end has more)
            Item {
                id: talkBox
                visible: root.on
                width: parent.width
                height: Math.min(talkCol.implicitHeight, Math.max(120, root.height - 320), 420)
                readonly property bool overflows: talk.contentHeight > talk.height + 1
            Flickable {
                id: talk
                anchors { fill: parent; rightMargin: talkBox.overflows ? 18 : 0 }
                contentHeight: talkCol.implicitHeight
                clip: true
                // While it scrolls, its corners are rounded like its cards and the shades at its
                // ends, so what passes them is cut round too (square, the cards showed past them)
                layer.enabled: talkBox.overflows
                layer.effect: MultiEffect { maskEnabled: true; maskSource: talkMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1 }
                boundsBehavior: Flickable.StopAtBounds
                SmoothWheel { flick: talk }
                // Follows the newest words as they arrive
                onContentHeightChanged: contentY = Math.max(0, contentHeight - height)
                onHeightChanged: contentY = Math.max(0, contentHeight - height)
                Column {
                    id: talkCol
                    width: parent.width
                    spacing: 14
                    // Nothing said yet: Nova says hello, so the window isn't a bare box. Not part
                    // of the conversation (it isn't kept, and it goes with your first words)
                    Rectangle {
                        visible: root.turns.length === 0
                        width: hello.implicitWidth + 28
                        height: hello.implicitHeight + 18
                        radius: Config.corner(14)
                        bottomLeftRadius: Config.corner(3)
                        color: root.replyColor
                        Column {
                            id: hello
                            anchors { left: parent.left; top: parent.top; leftMargin: 14; topMargin: 9 }
                            spacing: 8
                            Row {
                                spacing: 6
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: String.fromCodePoint(0xF014)
                                    color: Config.pageColour("assistant"); font.family: tabler.name; font.pixelSize: 13
                                }
                                Text {
                                    text: "Nova"
                                    color: Config.pageColour("assistant"); font.family: root.fontFamily; font.pixelSize: 12; font.weight: Font.DemiBold
                                }
                            }
                            Text {
                                text: "Hello, I'm Nova. How can I help?"
                                color: root.textColor; font.family: root.fontFamily; font.pixelSize: 14
                            }
                        }
                    }
                    Repeater {
                        model: root.turns.length
                        Column {
                            id: turn
                            required property int index
                            readonly property var t: root.turns[index] || ({ asked: "", answer: "", blocks: [], error: null, actions: [] })
                            readonly property bool latest: index === root.turns.length - 1
                            width: talkCol.width
                            spacing: turn.t.at ? 20 : 8        // (room for the time under your bubble)
                            // You, on the right, in the accent colour
                            Rectangle {
                                anchors.right: parent.right
                                width: Math.min(askedText.implicitWidth + 28, turn.width * 0.82)
                                height: askedText.implicitHeight + 16
                                radius: Config.corner(14)
                                bottomRightRadius: Config.corner(3)        // (the corner nearest your side squared off, as chat bubbles are)
                                color: root.accent
                                HoverHandler { id: youHover }
                                CopyChip {
                                    shownFor: youHover.hovered
                                    done: root.copied === turn.index + ":you"
                                    base: Qt.darker(root.accent, 1.18); ink: root.accentText
                                    hoverBase: root.accentText; hoverInk: root.accent
                                    onPressed: root.copy(turn.index + ":you", turn.t.asked)
                                }
                                // When you asked, small and dim under the bubble
                                Text {
                                    anchors { right: parent.right; rightMargin: 4; top: parent.bottom; topMargin: 3 }
                                    visible: text !== ""
                                    text: root.ago(turn.t.at)
                                    color: root.dimTextColor; font.family: root.fontFamily; font.pixelSize: 11
                                }
                                Text {
                                    id: askedText
                                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 14; rightMargin: 14 }
                                    text: turn.t.asked
                                    textFormat: Text.PlainText; wrapMode: Text.Wrap
                                    color: root.accentText; font.family: root.fontFamily; font.pixelSize: 14; font.weight: Font.Medium
                                }
                            }
                            // Nova, on the left: the answer as it arrives, or what went wrong, and
                            // under it what was done (Slate's own record)
                            Rectangle {
                                id: reply
                                readonly property bool wrong: !!turn.t.error
                                readonly property bool waiting: turn.latest && root.working && turn.t.answer === ""
                                // (drawn from its blocks, or shown as plain text)
                                readonly property bool drawn: turn.t.answer !== "" && !wrong && (turn.t.blocks || []).length > 0
                                visible: turn.t.answer !== "" || wrong || waiting || (turn.t.actions || []).length > 0
                                anchors.left: parent.left
                                width: Math.min(parent.width * 0.88, Math.max(replyCol.implicitWidth, 120) + 28)
                                height: replyCol.implicitHeight + 18
                                radius: Config.corner(14)
                                // (one shape, not a square laid over the corner: on glass the bubble
                                // is see-through, and the overlap showed as a lighter square)
                                bottomLeftRadius: Config.corner(3)
                                color: root.replyColor
                                border.width: wrong ? 1 : 0
                                border.color: Qt.rgba(root.danger.r, root.danger.g, root.danger.b, 0.55)
                                HoverHandler { id: replyHover }
                                CopyChip {
                                    visible: opacity > 0 && (turn.t.answer !== "" || reply.wrong)
                                    shownFor: replyHover.hovered
                                    done: root.copied === turn.index + ":nova"
                                    base: Config.tint("#2a313c"); ink: root.textColor
                                    onPressed: root.copy(turn.index + ":nova", reply.wrong ? turn.t.error.message : turn.t.answer)
                                }
                                Column {
                                    id: replyCol
                                    readonly property real inner: turn.width * 0.88 - 28
                                    anchors { left: parent.left; top: parent.top; leftMargin: 14; topMargin: 9 }
                                    spacing: 8
                                    Row {
                                        spacing: 6
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: String.fromCodePoint(0xF014)
                                            color: Config.pageColour("assistant"); font.family: tabler.name; font.pixelSize: 13
                                        }
                                        Text {
                                            text: "Nova"
                                            color: Config.pageColour("assistant"); font.family: root.fontFamily; font.pixelSize: 12; font.weight: Font.DemiBold
                                        }
                                        // When it answered
                                        Text {
                                            anchors.baseline: parent.children[1].baseline
                                            visible: text !== ""
                                            text: turn.t.doneAt ? "·  " + root.ago(turn.t.doneAt) : ""
                                            color: root.dimTextColor; font.family: root.fontFamily; font.pixelSize: 11
                                        }
                                    }
                                    // An answer without blocks (kept from before, or from a
                                    // runner that sent none): plain text, as typed
                                    TextEdit {
                                        visible: turn.t.answer !== "" && !reply.wrong && !reply.drawn
                                        width: Math.min(implicitWidth, replyCol.inner)
                                        text: visible ? turn.t.answer : ""
                                        textFormat: TextEdit.PlainText        // never markup: see the top of this file
                                        wrapMode: TextEdit.Wrap
                                        readOnly: true; selectByMouse: true
                                        color: root.textColor; selectionColor: root.accent; selectedTextColor: root.barColor
                                        font.family: root.fontFamily; font.pixelSize: 14
                                    }
                                    // The answer as Slate reads it: paragraphs and headings, lists
                                    // with Slate's own bullets and numbers, and code in a box
                                    Column {
                                        visible: reply.drawn
                                        spacing: 8
                                        Repeater {
                                            model: reply.drawn ? turn.t.blocks : []
                                            Column {
                                                id: block
                                                required property var modelData
                                                required property int index
                                                readonly property string kind: modelData.type
                                                AnswerWords {
                                                    visible: block.kind === "paragraph" || block.kind === "heading"
                                                    runs: visible ? block.modelData.runs : []
                                                    heading: block.kind === "heading"
                                                    maxWidth: replyCol.inner
                                                }
                                                Column {
                                                    visible: block.kind === "list"
                                                    spacing: 4
                                                    Repeater {
                                                        model: block.kind === "list" ? block.modelData.items : []
                                                        Row {
                                                            id: item
                                                            required property var modelData
                                                            leftPadding: item.modelData.level * 18
                                                            spacing: 6
                                                            Text {
                                                                id: marker
                                                                width: Math.max(implicitWidth, 10)
                                                                text: item.modelData.marker
                                                                textFormat: Text.PlainText
                                                                horizontalAlignment: Text.AlignRight
                                                                color: Config.pageColour("assistant")
                                                                font.family: root.fontFamily; font.pixelSize: 14; font.weight: Font.DemiBold
                                                            }
                                                            AnswerWords {
                                                                runs: item.modelData.runs
                                                                maxWidth: replyCol.inner - item.leftPadding - marker.width - item.spacing
                                                            }
                                                        }
                                                    }
                                                }
                                                CodeBox {
                                                    visible: block.kind === "code" || block.kind === "table"
                                                    code: visible ? block.modelData.text : ""
                                                    lang: visible ? block.modelData.lang : ""
                                                    table: block.kind === "table"
                                                    turnIndex: turn.index
                                                    blockIndex: block.index
                                                    maxWidth: replyCol.inner
                                                }
                                            }
                                        }
                                    }
                                    // Thinking: three dots taking turns, as chat apps show someone
                                    // typing. (Like a spinner, it isn't a transition, so its timing
                                    // is its own.) With animations off or in game mode nothing moves
                                    // or fades: the dots take turns to light up instead, a step at a time
                                    Row {
                                        id: typing
                                        visible: reply.waiting
                                        readonly property bool moving: visible && root.shown && Config.animate && !Config.gameMode
                                        // (without motion: which dot is lit; 3 is a beat with none)
                                        property int lit: 0
                                        Timer {
                                            interval: 380; repeat: true
                                            running: typing.visible && root.shown && !typing.moving
                                            onTriggered: typing.lit = (typing.lit + 1) % 4
                                        }
                                        spacing: 5
                                        topPadding: 5; bottomPadding: 5
                                        Repeater {
                                            model: 3
                                            Rectangle {
                                                id: dot
                                                required property int index
                                                width: 7; height: 7; radius: Config.corner(3.5)
                                                color: !typing.moving && typing.lit === index ? root.textColor : root.dimTextColor
                                                opacity: typing.moving ? 0.35 : 1
                                                transform: Translate { id: hop }
                                                SequentialAnimation {
                                                    running: typing.moving
                                                    loops: Animation.Infinite
                                                    onRunningChanged: if (!running) { hop.y = 0; dot.opacity = Qt.binding(() => typing.moving ? 0.35 : 1); }
                                                    PauseAnimation { duration: dot.index * 160 }
                                                    ParallelAnimation {
                                                        NumberAnimation { target: hop; property: "y"; to: -4; duration: 260; easing.type: Easing.OutSine }
                                                        NumberAnimation { target: dot; property: "opacity"; to: 1; duration: 260 }
                                                    }
                                                    ParallelAnimation {
                                                        NumberAnimation { target: hop; property: "y"; to: 0; duration: 260; easing.type: Easing.InSine }
                                                        NumberAnimation { target: dot; property: "opacity"; to: 0.35; duration: 260 }
                                                    }
                                                    PauseAnimation { duration: (2 - dot.index) * 160 + 420 }
                                                }
                                            }
                                        }
                                    }
                                    Text {
                                        visible: reply.wrong
                                        width: Math.min(implicitWidth, replyCol.inner)
                                        text: turn.t.error ? turn.t.error.message : ""
                                        textFormat: Text.PlainText; wrapMode: Text.WordWrap
                                        color: root.textColor; font.family: root.fontFamily; font.pixelSize: 14
                                    }
                                    Text {
                                        visible: reply.wrong && !!turn.t.error.detail
                                        width: Math.min(implicitWidth, replyCol.inner)
                                        text: turn.t.error ? (turn.t.error.detail || "") : ""
                                        textFormat: Text.PlainText; wrapMode: Text.WrapAnywhere; maximumLineCount: 3; elide: Text.ElideRight
                                        color: root.dimTextColor; font.family: root.fontFamily; font.pixelSize: 12
                                    }
                                    Column {
                                        visible: (turn.t.actions || []).length > 0
                                        spacing: 4
                                        Repeater {
                                            model: turn.t.actions || []
                                            Row {
                                                id: actionRow
                                                required property var modelData
                                                required property int index
                                                readonly property bool ok: modelData.state === "done"
                                                readonly property bool waiting: modelData.state === "asking"
                                                readonly property bool undone: ok && !!modelData.undone
                                                readonly property bool canUndo: root.undoable(modelData)
                                                spacing: 8
                                                // (the mark and the spinner are two items, so a tick or cross
                                                // never keeps the angle the spinner stopped at)
                                                Item {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: 14; height: 14
                                                    Text {
                                                        anchors.centerIn: parent
                                                        visible: !actionRow.waiting
                                                        text: String.fromCodePoint(actionRow.undone ? 0xEB77 : actionRow.ok ? 0xEA5E : 0xEB55)      // put back, tick, cross
                                                        color: actionRow.undone ? root.dimTextColor : actionRow.ok ? Config.pageColour("power") : root.danger
                                                        font.family: tabler.name; font.pixelSize: 14
                                                    }
                                                    Text {
                                                        anchors.centerIn: parent
                                                        visible: actionRow.waiting
                                                        text: String.fromCodePoint(0xF226)                               // Slate's loading spinner
                                                        color: root.accent
                                                        font.family: tabler.name; font.pixelSize: 14
                                                        // (a spinner: one of the animations that isn't a transition)
                                                        RotationAnimation on rotation { running: actionRow.waiting && root.shown && Config.animate && !Config.gameMode; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
                                                    }
                                                }
                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: Math.min(implicitWidth, replyCol.inner - 24 - (undoButton.visible ? undoButton.width + 8 : 0))
                                                    text: actionRow.modelData.text + (actionRow.undone ? " · undone" : actionRow.ok ? "" : (actionRow.waiting ? " · " : ": ") + (root.stateWords[actionRow.modelData.state] || ""))
                                                    textFormat: Text.PlainText; elide: Text.ElideRight
                                                    color: actionRow.ok ? root.dimTextColor : root.textColor
                                                    font.family: root.fontFamily; font.pixelSize: 13
                                                }
                                                // Undo, for a setting it changed: puts back the value it had before
                                                Rectangle {
                                                    id: undoButton
                                                    visible: actionRow.canUndo
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: undoLabel.implicitWidth + 16; height: 22
                                                    radius: Config.corner(6)
                                                    color: "transparent"
                                                    HoverFill { base: "transparent"; hovered: undoHover.hovered; radius: parent.radius }
                                                    Text {
                                                        id: undoLabel
                                                        anchors.centerIn: parent
                                                        text: "Undo"
                                                        color: root.textColor
                                                        font.family: root.fontFamily; font.pixelSize: 12; font.weight: Font.Medium
                                                    }
                                                    HoverHandler { id: undoHover }
                                                    ClickTap { onTapped: root.undo(turn.index, actionRow.index) }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
                ThinScrollbar {
                    flick: talk
                    color: root.textColor
                    anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
                }
                // (the conversation's shape, for its mask: rounded only at an end with more past
                // it, and rounding in as it's scrolled, with that end's shade; at the very top or
                // bottom it's square, so the cards there, angled corners and all, show whole)
                Item {
                    id: talkMask
                    anchors.fill: talk
                    visible: false
                    layer.enabled: true
                    readonly property real above: Math.max(0, Math.min(14, talk.contentY))
                    readonly property real below: Math.max(0, Math.min(14, talk.contentHeight - talk.height - talk.contentY))
                    Rectangle {
                        anchors.fill: parent
                        topLeftRadius: Config.corner(talkMask.above); topRightRadius: Config.corner(talkMask.above)
                        bottomLeftRadius: Config.corner(talkMask.below); bottomRightRadius: Config.corner(talkMask.below)
                    }
                }
                // Shades while there's more above or below: fading out just as you reach the end
                // (rounded like the cards they're over: square, they showed as hard-cornered blocks)
                Rectangle {
                    anchors { left: talk.left; right: talk.right; top: parent.top }
                    height: 28
                    topLeftRadius: Config.corner(14); topRightRadius: Config.corner(14)
                    opacity: Math.max(0, Math.min(1, talk.contentY / 24))
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: root.barColor }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                }
                Rectangle {
                    anchors { left: talk.left; right: talk.right; bottom: parent.bottom }
                    height: 28
                    bottomLeftRadius: Config.corner(14); bottomRightRadius: Config.corner(14)
                    opacity: Math.max(0, Math.min(1, (talk.contentHeight - talk.height - talk.contentY) / 24))
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 1.0; color: root.barColor }
                    }
                }
            }

            // ---- The line you type -----------------------------------------
            Rectangle {
                visible: root.on
                width: parent.width; height: 44; radius: Config.corner(10)
                color: root.fieldColor
                Text {
                    anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                    text: root.working ? "Nova is working…" : "What would you like to do?"
                    color: root.dimTextColor; font.family: root.fontFamily; font.pixelSize: 15; font.weight: Font.Medium
                    visible: field.text === ""
                }
                TextInput {
                    id: field
                    anchors { left: parent.left; right: parent.right; leftMargin: 14; rightMargin: root.working ? 50 : 14; verticalCenter: parent.verticalCenter }
                    color: root.textColor; selectionColor: root.accent; selectedTextColor: root.barColor
                    font.family: root.fontFamily; font.pixelSize: 15; font.weight: Font.Medium
                    focus: root.shown
                    clip: true
                    maximumLength: 2000
                    readOnly: root.working
                    onAccepted: root.send(text)
                    Keys.onPressed: e => {
                        if (e.key === Qt.Key_Escape) { root.closeWindow(); e.accepted = true; }
                        // Ctrl+C stops Nova while it works (with text selected, it copies as ever)
                        else if (e.key === Qt.Key_C && (e.modifiers & Qt.ControlModifier) && root.working && field.selectedText === "") { root.stop(); e.accepted = true; }
                        // Page Up / Page Down move through the conversation, as in Slate's lists
                        else if (e.key === Qt.Key_PageUp || e.key === Qt.Key_PageDown) {
                            const by = (e.key === Qt.Key_PageUp ? -1 : 1) * Math.max(40, talk.height - 40);
                            talk.contentY = Math.max(0, Math.min(Math.max(0, talk.contentHeight - talk.height), talk.contentY + by));
                            e.accepted = true;
                        }
                    }
                }
                // Stop, at the end of the box while Nova's working (Escape only hides the window,
                // and the work carries on)
                Rectangle {
                    id: stopButton
                    objectName: "assistantStop"
                    visible: opacity > 0
                    opacity: root.working ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Config.ms(120) } }
                    anchors { right: parent.right; rightMargin: 7; verticalCenter: parent.verticalCenter }
                    width: 30; height: 30; radius: Config.corner(15)
                    color: root.accent
                    Text {
                        anchors.centerIn: parent
                        text: String.fromCodePoint(0xED4A)
                        color: root.accentText
                        font.family: tabler.name; font.pixelSize: 15
                    }
                    ClickTap { enabled: root.working; onTapped: root.stop() }
                }
            }

            // ---- Footer: who's answering, and the one useful button -----------
            Item {
                visible: root.on
                width: parent.width; height: 32
                Text {
                    anchors { left: parent.left; leftMargin: 4; verticalCenter: parent.verticalCenter }
                    text: (root.agent ? root.agent.label : root.detectRunning ? "Looking for your agent…" : "No agent yet")
                        + (root.working ? "  ·  Ctrl+C to stop" : "  ·  Enter to send")
                    color: root.dimTextColor; font.family: root.fontFamily; font.pixelSize: 12; font.weight: Font.Medium
                }
                Row {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    spacing: 8
                    PillButton {
                        visible: !root.working && !!root.error && ["offline", "timeout", "failed"].indexOf(root.error.kind) >= 0
                        icon: 0xEB13; label: "Try again"; primary: true; onPressed: root.again()
                    }
                    PillButton {
                        visible: !root.working && !!root.error && root.error.kind === "signed-out"
                        icon: 0xEBEF; label: "Open a terminal"; primary: true; onPressed: root.signIn()
                    }
                    PillButton {
                        visible: !root.working && !!root.error && ["not-installed", "not-accepted", "off", "server"].indexOf(root.error.kind) >= 0
                        label: "Open Settings"; primary: true; onPressed: root.openSettings(root.error.kind === "server" ? "debug" : "assistant")
                    }
                    PillButton { visible: !root.working && !root.error; icon: 0xEB20; label: "Settings"; onPressed: root.openSettings() }
                }
            }
        }
    }
    readonly property bool detectRunning: detect.running
    function openSettings(page) { closeWindow(); Config.slateCall("settings", "page", page || "assistant"); }
    // Sign in: the agent's own command, in your terminal
    function signIn() {
        closeWindow();
        const cmd = root.agent && root.agent.signIn ? root.agent.signIn : "claude";
        Quickshell.execDetached(["hyprctl", "dispatch",
            `function() hl.exec_cmd((os.getenv("UWSM_FINALIZE_VARNAMES") and "uwsm app -- " or "") .. TERMINAL .. " -e ${cmd.replace(/[^\w.-]/g, "")}") end`]);
    }

    // A paragraph, heading or list item of an answer: its runs as Slate's own markup (rich():
    // the words escaped, so the only tags here are Slate's), selectable like plain text
    component AnswerWords: TextEdit {
        property var runs: []
        property bool heading: false
        property real maxWidth: 0
        width: Math.min(implicitWidth, maxWidth)
        text: root.rich(runs, heading)
        textFormat: TextEdit.RichText
        wrapMode: TextEdit.Wrap
        readOnly: true; selectByMouse: true
        color: root.textColor; selectionColor: root.accent; selectedTextColor: root.barColor
        font.family: root.fontFamily; font.pixelSize: 14
    }

    // Code in an answer: a box in the monospaced font, not wrapped (it scrolls sideways when
    // it's wider, with a sideways swipe or wheel), and Copy, which copies just
    // the code. A table is kept as its rows in the same box, without Copy
    component CodeBox: Rectangle {
        id: box
        property string code
        property string lang
        property bool table: false
        property int turnIndex: 0
        property int blockIndex: 0
        property real maxWidth: 0
        readonly property bool done: root.copied === turnIndex + ":code:" + blockIndex
        width: Math.min(maxWidth, Math.max(codeText.implicitWidth + 24, table ? 0 : copyBtn.width + langText.implicitWidth + 30))
        height: codeScroll.y + codeScroll.height + 10
        radius: Config.corner(8)
        color: root.codePlate
        Text {
            id: langText
            visible: !box.table
            anchors { left: parent.left; leftMargin: 12; verticalCenter: copyBtn.verticalCenter }
            text: box.lang
            textFormat: Text.PlainText
            color: root.dimTextColor; font.family: root.fontFamily; font.pixelSize: 11; font.weight: Font.Medium
        }
        Rectangle {
            id: copyBtn
            visible: !box.table
            anchors { top: parent.top; right: parent.right; topMargin: 4; rightMargin: 4 }
            width: copyRow.implicitWidth + 14; height: 22; radius: Config.corner(6)
            // (solid on the solid plate, so a hover never flashes through the accent)
            color: copyHover.hovered ? Qt.tint(root.codePlate, Config.hover) : root.codePlate
            Behavior on color { ColorAnimation { duration: Config.ms(100) } }
            Row {
                id: copyRow
                anchors.centerIn: parent
                spacing: 4
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: String.fromCodePoint(box.done ? 0xEA5E : 0xEA7A)      // tick, copy
                    color: box.done ? Config.pageColour("power") : root.dimTextColor
                    font.family: tabler.name; font.pixelSize: 13
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: box.done ? "Copied" : "Copy"
                    color: copyHover.hovered || box.done ? root.textColor : root.dimTextColor
                    font.family: root.fontFamily; font.pixelSize: 11; font.weight: Font.Medium
                }
            }
            HoverHandler { id: copyHover }
            ClickTap { onTapped: root.copyCode(box.turnIndex, box.blockIndex) }
        }
        Flickable {
            id: codeScroll
            x: 12; y: box.table ? 9 : 30
            width: box.width - 24; height: codeText.implicitHeight
            contentWidth: codeText.implicitWidth
            // (not by dragging, which selects; the wheel up and down still scrolls the conversation)
            interactive: false
            clip: true
            WheelHandler {
                target: null
                enabled: codeScroll.contentWidth > codeScroll.width
                orientation: Qt.Horizontal
                onWheel: e => codeScroll.contentX = Math.max(0, Math.min(codeScroll.contentWidth - codeScroll.width,
                                                                         codeScroll.contentX - (e.pixelDelta.x || e.angleDelta.x / 2)))
            }
            TextEdit {
                id: codeText
                text: box.code
                textFormat: TextEdit.PlainText
                wrapMode: TextEdit.NoWrap
                readOnly: true; selectByMouse: true
                color: root.textColor; selectionColor: root.accent; selectedTextColor: root.barColor
                font.family: root.codeFont; font.pixelSize: 13
            }
        }
    }

    // Copy this message: a small solid chip in the bubble's top right corner while the pointer
    // is on the bubble (solid, so on glass it doesn't lighten the see-through bubble under it)
    component CopyChip: Rectangle {
        id: chip
        property bool shownFor: false
        property bool done: false
        property color base: Config.tint("#2a313c")
        property color ink: root.textColor
        // Under the pointer: the accent, or on your own (accent-coloured) bubble its opposite
        property color hoverBase: root.accent
        property color hoverInk: root.accentText
        signal pressed()
        anchors { top: parent.top; right: parent.right; topMargin: 5; rightMargin: 5 }
        z: 2
        width: 24; height: 24; radius: Config.corner(8)
        color: chipHover.hovered ? hoverBase : base
        Behavior on color { ColorAnimation { duration: Config.ms(100) } }
        opacity: shownFor || done ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Config.ms(120) } }
        Text {
            anchors.centerIn: parent
            text: String.fromCodePoint(chip.done ? 0xEA5E : 0xEA7A)      // tick, copy
            color: chipHover.hovered ? chip.hoverInk : chip.ink
            font.family: tabler.name; font.pixelSize: 14
        }
        HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
        ClickTap { onTapped: chip.pressed() }
    }

    // A button, as in the Settings window (its Button): the same size, fill, hover, sheen, and
    // an optional icon before the label
    component PillButton: Rectangle {
        id: pill
        property string label
        property bool primary: false
        property int icon: 0
        signal pressed()
        readonly property color control: Config.raised(Config.tint("#2a313c"))
        readonly property color fg: primary ? root.accentText : root.textColor
        width: pillRow.implicitWidth + 28; height: 32; radius: Config.corner(8)
        color: primary ? root.accent : "transparent"
        HoverFill { base: control; hovered: pillHover.hovered; gone: primary; radius: parent.radius }
        Behavior on color { ColorAnimation { duration: Config.ms(100) } }
        Row {
            id: pillRow
            anchors.centerIn: parent
            spacing: 6
            Text {
                visible: pill.icon !== 0
                anchors.verticalCenter: parent.verticalCenter
                text: pill.icon ? String.fromCodePoint(pill.icon) : ""
                color: pill.fg
                font.family: tabler.name; font.pixelSize: 15
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: pill.label
                color: pill.fg
                font.family: root.fontFamily; font.pixelSize: 12; font.weight: Font.Medium
            }
        }
        HoverHandler { id: pillHover }
        ClickTap { onTapped: pill.pressed() }
    }
}
