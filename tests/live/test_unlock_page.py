"""Settings → Security → Face, Fingerprint & Keys: what's here, adding and removing your face,
turning it on for the lock screen, and Try it. What's here (scripts/unlock-info.py's answer) and
what the root helper answers are given by the test (settingsPoll "unlock", "unlockAnswer",
"unlockCode"), so nothing asks for a password or touches the test computer: the page notes what
it would have asked the helper ("unlockAsked"). Try it runs a PAM service of the test's own,
as the lock screen's tests do."""
import json
import os

from live import LiveCase

BRIO = [{"path": "/dev/v4l/by-id/usb-BRIO-video-index0", "name": "Logitech BRIO", "ir": False},
        {"path": "/dev/v4l/by-id/usb-BRIO-video-index2", "name": "Logitech BRIO", "ir": True}]
LIST = "1,2026-11-20 13:55:00,Me\n2,2026-11-20 14:01:00,Glasses\n"


class UnlockPage(LiveCase):
    def setUp(self):
        super().setUp()
        self.faces_file = self.s.h(".local", "state", "slate", "faces.json")
        if os.path.exists(self.faces_file):
            os.remove(self.faces_file)
        self.addCleanup(lambda: self.ipc("settings", "close"))
        self.addCleanup(lambda: self.ipc("power", "cancel"))
        for what in ("unlock", "unlockAnswer", "unlockCode", "unlockAsked", "unlockPam"):
            self.addCleanup(lambda w=what: self.ipc("test", "settingsPoll", w, ""))

    def open(self, howdy=True, cameras=BRIO, methods=(), faces=None):
        if faces is not None:
            os.makedirs(os.path.dirname(self.faces_file), exist_ok=True)
            with open(self.faces_file, "w") as f:
                json.dump({"camera": "", "faces": [{"id": i + 1, "label": l} for i, l in enumerate(faces)]}, f)
        self.ipc("settings", "page", "unlock")
        self.wait(lambda st: st["settings"]["open"] and st["settings"]["section"] == "unlock", "Face, Fingerprint & Keys")
        self.ipc("test", "settingsPoll", "unlock", json.dumps({"howdy": howdy, "cameras": cameras, "methods": list(methods)}))
        return self.wait(lambda st: st["settings"]["page"] and st["settings"]["page"]["looked"]
                         and st["settings"]["page"]["howdy"] == howdy, "the page to look")

    def page(self):
        return self.s.state()["settings"]["page"]

    def waiting(self):
        return {w["label"]: w["needs"] for w in self.s.state()["settings"]["waiting"]}

    def test_without_howdy_it_says_what_to_get(self):
        self.open(howdy=False)
        waiting = self.waiting()
        self.assertEqual(waiting.get("Camera"), "Needs Howdy to be installed")
        self.assertEqual(waiting.get("Unlock with your face"), "Needs Howdy to be installed")
        self.assertEqual(self.ipc("test", "settingsButton", "Face unlock needs Howdy", "Add your face"), "none")

    def test_the_infrared_camera_is_chosen(self):
        st = self.open()
        self.assertEqual(st["settings"]["page"]["camera"], BRIO[1]["path"])

    def test_adding_your_face_asks_first_then_lists_it(self):
        self.open()
        self.assertEqual(self.waiting().get("Unlock with your face"), "Needs your face to be added")
        self.ipc("test", "settingsPoll", "unlockAnswer", LIST)
        self.assertEqual(self.ipc("test", "settingsButton", "Your face", "Add your face"), "pressed")
        st = self.wait(lambda st: st["asking"] != "", "the question")
        self.assertEqual(st["asking"], "Add your face?")
        self.assertIn("Look straight at your camera", st["askingBody"])
        self.assertEqual(self.ipc("test", "typed"), "Me")
        self.ipc("test", "type", "Me")
        self.ipc("test", "answer", "true")
        st = self.wait(lambda st: st["settings"]["page"]["faces"] == ["Me", "Glasses"], "your faces listed")
        self.assertIn("Added", st["settings"]["page"]["said"])
        # Through the infrared camera, by name
        self.assertEqual(json.loads(self.pretend("unlockAsked")), ["face-add", "Me", BRIO[1]["path"]])
        # Kept for next time, without asking the helper (root's) again
        with open(self.faces_file) as f:
            self.assertEqual([x["label"] for x in json.load(f)["faces"]], ["Me", "Glasses"])

    def test_faces_added_before_are_shown_when_asked(self):
        """Faces Howdy has from before Settings did it (none listed yet): one look, when asked."""
        self.open()
        self.ipc("test", "settingsPoll", "unlockAnswer", "1,2026-11-20 13:55:00,Me\n")
        self.assertEqual(self.ipc("test", "settingsButton", "Your face", "Show your faces"), "pressed")
        self.wait(lambda st: st["settings"]["page"]["faces"] == ["Me"], "your face from before")
        self.assertEqual(json.loads(self.pretend("unlockAsked")), ["face-list"])
        # Known now: nothing more to show
        self.assertEqual(self.ipc("test", "settingsButton", "Another look", "Show your faces"), "none")

    def test_removing_one_asks_first(self):
        self.open(faces=["Me", "Glasses"])
        self.wait(lambda st: st["settings"]["page"]["faces"] == ["Me", "Glasses"], "your faces from last time")
        self.ipc("test", "settingsPoll", "unlockAnswer", "1,2026-11-20 13:55:00,Me\n")
        self.assertEqual(self.ipc("test", "settingsButton", "Glasses", "Remove"), "pressed")
        st = self.wait(lambda st: st["asking"] != "", "the question")
        self.assertEqual(st["asking"], "Remove “Glasses”?")
        self.ipc("test", "answer", "true")
        self.wait(lambda st: st["settings"]["page"]["faces"] == ["Me"], "it gone from the list")
        self.assertEqual(json.loads(self.pretend("unlockAsked")), ["face-remove", "2"])

    def test_turning_it_on(self):
        self.open(faces=["Me"])
        self.wait(lambda st: st["settings"]["page"]["faces"] == ["Me"], "your face")
        self.assertEqual(self.ipc("test", "settingsToggle", "Unlock with your face"), "pressed")
        self.wait(lambda st: st["settings"]["page"]["said"].startswith("On"), "it to say it's on")
        self.assertEqual(json.loads(self.pretend("unlockAsked")), ["enable", "face"])

    def test_a_cancelled_password_says_nothing(self):
        self.open(faces=["Me"])
        self.wait(lambda st: st["settings"]["page"]["faces"] == ["Me"], "your face")
        self.ipc("test", "settingsPoll", "unlockCode", "126")
        self.ipc("test", "settingsToggle", "Unlock with your face")
        self.s.settle(0.6)
        page = self.page()
        self.assertEqual((page["said"], page["problem"]), ("", False))

    def test_try_it(self):
        """The lock screen's own way in (slate-lock), without locking: a stand-in that lets you in."""
        d = self.s.h("pam.d")
        os.makedirs(d, exist_ok=True)
        script = os.path.join(d, "fake-face")
        with open(script, "w") as f:
            f.write('#!/bin/sh\necho "Attempting facial authentication"\nsleep 1\nexit 0\n')
        os.chmod(script, 0o755)
        with open(os.path.join(d, "try-face"), "w") as f:
            f.write(f"auth required pam_exec.so stdout {script}\naccount required pam_permit.so\n")
        self.ipc("test", "settingsPoll", "unlockPam", d + "|try-face")
        self.open(methods=["face"], faces=["Me"])
        self.wait(lambda st: st["settings"]["page"]["faceOn"] and st["settings"]["page"]["faces"] == ["Me"], "it on, with your face")
        self.assertEqual(self.ipc("test", "settingsButton", "Another look", "Try it"), "pressed")
        self.wait(lambda st: st["settings"]["page"]["said"].startswith("That's you"), "it to know you", timeout=10)

    def pretend(self, what):
        return self.ipc("test", "settingsPollValue", what)


