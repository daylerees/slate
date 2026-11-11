// Slate's side of the gate every assistant goes through (docs/ASSISTANT.md). Slate's MCP
// server (scripts/slate-mcp.py, `slate mcp`) asks here before each tool: whether assistants
// are allowed at all and what they may see, and, for anything that needs a yes, to put the
// question to you in Slate's own confirmation window (PowerConfirm). The server decides
// what needs asking and writes the question's words (fixed sentences, never the model's);
// this shows it and holds the answer until the server reads it.
//   slate ipc call assistant status
// Nothing here is loaded on the lock or login screens, and status says when the screen is
// locked so the server refuses.

import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root
    required property var powerConfirm
    required property var lockScreen

    // Questions asked and not yet read back: id → "yes" or "no" ("" while it's showing or
    // waiting its turn)
    property var answers: ({})
    function settle(id, answer) {
        if (answers[id] === undefined) return;        // withdrawn meanwhile
        const a = Object.assign({}, answers);
        a[id] = answer;
        answers = a;
    }
    function forget(id) {
        if (answers[id] === undefined) return;
        const a = Object.assign({}, answers);
        delete a[id];
        answers = a;
    }

    // What a yes does when it has to happen here rather than in the server: leaving the
    // session goes through Config.sessionAction (so goodbye plays first), sleep locks first
    function leave(how) {
        if (how === "suspend")
            Quickshell.execDetached(["sh", "-c", "\"$0\" ipc call lock lock; sleep 0.6; \"$1\" suspend",
                                     Config.slateCommand, Quickshell.shellPath("bin/slate-init")]);
        else if (["logout", "reboot", "shutdown"].indexOf(how) >= 0) Config.sessionAction(how);
    }

    IpcHandler {
        target: "assistant"
        function status(): string {
            return JSON.stringify({
                enabled: Config.assistantOn,
                risksChanged: Config.assistantRisksChanged,
                locked: root.lockScreen.locked,
                gameMode: Config.gameMode,
                askChanges: Config.s.assistantAskChanges,
                seeTitles: Config.s.assistantSeeTitles,
                seeNotifications: Config.s.assistantSeeNotifications
            });
        }
        // Ask: spec is JSON { title, body, button, danger?, leave? } (leave: logout, reboot,
        // shutdown or suspend, done here on a yes). The answer is read with answer(id)
        function confirm(id: string, spec: string): void {
            let q;
            try { q = JSON.parse(spec); } catch (e) { return; }
            if (!id || !q || root.answers[id] !== undefined || root.lockScreen.locked) return;
            const a = Object.assign({}, root.answers);
            a[id] = "";
            root.answers = a;
            root.powerConfirm.confirmWith({
                id: id, title: String(q.title || ""), body: String(q.body || ""), button: String(q.button || "Allow"),
                code: 0xEAC5, danger: !!q.danger
            }, () => { root.settle(id, "yes"); if (q.leave) root.leave(String(q.leave)); },
               () => root.settle(id, "no"));
        }
        // "" until it's answered, then "yes" or "no" (once: reading it forgets it)
        function answer(id: string): string {
            const a = root.answers[id] || "";
            if (a !== "") root.forget(id);
            return a;
        }
        // The server has stopped waiting: take the question away
        function withdraw(id: string): void {
            root.forget(id);
            root.powerConfirm.withdraw(id);
        }
    }
}
