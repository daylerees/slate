#!/usr/bin/env python3
"""A pretend media player for the live tests: an MPRIS player on the session bus with one
track playing, so the dock and the control centre have something to show (the test session
has no real player). Runs until it's stopped.

    fake_mpris.py [--title T] [--artist A] [--paused] [--art FILE] [--still]

--art gives the track a cover (a picture file); --still keeps its position where it is
(a Rate of 0, so nothing works out that time has passed), for a screenshot that's the same
every time. Prints "ready" once its name is on the bus."""
import argparse
import os
import sys

from gi.repository import Gio, GLib

NAME = "org.mpris.MediaPlayer2.slatetest"
PATH = "/org/mpris/MediaPlayer2"

XML = """
<node>
  <interface name="org.mpris.MediaPlayer2">
    <method name="Raise"/>
    <method name="Quit"/>
    <property name="CanQuit" type="b" access="read"/>
    <property name="CanRaise" type="b" access="read"/>
    <property name="HasTrackList" type="b" access="read"/>
    <property name="Identity" type="s" access="read"/>
    <property name="DesktopEntry" type="s" access="read"/>
    <property name="SupportedUriSchemes" type="as" access="read"/>
    <property name="SupportedMimeTypes" type="as" access="read"/>
  </interface>
  <interface name="org.mpris.MediaPlayer2.Player">
    <method name="Next"/>
    <method name="Previous"/>
    <method name="Pause"/>
    <method name="PlayPause"/>
    <method name="Stop"/>
    <method name="Play"/>
    <method name="Seek"><arg direction="in" name="Offset" type="x"/></method>
    <method name="SetPosition">
      <arg direction="in" name="TrackId" type="o"/><arg direction="in" name="Position" type="x"/>
    </method>
    <property name="PlaybackStatus" type="s" access="read"/>
    <property name="Rate" type="d" access="readwrite"/>
    <property name="Metadata" type="a{sv}" access="read"/>
    <property name="Volume" type="d" access="readwrite"/>
    <property name="Position" type="x" access="read"/>
    <property name="MinimumRate" type="d" access="read"/>
    <property name="MaximumRate" type="d" access="read"/>
    <property name="CanGoNext" type="b" access="read"/>
    <property name="CanGoPrevious" type="b" access="read"/>
    <property name="CanPlay" type="b" access="read"/>
    <property name="CanPause" type="b" access="read"/>
    <property name="CanSeek" type="b" access="read"/>
    <property name="CanControl" type="b" access="read"/>
  </interface>
</node>
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--title", default="Slow Tide")
    ap.add_argument("--artist", default="The Quiet Hours")
    ap.add_argument("--paused", action="store_true")
    ap.add_argument("--art", help="a picture file for the track's cover")
    ap.add_argument("--still", action="store_true", help="the position doesn't move (Rate 0)")
    args = ap.parse_args()

    state = {"status": "Paused" if args.paused else "Playing"}
    metadata = {
        "mpris:trackid": GLib.Variant("o", "/org/slate/track/1"),
        "mpris:length": GLib.Variant("x", 214_000_000),
        "xesam:title": GLib.Variant("s", args.title),
        "xesam:artist": GLib.Variant("as", [args.artist]),
        "xesam:album": GLib.Variant("s", "Test Pressing"),
    }
    if args.art:
        metadata["mpris:artUrl"] = GLib.Variant("s", "file://" + os.path.abspath(args.art))
    rate = 0.0 if args.still else 1.0
    props = {
        "org.mpris.MediaPlayer2": {
            "CanQuit": GLib.Variant("b", False), "CanRaise": GLib.Variant("b", False),
            "HasTrackList": GLib.Variant("b", False), "Identity": GLib.Variant("s", "Slate Test Player"),
            "DesktopEntry": GLib.Variant("s", ""), "SupportedUriSchemes": GLib.Variant("as", []),
            "SupportedMimeTypes": GLib.Variant("as", []),
        },
        "org.mpris.MediaPlayer2.Player": {
            "Rate": GLib.Variant("d", rate), "Metadata": GLib.Variant("a{sv}", metadata),
            "Volume": GLib.Variant("d", 1.0), "Position": GLib.Variant("x", 30_000_000),
            "MinimumRate": GLib.Variant("d", rate), "MaximumRate": GLib.Variant("d", 1.0),
            "CanGoNext": GLib.Variant("b", True), "CanGoPrevious": GLib.Variant("b", True),
            "CanPlay": GLib.Variant("b", True), "CanPause": GLib.Variant("b", True),
            "CanSeek": GLib.Variant("b", False), "CanControl": GLib.Variant("b", True),
        },
    }
    node = Gio.DBusNodeInfo.new_for_xml(XML)
    loop = GLib.MainLoop()

    def status_changed(conn):
        conn.emit_signal(None, PATH, "org.freedesktop.DBus.Properties", "PropertiesChanged",
                         GLib.Variant("(sa{sv}as)", ("org.mpris.MediaPlayer2.Player",
                                                     {"PlaybackStatus": GLib.Variant("s", state["status"])}, [])))

    def on_call(conn, sender, path, iface, method, params, invocation):
        if method in ("Play", "Pause", "PlayPause", "Stop"):
            state["status"] = {"Play": "Playing", "Pause": "Paused", "Stop": "Stopped",
                               "PlayPause": "Paused" if state["status"] == "Playing" else "Playing"}[method]
            status_changed(conn)
        elif method == "Quit":
            loop.quit()
        invocation.return_value(None)

    def on_get(conn, sender, path, iface, prop):
        if iface == "org.mpris.MediaPlayer2.Player" and prop == "PlaybackStatus":
            return GLib.Variant("s", state["status"])
        return props[iface][prop]

    def on_set(conn, sender, path, iface, prop, value):
        props[iface][prop] = value
        return True

    def on_bus(conn, name):
        for iface in node.interfaces:
            conn.register_object(PATH, iface, on_call, on_get, on_set)

    def on_name(conn, name):
        print("ready", flush=True)

    def on_lost(conn, name):
        print("couldn't take " + NAME, file=sys.stderr, flush=True)
        loop.quit()

    Gio.bus_own_name(Gio.BusType.SESSION, NAME, Gio.BusNameOwnerFlags.NONE, on_bus, on_name, on_lost)
    try:
        loop.run()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