# fprintd's commands, as stand-ins that say what the real ones do (fprintd 1.94), and note what
# they were asked in $dir/asked
ENROLL = """#!/bin/sh
echo "$0 $*" >> "$(dirname "$0")/asked"
echo "Using device /net/reactivated/Fprint/Device/0"
echo "Enrolling $2 finger."
for r in enroll-stage-passed enroll-retry-scan enroll-stage-passed enroll-stage-passed enroll-completed; do
    sleep 0.3; echo "Enroll result: $r"
done
"""
VERIFY = """#!/bin/sh
echo "$0 $*" >> "$(dirname "$0")/asked"
echo "Verify started!"
sleep 0.3
echo "Verify result: verify-match (done)"
"""
DELETE = """#!/bin/sh
echo "$0 $*" >> "$(dirname "$0")/asked"
echo "Fingerprint $3 of user $1 deleted on Synaptics Sensors"
"""


class Fingerprint(LiveCase):
    def setUp(self):
        super().setUp()
        self.addCleanup(lambda: self.ipc("settings", "close"))
        self.addCleanup(lambda: self.ipc("power", "cancel"))
        for what in ("unlock", "unlockAnswer", "unlockCode", "unlockAsked"):
            self.addCleanup(lambda w=what: self.ipc("test", "settingsPoll", w, ""))

    def page(self):
        return self.s.state()["settings"]["page"]

    def waiting(self):
        return {w["label"]: w["needs"] for w in self.s.state()["settings"]["waiting"]}

    def pretend(self, what):
        return self.ipc("test", "settingsPollValue", what)

    def tools(self):
        """The stand-ins, once Settings is open (a poll given before it's built is dropped)."""
        d = self.s.h("fprint-tools")
        os.makedirs(d, exist_ok=True)
        for name, text in (("fprintd-enroll", ENROLL), ("fprintd-verify", VERIFY), ("fprintd-delete", DELETE)):
            p = os.path.join(d, name)
            with open(p, "w") as f:
                f.write(text)
            os.chmod(p, 0o755)
        if os.path.exists(os.path.join(d, "asked")):
            os.remove(os.path.join(d, "asked"))
        self.ipc("test", "settingsPoll", "unlockTools", d)
        self.addCleanup(lambda: self.ipc("test", "settingsPoll", "unlockTools", ""))
        return d

    def show(self, fingers=(), reader="Synaptics Sensors", fprintd=True, methods=()):
        self.ipc("settings", "page", "unlock")
        self.wait(lambda st: st["settings"]["open"] and st["settings"]["section"] == "unlock", "Face, Fingerprint & Keys")
        self.ipc("test", "settingsPoll", "unlock", json.dumps({"howdy": False, "cameras": [], "methods": list(methods),
                                                                "fingerprint": {"fprintd": fprintd, "reader": reader, "fingers": list(fingers)}}))
        return self.wait(lambda st: st["settings"]["page"] and st["settings"]["page"]["fingers"] == list(fingers), "the fingers listed")

    def asked(self, d):
        with open(os.path.join(d, "asked")) as f:
            return [l.split(" ", 1)[1].strip() if " " in l else "" for l in f.read().splitlines()]

    def test_without_fprintd_or_a_reader(self):
        # (waiting for what each says: show() waits for the fingers listed, the same empty list
        # both times, so the second returned before the page had the new state, under load)
        def says(label, want):
            got = lambda st: {w["label"]: w["needs"] for w in st["settings"]["waiting"]}.get(label)
            try:
                self.wait(lambda st: got(st) == want, f"{label}: {want}")
            except AssertionError:
                self.assertEqual(got(self.s.state()), want)
        self.show(fprintd=False, reader="")
        says("Unlock with your fingerprint", "Needs fprintd to be installed")
        self.show(reader="")
        says("Your fingerprints", "Needs a fingerprint reader")

    def test_adding_a_finger_says_each_touch(self):
        self.show()
        d = self.tools()
        self.assertEqual(self.page()["adding"], "right-index-finger")
        self.assertEqual(self.ipc("test", "settingsButton", "Your fingerprints", "Add"), "pressed")
        st = self.wait(lambda st: st["asking"] != "", "the question")
        self.assertEqual(st["asking"], "Add your right index finger?")
        self.ipc("test", "answer", "true")
        seen = set()
        for _ in range(60):
            said = self.page()["fpSaid"]
            seen.add(said)
            if said.startswith("Added"):
                break
            self.s.settle(0.1)
        self.assertIn("Added. You can unlock with it once it's on below", seen)
        self.assertTrue(any(s.startswith("Lift your finger, then touch the reader again") for s in seen), seen)
        self.assertEqual(self.asked(d), ["-f right-index-finger"])

    def test_the_next_finger_is_one_not_added(self):
        self.show(fingers=["right-index-finger"])
        self.assertEqual(self.page()["adding"], "left-index-finger")

    def test_removing_a_finger_asks_first(self):
        self.show(fingers=["right-index-finger", "left-thumb"])
        d = self.tools()
        self.assertEqual(self.ipc("test", "settingsButton", "Left thumb", "Remove"), "pressed")
        st = self.wait(lambda st: st["asking"] != "", "the question")
        self.assertEqual(st["asking"], "Remove your left thumb?")
        self.ipc("test", "answer", "true")
        self.wait(lambda st: st["settings"]["page"]["fpSaid"] == "Removed", "it removed")
        self.assertTrue(self.asked(d)[0].endswith("-f left-thumb"), self.asked(d))

    def test_try_it(self):
        self.show(fingers=["right-index-finger"])
        self.tools()
        self.assertEqual(self.ipc("test", "settingsButton", "Your fingerprints", "Try it"), "pressed")
        self.wait(lambda st: st["settings"]["page"]["fpSaid"].startswith("That's you"), "it to know you")

    def test_turning_it_on(self):
        self.show(fingers=["right-index-finger"])
        self.assertEqual(self.waiting().get("Unlock with your fingerprint"), None)
        self.assertEqual(self.ipc("test", "settingsToggle", "Unlock with your fingerprint"), "pressed")
        self.wait(lambda st: st["settings"]["page"]["said"].startswith("On"), "it to say it's on")
        self.assertEqual(json.loads(self.pretend("unlockAsked")), ["enable", "fingerprint"])


