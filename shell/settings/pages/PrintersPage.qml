import QtQuick
import Quickshell
import Quickshell.Io
import "../.."
import ".."

// ---- Printers: CUPS's printers and SANE's scanners (scripts/printers.py) -------
Column {
    readonly property var win: SettingsHost.win
    id: printersPane
    spacing: 4
    readonly property string script: Quickshell.shellPath("scripts/printers.py")
    // From printers.py list: { service: "on"|"off"|"missing", printers: [...], configTool }
    property var state: ({ service: "", printers: [], configTool: "" })
    property string listText: ""           // what printers.py list last said, as it said it
    // The same as last time, as it nearly always is: nothing to do
    function take(text) {
        win.rowMade("printerLooks");
        if (text === listText) return;
        try { state = JSON.parse(text); listText = text; } catch (e) {}
    }
    property var found: []                 // printers that could be added (printers.py find)
    property bool searched: false          // Find printers has run at least once
    property var scan: ({ sane: true, scanners: [], app: null })
    property bool scanLooked: false
    property string note: ""               // how the last action went
    readonly property bool printingOn: state.service === "on"

    function refresh() { listProc.running = false; listProc.running = true; }
    function lookForScanners() { scanProc.running = false; scanProc.running = true; }
    // Run one of printers.py's actions, then show how it went and look again
    function act(args, doing) {
        note = doing;
        actProc.command = [script].concat(args);
        actProc.running = true;
    }
    FirstLook {
        id: listProc
        running: true
        command: [printersPane.script, "list"]
        stdout: StdioCollector { onStreamFinished: printersPane.take(win.pretendPolls.printers ?? text) }
    }
    // Printers change by themselves (a job finishes, one goes offline): look again now and
    // then while the page shows (it's let go when Settings closes)
    Timer { interval: 5000; repeat: true; running: !actProc.running; onTriggered: printersPane.refresh() }
    Process {
        id: findProc
        command: [printersPane.script, "find"]
        stdout: StdioCollector { onStreamFinished: { try { printersPane.found = JSON.parse(text); } catch (e) { printersPane.found = []; } printersPane.searched = true; } }
    }
    FirstLook {
        id: scanProc
        running: true
        command: [printersPane.script, "scanners"]
        stdout: StdioCollector { onStreamFinished: { try { printersPane.scan = JSON.parse(text); } catch (e) {} printersPane.scanLooked = true; } }
    }
    Process {
        id: actProc
        stdout: StdioCollector {
            onStreamFinished: {
                const line = text.trim();
                printersPane.note = line === "ok" ? "" : line.startsWith("error ")
                    ? (line === "error canceled" ? "" : "Slate couldn't do that: " + line.slice(6)) : line;
                printersPane.refresh();
                // A printer added: it's no longer one to add
                if (findProc.command && printersPane.searched) { findProc.running = false; findProc.running = true; }
            }
        }
    }
    // A glyph for a printer, by how it's connected
    function printerIcon(p) { return (p.uri || "").startsWith("usb:") ? 0xF00C : 0xEB0E; }
    function statusText(p) {
        const s = p.status === "printing" ? "Printing" : p.status === "stopped" ? "Stopped" : "Ready";
        const jobs = p.jobs > 0 ? " · " + p.jobs + (p.jobs === 1 ? " job waiting" : " jobs waiting") : "";
        return (p.default ? "Default · " : "") + s + jobs + (p.accepting ? "" : " · not taking jobs");
    }

    PageTitle { text: "Printers" }
    IntroText { text: "The printers and scanners this computer can use. Most printers from the last ten years work straight away, over the network or USB, with no driver to install." }

    GroupLabel { visible: printersPane.state.service === "missing" || printersPane.state.service === "off"; text: "Printing service" }
    // The printing service: not installed, or not running
    Group {
        visible: printersPane.state.service === "missing" || printersPane.state.service === "off"
        SettingRow {
            label: printersPane.state.service === "missing" ? "Printing isn't installed" : "Printing is off"
            detail: printersPane.state.service === "missing"
                ? "Install CUPS (the cups package) to print"
                : (printersPane.state.hint || "") !== ""
                    ? "The printing service (CUPS) isn't running. To switch it on, in a terminal:  " + printersPane.state.hint
                : "The printing service (CUPS) isn't running. Turning it on asks for your password"
            Button {
                // (without systemd Slate shows the command instead: scripts/printers.py)
                visible: printersPane.state.service === "off" && (printersPane.state.hint || "") === ""
                label: "Turn on"; primary: true
                onClicked: printersPane.act(["service-on"], "Turning printing on…")
            }
        }
    }
    Text {
        visible: printersPane.note !== ""
        width: parent.width; leftPadding: 4; bottomPadding: 4
        textFormat: Text.PlainText        // never markup: it can quote what the printing service said
        text: printersPane.note
        color: printersPane.note.startsWith("Slate couldn't do that") ? win.danger : win.dim
        font.family: win.font; font.pixelSize: Config.text(12); wrapMode: Text.Wrap
    }

    GroupLabel { visible: printersPane.printingOn; text: "Printers" }
    Group {
        visible: printersPane.printingOn
        Text {
            visible: printersPane.state.printers.length === 0
            x: 16; height: 48; verticalAlignment: Text.AlignVCenter
            text: "No printers just yet. Let's find one below"
            color: win.dim; font.family: win.font; font.pixelSize: Config.text(13)
        }
        Repeater {
            // A row for each printer, by its name, kept while the printer is: what it
            // shows is looked up as it changes (and kept as it goes, for the moment the
            // row outlives its printer)
            model: ScriptModel { values: printersPane.state.printers.map(p => p.name) }
            delegate: Item {
                id: printerRow
                required property var modelData      // its printer's name
                required property int index
                readonly property var now: printersPane.state.printers.find(p => p.name === modelData)
                property var kept: ({})
                onNowChanged: if (now) kept = now
                Component.onCompleted: { if (now) kept = now; win.rowMade("printers"); }
                readonly property var printer: now ?? kept
                width: parent.width
                height: 60
                Separator { visible: printerRow.index > 0 }
                Rectangle {
                    id: printerIcon
                    anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                    width: 34; height: 34; radius: Config.corner(9)
                    color: printerRow.printer.default ? win.accent : win.outline
                    Text {
                        anchors.centerIn: parent
                        text: Config.glyph(printersPane.printerIcon(printerRow.printer))
                        color: printerRow.printer.default ? win.accentText : win.text
                        font.family: win.bar.iconFont; font.pixelSize: 17
                    }
                }
                Column {
                    anchors { left: printerIcon.right; leftMargin: 12; right: printerButtons.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    spacing: 2
                    Text { width: parent.width; textFormat: Text.PlainText; text: printerRow.printer.info || printerRow.printer.name; color: win.text; font.family: win.font; font.pixelSize: Config.text(13); font.weight: Font.Medium; elide: Text.ElideRight }
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        textFormat: Text.PlainText        // never markup
                        text: printersPane.statusText(printerRow.printer)
                        color: printerRow.printer.status === "stopped" ? win.danger : printerRow.printer.default ? win.accent : win.dim
                        font.family: win.font; font.pixelSize: Config.text(12)
                    }
                }
                Row {
                    id: printerButtons
                    anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    spacing: 8
                    Button {
                        visible: printerRow.printer.jobs > 0
                        label: "Cancel jobs"
                        onClicked: printersPane.act(["cancel", printerRow.printer.name], "Canceling…")
                    }
                    Button {
                        visible: !printerRow.printer.default
                        label: "Make default"
                        onClicked: printersPane.act(["default", printerRow.printer.name], "")
                    }
                    Button {
                        label: "Test page"
                        onClicked: printersPane.act(["test", printerRow.printer.name], "Sending a test page…")
                    }
                    Button {
                        label: "Remove"
                        destructive: true
                        onClicked: win.ask = {
                            title: "Remove " + (printerRow.printer.info || printerRow.printer.name) + "?",
                            body: "It'll be taken off this computer's printers, along with any jobs still waiting. You can always add it again later. This asks for your password.",
                            button: "Remove", destructive: true,
                            run: () => printersPane.act(["remove", printerRow.printer.name], "Removing…")
                        }
                    }
                }
            }
        }
    }

    GroupLabel { visible: printersPane.printingOn; text: "Add a printer" }
    Group {
        visible: printersPane.printingOn
        SettingRow {
            label: "Find printers"
            detail: findProc.running ? "Looking on your network and USB…"
                : printersPane.searched && printersPane.found.length === 0 ? "None found that aren't added already. Check it's switched on and on the same network"
                : "Printers on your network or plugged in by USB that print with no driver"
            Row {
                spacing: 10
                Spinner {
                    visible: findProc.running
                    anchors.verticalCenter: parent.verticalCenter
                    colour: win.accent
                }
                Button {
                    icon: 0xEB1C
                    label: printersPane.searched ? "Search again" : "Search"
                    primary: !printersPane.searched
                    opacity: findProc.running ? 0.5 : 1
                    onClicked: if (!findProc.running) findProc.running = true
                }
            }
        }
        Repeater {
            model: printersPane.found
            delegate: Item {
                id: foundRow
                required property var modelData
                width: parent.width
                height: 56
                Separator {}
                Text {
                    id: foundIcon
                    anchors { left: parent.left; leftMargin: 22; verticalCenter: parent.verticalCenter }
                    text: Config.glyph(foundRow.modelData.via === "USB" ? 0xF00C : 0xEB0E)
                    color: win.dim; font.family: win.bar.iconFont; font.pixelSize: 17
                }
                Column {
                    anchors { left: foundIcon.right; leftMargin: 16; right: addButton.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    spacing: 2
                    Text { width: parent.width; textFormat: Text.PlainText; text: foundRow.modelData.name; color: win.text; font.family: win.font; font.pixelSize: Config.text(13); font.weight: Font.Medium; elide: Text.ElideRight }
                    Text { text: foundRow.modelData.via === "USB" ? "Plugged in by USB" : "On your network"; color: win.dim; font.family: win.font; font.pixelSize: Config.text(12) }
                }
                Button {
                    id: addButton
                    anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    label: "Add"; primary: true
                    onClicked: printersPane.act(["add", foundRow.modelData.uri, foundRow.modelData.name], "Adding " + foundRow.modelData.name + "… (this asks for your password)")
                }
            }
        }
        Separator {}
        SettingRow {
            label: "Other printers"
            detail: "For one that needs a driver of its own, or more settings: " + (printersPane.state.configTool ? "the printer settings app" : "CUPS's settings page, in your browser")
            Button {
                icon: 0xEA99
                label: "Open"
                onClicked: Quickshell.execDetached(printersPane.state.configTool
                    ? [printersPane.state.configTool] : ["xdg-open", "http://localhost:631/admin"])
            }
        }
    }

    GroupLabel { text: "Scanners" }
    Group {
        SettingRow {
            visible: !printersPane.scan.sane
            label: "Scanning isn't installed"
            detail: "To scan, you'll need SANE installed (sane-utils or sane-backends, with sane-airscan for network scanners)"
        }
        Text {
            visible: printersPane.scan.sane && printersPane.scan.scanners.length === 0
            x: 16; height: 48; verticalAlignment: Text.AlignVCenter
            text: scanProc.running ? "Looking for scanners…" : "No scanners found"
            color: win.dim; font.family: win.font; font.pixelSize: Config.text(13)
        }
        Repeater {
            model: printersPane.scan.sane ? printersPane.scan.scanners : []
            delegate: Item {
                id: scannerRow
                required property var modelData
                required property int index
                width: parent.width
                height: 56
                Separator { visible: scannerRow.index > 0 }
                Text {
                    id: scannerIcon
                    anchors { left: parent.left; leftMargin: 22; verticalCenter: parent.verticalCenter }
                    text: Config.glyph(0xEBC8)
                    color: win.dim; font.family: win.bar.iconFont; font.pixelSize: 17
                }
                Text {
                    anchors { left: scannerIcon.right; leftMargin: 16; right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                    textFormat: Text.PlainText        // never markup: the scanner's own name
                    text: scannerRow.modelData.name
                    color: win.text; font.family: win.font; font.pixelSize: Config.text(13); font.weight: Font.Medium; elide: Text.ElideRight
                }
            }
        }
        Separator { visible: printersPane.scan.sane }
        SettingRow {
            visible: printersPane.scan.sane
            label: "Scan a document"
            detail: printersPane.scan.app ? "Opens " + printersPane.scan.app.name
                : "Install a scanning app, like Document Scanner (simple-scan)"
            Row {
                spacing: 8
                Button {
                    icon: 0xEB13
                    label: "Look again"
                    opacity: scanProc.running ? 0.5 : 1
                    onClicked: if (!scanProc.running) printersPane.lookForScanners()
                }
                Button {
                    visible: !!printersPane.scan.app
                    icon: 0xEBC8
                    label: "Scan"; primary: true
                    onClicked: Quickshell.execDetached([printersPane.scan.app.command])
                }
            }
        }
    }
}
