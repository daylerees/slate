"""Screen recording, Slate's side (ScreenRecorder.qml; scripts/record.sh is tests/unit/
test_record.py): while the script's mark is there (written here as the script writes it, and
`record changed` as the script says), the menu bar's Screenshot button is the indicator, shown
even when it's turned off, red, counting the time; the Screenshot panel offers Stop instead of
the three ways to record. Nothing is really recorded."""
import os
import time

from live import LiveCase


class Recording(LiveCase):
    def mark(self):
        return os.path.join(self.s.h.runtime, "slate-recording")

    def recording(self, since):
        with open(self.mark(), "w") as f:
            f.write("%d\n%s\n%d\n" % (os.getpid(), "/tmp/a video.mp4", since))
        self.ipc("record", "changed")

    def stopped(self):
        if os.path.exists(self.mark()):
            os.remove(self.mark())
        self.ipc("record", "changed")

    def test_the_bar_shows_it_and_the_time(self):
        self.addCleanup(self.stopped)
        self.keep_setting("barShowScreenshot")
        self.config("barShowScreenshot", "false")
        self.wait(lambda st: not st["bars"][0]["shot"]["shown"], "the Screenshot button off")
        self.recording(int(time.time()) - 65)
        st = self.wait(lambda st: st["recording"]["on"] and st["bars"][0]["shot"]["shown"], "the indicator on the bar")
        self.assertTrue(st["bars"][0]["shot"]["recording"], "not the red recording dot")
        self.wait(lambda st: st["bars"][0]["shot"]["label"] in ("1:05", "1:06", "1:07"), "how long it's been")
        self.assertEqual(st["recording"]["file"], "/tmp/a video.mp4")
        self.stopped()
        st = self.wait(lambda st: not st["recording"]["on"] and not st["bars"][0]["shot"]["shown"], "the indicator gone")
        self.assertEqual(st["bars"][0]["shot"]["label"], "")

    def test_start_goes_through_slate(self):
        before = self.s.state()["recording"]["started"]
        self.ipc("record", "start", "screen")
        self.wait(lambda st: st["recording"]["started"] == before + 1, "record start reaching Slate")
