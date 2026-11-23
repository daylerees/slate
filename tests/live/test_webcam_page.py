"""Settings → Webcam's preview. It looked for WebcamPreview.qml next to the page, in
settings/pages/, since the pages moved into files of their own; the file is in Slate's own
folder, so the preview never loaded and the page said Qt Multimedia was missing, even with it
installed (a bug). The container has no camera: one is handed to the page (testPretend), and
the preview has nothing to show, but it loads."""
import json

from live import LiveCase

CAM = {"device": "/dev/video-test", "name": "Test camera", "key": "test", "controls": []}


class Preview(LiveCase):
    def setUp(self):
        super().setUp()
        self.addCleanup(lambda: self.ipc("settings", "close"))

    def page(self, want, what):
        return self.wait(lambda st: st["settings"]["page"] is not None and want(st["settings"]["page"]), what)["settings"]["page"]

    def test_the_preview_loads(self):
        self.ipc("settings", "page", "webcam")
        self.page(lambda p: "cams" in p, "the Webcam page")
        self.assertEqual(self.ipc("test", "settingsPagePretend", json.dumps({"cams": [CAM], "preview": True})), "done")
        p = self.page(lambda p: p["previewLoaded"] or p["previewFailed"], "the preview to load, or fail")
        self.assertFalse(p["previewFailed"], "the preview didn't load (it would say Qt Multimedia is missing)")
        self.assertTrue(p["previewLoaded"])
