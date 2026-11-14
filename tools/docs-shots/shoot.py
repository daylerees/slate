#!/usr/bin/env python3
"""Takes the pictures on the docs pages (site/docs/img/), in the test container: a real Slate
session like the visual tier's, set up the way Slate looks out of the box (dark, its own accent,
flat), with harmless pretend apps, files and notifications. See README.md beside this file.

    tests/run --docs-shots              every picture
    tests/run --docs-shots dock-menu    just these (names from scenes.py)
    python3 tools/docs-shots/shoot.py --recrop [name…]   crop the last whole screens again, after
                                        changing a crop (no container, nothing re-shot)

Not a test: nothing is compared. Each picture is taken at twice the size (the screen is 1440×900
at a scale of 2), cropped to what it explains, and saved as WebP in site/docs/img/<name>.webp;
the whole screen is kept in tests/out/docs-shots/<name>.png to look at.
"""
import json
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path[:0] = [os.path.join(ROOT, "tests", "lib"), HERE]

import slate  # noqa: E402
from session import Session, SessionError, in_container  # noqa: E402
from PIL import Image  # noqa: E402

import scenes  # noqa: E402

SCALE = 2                       # pictures at twice the size, for sharp screens
IMG = slate.path("site", "docs", "img")
RAW = os.path.join(slate.OUT, "docs-shots")
# One of Slate's own (shell/wallpapers), in its default accent's blues, without the logo (it sat
# behind the panels and the lock screen's picture)
WALLPAPER = "slate-cobalt-plain.png"


class DocsSession(Session):
    """The visual tier's session, at a scale of 2, with Slate's default look and pretend things
    to show: apps, windows' contents, downloads, saved spaces, speakers."""

    def _prepare(self):
        super()._prepare()
        h = self.h
        hypr = os.path.join(self.slate_dir, "hypr")
        # The same screen, drawn at twice the pixels
        with open(os.path.join(hypr, "monitors.lua"), encoding="utf-8") as f:
            text = f.read()
        text = text.replace(f'mode = "{self.width}x{self.height}@60", position = "0x0", scale = 1',
                            f'mode = "{self.width * SCALE}x{self.height * SCALE}@60", position = "0x0", scale = {SCALE}')
        self._write(os.path.join(hypr, "monitors.lua"), text)
        # Slate as it comes: every look setting at its default (dark, Slate's accent, flat), the
        # Welcome window seen, nothing that would interrupt
        settings = {"welcomeShown": True, "updateCheck": False, "themeMode": "dark", "lightMode": False,
                    "glass": False, "accent": "#8fb3e8", "accentFromWallpaper": False,
                    "screensaverMinutes": 0, "idleLockMinutes": 0, "idleScreenOffMinutes": 0, "idleSuspendMinutes": 0,
                    "wallpaper": os.path.join(self.slate_dir, "wallpapers", WALLPAPER)}
        self._write(os.path.join(self.slate_dir, "settings.json"), json.dumps(settings, indent=2))
        os.remove(h("Pictures", "wallpaper.png"))      # (the visual tier's own, unused here)
        # Pretend apps (each a terminal underneath, with an app id of its own), and the
        # container's own apps hidden from the launcher
        apps = h.data + "/applications"
        os.makedirs(apps, exist_ok=True)
        for app_id, name, icon, comment, cats in scenes.APPS:
            self._write(os.path.join(apps, app_id + ".desktop"),
                        "[Desktop Entry]\nType=Application\n"
                        f"Name={name}\nComment={comment}\nIcon={icon}\nCategories={cats}\n"
                        f"Exec=foot --app-id {app_id}\nStartupWMClass={app_id}\n")
        for d in ("/usr/share/applications", "/usr/local/share/applications"):
            for n in (os.listdir(d) if os.path.isdir(d) else []):
                if n.endswith(".desktop") and n not in scenes.KEEP_APPS:
                    self._write(os.path.join(apps, n), "[Desktop Entry]\nType=Application\nName=-\nHidden=true\n")
        self._write(h(".local", "state", "slate", "dock.json"), json.dumps({"pinned": scenes.PINNED}))
        # The pretend apps' windows (terminals) with room round their text
        self._write(h(".config", "foot", "foot.ini"), "pad=18x14\n")
        # Downloads, and two saved spaces
        for name, make in scenes.DOWNLOADS:
            make(h("Downloads", name), self.slate_dir)
        self._write(os.path.join(h.data, "slate", "spaces.json"), json.dumps({"spaces": scenes.SPACES}, indent=1))
        self.sound()

    def sound(self):
        """Speakers and a microphone: PipeWire with a pretend output and input, started before
        Slate is (without them the bar's volume says 0%)."""
        self._sound = []
        for cmd in (["pipewire"], ["wireplumber"]):
            self._sound.append(subprocess.Popen(cmd, env=self.env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                                start_new_session=True))
            time.sleep(1.0)
        for kind, name, desc in (("Audio/Sink", "docs-speakers", "Speakers"),
                                 ("Audio/Source/Virtual", "docs-mic", "Microphone")):
            self.run(["pw-cli", "create-node", "adapter",
                      "{ factory.name=support.null-audio-sink node.name=%s node.description=\"%s\" "
                      "media.class=%s object.linger=true audio.position=[FL FR] }" % (name, desc, kind)])
        time.sleep(1.0)
        self.run(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "0.6"])

    def stop(self):
        for p in getattr(self, "_sound", []):
            try:
                os.killpg(p.pid, 15)
            except OSError:
                pass
        super().stop()


