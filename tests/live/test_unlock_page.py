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
