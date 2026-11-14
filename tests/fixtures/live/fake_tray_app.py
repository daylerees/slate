"""A pretend tray app (as Electron apps do it): signs its icon up with the register once, at
start, and never again. For tests/live/test_tray.py (and test_bar.py's label, which gives it an
id and a title of its own: fake_tray_app.py [id [title]])."""
import sys
import gi; gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib
XML = """<node><interface name="org.kde.StatusNotifierItem">
<property name="Id" type="s" access="read"/><property name="Title" type="s" access="read"/>
<property name="IconName" type="s" access="read"/><property name="Status" type="s" access="read"/>
<property name="Category" type="s" access="read"/></interface></node>"""
ID = sys.argv[1] if len(sys.argv) > 1 else "fake"
TITLE = sys.argv[2] if len(sys.argv) > 2 else "Fake tray app"
P = "/org/ayatana/NotificationItem/" + ID
vals = {"Id": ID, "Title": TITLE, "IconName": "mail-unread", "Status": "Active", "Category": "ApplicationStatus"}
bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
bus.register_object(P, Gio.DBusNodeInfo.new_for_xml(XML).interfaces[0], None, lambda *a: GLib.Variant("s", vals[a[4]]), None)
bus.call_sync("org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher", "org.kde.StatusNotifierWatcher",
              "RegisterStatusNotifierItem", GLib.Variant("(s)", (P,)), None, 0, -1, None)
print("registered", flush=True)
GLib.MainLoop().run()
