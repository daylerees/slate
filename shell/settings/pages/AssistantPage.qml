import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Qt.labs.folderlistmodel
import "../.."
import ".."

// ---- Assistant (docs/ASSISTANT.md): AI agents using Slate's MCP server (slate mcp) -----
Column {
    readonly property var win: SettingsHost.win
    id: assistantPane
    spacing: 4
    PageTitle { text: "Assistant" }
    readonly property string server: Config.slateCommand.replace(Quickshell.env("HOME"), "~") + " mcp"
    // What the tools are, from the server's own table, so these lists can't go stale
    property var tools: []
    Process {
        running: true
        command: ["python3", Quickshell.shellPath("scripts/slate-mcp.py"), "--tools"]
        stdout: StdioCollector { onStreamFinished: { try { assistantPane.tools = JSON.parse(text); } catch (e) {} } }
    }
    function titles(tier) { return tools.filter(t => t.tier === tier).map(t => t.title).join(" · "); }
    function toolTitle(name) { const t = tools.find(x => x.name === name); return t ? t.title : name; }
    // What assistants did (the server's activity log), newest first
    readonly property string logPath: Config.stateHome + "/slate/assistant/activity.jsonl"
    property bool showAll: false
    FileView { id: activityFile; path: assistantPane.logPath; watchChanges: true; printErrors: false; onFileChanged: reload() }
    readonly property var activity: {
        const out = [];
        const lines = (activityFile.text() || "").split("\n");
        for (let i = lines.length - 1; i >= 0 && out.length < 50; i--) {
            if (!lines[i]) continue;
            try { out.push(JSON.parse(lines[i])); } catch (e) {}
        }
        return out;
    }
    readonly property var outcomes: ({ done: "Done", declined: "You said no", "no answer": "No answer", refused: "Slate said no", failed: "Didn't work" })
    function when(iso) {
        const d = new Date(iso);
        return isNaN(d) ? "" : Config.dateText(d, "day") + ", " + Config.timeText(d);
    }
    // The agents there are (scripts/assistant.py detect), and the one a prompt would go to
    property var agents: []
    onAgentsChanged: win.assistantAgentsSeen = agents.map(a => ({ id: a.id, label: a.label, installed: a.installed, running: !!a.running,
                                                               models: (a.models || []).map(m => m.name) }))
    Process {
        id: detectProc
        running: true
        command: ["python3", Quickshell.shellPath("scripts/assistant.py"), "detect"]
        stdout: StdioCollector { onStreamFinished: { try { assistantPane.agents = JSON.parse(text); } catch (e) {} } }
    }
    // The one chosen ("" none, which is how it starts: Nova asks for one to be chosen), and,
    // for an agent Slate knows, what's known about it
    readonly property string inUse: Config.s.assistantAgent
    readonly property var chosen: inUse === "" || inUse === "custom" ? null : (agents.find(a => a.id === inUse) || null)
    function signIn(cmd) {
        // (the agent's own words, from scripts/slate_agents.py: letters, dots, dashes and spaces)
        // In your terminal, as Nova's Sign in does (Config.runInTerminal: the flag your terminal
        // wants, which isn't always -e)
        Config.runInTerminal(String(cmd).replace(/[^\w. -]/g, ""));
    }
    // ---- Set up Ollama (scripts/ollama-setup.py): its package and service, with an
    // administrator's password (slate-system --ollama), then a model that can use Slate's tools,
    // chosen for this computer. Asked first, with the download's size. The setting up runs on
    // its own (closing Settings doesn't stop a download), saying how it's going in a file
    property var ollamaPlan: null           // ollama-setup.py plan, looked at once Ollama's chosen
    readonly property bool ollamaChosen: !!chosen && chosen.local
    onOllamaChosenChanged: if (ollamaChosen) lookAtOllama()
    function lookAtOllama() { if (!planProc.running) planProc.running = true; }
    function gb(bytes) { return (bytes / 1e9).toFixed(1) + " GB"; }
    Process {
        id: planProc
        command: ["python3", Quickshell.shellPath("scripts/ollama-setup.py"), "plan"]
        stdout: StdioCollector { onStreamFinished: { try { assistantPane.ollamaPlan = JSON.parse(text); } catch (e) {} } }
    }
    // {step: installing|starting|downloading|done|failed, model, got, size, problem}
    property var ollamaSetup: ({})
    FileView {
        path: Config.stateHome + "/slate/ollama-setup.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { assistantPane.ollamaSetup = JSON.parse(text()); assistantPane.nowS = Date.now() / 1000; } catch (e) {} }
    }
    // A step still going, unless it's gone quiet for long (cut short by a restart): the password
    // prompt can wait a while, the others write every moment
    property real nowS: Date.now() / 1000
    Timer { interval: 30000; repeat: true; running: assistantPane.ollamaStepWritten !== ""; onTriggered: assistantPane.nowS = Date.now() / 1000 }
    readonly property string ollamaStepWritten: ["installing", "starting", "downloading"].indexOf(ollamaSetup.step) >= 0 ? ollamaSetup.step : ""
    readonly property string ollamaStep: ollamaStepWritten !== "" && (!ollamaSetup.at || nowS - ollamaSetup.at < (ollamaStepWritten === "installing" ? 900 : 300))
        ? ollamaStepWritten : ""
    readonly property string ollamaProblem: ollamaSetup.step === "failed" ? (ollamaSetup.problem || "") : ""
    // (finished: what's there now, and the model it chose)
    onOllamaStepChanged: if (ollamaStep === "" && ollamaChosen) { lookAtOllama(); detectProc.running = false; detectProc.running = true; }
    // (for the tests: the agent's row, and Set up)
    readonly property var testState: ({ agent: agentRow.visible ? agentRow.detail : "", setUp: setUpButton.visible,
                                        plan: ollamaPlan, step: ollamaStep, problem: ollamaProblem })
    function askOllamaSetup() {
        const p = ollamaPlan;
        if (!p) return;
        const install = !p.running;
        win.askQuestion({
            title: "Set up Ollama?",
            body: (install ? "Slate installs Ollama from your system's packages (" + p.package + ") and turns it on, which asks for an administrator's password. Then it downloads "
                           : "Slate downloads ")
                + p.model + " (about " + gb(p.modelSize) + "), a model that suits this computer and can use Slate's tools. "
                + "It runs on this computer, and nothing you ask Nova leaves it. You can remove it at any time with ollama rm " + p.model + ".",
            button: "Set up", code: 0xEA96,
            run: () => {
                assistantPane.ollamaSetup = { step: install ? "installing" : "downloading", model: p.model, got: 0, size: 0, problem: "" };
                Quickshell.execDetached(["setsid", "-f", "python3", Quickshell.shellPath("scripts/ollama-setup.py"), "setup",
                                         install ? p.package : "-", p.model]);
            }
        });
    }

    // What Slate adds to a prompt (scripts/assistant.py briefing), read when asked for
    property bool showAdds: false
    property string adds: ""
    Process {
        id: addsProc
        command: ["python3", Quickshell.shellPath("scripts/assistant.py"), "briefing"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const b = JSON.parse(text);
                    assistantPane.adds = b.briefing + "\n\n" + (b.context || "(Right now: a few lines on the time and the focused window, added while the assistant is switched on.)");
                } catch (e) {}
            }
        }
    }
    property string copied: ""
    Timer { id: copiedReset; interval: 1600; onTriggered: assistantPane.copied = "" }
    function copy(what, text) { Quickshell.execDetached(["wl-copy", "--", text]); copied = what; copiedReset.restart(); }

    IntroText {
        text: "Ask an AI agent you already use, like Claude Code or Codex, or a model on this computer through Ollama, to change a setting, move a window or tell you what's where. "
            + "It works through Slate's own tools, and Slate asks you before anything that can't be undone. "
            + "Nova is Slate's own way to ask: press Super+K, type what you want, and your agent does it."
    }
    GroupLabel { text: "Assistant" }
    Group {
        SettingRow {
            label: "Let assistants use Slate"
            settingKey: "assistantEnabled"
            detail: Config.s.privateMode && Config.s.assistantEnabled
                ? "Off while Private Mode is on, and back when you turn Private Mode off in the control center."
                : Config.assistantRisksChanged
                ? "Something's changed about the assistant, so it's paused. Switch it on again to read what's new."
                : "What Slate tells an assistant about your desktop (your settings, your open windows and their titles) is sent to the service behind the agent you use, "
                + "under your own account with them. With Ollama, it stays on this computer. Slate itself sends nothing anywhere. Slate does its best to keep an assistant within these limits, "
                + "but it can't promise what one will do, so using it is your choice and your responsibility."
            // (Private Mode keeps it off: Sound's Private Mode row turns that off)
            needsMet: !Config.s.privateMode
            needs: "Needs Private Mode to be off"
            needsPage: "sound"; needsLabel: "Private Mode is on"
            SettingToggle { checked: Config.assistantOn; onToggled: v => win.assistantSwitch(v) }
            below: [Button { visible: Config.assistantOn; label: "Read the risks again"; onClicked: win.assistantReadRisks() }]
        }
    }
    GroupLabel { text: "Agent" }
    Group {
        // Which agent answers Nova: none to start with. What the chosen one needs shows beneath
        DropdownSetting {
            label: "Agent"
            settingKey: "assistantAgent"
            detail: assistantPane.inUse === "" ? "Nova needs an agent to ask. Choose the one you use, and what it needs shows here"
                : assistantPane.inUse === "custom" ? "Slate runs your command as you typed it, with what you ask on its input. What it can see and do beyond Slate's tools is up to the command"
                : assistantPane.chosen ? (assistantPane.chosen.confined ? "" : "Keeps its own tools: ") + assistantPane.chosen.note
                : "Slate couldn't find this one. It may have been removed"
            value: assistantPane.inUse
            options: [{ value: "", label: "None" }]
                .concat(assistantPane.agents.filter(a => a.id !== "custom").map(a => ({ value: a.id, label: a.label })))
                .concat([{ value: "custom", label: "A command of your own" }])
            onPicked: v => {
                const a = assistantPane.agents.find(x => x.id === v);
                if (v === "") Config.s.assistantAgent = "";
                else if (v === "custom") win.assistantChoose("custom", "your own command", false);
                else if (a) win.assistantChoose(a.id, a.label, a.confined);
            }
        }
        // An agent Slate knows: whether it's ready, and its model
        Separator { visible: !!assistantPane.chosen }
        SettingRow {
            id: agentRow
            visible: !!assistantPane.chosen
            readonly property var a: assistantPane.chosen
            readonly property bool ready: !!a && a.installed && a.signedIn
            // (a model on this computer: Ollama running, with a model, rather than signed in)
            readonly property bool idle: !!a && a.local && a.installed && !a.running
            // Ollama, and Slate can set it up here: the distro has a package, or it's running
            // and only needs a model
            readonly property var plan: assistantPane.ollamaPlan
            readonly property bool canSetUp: !!a && a.local && !ready && !!plan && (plan.package !== "" || plan.running)
            readonly property string step: assistantPane.ollamaStep
            readonly property string stepModel: assistantPane.ollamaSetup.model || (plan ? plan.model : "")
            label: a ? a.label : ""
            detail: !a ? ""
                : step === "installing" ? "Installing Ollama… Your password lets it in"
                : step === "starting" ? "Turning Ollama on…"
                : step === "downloading" ? "Downloading " + stepModel
                    + (assistantPane.ollamaSetup.size > 0 ? ": " + assistantPane.gb(assistantPane.ollamaSetup.got) + " of " + assistantPane.gb(assistantPane.ollamaSetup.size) : "…")
                    + ". You can close Settings: it carries on"
                : ready ? "Ready"
                : assistantPane.ollamaProblem !== "" && a.local ? assistantPane.ollamaProblem
                : canSetUp ? (plan.running ? "No models yet. Set up downloads " + plan.model + " (about " + assistantPane.gb(plan.modelSize) + "), which suits this computer"
                                           : "Not set up yet. Set up installs Ollama from your system's packages, then downloads " + plan.model
                                             + " (about " + assistantPane.gb(plan.modelSize) + "), which suits this computer")
                : a.local && plan && plan.package === "" && !a.installed ? "Your system doesn't have a package for Ollama. Its own site shows how to install it"
                : !a.installed ? "Not installed yet"
                : idle ? "Ollama isn't running. Start it (ollama serve in a terminal, or its service), then check again"
                : a.local ? "No models yet. Open a terminal and run " + a.signIn + " to get one, then check again"
                : "Not signed in. Open a terminal and run " + a.signIn + " once"
            below: [
                Meter {
                    id: ollamaMeter
                    visible: agentRow.step === "downloading" && assistantPane.ollamaSetup.size > 0
                    width: Math.min(320, agentRow.width - 32)
                    value: assistantPane.ollamaSetup.size > 0 ? Math.min(1, assistantPane.ollamaSetup.got / assistantPane.ollamaSetup.size) : 0
                    colour: win.accent
                    trackColour: win.control
                    minFill: 0
                    slideMs: 200
                }
            ]
            Row {
                spacing: 8
                // (while it's being set up: turning, as Bluetooth's search does)
                Spinner {
                    visible: agentRow.step !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    colour: win.accent
                }
                Button {
                    id: setUpButton
                    visible: agentRow.canSetUp && agentRow.step === ""
                    primary: true
                    icon: 0xEA96
                    label: assistantPane.ollamaProblem !== "" ? "Try again" : "Set up"
                    onClicked: assistantPane.askOllamaSetup()
                }
                Button {
                    visible: !!agentRow.a && !agentRow.ready && !agentRow.idle && !agentRow.canSetUp && agentRow.step === ""
                    primary: true
                    label: agentRow.a && !agentRow.a.installed ? "Get it" : agentRow.a && agentRow.a.local ? "Get a model" : "Sign in"
                    onClicked: {
                        if (!agentRow.a.installed) Qt.openUrlExternally(agentRow.a.local && agentRow.plan && agentRow.plan.link ? agentRow.plan.link : agentRow.a.url);
                        else assistantPane.signIn(agentRow.a.signIn);
                    }
                }
                Button {
                    visible: !!agentRow.a && !agentRow.ready && agentRow.step === ""
                    label: "Check again"
                    onClicked: { detectProc.running = false; detectProc.running = true; if (assistantPane.ollamaChosen) assistantPane.lookAtOllama(); }
                }
            }
        }
        // A model on this computer (Ollama): one of those it has
        Separator { visible: !!assistantPane.chosen && assistantPane.chosen.local }
        DropdownSetting {
            visible: !!assistantPane.chosen && assistantPane.chosen.local
            label: "Model"
            settingKey: "assistantLocalModel"
            detail: "Small models can be unreliable with tools: a bigger one follows Slate's tools better, but answers more slowly. "
                + "Slow on a laptop? Ollama leaves built-in graphics unused unless its service has OLLAMA_VULKAN=1 and OLLAMA_IGPU_ENABLE=1"
            value: Config.s.assistantLocalModel
            noneLabel: Config.s.assistantLocalModel
            options: [{ value: "", label: "The first that can use tools" }]
                .concat(((assistantPane.chosen && assistantPane.chosen.models) || [])
                    .map(m => ({ value: m.name, label: m.tools ? m.name : m.name + " (can't use tools)" })))
            onPicked: v => Config.s.assistantLocalModel = v
        }
        Separator { visible: !!assistantPane.chosen && !assistantPane.chosen.local }
        SettingRow {
            visible: !!assistantPane.chosen && !assistantPane.chosen.local
            label: "Model"
            settingKey: "assistantModel"
            detail: "For agents that let you pick one. Empty: the agent's own choice"
            TextField {
                id: modelInput
                width: 160
                text: Config.s.assistantModel
                onFinished: Config.s.assistantModel = text.trim().replace(/[^\w.:\-\[\]]/g, "")
            }
        }
        // A command of your own: the command, and whether Slate adds anything to what you type
        Separator { visible: assistantPane.inUse === "custom" }
        SettingRow {
            visible: assistantPane.inUse === "custom"
            label: "Command"
            settingKey: "assistantCommand"
            detail: Config.s.assistantCommand === "" ? "Nothing to run yet. Type the command Nova should hand what you ask to" : "Run as you typed it"
            TextField {
                id: commandInput
                width: 260
                text: Config.s.assistantCommand
                onFinished: Config.s.assistantCommand = text.trim()
            }
        }
        Separator { visible: assistantPane.inUse === "custom" }
        ToggleSetting {
            visible: assistantPane.inUse === "custom"
            label: "Just what you type"
            key: "assistantCommandBare"
            detail: "Your command gets your words alone, without what Slate adds: for a command that sets its own scene"
        }
    }
    GroupLabel { text: "What it can do" }
    Group {
        SettingRow {
            label: "Without asking"
            detail: "Looking: " + assistantPane.titles("look")
        }
        Separator {}
        SettingRow {
            label: "Changes"
            detail: "These can be undone: " + assistantPane.titles("change")
        }
        Separator {}
        ToggleSetting {
            label: "Ask before changing anything"
            key: "assistantAskChanges"
            detail: "Slate asks you about every change, not only the ones that can't be undone"
        }
        Separator {}
        SettingRow {
            label: "Always asks first"
            detail: "These can't be undone, so Slate asks every time: " + assistantPane.titles("ask")
        }
    }
    GroupLabel { text: "What it can see" }
    Group {
        ToggleSetting {
            label: "Window titles"
            key: "assistantSeeTitles"
            detail: "Titles carry document names and web page titles. Off: assistants get app names only"
        }
        Separator {}
        ToggleSetting {
            label: "Notifications"
            key: "assistantSeeNotifications"
            detail: "Assistants can read your recent notifications"
        }
    }
    Footnote { text: "Slate's tools never show an assistant your screen, your files or your clipboard. An agent with tools of its own can do more than Slate's tools allow, and Slate can't limit those." }
    GroupLabel { text: "Nova" }
    Group {
        SettingRow {
            label: "Ask Nova"
            detail: "Super+K, or your keyboard's Copilot or assistant key if it has one. You can change them in Shortcuts"
            Button { label: "Shortcuts"; onClicked: win.goTo("shortcuts", "") }
        }
        Separator {}
        ToggleSetting {
            label: "Keep chat history"
            key: "assistantKeepChat"
            detail: "What you asked Nova and what it answered are still in its window after Slate restarts: the last 100 messages, kept on this computer only. Off: it's forgotten when Slate restarts, and what was kept is deleted"
        }
        Separator {}
        SettingRow {
            label: "Clear chat history"
            detail: "Empties Nova's window, and what's kept of it. Nothing Nova did is undone"
            Button { label: "Clear"; destructive: true; onClicked: Config.slateCall("assistant", "clear") }
        }
    }
    // Talking to Nova: hold Super+K or the microphone, turned into text on this computer
    // (whisper.cpp, optional, and its model, downloaded when you ask: VoiceModel.qml)
    GroupLabel { text: "Voice" }
    Group {
        SettingRow {
            label: "Talk to Nova"
            settingKey: "assistantVoice"
            Component.onCompleted: if (win.voice) win.voice.check()     // (whisper.cpp installed since?)
            detail: win.voice && win.voice.looked && win.voice.whisper === ""
                ? "Slate needs whisper.cpp to understand you, and it isn't installed yet. Install it from your system's packages "
                  + "(whisper-cpp on Arch, Fedora and NixOS; whisper.cpp on Debian and Ubuntu), then turn this on"
                : "Hold Super+K, or the microphone in Nova's window, and say what you want. Let go, and it's written down and sent. "
                  + "Slate only listens while you hold it, and turns what you say into text on this computer"
            needsMet: Config.assistantOn
            needs: "Needs Let assistants use Slate to be on"
            needsPage: "assistant"; needsLabel: "Let assistants use Slate"
            SettingToggle { checked: Config.s.assistantVoice; onToggled: v => win.voiceSwitch(v) }
        }
        Separator {}
        SettingRow {
            id: modelRow
            readonly property var vm: win.voice
            label: "Speech model"
            detail: !vm ? ""
                : vm.downloading ? "Downloading… " + Math.round(vm.progress * 100) + "% of " + vm.sizeText
                : vm.error !== "" ? vm.error
                : vm.model ? "Downloaded (" + vm.sizeText + "), in ~/.local/share/slate/whisper. Slate uses it to turn what you say into text"
                : vm.sizeText + ", downloaded once from Hugging Face. Slate needs it to turn what you say into text, and asks before downloading it"
            Button {
                visible: !!modelRow.vm
                label: !modelRow.vm ? "" : modelRow.vm.downloading ? "Cancel" : modelRow.vm.model ? "Delete" : "Download"
                destructive: !!modelRow.vm && modelRow.vm.model && !modelRow.vm.downloading
                onClicked: {
                    const vm = win.voice;
                    if (vm.downloading) vm.cancel();
                    else if (vm.model) vm.remove();
                    else win.voiceDownload(null);
                }
            }
        }
        Separator {}
        SettingRow {
            label: "Hold to talk"
            detail: "Hold Super+K for a moment and talk; a quick press still opens Nova. Nova's window shows when it's listening"
            Button { label: "Shortcuts"; onClicked: win.goTo("shortcuts", "") }
        }
    }
    Footnote { text: "Slate only listens while you hold the key or the microphone, never in Private Mode or while the screen is locked. What you say is turned into text on this computer, and the recording is deleted straight after." }
    GroupLabel { text: "Activity" }
    Group {
        SettingRow {
            label: assistantPane.activity.length === 0 ? "Nothing here yet" : "What assistants did"
            detail: assistantPane.activity.length === 0 ? "What assistants do with Slate's tools will show up here"
                : "The latest " + assistantPane.activity.length + (assistantPane.activity.length === 1 ? " thing" : " things") + ", newest first. This list holds what was done, never what you typed"
            Button {
                visible: assistantPane.activity.length > 0
                label: "Clear"; destructive: true
                onClicked: Quickshell.execDetached(["sh", "-c", ': > "$0"', assistantPane.logPath])
            }
        }
        Repeater {
            model: assistantPane.showAll ? assistantPane.activity : assistantPane.activity.slice(0, 8)
            Column {
                id: activityRow
                required property var modelData
                width: parent ? parent.width : 0
                Separator {}
                SettingRow {
                    label: assistantPane.toolTitle(activityRow.modelData.tool)
                        + (activityRow.modelData.args && activityRow.modelData.args.key ? ": " + activityRow.modelData.args.key : "")
                    detail: [assistantPane.when(activityRow.modelData.time), activityRow.modelData.who,
                             activityRow.modelData.before !== undefined ? "was " + activityRow.modelData.before : ""].filter(x => x).join(" · ")
                    Text {
                        text: assistantPane.outcomes[activityRow.modelData.outcome] || ""
                        textFormat: Text.PlainText
                        color: activityRow.modelData.outcome === "done" ? win.dim : win.text
                        font.family: win.font; font.pixelSize: Config.text(13)
                    }
                }
            }
        }
        Separator { visible: assistantPane.activity.length > 8 }
        SettingRow {
            visible: assistantPane.activity.length > 8
            label: assistantPane.showAll ? "Showing all " + assistantPane.activity.length : "Showing the latest 8"
            Button { label: assistantPane.showAll ? "Show fewer" : "Show more"; onClicked: assistantPane.showAll = !assistantPane.showAll }
        }
    }
    GroupLabel { text: "What Slate adds" }
    Group {
        SettingRow {
            label: "See what Slate adds"
            detail: "Alongside what you type, Slate tells the agent who it is here and a few lines about the moment. Nothing else is sent with your words"
            Button {
                label: assistantPane.showAdds ? "Hide" : "Show"
                onClicked: { assistantPane.showAdds = !assistantPane.showAdds; if (assistantPane.showAdds) { addsProc.running = false; addsProc.running = true; } }
            }
        }
        Text {
            visible: assistantPane.showAdds
            x: 16; width: parent.width - 32
            bottomPadding: 12
            text: assistantPane.adds
            textFormat: Text.PlainText; wrapMode: Text.Wrap
            color: win.dim; font.family: win.font; font.pixelSize: Config.text(12)
        }
    }
    GroupLabel { text: "Use Slate from other apps" }
    Group {
        SettingRow {
            label: "Claude Code"
            detail: "claude mcp add slate -- " + assistantPane.server
            Button { label: assistantPane.copied === "claude" ? "Copied" : "Copy"; onClicked: assistantPane.copy("claude", "claude mcp add slate -- " + assistantPane.server) }
        }
        Separator {}
        SettingRow {
            label: "Codex"
            detail: "codex mcp add slate -- " + assistantPane.server
            Button { label: assistantPane.copied === "codex" ? "Copied" : "Copy"; onClicked: assistantPane.copy("codex", "codex mcp add slate -- " + assistantPane.server) }
        }
        Separator {}
        SettingRow {
            label: "Other agents"
            detail: "Most take an “mcpServers” block in their settings, naming Slate's MCP server"
            Button {
                label: assistantPane.copied === "json" ? "Copied" : "Copy"
                onClicked: assistantPane.copy("json", JSON.stringify({ mcpServers: { slate: { command: Config.slateCommand, args: ["mcp"] } } }, null, 2))
            }
        }
    }
    Footnote { text: "Run the line for your agent in a terminal once. Slate's tools stay off for every agent until the switch at the top is on." }
    // (only with glass on: Appearance → Glass)
    GroupLabel { visible: Config.s.glass; text: "Glass" }
    Group {
        visible: Config.s.glass
        ToggleSetting {
            label: "Blur"
            detail: "What's behind Nova's window is blurred, like frosted glass. Off, you see straight through it"
            key: "assistantBlur"
        }
        Separator {}
        SettingRow {
            label: "Opacity"
            settingKey: "assistantOpacity"
            detail: "How solid its background is: 100% can't be seen through, lower is clearer"
            ValueSlider { per: 100; from: 0; to: 100; stepSize: 1; suffix: "%"; value: Math.round(Config.assistantGlassOpacity * 100); onMoved: v => Config.s.assistantOpacity = v / 100 }
        }
    }
}
