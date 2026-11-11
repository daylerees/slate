// Chalk, Slate's assistant: a small prompt window, like the launcher. Type what you want
// ("turn on glass", "put Firefox on workspace 2") and it's handed to the agent you chose
// (Settings → Assistant), which acts through Slate's own tools (docs/ASSISTANT.md).
//   slate ipc call assistant toggle      (or open / close / stop; Super+K)
//   slate ipc call assistant ask <text>  open and send
// scripts/assistant.py runs the agent and says what comes back, a JSON line at a time. The
// answer is shown as plain text, never markup (rich text would load a picture a misled
// agent linked to). "What it did" is Slate's own record, sent by Slate's MCP server as each
// tool is used (did(), from AssistantGate's IPC): words Slate wrote, not the agent's.
// It reads as a chat: what you asked on the right in the accent colour, Chalk's answers on
// the left in its own, in order, kept until New
// (Ctrl+N) or Slate restarts; what you type next carries the same conversation on. Closing the
// window lets a run carry on (a notification says when it's done); Stop ends it. Not loaded
// on the lock or login screens, and a run stops when the screen locks.

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: root

    // ---- Look: the launcher's ------------------------------------------------
    readonly property real panelWidth: Math.max(300, Math.min(560, width - 32))
    readonly property int fadeMs: 200
    readonly property real dropDistance: 18
    readonly property color barColor: Config.surface(Config.tint("#0f1216"))
    readonly property color fieldColor: Config.raised(Config.tint("#1d222a"))
    // Chalk's side of the conversation: a touch of its own colour over the field's
    readonly property color replyColor: Qt.tint(fieldColor, Qt.rgba(Config.pageColour("assistant").r, Config.pageColour("assistant").g, Config.pageColour("assistant").b, 0.10))
    readonly property color textColor: Config.tint("#eef1f5")
    readonly property color dimTextColor: Config.tint("#8b94a3")
    readonly property color accent: Config.accent
    readonly property color accentText: Config.tint("#12151a")
    readonly property color danger: Config.tint("#f28b8b")
    readonly property string fontFamily: Config.s.fontFamily
    FontLoader { id: tabler; source: "file://" + Quickshell.shellPath("fonts/tabler.ttf") }

    // ---- State ---------------------------------------------------------------
    property bool shown: false
    property bool working: false
    // The conversation, oldest first: [{ asked, answer, error, actions }] (error: { kind,
    // message, detail } when it went wrong; actions: what it did, [{ id, text, state }]).
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
                const clean = t => ({ asked: String(t.asked || ""), answer: String(t.answer || ""),
                                      error: t.error && t.error.message ? { kind: String(t.error.kind || "failed"), message: String(t.error.message), detail: String(t.error.detail || "") } : null,
                                      actions: (t.actions || []).map(a => ({ id: a.id, text: String(a.text || ""), state: String(a.state || "") })) });
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
    function begin(text) { turns = turns.concat([{ asked: text, answer: "", error: null, actions: [] }]).slice(-maxTurns); }
    function patch(change) {
        if (turns.length === 0) return;
        const t = turns.slice();
        t[t.length - 1] = Object.assign({}, t[t.length - 1], change);
        turns = t;
    }
    property string session: ""            // the agent's conversation, for a follow-up
    property string runId: ""
    property real answeredAt: 0
    property bool copied: false
    readonly property bool on: Config.assistantOn
    // The agents there are (scripts/assistant.py detect), looked for when the window first opens
    property var agents: []
    property bool looked: false
    readonly property var agent: {
        const want = Config.s.assistantAgent;
        if (want === "custom") return { id: "custom", label: "Your command", installed: Config.s.assistantCommand !== "", signedIn: true, confined: false, followUps: false };
        const usable = a => a.installed && a.signedIn && a.id !== "custom";
        return agents.find(a => a.id === want) || agents.find(usable) || null;
    }
    readonly property bool canFollowUp: session !== "" && !!agent && agent.followUps !== false

    function openWindow() {
        screen = Config.focusedScreen;
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
            if (!looked || detect.running) { pending = text; if (!looked) { looked = true; detect.running = true; } return; }
            begin(text);
            patch({ error: noAgent });
            field.text = "";
            return;
        }
        begin(text);
        copied = false;
        field.text = "";
        runId = Date.now().toString(36) + Math.floor(Math.random() * 1e6).toString(36);
        const cmd = ["python3", Quickshell.shellPath("scripts/assistant.py"), "run", "--agent", agent.id, "--run", runId];
        if (Config.s.assistantModel !== "" && agent.id !== "custom") cmd.push("--model", Config.s.assistantModel);
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
    readonly property var noAgent: ({ kind: "not-installed", message: "There's no assistant set up yet. Slate can use Claude Code or a command of your own." })
    function stop() { if (working) runner.signal(15); }
    // Try again: the same words, in place of the exchange that went wrong
    function again() {
        const t = asked;
        if (t === "" || working) return;
        turns = turns.slice(0, -1);
        send(t);
    }

    // One line from the runner: {type: start | text | done | error, …}
    function handle(e) {
        if (!e || !e.type) return;
        if (e.type === "start") { if (e.session) session = e.session; }
        else if (e.type === "text") patch({ answer: e.fresh ? String(e.delta || "") : answer + String(e.delta || "") });
        else if (e.type === "done") {
            patch({ answer: String(e.text || answer) });
            if (e.session) session = e.session;
            finished();
        } else if (e.type === "error") {
            if (e.kind !== "stopped") patch({ error: { kind: e.kind || "failed", message: String(e.message || ""), detail: String(e.detail || "") } });
            else if (answer === "") patch({ answer: "Stopped." });
            finished();
        }
    }
    function finished() {
        if (!working) return;
        working = false;
        answeredAt = Date.now();
        // Finished out of sight: an ordinary notification, which opens the window again
        if (!shown && !Config.testMode) {
            const line = (error ? error.message : answer).split("\n")[0].slice(0, 160);
            if (line !== "") {
                doneNote.command = ["notify-send", "-a", "Slate", "-i", Quickshell.shellPath("assets/icon/icon-64.png"),
                                    "-h", "string:x-slate-page:assistant", "-A", "default=Open", "Chalk", line];
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
        const item = { id: d.id, text: String(d.text || ""), state: String(d.state || "") };
        if (i >= 0) list[i] = item; else list.push(item);
        patch({ actions: list.slice(-12) });
    }
    readonly property var stateWords: ({ asking: "Waiting for you", declined: "you said no", "no answer": "no answer", refused: "Slate said no", failed: "didn't work" })

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
        x: Math.round((parent.width - width) / 2)
        y: Math.round(Math.max(24, (parent.height - 520) / 2))
        radius: 18
        color: root.barColor
        opacity: root.fade
        scale: 0.98 + 0.02 * root.fade
        border.width: Config.glassShine ? 1 : 0
        border.color: Config.glassEdge
        layer.enabled: !Config.glass
        layer.effect: MultiEffect {
            shadowEnabled: !Config.glass
            shadowColor: "#000000"; shadowOpacity: 0.45; shadowBlur: 1.0; shadowVerticalOffset: 8; blurMax: 48
        }
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
                        text: String.fromCodePoint(0xF6D7)
                        color: Config.pageColour("assistant"); font.family: tabler.name; font.pixelSize: 17
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Chalk"
                        color: root.textColor; font.family: root.fontFamily; font.pixelSize: 15; font.weight: Font.DemiBold
                    }
                }
                Rectangle {
                    id: closeBtn
                    anchors { right: parent.right; rightMargin: -4; verticalCenter: parent.verticalCenter }
                    width: 32; height: 32; radius: 16
                    color: closeHover.hovered ? Config.hover : "transparent"
                    Behavior on color { ColorAnimation { duration: Config.ms(100) } }
                    Gloss { radius: parent.radius; opacity: closeHover.hovered ? 1 : 0 }
                    Text {
                        anchors.centerIn: parent
                        text: String.fromCodePoint(0xEB55)
                        color: closeHover.hovered ? root.textColor : root.dimTextColor
                        font.family: tabler.name; font.pixelSize: 17
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
                    text: Config.assistantRisksChanged ? "Something's changed about the assistant. Have a look in Settings → Assistant."
                        : "The assistant isn't switched on yet. You can switch it on in Settings, which says what that means first."
                    textFormat: Text.PlainText; wrapMode: Text.WordWrap
                    color: root.textColor; font.family: root.fontFamily; font.pixelSize: 14; font.weight: Font.Medium
                }
                PillButton { label: "Open Settings"; primary: true; onPressed: root.openSettings() }
            }

            // ---- The conversation: what you asked, what came back, what it did ----
            // (it scrolls once it's taller than its share of the screen, with Slate's slim
            // scrollbar and a shade at whichever end has more)
            Item {
                id: talkBox
                visible: root.on && root.turns.length > 0
                width: parent.width
                height: Math.min(talkCol.implicitHeight, Math.max(120, root.height - 320), 420)
                readonly property bool overflows: talk.contentHeight > talk.height + 1
            Flickable {
                id: talk
                anchors { fill: parent; rightMargin: talkBox.overflows ? 18 : 0 }
                contentHeight: talkCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                SmoothWheel { flick: talk }
                // Follows the newest words as they arrive
                onContentHeightChanged: contentY = Math.max(0, contentHeight - height)
                onHeightChanged: contentY = Math.max(0, contentHeight - height)
                Column {
                    id: talkCol
                    width: parent.width
                    spacing: 14
                    Repeater {
                        model: root.turns.length
                        Column {
                            id: turn
                            required property int index
                            readonly property var t: root.turns[index] || ({ asked: "", answer: "", error: null, actions: [] })
                            readonly property bool latest: index === root.turns.length - 1
                            width: talkCol.width
                            spacing: 8
                            // You, on the right, in the accent colour
                            Rectangle {
                                anchors.right: parent.right
                                width: Math.min(askedText.implicitWidth + 28, parent.width * 0.82)
                                height: askedText.implicitHeight + 16
                                radius: 14
                                color: root.accent
                                // (the corner nearest your side squared off, as chat bubbles are)
                                Rectangle { anchors { right: parent.right; bottom: parent.bottom } width: 14; height: 14; radius: 3; color: parent.color }
                                Text {
                                    id: askedText
                                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 14; rightMargin: 14 }
                                    text: turn.t.asked
                                    textFormat: Text.PlainText; wrapMode: Text.Wrap
                                    color: root.accentText; font.family: root.fontFamily; font.pixelSize: 14; font.weight: Font.Medium
                                }
                            }
                            // Chalk, on the left: the answer as it arrives, or what went wrong, and
                            // under it what was done (Slate's own record)
                            Rectangle {
                                id: reply
                                readonly property bool wrong: !!turn.t.error
                                readonly property bool waiting: turn.latest && root.working && turn.t.answer === ""
                                visible: turn.t.answer !== "" || wrong || waiting || (turn.t.actions || []).length > 0
                                anchors.left: parent.left
                                width: Math.min(parent.width * 0.88, Math.max(replyCol.implicitWidth, 120) + 28)
                                height: replyCol.implicitHeight + 18
                                radius: 14
                                color: root.replyColor
                                border.width: wrong ? 1 : 0
                                border.color: Qt.rgba(root.danger.r, root.danger.g, root.danger.b, 0.55)
                                Rectangle { anchors { left: parent.left; bottom: parent.bottom } width: 14; height: 14; radius: 3; color: parent.color; visible: !reply.wrong }
                                Column {
                                    id: replyCol
                                    readonly property real inner: turn.width * 0.88 - 28
                                    anchors { left: parent.left; top: parent.top; leftMargin: 14; topMargin: 9 }
                                    spacing: 8
                                    Row {
                                        spacing: 6
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: String.fromCodePoint(0xF6D7)
                                            color: Config.pageColour("assistant"); font.family: tabler.name; font.pixelSize: 13
                                        }
                                        Text {
                                            text: "Chalk"
                                            color: Config.pageColour("assistant"); font.family: root.fontFamily; font.pixelSize: 12; font.weight: Font.DemiBold
                                        }
                                    }
                                    TextEdit {
                                        visible: turn.t.answer !== "" && !reply.wrong
                                        width: Math.min(implicitWidth, replyCol.inner)
                                        text: turn.t.answer
                                        textFormat: TextEdit.PlainText        // never markup: see the top of this file
                                        wrapMode: TextEdit.Wrap
                                        readOnly: true; selectByMouse: true
                                        color: root.textColor; selectionColor: root.accent; selectedTextColor: root.barColor
                                        font.family: root.fontFamily; font.pixelSize: 14
                                    }
                                    Text {
                                        visible: reply.waiting
                                        text: "Working on it…"
                                        color: root.dimTextColor; font.family: root.fontFamily; font.pixelSize: 14
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
                                                readonly property bool ok: modelData.state === "done"
                                                readonly property bool waiting: modelData.state === "asking"
                                                spacing: 8
                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: String.fromCodePoint(actionRow.ok ? 0xEA5E : actionRow.waiting ? 0xEB13 : 0xEB55)     // tick, turning arrows, cross
                                                    color: actionRow.ok ? Config.pageColour("power") : actionRow.waiting ? root.accent : root.danger
                                                    font.family: tabler.name; font.pixelSize: 14
                                                    // (a spinner: one of the animations that isn't a transition)
                                                    RotationAnimation on rotation { running: actionRow.waiting && root.shown && Config.animate; from: 0; to: 360; duration: 1400; loops: Animation.Infinite }
                                                }
                                                Text {
                                                    width: Math.min(implicitWidth, replyCol.inner - 24)
                                                    text: actionRow.modelData.text + (actionRow.ok ? "" : (actionRow.waiting ? " · " : ": ") + (root.stateWords[actionRow.modelData.state] || ""))
                                                    textFormat: Text.PlainText; elide: Text.ElideRight
                                                    color: actionRow.ok ? root.dimTextColor : root.textColor
                                                    font.family: root.fontFamily; font.pixelSize: 13
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
                // Shades while there's more above or below: fading out just as you reach the end
                Rectangle {
                    anchors { left: talk.left; right: talk.right; top: parent.top }
                    height: 28
                    opacity: Math.max(0, Math.min(1, talk.contentY / 24))
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: root.barColor }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                }
                Rectangle {
                    anchors { left: talk.left; right: talk.right; bottom: parent.bottom }
                    height: 28
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
                width: parent.width; height: 44; radius: 10
                color: root.fieldColor
                Text {
                    id: mark
                    anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                    text: String.fromCodePoint(0xF6D7)
                    color: Config.pageColour("assistant"); font.family: tabler.name; font.pixelSize: 18
                }
                Text {
                    anchors { left: mark.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
                    text: root.working ? "Chalk is working…" : root.turns.length > 0 ? "Ask a follow-up" : "What would you like to do?"
                    color: root.dimTextColor; font.family: root.fontFamily; font.pixelSize: 15; font.weight: Font.Medium
                    visible: field.text === ""
                }
                TextInput {
                    id: field
                    anchors { left: mark.right; right: parent.right; leftMargin: 10; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    color: root.textColor; selectionColor: root.accent; selectedTextColor: root.barColor
                    font.family: root.fontFamily; font.pixelSize: 15; font.weight: Font.Medium
                    focus: root.shown
                    clip: true
                    maximumLength: 2000
                    readOnly: root.working
                    onAccepted: root.send(text)
                    Keys.onPressed: e => {
                        if (e.key === Qt.Key_Escape) { root.closeWindow(); e.accepted = true; }
                        else if (e.key === Qt.Key_N && (e.modifiers & Qt.ControlModifier)) { root.fresh(); e.accepted = true; }
                    }
                }
            }

            // ---- Footer: who's answering, and the one useful button -----------
            Item {
                visible: root.on
                width: parent.width; height: 28
                Text {
                    anchors { left: parent.left; leftMargin: 4; verticalCenter: parent.verticalCenter }
                    text: root.agent ? root.agent.label : root.detectRunning ? "Looking for your agent…" : "No agent yet"
                    color: root.dimTextColor; font.family: root.fontFamily; font.pixelSize: 12
                }
                Row {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    spacing: 8
                    PillButton { visible: root.working; label: "Stop"; onPressed: root.stop() }
                    PillButton {
                        visible: !root.working && !!root.error && ["offline", "timeout", "failed"].indexOf(root.error.kind) >= 0
                        label: "Try again"; primary: true; onPressed: root.again()
                    }
                    PillButton {
                        visible: !root.working && !!root.error && root.error.kind === "signed-out"
                        label: "Open a terminal"; primary: true; onPressed: root.signIn()
                    }
                    PillButton {
                        visible: !root.working && !!root.error && ["not-installed", "not-accepted", "off", "server"].indexOf(root.error.kind) >= 0
                        label: "Open Settings"; primary: true; onPressed: root.openSettings(root.error.kind === "server" ? "debug" : "assistant")
                    }
                    PillButton {
                        visible: !root.working && !root.error && root.answer !== ""
                        label: root.copied ? "Copied" : "Copy"
                        onPressed: { Quickshell.execDetached(["wl-copy", root.answer]); root.copied = true; }
                    }
                    PillButton { visible: !root.working && (root.asked !== ""); label: "New"; onPressed: { root.fresh(); field.forceActiveFocus(); } }
                    PillButton { visible: !root.working && root.asked === ""; label: "Settings"; onPressed: root.openSettings() }
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

    // A small button, as on the confirmation window
    component PillButton: Rectangle {
        id: pill
        property string label
        property bool primary: false
        signal pressed()
        width: pillText.implicitWidth + 24; height: 28; radius: 9
        color: primary ? (pillHover.hovered ? Qt.lighter(root.accent, 1.1) : root.accent)
            : pillHover.hovered ? Config.tint("#262c35") : root.fieldColor
        Behavior on color { ColorAnimation { duration: Config.ms(100) } }
        Gloss { radius: parent.radius }
        HoverHandler { id: pillHover }
        Text {
            id: pillText
            anchors.centerIn: parent
            text: pill.label
            color: pill.primary ? root.accentText : root.textColor
            font.family: root.fontFamily; font.pixelSize: 12; font.weight: Font.Medium
        }
        ClickTap { onTapped: pill.pressed() }
    }
}