def run_steps(s, name, steps, background):
    for step in steps:
        if callable(step):
            s.wait(step, timeout=15, what=f"the {name} picture, part way")
        elif step[0].startswith("!"):
            s.run([step[0][1:]] + list(step[1:]), check=True)
        elif step[0].startswith("&"):
            background.append(subprocess.Popen([step[0][1:]] + list(step[1:]), env=s.env,
                                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
        else:
            s.ipc(*step)


def shoot(s, name, scene):
    """Put Slate in the scene's state, take the picture, crop and save it; then undo it all."""
    s.ipc("notifications", "clear")
    s.wait(lambda st: st["notifications"]["toasts"] == 0, what="the pop-ups to go")
    old, background = {}, []
    try:
        for k, v in scene.get("settings", {}).items():
            old[k] = s.ipc("config", "get", k)
            s.ipc("config", "set", k, v)
        run_steps(s, name, scene.get("do", []), background)
        s.wait(scene.get("wait", lambda st: True), timeout=15, what=f"the {name} picture")
        s.wait(lambda st: not st["icons"]["busy"], timeout=15, what=f"the {name} picture's app icons")
        s.settle(scene.get("settle", 1.0))
        raw = s.screenshot(os.path.join(RAW, name + ".png"))
    finally:
        undo = scene.get("undo", [])
        for step in undo:
            if callable(step):
                continue
            try:
                if step[0].startswith("!"):
                    s.run([step[0][1:]] + list(step[1:]))
                else:
                    s.ipc(*step)
            except SessionError:
                pass
        for p in background:
            p.terminate()
            try:
                p.wait(timeout=3)
            except subprocess.TimeoutExpired:
                p.kill()
        for step in undo:
            if callable(step):
                s.wait(step, timeout=15, what=f"the {name} picture to be undone")
        for k, v in old.items():
            s.ipc("config", "set", k, v)
        if old:
            s.settle(0.8)
    return save(name, scene, raw)


def save(name, scene, raw):
    """The whole screen cropped to the scene's part, as site/docs/img/<name>.webp."""
    img = Image.open(raw).convert("RGB")
    x, y, w, h = scene.get("crop", (0, 0, img.width // SCALE, img.height // SCALE))
    img = img.crop((x * SCALE, y * SCALE, (x + w) * SCALE, (y + h) * SCALE))
    out = os.path.join(IMG, name + ".webp")
    # (lossy, but at a quality where text and edges stay clean: a fraction of a lossless file's size)
    img.save(out, "WEBP", quality=88, method=6)
    return out, img.size


def recrop(names):
    for name in names or list(scenes.SHOTS):
        raw = os.path.join(RAW, name + ".png")
        if not os.path.exists(raw):
            print(f"  {name}: no whole screen in {os.path.relpath(RAW, ROOT)} (take it with tests/run --docs-shots {name})")
            continue
        out, size = save(name, scenes.SHOTS[name], raw)
        print(f"  {name}: {size[0]}×{size[1]}, {os.path.getsize(out) // 1024} KB")


def main(argv):
    if argv[:1] == ["--recrop"]:
        return recrop(argv[1:])
    if not in_container():
        sys.exit("docs-shots: run it through tests/run --docs-shots (it needs the test container)")
    want = argv or list(scenes.SHOTS)
    unknown = [n for n in want if n not in scenes.SHOTS]
    if unknown:
        sys.exit("docs-shots: no such picture: " + ", ".join(unknown) + " (see tools/docs-shots/scenes.py)")
    os.makedirs(IMG, exist_ok=True)
    os.makedirs(RAW, exist_ok=True)
    s = DocsSession()
    try:
        s.start()
        s.settle(4)             # the bar's segments and fonts settle before the first picture
        # (the clock laid out again, now Slate's font is there: as the visual tier does)
        s.ipc("config", "set", "barClockDate", "false")
        s.settle(0.5)
        s.ipc("config", "set", "barClockDate", "true")
        s.settle(1.5)
        failed = []
        for name in want:
            try:
                out, size = shoot(s, name, scenes.SHOTS[name])
                print(f"  {name}: {size[0]}×{size[1]}, {os.path.getsize(out) // 1024} KB", flush=True)
            except (AssertionError, SessionError) as e:
                failed.append(name)
                print(f"  {name}: FAILED: {str(e)[:300]}", flush=True)
                s.reset()
        errors = s.new_log_errors()
        if errors:
            print(f"Slate logged {len(errors)} error(s) meanwhile, the first: {errors[0][:200]}")
        print(f"{len(want) - len(failed)} of {len(want)} pictures in site/docs/img (whole screens: tests/out/docs-shots)")
        return 1 if failed else 0
    finally:
        s.stop()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
