import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import "../.."
import ".."

// ---- App rules: where and how an app's windows open (Config.appRulesLua makes them
// Hyprland's window rules, matched on the app's window class) ----------------------------
Column {
    readonly property var win: SettingsHost.win
    id: rulesPane
    spacing: 4
    PageTitle { text: "App Rules" }
    IntroText {
        text: "Choose where an app's windows open and how: on a workspace of their own, floating, maximized or full screen. "
            + "A rule takes effect the next time the app opens a window, and you can change or remove it at any time."
    }
    readonly property var rules: Config.s.appRules || []
    function update(i, change) {
        const list = rules.slice();
        list[i] = Object.assign({}, list[i], change);
        Config.s.appRules = list;
    }
    // What a rule does, in a few words ("Workspace 3 · Floating"), or that it does nothing yet
    function summary(r) {
        const parts = [];
        if (r.workspace > 0) parts.push(Config.workspaceLabel(r.workspace));
        if (r.as) parts.push(({ float: "Floating", tile: "Tiled", maximize: "Maximized", fullscreen: "Full screen" })[r.as] || "");
        if (r.monitor) parts.push(r.monitor);
        return parts.filter(p => p).join(" · ");
    }
    // Apps to choose from: those with a window open first (their class is known for certain),
    // then every installed app by its window class (StartupWMClass, else its id)
    readonly property var choices: {
        DesktopEntries.applications.values;
        const seen = new Set(rules.map(r => r.cls)), out = [];
        for (const t of ToplevelManager.toplevels.values) {
            const cls = Config.appIdOf(t);
            if (!cls || seen.has(cls) || Config.isNova(t) || Config.isDropdown(t) || cls === "slate-settings") continue;
            seen.add(cls);
            const e = Config.appEntry(cls);
            out.push({ value: cls, label: (e ? e.name : cls) + " · open now", name: e ? e.name : cls, detail: "", entry: e ? e.id : "", app: e ? e.id : cls });
        }
        const installed = DesktopEntries.applications.values.filter(e => !e.noDisplay).slice().sort((a, b) => a.name.localeCompare(b.name));
        for (const e of installed) {
            const cls = Config.ruleClassOf(e);
            if (!cls || seen.has(cls)) continue;
            seen.add(cls);
            out.push({ value: cls, label: e.name, name: e.name, detail: e.genericName || e.comment || "", entry: e.id, app: e.id });
        }
        return out;
    }
    readonly property var workspaceOptions: [{ value: 0, label: "Any workspace" }]
        .concat([1, 2, 3, 4, 5, 6, 7, 8, 9, 10].map(n => ({ value: n, label: Config.workspaceLabel(n) })))
    readonly property var screenNames: Quickshell.screens.map(s => s.name)

    Repeater {
        model: rulesPane.rules
        delegate: Column {
            id: ruleBlock
            required property var modelData
            required property int index
            width: parent ? parent.width : 0
            spacing: 4
            // (its own entry, or the name it was added with: guessed from the class, a GNOME app's
            // could come back as another GNOME app)
            readonly property var entry: modelData.entry ? DesktopEntries.byId(modelData.entry) : null
            readonly property string name: entry ? entry.name : (modelData.name || modelData.cls)
            GroupLabel { text: ruleBlock.name }
            Group {
                DropdownSetting {
                    label: "Opens on"
                    detail: ruleBlock.modelData.workspace > 0
                        ? "Its windows open on " + Config.workspaceLabel(ruleBlock.modelData.workspace) + ", and Slate takes you there"
                        : "Wherever you are, as usual"
                    options: rulesPane.workspaceOptions
                    value: ruleBlock.modelData.workspace || 0
                    onPicked: v => rulesPane.update(ruleBlock.index, { workspace: v })
                }
                Separator {}
                DropdownSetting {
                    label: "Opens as"
                    detail: ({ float: "A floating window, in the middle of the screen",
                               tile: "Tiled beside the others, even where windows float",
                               maximize: "Filling the screen up to the bar",
                               fullscreen: "Full screen, over the bar and the dock" })[ruleBlock.modelData.as || ""]
                        ?? "However the workspace arranges windows"
                    options: [{ value: "", label: "As usual" }, { value: "float", label: "Floating" }, { value: "tile", label: "Tiled" },
                              { value: "maximize", label: "Maximized" }, { value: "fullscreen", label: "Full screen" }]
                    value: ruleBlock.modelData.as || ""
                    onPicked: v => rulesPane.update(ruleBlock.index, { as: v })
                }
                Separator { visible: monitorRow.visible }
                DropdownSetting {
                    id: monitorRow
                    // (only with more than one screen, or a screen chosen before that's gone now)
                    visible: rulesPane.screenNames.length > 1 || !!ruleBlock.modelData.monitor
                    label: "Monitor"
                    detail: ruleBlock.modelData.monitor ? "Its windows open on " + ruleBlock.modelData.monitor : "Whichever one you're on"
                    options: [{ value: "", label: "Any monitor" }].concat(rulesPane.screenNames.map(n => ({ value: n, label: n })))
                    value: ruleBlock.modelData.monitor || ""
                    onPicked: v => rulesPane.update(ruleBlock.index, { monitor: v })
                }
                Separator {}
                ListItemRow {
                    label: "Remove this rule"
                    detail: ruleBlock.name + " opens its windows as it likes again"
                    // Asks first, in Slate's confirmation window (by its class, not its place:
                    // the list may have changed by the time it's answered)
                    onRemoved: {
                        const cls = ruleBlock.modelData.cls, name = ruleBlock.name;
                        win.ask = {
                            title: "Remove the rule for " + name + "?",
                            body: name + "'s windows will open wherever and however they like again. The app itself isn't touched, "
                                + "and you can add the rule back here at any time.",
                            button: "Remove", destructive: true,
                            run: () => Config.s.appRules = (Config.s.appRules || []).filter(r => r.cls !== cls)
                        };
                    }
                }
            }
        }
    }

    GroupLabel { text: "Add a rule" }
    Group {
        SettingRow {
            visible: rulesPane.rules.length === 0
            label: "No rules yet"
            detail: "Pick an app below, then choose where and how its windows open"
        }
        Separator { visible: rulesPane.rules.length === 0 }
        DropdownSetting {
            label: "Choose an app"
            detail: "Type to find it. Apps with a window open are at the top"
            searchable: true
            noneLabel: "Choose"
            value: ""
            options: rulesPane.choices
            onPicked: v => {
                const c = rulesPane.choices.find(o => o.value === v);
                Config.s.appRules = rulesPane.rules.concat([{ cls: v, entry: c ? c.entry : "", name: c ? c.name : v,
                                                             workspace: 0, as: "", monitor: "" }]);
            }
        }
    }
    Footnote { text: "Rules match an app by its window class. Your own window rules in ~/.config/slate/hypr/ still apply too." }
}
