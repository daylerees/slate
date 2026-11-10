"""scripts/tray-watcher.py: the tray's register, kept apart from Slate so tray icons outlive
Slate's restarts. Each test runs it on a private session bus (dbus-daemon), never yours."""
import os
import signal
import subprocess
import time
import unittest

import slate
from slate import Case, need, run

SCRIPT = slate.path("shell", "scripts", "tray-watcher.py")
WATCHER = ("org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher", "org.kde.StatusNotifierWatcher")

try:
    import gi
    gi.require_version("Gio", "2.0")
    from gi.repository import Gio, GLib
except (ImportError, ValueError):
    Gio = None

ITEM_XML = """<node><interface name="org.kde.StatusNotifierItem">
<property name="Id" type="s" access="read"/></interface></node>"""


class TrayWatcher(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        if Gio is None:
            self.skipTest("PyGObject isn't installed")
        need("dbus-daemon")
        # A private session bus for this test
        self.bus_proc = subprocess.Popen(["dbus-daemon", "--session", "--nofork", "--print-address"],
                                         stdout=subprocess.PIPE, text=True, env=self.h.env)
        self.addCleanup(self.bus_proc.kill)
        self.address = self.bus_proc.stdout.readline().strip()
        self.env = dict(self.h.env, DBUS_SESSION_BUS_ADDRESS=self.address)
        self.procs = []
        self.addCleanup(self.stop_all)

    def stop_all(self):
        for p in self.procs:
            if p.poll() is None:
                p.kill()

    def connect(self):
        """A new connection to the private bus (one per pretend app)."""
        c = Gio.DBusConnection.new_for_address_sync(
            self.address, Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION,
            None, None)
        self.addCleanup(lambda: c.is_closed() or c.close_sync(None))
        return c

    def start(self):
        p = subprocess.Popen(["python3", SCRIPT], env=self.env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.procs.append(p)
        return p

    def owner(self, conn, name):
        try:
            return conn.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
                                  "GetNameOwner", GLib.Variant("(s)", (name,)), None, 0, -1, None).unpack()[0]
        except GLib.Error:
            return None

    def wait(self, check, what, timeout=5):
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            v = check()
            if v:
                return v
            time.sleep(0.05)
        self.fail(f"timed out waiting for {what}")

    def prop(self, conn, name):
        return conn.call_sync(WATCHER[0], WATCHER[1], "org.freedesktop.DBus.Properties", "Get",
                              GLib.Variant("(ss)", (WATCHER[2], name)), None, 0, -1, None).unpack()[0]

    def call(self, conn, method, arg):
        conn.call_sync(WATCHER[0], WATCHER[1], WATCHER[2], method, GLib.Variant("(s)", (arg,)), None, 0, -1, None)

    def host(self):
        """A pretend Slate tray: it owns its host name, as Slate's does, then signs up."""
        h = self.connect()
        name = "org.kde.StatusNotifierHost-%d-1" % os.getpid()
        h.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "RequestName",
                    GLib.Variant("(su)", (name, 0)), None, 0, -1, None)
        self.call(h, "RegisterStatusNotifierHost", name)
        return h

    def running_watcher(self):
        c = self.connect()
        self.start()
        self.wait(lambda: self.owner(c, WATCHER[0]), "the register to start")
        return c

    # ---- the tests ------------------------------------------------------------------------
    def test_items_by_path_and_by_name(self):
        """An app signs up by object path (on its own connection) or by bus name (at the usual path)."""
        c = self.running_watcher()
        app1, app2 = self.connect(), self.connect()
        self.call(app1, "RegisterStatusNotifierItem", "/org/ayatana/NotificationItem/one")
        self.call(app2, "RegisterStatusNotifierItem", app2.get_unique_name())
        self.call(app1, "RegisterStatusNotifierItem", "/org/ayatana/NotificationItem/one")      # again: once only
        self.assertEqual(self.prop(c, "RegisteredStatusNotifierItems"),
                         [app1.get_unique_name() + "/org/ayatana/NotificationItem/one",
                          app2.get_unique_name() + "/StatusNotifierItem"])
        self.assertEqual(self.prop(c, "ProtocolVersion"), 0)

    def test_host_always_reported(self):
        """Apps are always told a tray is showing, even before Slate's signs up: Electron apps
        (Mullvad) check once, as they start, and if there's no tray yet they never show an icon.
        At login they started in the second before Slate's tray signed up, and lost theirs."""
        c = self.running_watcher()
        self.assertTrue(self.prop(c, "IsStatusNotifierHostRegistered"), "an app starting before Slate's tray gets no icon")
        self.host()
        self.assertTrue(self.prop(c, "IsStatusNotifierHostRegistered"))

    def test_app_leaving_removes_its_item(self):
        c = self.running_watcher()
        app, stays = self.connect(), self.connect()
        self.call(app, "RegisterStatusNotifierItem", "/item")
        self.call(stays, "RegisterStatusNotifierItem", "/item")
        app.close_sync(None)
        self.wait(lambda: self.prop(c, "RegisteredStatusNotifierItems") == [stays.get_unique_name() + "/item"],
                  "the closed app's item to go")

    def test_items_outlive_the_host(self):
        """The point of it: Slate (the host) going and coming back finds the icons still there."""
        c = self.running_watcher()
        app = self.connect()
        self.call(app, "RegisterStatusNotifierItem", "/item")
        host = self.host()
        self.assertTrue(self.prop(c, "IsStatusNotifierHostRegistered"))
        # Apps listening for the tray going away (some give up their icon when it does)
        gone = []
        c.signal_subscribe(WATCHER[0], WATCHER[2], "StatusNotifierHostUnregistered", WATCHER[1], None,
                           Gio.DBusSignalFlags.NONE, lambda *a: gone.append(a))
        host.close_sync(None)                     # Slate restarting
        end = time.monotonic() + 1
        while time.monotonic() < end:             # (let any signal arrive)
            GLib.MainContext.default().iteration(False)
            time.sleep(0.02)
        self.assertEqual(self.prop(c, "RegisteredStatusNotifierItems"), [app.get_unique_name() + "/item"])
        # Still a tray as far as apps can tell: one starting while Slate restarts gets its icon
        self.assertTrue(self.prop(c, "IsStatusNotifierHostRegistered"))
        self.assertEqual(gone, [], "told apps the tray went away")

    def test_one_copy(self):
        c = self.running_watcher()
        first = self.owner(c, WATCHER[0])
        second = self.start()
        self.assertEqual(second.wait(5), 0, "a second copy should just exit")
        self.assertEqual(self.owner(c, WATCHER[0]), first)

    def test_takes_over_when_slate_lets_go(self):
        """An older Slate holding the register itself: this waits in line, then takes over."""
        old = self.connect()
        old.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "RequestName",
                      GLib.Variant("(su)", (WATCHER[0], 0)), None, 0, -1, None)
        c = self.connect()
        self.start()
        time.sleep(0.5)
        self.assertEqual(self.owner(c, WATCHER[0]), old.get_unique_name(), "took the name from a running Slate")
        old.close_sync(None)                      # that Slate restarts
        self.wait(lambda: self.owner(c, WATCHER[0]) not in (None, old.get_unique_name()), "the register to take over")

    def test_no_session_bus(self):
        env = dict(self.h.env, DBUS_SESSION_BUS_ADDRESS="unix:path=/nonexistent")
        code, out = run(["python3", SCRIPT], env=env, timeout=10)
        self.assertEqual(code, 1)
        self.assertIn("no session bus", out)