PAMU2FCFG = """#!/bin/sh
echo "$0 $*" >> "$(dirname "$0")/asked"
echo "Please touch the device." >&2
sleep 0.3
echo ":KEYHANDLE1234567890,PUBLICKEY1234567890,es256,+presence"
"""


class SecurityKeys(Fingerprint):
    """Security keys: pamu2fcfg (a stand-in) registers the key as you, then the helper (its answer
    given by the test) adds it to the list root keeps. Its name is yours, kept by Slate."""
    # (Fingerprint's own tests run in their own class)
    test_without_fprintd_or_a_reader = test_adding_a_finger_says_each_touch = None
    test_the_next_finger_is_one_not_added = test_removing_a_finger_asks_first = None
    test_try_it = test_turning_it_on = None

    def show_keys(self, keys=(), u2f=True, methods=()):
        self.ipc("settings", "page", "unlock")
        self.wait(lambda st: st["settings"]["open"] and st["settings"]["section"] == "unlock", "Face, Fingerprint & Keys")
        self.ipc("test", "settingsPoll", "unlock", json.dumps({"howdy": False, "cameras": [], "methods": list(methods),
                                                                "fingerprint": {"fprintd": False, "reader": "", "fingers": []},
                                                                "keys": {"u2f": u2f, "keys": list(keys)}}))
        return self.wait(lambda st: st["settings"]["page"] and len(st["settings"]["page"]["keys"]) == len(keys), "the keys listed")

    def test_without_pam_u2f(self):
        self.show_keys(u2f=False)
        self.assertEqual(self.waiting().get("Unlock with your security key"), "Needs pam-u2f to be installed")
        self.assertEqual(self.waiting().get("Your security key"), "Needs pam-u2f to be installed")

    def test_adding_a_key(self):
        names = self.s.h(".local", "state", "slate", "keys.json")
        if os.path.exists(names):
            os.remove(names)
        self.show_keys()
        d = self.tools()
        p = os.path.join(d, "pamu2fcfg")
        with open(p, "w") as f:
            f.write(PAMU2FCFG)
        os.chmod(p, 0o755)
        self.assertEqual(self.ipc("test", "settingsButton", "Your security key", "Add a key"), "pressed")
        st = self.wait(lambda st: st["asking"] != "", "the question")
        self.assertEqual(st["asking"], "Add a security key?")
        self.ipc("test", "type", "YubiKey")
        self.ipc("test", "answer", "true")
        self.wait(lambda st: st["settings"]["page"]["said"].startswith("Added"), "it added")
        self.assertEqual(self.asked(d), ["-n"])
        self.assertEqual(json.loads(self.pretend("unlockAsked")), ["key-add", "KEYHANDLE1234567890,PUBLICKEY1234567890,es256,+presence"])
        # Listed by its name, once the list has it
        self.show_keys(keys=["KEYHANDLE1234567890"])
        self.assertEqual(self.page()["keys"], ["YubiKey"])

    def test_a_key_that_cant_be_read(self):
        self.show_keys()
        d = self.tools()
        p = os.path.join(d, "pamu2fcfg")
        with open(p, "w") as f:
            f.write("#!/bin/sh\necho 'No FIDO devices found' >&2\nexit 1\n")
        os.chmod(p, 0o755)
        self.ipc("test", "settingsButton", "Your security key", "Add a key")
        self.wait(lambda st: st["asking"] != "", "the question")
        self.ipc("test", "answer", "true")
        st = self.wait(lambda st: st["settings"]["page"]["keyProblem"], "it to say so")
        self.assertIn("Check it's plugged in", st["settings"]["page"]["keySaid"])
        self.assertEqual(self.pretend("unlockAsked"), "", "the helper was asked without a key")

    def test_removing_one_asks_first(self):
        self.show_keys(keys=["H1", "H2"])
        self.assertEqual(self.ipc("test", "settingsButton", "Security key 2", "Remove"), "pressed")
        st = self.wait(lambda st: st["asking"] != "", "the question")
        self.assertEqual(st["asking"], "Remove “Security key 2”?")
        self.ipc("test", "answer", "true")
        self.wait(lambda st: st["settings"]["page"]["said"] == "Removed", "it removed")
        self.assertEqual(json.loads(self.pretend("unlockAsked")), ["key-remove", "2"])

    def test_turning_it_on(self):
        self.show_keys(keys=["H1"])
        self.assertEqual(self.ipc("test", "settingsToggle", "Unlock with your security key"), "pressed")
        self.wait(lambda st: st["settings"]["page"]["said"].startswith("On"), "it to say it's on")
        self.assertEqual(json.loads(self.pretend("unlockAsked")), ["enable", "key"])


