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
    property var info: ({ howdy: false, cameras: [], methods: [], fingerprint: { fprintd: false, reader: "", fingers: [] },
                          keys: { u2f: false, keys: [] } })
    property bool looked: false
    property var faces: []
    property bool known: false           // Slate has asked Howdy for your faces (faces.json is there)
    property string camera: ""           // the camera chosen here (its path); "" for the best there is
    property string doing: ""            // what the helper's doing, while it runs
    property string said: ""             // what it did, or what went wrong
    property bool saidProblem: false
    readonly property bool faceOn: (info.methods || []).indexOf("face") >= 0
    readonly property var cams: info.cameras || []
    // The camera in use: the one chosen, else an infrared one, else the first
    readonly property var chosen: cams.find(c => c.path === camera) || cams.find(c => c.ir) || cams[0] || null
    readonly property bool busy: doing !== "" || tryPam.active || fp.running || fpTry.running || fpDelete.running || keyReg.running

    // ---- Security keys (pam_u2f): registering one is pamu2fcfg, as you (touch the key); the
    // list of keys is root's (/etc/slate/u2f_keys, never in your home), so adding and removing
    // go through the helper. Anyone can read the list (unlock-info.py), so no password to see
    // it. Their names are yours, kept here (keys.json, by each key's handle)
    readonly property var keyInfo: info.keys || ({ u2f: false, keys: [] })
    readonly property var keyHandles: keyInfo.keys || []
    readonly property bool keyOn: (info.methods || []).indexOf("key") >= 0
    property var keyNames: ({})
    property string keySaid: ""
    property bool keyProblem: false
    property string addingKeyName: ""
    function keyName(handle, i) { return keyNames[handle] || "Security key " + (i + 1); }
    readonly property string keyNamesPath: Config.stateHome + "/slate/keys.json"
    FileView {
        id: keyNamesFile
        path: unlockPage.keyNamesPath
        printErrors: false
        onLoaded: { try { const o = JSON.parse(text()); unlockPage.keyNames = o.names || {}; } catch (e) {} }
    }
    function keepKeyNames() {
        Quickshell.execDetached(["sh", "-c", 'mkdir -p "${0%/*}"', keyNamesPath]);
        keyNamesFile.setText(JSON.stringify({ names: keyNames }));
    }
    function askAddKey() {
        win.confirmer.confirmWith({
            title: "Add a security key?",
            body: "Plug in your key, and touch it when it blinks. Then Slate asks for your password to save it. "
                + "Only the key's public half is kept, on this computer.",
            button: "Add", code: 0xEAC7, danger: false,
            input: { text: "", placeholder: "A name for it, like YubiKey", maxLength: 40 }
        }, (opt, typed) => {
            addingKeyName = String(typed || "").trim().slice(0, 40);
            keySaid = "Touch your security key"; keyProblem = false;
            keyReg.command = [fpTool("pamu2fcfg"), "-n"];
            keyReg.running = true;
        });
    }
    // pamu2fcfg -n: its last line is the key's registration (":<handle>,<public key>,<type>,<flags>")
    Process {
        id: keyReg
        stdout: StdioCollector { id: keyRegOut }
        onExited: code => {
            const line = keyRegOut.text.trim().split("\n").filter(l => l !== "").pop() || "";
            const reg = line.indexOf(":") >= 0 ? line.slice(line.indexOf(":") + 1) : line;
            if (code !== 0 || !/^[^,]+,[^,]+,[a-z0-9]+,/.test(reg)) {
                unlockPage.keySaid = "Slate couldn't read the key. Check it's plugged in, then try again";
                unlockPage.keyProblem = true;
                return;
            }
            unlockPage.keySaid = "";
            if (unlockPage.addingKeyName !== "") {
                const n = Object.assign({}, unlockPage.keyNames);
                n[reg.split(",")[0]] = unlockPage.addingKeyName;
                unlockPage.keyNames = n;
                unlockPage.keepKeyNames();
            }
            unlockPage.helper(["key-add", reg], "Saving your key…", "Added. You can unlock with it once it's on below", "Slate couldn't add the key", false);
        }
    }
    function askRemoveKey(i) {
        const name = keyName(keyHandles[i], i);
        win.ask = {
            title: "Remove “" + name + "”?",
            body: "This key won't unlock the lock screen any more. Your password and any other keys still work, "
                + "and you can add it again at any time.",
            button: "Remove", destructive: true, code: 0xEAC7,
            run: () => helper(["key-remove", String(i + 1)], "Removing…", "Removed", "Slate couldn't remove it", false)
        };
    }
    // ---- The login screen: the same ways in, on Slate's own (greetd) login screen, each turned on
    // for it apart from the lock screen (slate-unlock login-enable: /etc/pam.d/slate-greetd)
    readonly property bool loginScreen: !!info.loginScreen
    readonly property var loginMethods: info.loginMethods || []
    function loginOn(method) { return loginMethods.indexOf(method) >= 0; }
    function setLoginOn(method, on) {
        helper([on ? "login-enable" : "login-disable", method], on ? "Turning it on…" : "Turning it off…",
               on ? "On: the login screen takes it too, from your next login" : "Off: the login screen asks for your password",
               on ? "Slate couldn't turn it on" : "Slate couldn't turn it off", false);
    }
    readonly property string loginNote: "Your saved passwords (the keyring) stay locked until you type your password"
    function setKeyOn(on) {
        helper([on ? "enable" : "disable", "key"], on ? "Turning it on…" : "Turning it off…",
               on ? "On: the lock screen takes your security key" : "Off: the lock screen asks for your password",
               on ? "Slate couldn't turn it on" : "Slate couldn't turn it off", false);
    }

    // ---- Fingerprint: fprintd's own commands, as you (it lets you enroll, list, remove and
    // check your own fingers); only turning it on for the lock screen needs your password
    readonly property var fpInfo: info.fingerprint || ({ fprintd: false, reader: "", fingers: [] })
    readonly property var fingers: fpInfo.fingers || []
    readonly property bool fingerOn: (info.methods || []).indexOf("fingerprint") >= 0
    // fprintd's names for the fingers, in the order they're offered
    readonly property var fingerNames: ["right-index-finger", "left-index-finger", "right-thumb", "left-thumb",
        "right-middle-finger", "left-middle-finger", "right-ring-finger", "left-ring-finger",
        "right-little-finger", "left-little-finger"]
    function fingerLabel(n) {
        const s = String(n).replace(/-finger$/, "").replace(/-/g, " ");
        return s.charAt(0).toUpperCase() + s.slice(1) + (/thumb$/.test(n) ? "" : " finger");
    }
    readonly property var freeFingers: fingerNames.filter(n => fingers.indexOf(n) < 0)
    property string nextFinger: ""
    readonly property string addingFinger: freeFingers.indexOf(nextFinger) >= 0 ? nextFinger : (freeFingers[0] || "")
    property string fpSaid: ""
    property bool fpProblem: false
    property int touches: 0
    // (the tests: stand-ins for fprintd's commands, in a folder of theirs)
    function fpTool(name) { return Config.testMode && win.pretendPolls.unlockTools ? win.pretendPolls.unlockTools + "/" + name : name; }
    readonly property string me: Quickshell.env("USER") || ""
    // Enrolling: fprintd-enroll says how each touch went ("Enroll result: enroll-stage-passed",
    // … "enroll-completed"); a few touches of the same finger make one fingerprint
    Process {
        id: fp
        stdout: SplitParser { onRead: line => unlockPage.enrollSaid(line) }
        onExited: code => { if (unlockPage.fpSaid.startsWith("Touch") || unlockPage.fpSaid.startsWith("Lift")) { unlockPage.fpSaid = "Slate couldn't finish adding it. Try again"; unlockPage.fpProblem = true; } unlockPage.refresh(); }
    }
    function enrollSaid(line) {
        const m = String(line).match(/Enroll result: (\S+)/);
        if (!m) return;
        const r = m[1];
        if (r === "enroll-stage-passed") { touches++; fpSaid = "Lift your finger, then touch the reader again (" + touches + ")"; fpProblem = false; }
        else if (r === "enroll-completed") { fpSaid = "Added. You can unlock with it once it's on below"; fpProblem = false; }
        else if (r === "enroll-retry-scan" || r === "enroll-remove-and-retry") { fpSaid = "That didn't read well. Touch the reader again"; fpProblem = false; }
        else if (r === "enroll-swipe-too-short") { fpSaid = "Too short: swipe a little slower"; fpProblem = false; }
        else if (r === "enroll-finger-not-centered") { fpSaid = "Put your finger in the middle of the reader"; fpProblem = false; }
        else if (r === "enroll-data-full") { fpSaid = "The reader is full: remove a fingerprint first"; fpProblem = true; }
        else if (r === "enroll-duplicate") { fpSaid = "That finger's already added"; fpProblem = true; }
        else { fpSaid = "Slate couldn't add it. Try again"; fpProblem = true; }
    }
    function askAddFinger() {
        const finger = addingFinger;
        if (finger === "") return;
        win.ask = {
            title: "Add your " + fingerLabel(finger).toLowerCase() + "?",
            body: "Touch the reader with it, lift it, and touch again, until Slate says it's done. A few touches, "
                + "each a little different, help it know your finger. It stays on this computer.",
            button: "Add", code: 0xEBD1,
            run: () => {
                touches = 0; fpSaid = "Touch the reader with your " + fingerLabel(finger).toLowerCase(); fpProblem = false;
                fp.command = [fpTool("fprintd-enroll"), "-f", finger];
                fp.running = true;
            }
        };
    }
    function askRemoveFinger(finger) {
        win.ask = {
            title: "Remove your " + fingerLabel(finger).toLowerCase() + "?",
            body: "Slate won't recognize this finger any more. Your password and your other fingers still work, "
                + "and you can add it again at any time.",
            button: "Remove", destructive: true, code: 0xEBD1,
            run: () => { fpSaid = ""; fpDelete.command = [fpTool("fprintd-delete"), unlockPage.me, "-f", finger]; fpDelete.running = true; }
        };
    }
    Process {
        id: fpDelete
        onExited: code => { unlockPage.fpSaid = code === 0 ? "Removed" : "Slate couldn't remove it"; unlockPage.fpProblem = code !== 0; unlockPage.refresh(); }
    }
    // Try it: fprintd-verify, any of your fingers ("Verify result: verify-match (done)")
    Process {
        id: fpTry
        stdout: SplitParser {
            onRead: line => {
                const m = String(line).match(/Verify result: (\S+)/);
                if (!m) return;
                const ok = m[1] === "verify-match";
                unlockPage.fpSaid = ok ? "That's you: the lock screen will let you in" : m[1] === "verify-no-match"
                    ? "Slate didn't recognize that finger. Try again, or add it" : "Slate couldn't read it. Try again";
                unlockPage.fpProblem = !ok;
            }
        }
    }
    function tryFinger() {
        fpSaid = "Touch the reader"; fpProblem = false;
        fpTry.command = [fpTool("fprintd-verify")];
        fpTry.running = true;
    }
    function setFingerOn(on) {
        helper([on ? "enable" : "disable", "fingerprint"], on ? "Turning it on…" : "Turning it off…",
               on ? "On: the lock screen takes your fingerprint" : "Off: the lock screen asks for your password",
               on ? "Slate couldn't turn it on" : "Slate couldn't turn it off", false);
    }

    readonly property var testState: ({ looked: looked, howdy: !!info.howdy, faces: faces.map(f => f.label), faceOn: faceOn,
                                        camera: chosen ? chosen.path : "", said: said, problem: saidProblem, doing: doing,
                                        loginMethods: loginMethods,
                                        fingers: fingers, fingerOn: fingerOn, adding: addingFinger, fpSaid: fpSaid, fpProblem: fpProblem,
                                        keys: keyHandles.map((h, i) => keyName(h, i)), keyOn: keyOn, keySaid: keySaid, keyProblem: keyProblem })
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
                unlockPage.known = Array.isArray(o.faces);
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
        known = true;
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
                : unlockPage.faces.length === 0 && !unlockPage.known ? "Slate learns your face through the camera above. Faces added before (outside Settings) show once you ask"
                : unlockPage.faces.length === 0 ? "Slate learns your face through the camera above. Nothing's added yet"
                : "With glasses, say, or in different light: more looks help it know you"
            needsMet: unlockPage.info.howdy && !!unlockPage.chosen && !unlockPage.busy
            needs: !unlockPage.info.howdy ? "Needs Howdy to be installed" : !unlockPage.chosen ? "Needs a camera" : "Wait a moment"
            Row {
                spacing: 8
                // Faces Howdy already has (added outside Settings): listing them is root's, so
                    // only when asked, once
                Button {
                    visible: !unlockPage.known && unlockPage.faces.length === 0
                    label: "Show your faces"
                    onClicked: unlockPage.helper(["face-list"], "Looking…", "", "Slate couldn't look", true)
                }
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
            detail: "The lock screen looks for your face when you come back. Locked with Super+L, it waits for a key "
                + "or the pointer, so it doesn't let you straight back in"
            needsMet: unlockPage.info.howdy && unlockPage.faces.length > 0 && !unlockPage.busy
            needs: !unlockPage.info.howdy ? "Needs Howdy to be installed" : unlockPage.faces.length === 0 ? "Needs your face to be added" : "Wait a moment"
            SettingToggle {
                checked: unlockPage.faceOn
                onToggled: v => unlockPage.setOn(v)
                Accessible.name: "Unlock with your face"
            }
        }
        Separator {}
        SettingRow {
            label: "Face on the login screen"
            detail: "Log in with it too. " + unlockPage.loginNote
            needsMet: unlockPage.loginScreen && unlockPage.info.howdy && unlockPage.faces.length > 0 && !unlockPage.busy
            needs: !unlockPage.loginScreen ? "Needs Slate's login screen to be installed" : !(unlockPage.info.howdy && unlockPage.faces.length > 0) ? "Needs your face to be added" : "Wait a moment"
            needsPage: !unlockPage.loginScreen ? "lock" : ""
            needsLabel: !unlockPage.loginScreen ? "Slate login screen" : ""
            SettingToggle {
                checked: unlockPage.loginOn("face")
                onToggled: v => unlockPage.setLoginOn("face", v)
                Accessible.name: "Face on the login screen"
            }
        }
    }
    GroupLabel { text: "Fingerprint" }
    Group {
        SettingRow {
            visible: unlockPage.looked && (!unlockPage.fpInfo.fprintd || unlockPage.fpInfo.reader === "")
            label: !unlockPage.fpInfo.fprintd ? "Fingerprint unlock needs fprintd" : "No fingerprint reader"
            detail: !unlockPage.fpInfo.fprintd
                ? "fprintd reads your fingerprint reader. Install fprintd with your package manager (on Debian and Ubuntu, libpam-fprintd too), then come back here"
                : "Slate can't find a fingerprint reader that fprintd supports"
        }
        Separator { visible: unlockPage.looked && (!unlockPage.fpInfo.fprintd || unlockPage.fpInfo.reader === "") }
        Repeater {
            model: unlockPage.fingers
            delegate: Column {
                required property var modelData
                width: parent ? parent.width : 0
                ListItemRow {
                    width: parent.width
                    label: unlockPage.fingerLabel(modelData)
                    detail: "On " + unlockPage.fpInfo.reader
                    removable: !unlockPage.busy
                    onRemoved: unlockPage.askRemoveFinger(modelData)
                }
                Separator {}
            }
        }
        DropdownSetting {
            label: "Finger to add"
            detail: unlockPage.fpSaid !== "" ? unlockPage.fpSaid
                : unlockPage.fingers.length === 0 ? "Slate learns your fingerprint through the reader. Nothing's added yet"
                : "More fingers mean another way in when one's busy"
            needsMet: unlockPage.fpInfo.reader !== "" && unlockPage.freeFingers.length > 0 && !unlockPage.busy
            needs: !unlockPage.fpInfo.fprintd ? "Needs fprintd to be installed" : unlockPage.fpInfo.reader === "" ? "Needs a fingerprint reader"
                : unlockPage.freeFingers.length === 0 ? "Every finger's added" : "Wait a moment"
            options: unlockPage.freeFingers.map(n => ({ value: n, label: unlockPage.fingerLabel(n) }))
            value: unlockPage.addingFinger
            onPicked: v => unlockPage.nextFinger = v
        }
        Separator {}
        SettingRow {
            label: "Your fingerprints"
            detail: unlockPage.fingers.length === 0 ? "Add one, then turn it on below" : "Check the reader knows you"
            needsMet: unlockPage.fpInfo.reader !== "" && !unlockPage.busy
            needs: !unlockPage.fpInfo.fprintd ? "Needs fprintd to be installed" : unlockPage.fpInfo.reader === "" ? "Needs a fingerprint reader" : "Wait a moment"
            Row {
                spacing: 8
                Button {
                    visible: unlockPage.fingers.length > 0
                    label: "Try it"
                    onClicked: unlockPage.tryFinger()
                }
                Button {
                    label: "Add"
                    primary: unlockPage.fingers.length === 0
                    enabled: unlockPage.addingFinger !== ""
                    onClicked: unlockPage.askAddFinger()
                }
            }
        }
        Separator {}
        SettingRow {
            label: "Unlock with your fingerprint"
            detail: unlockPage.faceOn && unlockPage.fingerOn
                ? "The lock screen takes your fingerprint. With your face on too, it looks for your face first"
                : "The lock screen takes your fingerprint, and you can still type your password"
            needsMet: unlockPage.fpInfo.fprintd && unlockPage.fingers.length > 0 && !unlockPage.busy
            needs: !unlockPage.fpInfo.fprintd ? "Needs fprintd to be installed" : unlockPage.fingers.length === 0 ? "Needs a fingerprint to be added" : "Wait a moment"
            SettingToggle {
                checked: unlockPage.fingerOn
                onToggled: v => unlockPage.setFingerOn(v)
                Accessible.name: "Unlock with your fingerprint"
            }
        }
        Separator {}
        SettingRow {
            label: "Fingerprint on the login screen"
            detail: "Log in with it too. " + unlockPage.loginNote
            needsMet: unlockPage.loginScreen && unlockPage.fpInfo.fprintd && unlockPage.fingers.length > 0 && !unlockPage.busy
            needs: !unlockPage.loginScreen ? "Needs Slate's login screen to be installed" : !(unlockPage.fpInfo.fprintd && unlockPage.fingers.length > 0) ? "Needs a fingerprint to be added" : "Wait a moment"
            needsPage: !unlockPage.loginScreen ? "lock" : ""
            needsLabel: !unlockPage.loginScreen ? "Slate login screen" : ""
            SettingToggle {
                checked: unlockPage.loginOn("fingerprint")
                onToggled: v => unlockPage.setLoginOn("fingerprint", v)
                Accessible.name: "Fingerprint on the login screen"
            }
        }
    }
    GroupLabel { text: "Security keys" }
    Group {
        SettingRow {
            visible: unlockPage.looked && !unlockPage.keyInfo.u2f
            label: "Security keys need pam-u2f"
            detail: "pam-u2f lets a security key (a YubiKey, say) unlock your computer. Install pam-u2f with your package manager "
                + "(on Debian and Ubuntu, libpam-u2f and pamu2fcfg), then come back here"
        }
        Separator { visible: unlockPage.looked && !unlockPage.keyInfo.u2f }
        Repeater {
            model: unlockPage.keyHandles
            delegate: Column {
                required property var modelData
                required property int index
                width: parent ? parent.width : 0
                ListItemRow {
                    width: parent.width
                    label: unlockPage.keyName(modelData, index)
                    detail: "Touch it to unlock"
                    removable: !unlockPage.busy
                    onRemoved: unlockPage.askRemoveKey(index)
                }
                Separator {}
            }
        }
        SettingRow {
            label: unlockPage.keyHandles.length === 0 ? "Your security key" : "Another key"
            detail: unlockPage.keySaid !== "" ? unlockPage.keySaid
                : unlockPage.keyHandles.length === 0 ? "Plug in a security key and touch it to add it. Nothing's added yet"
                : "A spare key keeps a way in if one's lost"
            needsMet: unlockPage.keyInfo.u2f && !unlockPage.busy
            needs: !unlockPage.keyInfo.u2f ? "Needs pam-u2f to be installed" : "Wait a moment"
            Button {
                label: unlockPage.keyHandles.length === 0 ? "Add a key" : "Add"
                primary: unlockPage.keyHandles.length === 0
                onClicked: unlockPage.askAddKey()
            }
        }
        Separator {}
        SettingRow {
            label: "Unlock with your security key"
            detail: "The lock screen lets you in when you touch your key, and you can still type your password"
            needsMet: unlockPage.keyInfo.u2f && unlockPage.keyHandles.length > 0 && !unlockPage.busy
            needs: !unlockPage.keyInfo.u2f ? "Needs pam-u2f to be installed" : unlockPage.keyHandles.length === 0 ? "Needs a key to be added" : "Wait a moment"
            SettingToggle {
                checked: unlockPage.keyOn
                onToggled: v => unlockPage.setKeyOn(v)
                Accessible.name: "Unlock with your security key"
            }
        }
        Separator {}
        SettingRow {
            label: "Security key on the login screen"
            detail: "Log in with it too. " + unlockPage.loginNote
            needsMet: unlockPage.loginScreen && unlockPage.keyInfo.u2f && unlockPage.keyHandles.length > 0 && !unlockPage.busy
            needs: !unlockPage.loginScreen ? "Needs Slate's login screen to be installed" : !(unlockPage.keyInfo.u2f && unlockPage.keyHandles.length > 0) ? "Needs a key to be added" : "Wait a moment"
            needsPage: !unlockPage.loginScreen ? "lock" : ""
            needsLabel: !unlockPage.loginScreen ? "Slate login screen" : ""
            SettingToggle {
                checked: unlockPage.loginOn("key")
                onToggled: v => unlockPage.setLoginOn("key", v)
                Accessible.name: "Security key on the login screen"
            }
        }
    }
    Footnote {
        text: "Faces, fingerprints and keys stay on this computer. Only Slate's lock screen uses them, and its login screen "
            + "where you've turned that on: sudo, other login screens and other apps still ask for your password."
    }
}
