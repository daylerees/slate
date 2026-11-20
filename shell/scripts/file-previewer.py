#!/usr/bin/env python3
"""Space in Nautilus or Nemo shows the file in Slate's Quick Look. Both ask a previewer on the
session bus to show the selected file: Nautilus GNOME Sushi (org.gnome.NautilusPreviewer,
interface org.gnome.NautilusPreviewer2), Nemo nemo-preview (org.nemo.Preview). Where that
previewer isn't installed (nothing can be started under its name) and nothing owns the name,
this takes the name and passes the files on to Slate. With the real one installed, it's left
to do its job.

    file-previewer.py          started by Slate (shell.qml), which reads and writes its lines

To Slate, a line of JSON each:   {"show": "<path>", "from": "nautilus"|"nemo"}   {"close": true}
From Slate, a line each:         visible 0|1     Quick Look shown or hidden
                                 select left|right   Left/Right in Quick Look: Nautilus moves
                                                 its selection, and asks for the next file
Exits when Slate does (its stdin closes), and at once when neither file manager is installed,
there's no session bus, or every name is taken."""
import json
import os
import shutil
import sys
import time

NAUTILUS = ("org.gnome.NautilusPreviewer", "/org/gnome/NautilusPreviewer", """
<node>
  <interface name="org.gnome.NautilusPreviewer2">
    <method name="ShowFile">
      <arg type="s" direction="in" name="uri"/>
      <arg type="s" direction="in" name="windowHandle"/>
      <arg type="b" direction="in" name="closeIfAlreadyShown"/>
      <arg type="s" direction="in" name="activationToken"/>
    </method>
    <method name="Close"/>
    <property name="ParentHandle" type="s" access="read"/>
    <property name="Visible" type="b" access="read"/>
    <signal name="SelectionEvent"><arg type="u" name="direction"/></signal>
  </interface>
</node>""")
NEMO = ("org.nemo.Preview", "/org/nemo/Preview", """
<node>
  <interface name="org.nemo.Preview">
    <method name="ShowFile">
      <arg type="s" direction="in" name="uri"/>
      <arg type="i" direction="in" name="xid"/>
      <arg type="b" direction="in" name="closeIfAlreadyShown"/>
    </method>
    <method name="Close"/>
  </interface>
</node>""")
# GTK's direction for a selection moved (GtkDirectionType: left 4, right 5)
DIRECTIONS = {"left": 4, "right": 5}


def say(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


class Previewer:
    """The state both names share: what's showing, and the connection to tell Nautilus with."""

    def __init__(self, bus):
        self.bus = bus
        self.visible = False
        self.path = ""
        self.owned = []          # (name, path, interface name) taken

    def path_of(self, uri):
        from gi.repository import Gio
        try:
            return Gio.File.new_for_uri(uri).get_path() or ""
        except Exception:
            return ""

    def show(self, uri, close_if_shown, who):
        p = self.path_of(uri)
        if not p:
            return
        if close_if_shown and self.visible and p == self.path:
            say({"close": True})
            return
        self.path = p
        say({"show": p, "from": who})

    def call(self, who):
        def handler(conn, sender, path, iface, method, params, invocation):
            args = params.unpack()
            if method == "ShowFile":
                self.show(args[0], bool(args[2]), who)
            elif method == "Close":
                say({"close": True})
            invocation.return_value(None)
        return handler

    def get(self, conn, sender, path, iface, prop):
        from gi.repository import GLib
        if prop == "Visible":
            return GLib.Variant("b", self.visible)
        if prop == "ParentHandle":
            return GLib.Variant("s", "")
        return None

    def heard(self, line):
        """A line from Slate."""
        from gi.repository import GLib
        word, _, arg = line.strip().partition(" ")
        nautilus = next((o for o in self.owned if o[0] == NAUTILUS[0]), None)
        if word == "visible":
            self.visible = arg == "1"
            if not self.visible:
                self.path = ""
            if nautilus:
                self.bus.emit_signal(None, nautilus[1], "org.freedesktop.DBus.Properties", "PropertiesChanged",
                                     GLib.Variant("(sa{sv}as)", (nautilus[2], {"Visible": GLib.Variant("b", self.visible)}, [])))
        elif word == "select" and arg in DIRECTIONS and nautilus:
            self.bus.emit_signal(None, nautilus[1], nautilus[2], "SelectionEvent", GLib.Variant("(u)", (DIRECTIONS[arg],)))


def free(bus, name):
    """Nothing owns the name, and nothing would be started for it (Sushi, nemo-preview)."""
    from gi.repository import Gio, GLib

    def ask(method, args, kind):
        return bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", method,
                             args, GLib.VariantType(kind), Gio.DBusCallFlags.NONE, 2000, None).unpack()[0]
    if ask("NameHasOwner", GLib.Variant("(s)", (name,)), "(b)"):
        return False
    return name not in ask("ListActivatableNames", None, "(as)")


def main():
    wanted = [(NAUTILUS, "nautilus")] if shutil.which("nautilus") else []
    wanted += [(NEMO, "nemo")] if shutil.which("nemo") else []
    if not wanted:
        return 0
    try:
        import gi
        gi.require_version("Gio", "2.0")
        from gi.repository import Gio, GLib
        bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    except Exception as e:
        print("file-previewer: no session bus (%s)" % e, file=sys.stderr)
        return 0
    pv = Previewer(bus)
    # Asking for a name is answered later, by the bus: ready is said only once each is ours (or
    # known to be someone else's), or a file manager asking straight after could find nobody there
    settled = {}
    for (name, path, xml), who in wanted:
        try:
            if not free(bus, name):
                continue
            iface = Gio.DBusNodeInfo.new_for_xml(xml).interfaces[0]
            bus.register_object(path, iface, pv.call(who), pv.get, None)
            Gio.bus_own_name_on_connection(bus, name, Gio.BusNameOwnerFlags.DO_NOT_QUEUE,
                                           lambda c, n: settled.__setitem__(n, True),
                                           lambda c, n: settled.__setitem__(n, False))
            pv.owned.append((name, path, iface.name))
        except Exception as e:
            print("file-previewer: %s: %s" % (name, e), file=sys.stderr)
    context, until = GLib.MainContext.default(), time.monotonic() + 3
    while len(settled) < len(pv.owned) and time.monotonic() < until:
        context.iteration(False) or time.sleep(0.01)
    pv.owned = [o for o in pv.owned if settled.get(o[0])]
    if not pv.owned:
        return 0
    say({"ready": [o[0] for o in pv.owned]})
    loop = GLib.MainLoop()

    pending = [b""]

    def readable(fd, cond):
        # (read from the descriptor itself: a buffered readline could hold back a line the
        # watch would never be told about)
        chunk = os.read(fd, 4096)
        if not chunk:                  # (Slate's gone)
            loop.quit()
            return False
        *lines, pending[0] = (pending[0] + chunk).split(b"\n")
        for line in lines:
            pv.heard(line.decode("utf-8", "replace"))
        return True
    GLib.io_add_watch(sys.stdin.fileno(), GLib.IO_IN | GLib.IO_HUP, readable)
    loop.run()
    return 0


if __name__ == "__main__":
    sys.exit(main())