class OnTheLoginScreen(UnlockPage):
    """Each way in can be turned on for Slate's login screen too (slate-unlock login-enable): only
    with Slate's login screen installed, and once the method's set up."""
    # (UnlockPage's own tests run in their own class)
    test_without_howdy_it_says_what_to_get = test_the_infrared_camera_is_chosen = None
    test_adding_your_face_asks_first_then_lists_it = test_faces_added_before_are_shown_when_asked = None
    test_removing_one_asks_first = test_turning_it_on = test_a_cancelled_password_says_nothing = test_try_it = None

    def show(self, login_screen, faces=("Me",), login_methods=()):
        if faces:
            os.makedirs(os.path.dirname(self.faces_file), exist_ok=True)
            with open(self.faces_file, "w") as f:
                json.dump({"camera": "", "faces": [{"id": i + 1, "label": l} for i, l in enumerate(faces)]}, f)
        self.ipc("settings", "page", "unlock")
        self.wait(lambda st: st["settings"]["open"] and st["settings"]["section"] == "unlock", "Face, Fingerprint & Keys")
        self.ipc("test", "settingsPoll", "unlock", json.dumps({"howdy": True, "cameras": BRIO, "methods": ["face"],
                                                                "loginScreen": login_screen, "loginMethods": list(login_methods)}))
        # (all three, login_screen too: in another order, the page still had the last test's
        # "not installed" when it was read)
        return self.wait(lambda st: st["settings"]["page"] and st["settings"]["page"]["faces"] == list(faces)
                         and st["settings"]["page"]["loginMethods"] == list(login_methods)
                         and st["settings"]["page"]["loginScreen"] == login_screen, "the page to look")

    def test_needs_slates_login_screen(self):
        self.show(login_screen=False)
        self.assertEqual(self.waiting().get("Face on the login screen"), "Needs Slate's login screen to be installed")
        self.assertEqual(self.ipc("test", "settingsToggle", "Face on the login screen"), "none")

    def test_needs_the_method_set_up(self):
        self.show(login_screen=True, faces=())
        self.assertEqual(self.waiting().get("Face on the login screen"), "Needs your face to be added")

    def test_turning_it_on_and_off(self):
        self.show(login_screen=True)
        self.assertEqual(self.ipc("test", "settingsToggle", "Face on the login screen"), "pressed")
        self.wait(lambda st: "next login" in st["settings"]["page"]["said"], "it to say when")
        self.assertEqual(json.loads(self.pretend("unlockAsked")), ["login-enable", "face"])
        self.show(login_screen=True, login_methods=["face"])
        self.ipc("test", "settingsToggle", "Face on the login screen")
        self.wait(lambda st: st["settings"]["page"]["said"].startswith("Off"), "it to say it's off")
        self.assertEqual(json.loads(self.pretend("unlockAsked")), ["login-disable", "face"])
