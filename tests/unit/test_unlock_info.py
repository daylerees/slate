"""scripts/unlock-info.py: what Settings → Face, Fingerprint & Keys shows, as you: whether Howdy is
installed, the cameras and which are infrared, and the ways in the lock screen takes now. Run
against a scratch /dev, /sys and /etc (SLATE_UNLOCK_TEST), with the cameras' formats stood in for."""
import importlib.util
import json
import os
import sys

import slate
from slate import Case, run

SCRIPT = slate.path("shell", "scripts", "unlock-info.py")


def load(root):
    os.environ["SLATE_UNLOCK_TEST"] = root
    try:
        spec = importlib.util.spec_from_file_location("slate_unlock_info", SCRIPT)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
    finally:
        del os.environ["SLATE_UNLOCK_TEST"]
    return mod


class UnlockInfo(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        self.root = self.h.dir
        self.mod = load(self.root)

    def put(self, path, text=""):
        p = self.root + path
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w") as f:
            f.write(text)
        return p

    def camera(self, n, name, by_id=None):
        dev = self.put(f"/dev/video{n}")
        self.put(f"/sys/class/video4linux/video{n}/name", name + "\n")
        if by_id:
            os.makedirs(self.root + "/dev/v4l/by-id", exist_ok=True)
            os.symlink(dev, self.root + "/dev/v4l/by-id/" + by_id)

    def test_infrared_told_from_colour(self):
        """A webcam with Windows Hello (a Logitech BRIO, say) is several devices: colour, infrared,
        and metadata nodes with no picture at all. Only the first two are cameras, by their
        stable names, and only the greyscale one is infrared."""
        self.camera(0, "Logitech BRIO", "usb-BRIO-video-index0")
        self.camera(1, "Logitech BRIO", "usb-BRIO-video-index1")
        self.camera(2, "Logitech BRIO", "usb-BRIO-video-index2")
        self.camera(3, "Logitech BRIO", "usb-BRIO-video-index3")
        fmts = {"video0": [b"YUYV", b"MJPG", b"NV12"], "video1": [], "video2": [b"GREY"], "video3": []}
        got = self.mod.cameras(lambda d: fmts[os.path.basename(d)])
        self.assertEqual(got, [
            {"path": "/dev/v4l/by-id/usb-BRIO-video-index0", "name": "Logitech BRIO", "ir": False},
            {"path": "/dev/v4l/by-id/usb-BRIO-video-index2", "name": "Logitech BRIO", "ir": True}])

    def test_without_a_stable_name(self):
        self.camera(0, "Laptop Camera")
        self.assertEqual(self.mod.cameras(lambda d: [b"YUYV"]), [{"path": "/dev/video0", "name": "Laptop Camera", "ir": False}])

    def test_ir_only_when_all_greyscale(self):
        self.assertTrue(self.mod.is_ir([b"GREY"]))
        self.assertTrue(self.mod.is_ir([b"Y16 ", b"GREY"]))
        self.assertFalse(self.mod.is_ir([b"GREY", b"YUYV"]))
        self.assertFalse(self.mod.is_ir([]))

    def test_howdy_needs_its_pam_module_and_command(self):
        self.assertFalse(self.mod.howdy())
        self.put("/usr/lib/security/pam_howdy.so")
        self.assertFalse(self.mod.howdy(), "the PAM module alone")
        self.put("/usr/bin/howdy")
        self.assertTrue(self.mod.howdy())

    def test_methods_from_slate_lock(self):
        self.assertEqual(self.mod.methods(), [])
        self.put("/etc/pam.d/slate-lock", "#%PAM-1.0\n# slate-unlock: face\nauth sufficient pam_howdy.so\n"
                                          "# slate-unlock: key\nauth sufficient pam_u2f.so\nauth required pam_deny.so\n")
        self.assertEqual(self.mod.methods(), ["face", "key"])

    def test_json_with_nothing_here(self):
        code, out = run([sys.executable, SCRIPT], env=dict(os.environ, SLATE_UNLOCK_TEST=self.root))
        self.assertEqual(code, 0, out)
        self.assertEqual(json.loads(out), {"howdy": False, "cameras": [], "methods": []})
