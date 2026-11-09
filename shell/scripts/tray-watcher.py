#!/usr/bin/env python3
"""The tray's register (org.kde.StatusNotifierWatcher), kept apart from Slate.

Usage: tray-watcher.py

Apps with a tray icon (Mullvad, Spotify, Steam, Discord…) sign it up with this register, and
Slate's tray (the "host") asks it what's signed up. Quickshell can be the register itself,
but then it lives and dies with Slate: after Slate restarts it starts empty, and apps that
only sign up once, when they start (Electron and Chromium ones), lose their icons until
they're reopened. Run apart (Slate starts it, detached, and it keeps going), the register
outlives Slate's restarts, and Slate just reads it again.

One copy at a time (it holds org.slate.TrayWatcher too). If the register's name is taken (by
an older Slate that's still its own register), it waits its turn and takes over when that
lets go, at Slate's next restart. Items leave the list when their app goes. Needs PyGObject.
"""
import sys

try:
    import gi
    gi.require_version("Gio", "2.0")
    from gi.repository import Gio, GLib
except (ImportError, ValueError):
    sys.exit("tray-watcher: needs PyGObject (python-gobject / python3-gi); Slate's own register is used meanwhile")

NAME = "org.kde.StatusNotifierWatcher"
PATH = "/StatusNotifierWatcher"
LOCK = "org.slate.TrayWatcher"
XML = """
<node>
  <interface name="org.kde.StatusNotifierWatcher">
    <method name="RegisterStatusNotifierItem"><arg type="s" direction="in" name="service"/></method>
    <method name="RegisterStatusNotifierHost"><arg type="s" direction="in" name="service"/></method>
    <property name="RegisteredStatusNotifierItems" type="as" access="read"/>
    <property name="IsStatusNotifierHostRegistered" type="b" access="read"/>
    <property name="ProtocolVersion" type="i" access="read"/>
    <signal name="StatusNotifierItemRegistered"><arg type="s"/></signal>
    <signal name="StatusNotifierItemUnregistered"><arg type="s"/></signal>
    <signal name="StatusNotifierHostRegistered"/>
    <signal name="StatusNotifierHostUnregistered"/>
  </interface>
</node>
"""


class Watcher:
    def __init__(self, bus):
        self.bus = bus
        self.items = []        # "bus name/object path", in the order they signed up
        self.hosts = []        # hosts' bus names (Slate's tray)
        self.watches = {}      # bus name -> name watch id (to notice when an app goes)
        info = Gio.DBusNodeInfo.new_for_xml(XML).interfaces[0]
        bus.register_object(PATH, info, self.call, self.get, None)

    # ---- D-Bus ----------------------------------------------------------------------
    def call(self, bus, sender, path, iface, method, params, invocation):
        arg = params.unpack()[0]
        if method == "RegisterStatusNotifierItem":
            # Either a bus name (its item at the usual path) or an object path (on the sender)
            name, obj = (sender, arg) if arg.startswith("/") else (arg, "/StatusNotifierItem")
            item = name + obj
            if item not in self.items:
                self.items.append(item)
                self.follow(name)
                self.emit("StatusNotifierItemRegistered", GLib.Variant("(s)", (item,)))
                self.changed()
        elif method == "RegisterStatusNotifierHost":
            name = arg if not arg.startswith("/") else sender
            if name not in self.hosts:
                self.hosts.append(name)
                self.follow(name)
                self.emit("StatusNotifierHostRegistered", None)
                self.changed()
        invocation.return_value(None)

    def get(self, bus, sender, path, iface, prop):
        if prop == "RegisteredStatusNotifierItems":
            return GLib.Variant("as", self.items)
        if prop == "IsStatusNotifierHostRegistered":
            return GLib.Variant("b", bool(self.hosts))
        if prop == "ProtocolVersion":
            return GLib.Variant("i", 0)
        return None

    def emit(self, signal, params):
        self.bus.emit_signal(None, PATH, NAME, signal, params)

    def changed(self):
        props = {"RegisteredStatusNotifierItems": GLib.Variant("as", self.items),
                 "IsStatusNotifierHostRegistered": GLib.Variant("b", bool(self.hosts))}
        self.bus.emit_signal(None, PATH, "org.freedesktop.DBus.Properties", "PropertiesChanged",
                             GLib.Variant("(sa{sv}as)", (NAME, props, [])))

    # ---- Apps going away ----------------------------------------------------------------
    def follow(self, name):
        if name not in self.watches:
            self.watches[name] = Gio.bus_watch_name_on_connection(
                self.bus, name, Gio.BusNameWatcherFlags.NONE, None, self.gone)

    def gone(self, bus, name):
        Gio.bus_unwatch_name(self.watches.pop(name))
        for item in [i for i in self.items if i.startswith(name + "/")]:
            self.items.remove(item)
            self.emit("StatusNotifierItemUnregistered", GLib.Variant("(s)", (item,)))
        if name in self.hosts:
            self.hosts.remove(name)
            self.emit("StatusNotifierHostUnregistered", None)
        self.changed()


def main():
    try:
        bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    except GLib.Error as e:
        sys.exit("tray-watcher: no session bus (%s)" % e.message)
    # One copy: a second one goes straight away
    reply = bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "RequestName",
                          GLib.Variant("(su)", (LOCK, 4)), None, Gio.DBusCallFlags.NONE, -1, None)   # 4: DO_NOT_QUEUE
    if reply.unpack()[0] != 1:                                                                     # 1: primary owner
        return
    loop = GLib.MainLoop()
    Watcher(bus)
    # Waits in line if an older Slate is still its own register, and takes over when it lets go
    Gio.bus_own_name_on_connection(bus, NAME, Gio.BusNameOwnerFlags.NONE, None, None)
    loop.run()


if __name__ == "__main__":
    main()
