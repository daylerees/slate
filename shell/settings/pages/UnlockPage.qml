import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import "../.."
import ".."

// ---- Face, Fingerprint & Keys ------------------------------------------------
// Unlocking the lock screen without typing your password, starting with your face (Howdy, which
// Slate never installs: it isn't packaged on most distros, so the page says what to get).
// What's here is looked at without a password (scripts/unlock-info.py: Howdy, the cameras and
// which are infrared, the ways in the lock screen takes now); everything that changes something
// goes through the root helper (bin/slate-unlock, by slate-system --root: your password). Your
// faces are Howdy's, root's even to list, so the list here is the helper's last answer, kept in
// ~/.local/state/slate/faces.json. The password always works too: the lock screen asks for it
// through a conversation of its own (LockScreen.qml)
Column {
    readonly property var win: SettingsHost.win
    id: unlockPage
    spacing: 4
    readonly property string script: Quickshell.shellPath("scripts/unlock-info.py")
    property var info: ({ howdy: false, cameras: [], methods: [] })
    property bool looked: false
    property var faces: []
    property string camera: ""           // the camera chosen here (its path); "" for the best there is
    property string doing: ""            // what the helper's doing, while it runs
    property string said: ""             // what it did, or what went wrong
    property bool saidProblem: false
    readonly property bool faceOn: (info.methods || []).indexOf("face") >= 0
    readonly property var cams: info.cameras || []
    // The camera in use: the one chosen, else an infrared one, else the first
    readonly property var chosen: cams.find(c => c.path === camera) || cams.find(c => c.ir) || cams[0] || null
    readonly property bool busy: doing !== "" || tryPam.active

    readonly property var testState: ({ looked: looked, howdy: !!info.howdy, faces: faces.map(f => f.label), faceOn: faceOn,
                                        camera: chosen ? chosen.path : "", said: said, problem: saidProblem, doing: doing })
    // (the tests: what's here and what the helper answers, given in place of the real ones)
    readonly property bool pretending: Config.testMode && win.pretendPolls.unlock !== undefined

    // ---- What's here --------------------------------------------------------------
    function refresh() { look.running = false; look.running = true; }
    Connections { target: win; enabled: Config.testMode; function onPretendPollsChanged() { unlockPage.refresh(); } }
    FirstLook {
        id: look
        running: true
        command: ["python3", unlockPage.script]
        stdout: StdioCollector {
            onStreamFinished: {
                try { unlockPage.info = JSON.parse(win.pretendPolls.unlock ?? text); } catch (e) {}
                unlockPage.looked = true;
            }
        }
    }

    // ---- Your faces, as the helper last listed them ------------------------------
    readonly property string facesPath: Config.stateHome + "/slate/faces.json"
    FileView {
        id: facesFile
        path: unlockPage.facesPath
        printErrors: false
        onLoaded: {
            try {
                const o = JSON.parse(text());
                unlockPage.faces = Array.isArray(o.faces) ? o.faces : [];
                unlockPage.camera = String(o.camera || "");
            } catch (e) {}
        }
    }
    function keep() {
        Quickshell.execDetached(["sh", "-c", 'mkdir -p "${0%/*}"', facesPath]);
        facesFile.setText(JSON.stringify({ camera: camera, faces: faces }));
    }
    // face-list's answer (face-add and face-remove end with it): "<id>,<date>,<label>" a line
    function takeList(text) {
        const out = [];
        for (const line of String(text).split("\n")) {
            const m = line.trim().match(/^(\d+),[^,]*,(.*)$/);
            if (m) out.push({ id: Number(m[1]), label: m[2] });
        }
        faces = out;
        keep();
    }

    // ---- The helper (your password) ------------------------------------------------
    Process {
        id: run
        property string done: ""
        property string failed: ""
        property bool lists: false        // it answers with your faces
        stdout: StdioCollector { id: runOut }
        stderr: StdioCollector { id: runErr }
        onExited: code => unlockPage.finished(code, runOut.text, runErr.text)
    }
    function finished(code, out, err) {
        const why = String(err).trim().split("\n").filter(l => l !== "").pop() || "";
        doing = "";
        if (code === 0) {
            if (run.lists) takeList(out);
            said = run.done; saidProblem = false;
        } else if (code === 126 || code === 127) {
            said = "";                       // (the password prompt cancelled: nothing changed)
        } else {
            said = run.failed + (why !== "" ? ": " + why : ""); saidProblem = true;
        }
        refresh();
    }
    function helper(args, doing, done, failed, lists) {
        unlockPage.doing = doing; said = ""; saidProblem = false;
        run.done = done; run.failed = failed; run.lists = !!lists;
        // (the tests: the answer given in place of the helper's, and what it was asked kept)
        if (pretending) {
            win.pretendPoll("unlockAsked", JSON.stringify(args));
            Qt.callLater(() => unlockPage.finished(Number(win.pretendPolls.unlockCode || 0), win.pretendPolls.unlockAnswer || "", ""));
            return;
        }
        run.command = [Quickshell.shellPath("bin/slate-system"), "--root", "slate-unlock"].concat(args);
        run.running = true;
    }

    // Adding a face: what it is and that it looks through the camera, said first, with a name
    // for it (yours to tell apart: "Glasses", "Me"), then your password, then a few seconds of
    // looking at you
    function askAdd() {
        const first = faces.length === 0;
        win.confirmer.confirmWith({
            title: first ? "Add your face?" : "Add another look?",
            body: "Look straight at your camera when it starts. Slate asks for your password, then takes a few seconds "
                + "to learn your face. It stays on this computer." + (first ? "" : " Another look (with glasses, say) helps it know you."),
            button: "Add", code: 0xEA9B, danger: false,
            input: { text: first ? "Me" : "", placeholder: "A name for it, like Glasses", maxLength: 40 }
        }, (opt, typed) => {
            const label = String(typed || "").trim().replace(/[^A-Za-z0-9 _.-]/g, "").slice(0, 40) || (first ? "Me" : "Face " + (faces.length + 1));
            const args = ["face-add", /^[A-Za-z0-9]/.test(label) ? label : "Face " + (faces.length + 1)];
            if (chosen) args.push(chosen.path);
            helper(args, "Looking at you…", "Added. You can unlock with your face once it's on below", "Slate couldn't add your face", true);
        });
    }
    function askRemove(face) {
        win.ask = {
            title: "Remove “" + face.label + "”?",
            body: "Slate won't recognize you by this look any more. Your password and any other looks still work, "
                + "and you can add it again at any time.",
            button: "Remove", destructive: true, code: 0xEA9B,
            run: () => helper(["face-remove", String(face.id)], "Removing…", "Removed", "Slate couldn't remove it", true)
        };
    }
    function setOn(on) {
        helper([on ? "enable" : "disable", "face"], on ? "Turning it on…" : "Turning it off…",
               on ? "On: the lock screen looks for your face" : "Off: the lock screen asks for your password",
               on ? "Slate couldn't turn it on" : "Slate couldn't turn it off", false);
    }
    function pickCamera(path) {
        camera = path;
        keep();
        // Faces already added: Howdy looks through the new camera from now on (your password)
        if (faces.length > 0)
            helper(["face-camera", path], "Changing the camera…", "Howdy looks through this camera now", "Slate couldn't change the camera", false);
    }

    // ---- Try it: the lock screen's own way in, without locking ---------------------
    property string tryDir: Config.testMode && win.pretendPolls.unlockPam ? win.pretendPolls.unlockPam.split("|")[0] : "/etc/pam.d"
    PamContext {
        id: tryPam
        config: Config.testMode && win.pretendPolls.unlockPam ? win.pretendPolls.unlockPam.split("|")[1] : "slate-lock"
        configDirectory: unlockPage.tryDir
        onPamMessage: {
            // (a question is for a password: this never answers one)
            if (responseRequired) { abort(); return; }
            if (message !== "" && !messageIsError) { unlockPage.said = "Looking for your face…"; unlockPage.saidProblem = false; }
        }
        onCompleted: result => {
            const ok = result === PamResult.Success;
            unlockPage.said = ok ? "That's you: the lock screen will let you in" : "Slate didn't recognize you. Try again, or add another look";
            unlockPage.saidProblem = !ok;
        }
        onError: err => { unlockPage.said = "Slate couldn't try it"; unlockPage.saidProblem = true; }
    }
    function tryIt() {
        said = "Looking for your face…"; saidProblem = false;
        tryPam.start();
    }

    PageTitle { text: "Face, Fingerprint & Keys" }
    IntroText {
        text: "Unlock the lock screen without typing your password. Your password always works too, "
            + "so a camera that can't see you never locks you out."
    }

    GroupLabel { text: "Face" }
    Group {
        // Howdy isn't here: what to get (nothing else on the page can work without it)
        SettingRow {
            visible: unlockPage.looked && !unlockPage.info.howdy
            label: "Face unlock needs Howdy"
            detail: "Howdy recognizes your face through your camera. Slate doesn't install it for you: on Arch it's "
                + "howdy-next in the AUR; on other systems, see howdy's own instructions. Then come back here"
        }
        Separator { visible: unlockPage.looked && !unlockPage.info.howdy }
        DropdownSetting {
            label: "Camera"
            detail: !unlockPage.chosen ? "Slate can't find a camera"
                : unlockPage.chosen.ir ? "An infrared camera: it sees your face in the dark, and a photo can't fool it"
                : "This camera isn't infrared, so a photo of you could fool it. An infrared camera (one made for Windows Hello) is much safer"
            needsMet: unlockPage.info.howdy && unlockPage.cams.length > 0 && !unlockPage.busy
            needs: !unlockPage.info.howdy ? "Needs Howdy to be installed" : unlockPage.cams.length === 0 ? "Needs a camera" : "Wait a moment"
            options: unlockPage.cams.map(c => ({ value: c.path, label: c.name + (c.ir ? " · infrared" : "") }))
            value: unlockPage.chosen ? unlockPage.chosen.path : ""
            onPicked: v => unlockPage.pickCamera(v)
        }
        Separator {}
        Repeater {
            model: unlockPage.faces
            delegate: Column {
                required property var modelData
                width: parent ? parent.width : 0
                ListItemRow {
                    width: parent.width
                    label: modelData.label
                    detail: "A look Slate knows you by"
                    removable: !unlockPage.busy
                    onRemoved: unlockPage.askRemove(modelData)
                }
                Separator {}
            }
        }
        SettingRow {
            label: unlockPage.faces.length === 0 ? "Your face" : "Another look"
            detail: unlockPage.doing !== "" ? unlockPage.doing
                : unlockPage.said !== "" ? unlockPage.said
                : unlockPage.faces.length === 0 ? "Slate learns your face through the camera above. Nothing's added yet"
                : "With glasses, say, or in different light: more looks help it know you"
            needsMet: unlockPage.info.howdy && !!unlockPage.chosen && !unlockPage.busy
            needs: !unlockPage.info.howdy ? "Needs Howdy to be installed" : !unlockPage.chosen ? "Needs a camera" : "Wait a moment"
            Row {
                spacing: 8
                Button {
                    visible: unlockPage.faceOn && unlockPage.faces.length > 0
                    label: "Try it"
                    onClicked: unlockPage.tryIt()
                }
                Button {
                    label: unlockPage.faces.length === 0 ? "Add your face" : "Add a look"
                    primary: unlockPage.faces.length === 0
                    onClicked: unlockPage.askAdd()
                }
            }
        }
        Separator {}
        SettingRow {
            label: "Unlock with your face"
            detail: unlockPage.faceOn ? "The lock screen looks for your face as soon as it wakes"
                : "The lock screen looks for your face as it wakes, and you can still type your password"
            needsMet: unlockPage.info.howdy && unlockPage.faces.length > 0 && !unlockPage.busy
            needs: !unlockPage.info.howdy ? "Needs Howdy to be installed" : unlockPage.faces.length === 0 ? "Needs your face to be added" : "Wait a moment"
            SettingToggle {
                checked: unlockPage.faceOn
                onToggled: v => unlockPage.setOn(v)
                Accessible.name: "Unlock with your face"
            }
        }
    }
    Footnote {
        text: "Faces are kept by Howdy, on this computer only, and only the lock screen uses them: sudo, the login screen "
            + "and other apps still ask for your password."
    }
}
