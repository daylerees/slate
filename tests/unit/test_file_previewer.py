"""scripts/file-previewer.py: Space in Nautilus or Nemo shows the file in Slate's Quick Look. On
a session bus of its own (a private dbus-daemon), with stand-in file managers on PATH: the
helper takes the previewers' names only where nothing else would answer to them (GNOME Sushi,
nemo-preview), and turns the file managers' calls into lines for Slate, and Slate's lines into
what Nautilus listens for."""
import json
import os
import subprocess
import sys
import time
import unittest

import slate
from slate import Case
from stubs import Stubs

SCRIPT = slate.path("shell", "scripts", "file-previewer.py")
CONFIG = """<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>session</type>
  <listen>unix:dir=%s</listen>
  <servicedir>%s</servicedir>
  <policy context="default">
    <allow send_destination="*" eavesdrop="true"/>
    <allow eavesdrop="true"/>
    <allow own="*"/>
  </policy>
</busconfig>
"""

try:
    import gi
    gi.require_version("Gio", "2.0")
    from gi.repository import Gio, GLib
except (ImportError, ValueError):
    Gio = None


@unittest.skipIf(Gio is None, "PyGObject isn't installed")
class FilePreviewer(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        if not any(os.access(os.path.join(d, "dbus-daemon"), os.X_OK) for d in os.environ.get("PATH", "").split(":")):
            self.skipTest("no dbus-daemon")
        self.services = os.path.join(self.h.dir, "services")
        os.makedirs(self.services)
        conf = os.path.join(self.h.dir, "bus.conf")
        with open(conf, "w") as f:
            f.write(CONFIG % (self.h.runtime, self.services))
        self.daemon = subprocess.Popen(["dbus-daemon", "--config-file=" + conf, "--print-address", "--nofork"],
                                       stdout=subprocess.PIPE, text=True)
        self.addCleanup(self.daemon.kill)
        self.address = self.daemon.stdout.readline().strip()
        self.bus = Gio.DBusConnection.new_for_address_sync(
            self.address, Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION, None, None)
        self.addCleanup(self.bus.close_sync, None)
        self.s = Stubs(self.h)

    def start(self, *apps):
        for a in apps:
            self.s.add(a)
        env = dict(self.s.env, PATH=self.s.dir, DBUS_SESSION_BUS_ADDRESS=self.address)
        p = subprocess.Popen([sys.executable, SCRIPT], env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
        self.addCleanup(lambda: (p.kill(), p.wait()))
        return p

    def line(self, p):
        return json.loads(p.stdout.readline())

    def call(self, name, path, iface, method, args):
        self.bus.call_sync(name, path, iface, method, args, None, Gio.DBusCallFlags.NONE, 3000, None)

    def nautilus_show(self, uri, close_if_shown=False):
        self.call("org.gnome.NautilusPreviewer", "/org/gnome/NautilusPreviewer", "org.gnome.NautilusPreviewer2", "ShowFile",
                  GLib.Variant("(ssbs)", (uri, "", close_if_shown, "")))

    def test_nautilus_and_nemo(self):
        p = self.start("nautilus", "nemo")
        self.assertEqual(self.line(p), {"ready": ["org.gnome.NautilusPreviewer", "org.nemo.Preview"]})
        path = "/home/me/My Pictures/a #1.png"
        self.nautilus_show(Gio.File.new_for_path(path).get_uri())
        self.assertEqual(self.line(p), {"show": path, "from": "nautilus"})
        self.call("org.nemo.Preview", "/org/nemo/Preview", "org.nemo.Preview", "ShowFile",
                  GLib.Variant("(sib)", (Gio.File.new_for_path("/tmp/b.txt").get_uri(), 0, False)))
        self.assertEqual(self.line(p), {"show": "/tmp/b.txt", "from": "nemo"})
        self.call("org.gnome.NautilusPreviewer", "/org/gnome/NautilusPreviewer", "org.gnome.NautilusPreviewer2", "Close", None)
        self.assertEqual(self.line(p), {"close": True})

    def test_space_again_closes_it(self):
        """Nautilus asks to close it if it's showing that file (Space a second time)."""
        p = self.start("nautilus")
        self.line(p)
        uri = Gio.File.new_for_path("/tmp/c.pdf").get_uri()
        self.nautilus_show(uri, True)
        self.assertEqual(self.line(p), {"show": "/tmp/c.pdf", "from": "nautilus"})
        p.stdin.write("visible 1\n")
        p.stdin.flush()
        time.sleep(0.3)
        visible = self.bus.call_sync("org.gnome.NautilusPreviewer", "/org/gnome/NautilusPreviewer", "org.freedesktop.DBus.Properties",
                                     "Get", GLib.Variant("(ss)", ("org.gnome.NautilusPreviewer2", "Visible")),
                                     None, Gio.DBusCallFlags.NONE, 3000, None).unpack()[0]
        self.assertTrue(visible)
        self.nautilus_show(uri, True)
        self.assertEqual(self.line(p), {"close": True})

    def test_left_and_right_move_nautilus_selection(self):
        p = self.start("nautilus")
        self.line(p)
        got = []
        self.bus.signal_subscribe(None, "org.gnome.NautilusPreviewer2", "SelectionEvent", "/org/gnome/NautilusPreviewer",
                                  None, Gio.DBusSignalFlags.NONE, lambda *a: got.append(a[5].unpack()[0]))
        p.stdin.write("select right\nselect left\n")
        p.stdin.flush()
        ctx, end = GLib.MainContext.default(), time.time() + 5
        while len(got) < 2 and time.time() < end:
            ctx.iteration(False)
            time.sleep(0.02)
        self.assertEqual(got, [5, 4], "GTK's right and left")

    def test_sushi_installed_is_left_alone(self):
        with open(os.path.join(self.services, "org.gnome.NautilusPreviewer.service"), "w") as f:
            f.write("[D-BUS Service]\nName=org.gnome.NautilusPreviewer\nExec=/nonexistent/sushi\n")
        p = self.start("nautilus", "nemo")
        self.assertEqual(self.line(p), {"ready": ["org.nemo.Preview"]})

    def test_nothing_without_the_file_managers(self):
        p = self.start()
        self.assertEqual(p.wait(timeout=10), 0)
        self.assertEqual(p.stdout.read(), "")

    def test_ends_with_slate(self):
        p = self.start("nautilus")
        self.line(p)
        p.stdin.close()
        self.assertEqual(p.wait(timeout=10), 0)
