"""Settings → Storage's warning (StorageWatch.qml): a drive nearly full is said once, not again
while it stays short, and again only after it's had room. Drives are pretended
(`storage testDrives`); the page itself is in the visual scenes."""
import json

from live import LiveCase

GB = 1_000_000_000


def drive(free, size=500 * GB, name="This computer", mount="/", removable=False):
    return {"mount": mount, "name": name, "size": size, "free": free, "used": size - free, "removable": removable}


class StorageWarning(LiveCase):
    def tell(self, *drives):
        self.ipc("storage", "testDrives", " " + json.dumps(list(drives)))     # (a space first: qs ipc and "[")

    def test_once_until_it_has_room_again(self):
        self.tell(drive(200 * GB))
        st = self.s.state()["storage"]
        self.assertEqual(st["warned"], [])
        self.tell(drive(20 * GB))                       # under a tenth
        st = self.wait(lambda st: st["storage"]["warned"] == ["/"], "the warning")["storage"]
        self.assertEqual(st["said"], "This computer")
        checks = st["checks"]
        self.ipc("storage", "testDrives", " " + json.dumps([drive(18 * GB)]))
        self.wait(lambda st: st["storage"]["checks"] > checks, "the next check")
        self.assertEqual(self.s.state()["storage"]["warned"], ["/"], "said again while still short")
        self.tell(drive(100 * GB))                      # room again
        self.wait(lambda st: st["storage"]["warned"] == [], "forgotten once there's room")

    def test_not_for_a_card_or_stick(self):
        self.tell(drive(1 * GB, size=64 * GB, name="Photo Card", mount="/run/media/me/Photo Card", removable=True))
        self.s.settle(0.3)
        self.assertEqual(self.s.state()["storage"]["warned"], [], "warned about a removable drive")
