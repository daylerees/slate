import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import ".."

// A few good pointer or icon themes, put in with a button each (scripts/theme-packs.py:
// downloaded from their makers' releases, checked, into ~/.local/share/icons; no password).
// kind: "cursors" or "icons"; installed(): when one's in, so the list above it can look again
Group {
    id: packs
    property string kind
    property string chooseIn                // where to pick it once it's in ("Pointer style")
    signal installed()
    property var all: []
    property string busy: ""                // the one being put in
    readonly property var mine: all.filter(p => p.kind === kind)
    readonly property string script: Quickshell.shellPath("scripts/theme-packs.py")
    function look() { packList.running = false; packList.running = true; }
    Process {
        id: packList
        running: true
        command: [packs.script, "--list"]
        stdout: StdioCollector { onStreamFinished: { try { packs.all = JSON.parse(text); } catch (e) {} } }
    }
    Process {
        id: packRun
        property var pack: null
        stderr: StdioCollector { id: packErr }
        onExited: code => {
            const p = pack;
            packs.busy = "";
            packs.look();
            if (!p) return;
            const icon = "--icon=" + Quickshell.shellPath("assets/icon/icon-64.png");
            if (code === 0) {
                packs.installed();
                Quickshell.execDetached(["notify-send", "--app-name=Slate", icon, "--", p.name + " is ready",
                    "Choose it in " + packs.chooseIn + " whenever you like."]);
            } else {
                const why = packErr.text.replace(/^theme-packs: /, "").trim();
                Quickshell.execDetached(["notify-send", "--app-name=Slate", icon, "--", "Slate couldn't add " + p.name,
                    (why !== "" && why.indexOf("fingerprint") >= 0 ? why.charAt(0).toUpperCase() + why.slice(1) + "."
                        : "Check you're connected to the internet, then try again.")]);
            }
        }
    }
    Repeater {
        model: packs.mine
        delegate: Column {
            required property var modelData
            required property int index
            width: parent ? parent.width : 0
            Separator { visible: index > 0 }
            SettingRow {
                label: modelData.name
                detail: modelData.about
                Button {
                    readonly property bool here: modelData.installed
                    enabled: !here && packs.busy === ""
                    opacity: enabled || packs.busy === modelData.id ? 1 : 0.4
                    icon: here ? 0xEA5E : packs.busy === modelData.id ? 0 : 0xEA96
                    label: here ? "Installed" : packs.busy === modelData.id ? "Installing…" : "Install"
                    onClicked: {
                        packs.busy = modelData.id;
                        packRun.pack = modelData;
                        packRun.command = [packs.script, "--install", modelData.id];
                        packRun.running = true;
                    }
                }
            }
        }
    }
}
