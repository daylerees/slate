#!/usr/bin/env python3
"""A pretend light sensor for the tests: iio-sensor-proxy's net.hadess.SensorProxy on the
session bus (the tests' Slate looks there: SLATE_SENSOR_BUS=session), for Automatic brightness
(scripts/auto-brightness.py). Runs until it's stopped.

    fake_sensor.py [--lux N] [--unit lux|vendor]

Reads lines on stdin: "lux 300" changes the light (and says so, as the real one does). Keeps
what's been asked of it in --record (a JSON file, rewritten each time): how many claims are
held now, and how many were ever made and given back. A claim is also dropped when whoever made
it leaves the bus, as iio-sensor-proxy does. Prints "ready" once its name is on the bus."""
import argparse
import json
import os
import sys

from gi.repository import Gio, GLib

NAME = "net.hadess.SensorProxy"
PATH = "/net/hadess/SensorProxy"
IFACE = "net.hadess.SensorProxy"

XML = """
<node>
  <interface name="net.hadess.SensorProxy">
    <method name="ClaimLight"/>
    <method name="ReleaseLight"/>
    <property name="HasAmbientLight" type="b" access="read"/>
    <property name="LightLevelUnit" type="s" access="read"/>
    <property name="LightLevel" type="d" access="read"/>
  </interface>
</node>
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lux", type=float, default=100.0)
    ap.add_argument("--unit", default="lux")
    ap.add_argument("--record", default="")
    args = ap.parse_args()
    state = {"lux": args.lux, "claims": set(), "claimed": 0, "released": 0}
    node = Gio.DBusNodeInfo.new_for_xml(XML)
    loop = GLib.MainLoop()
    bus = {}

    def record():
        if args.record:
            with open(args.record + ".tmp", "w") as f:
                json.dump({"held": len(state["claims"]), "claimed": state["claimed"], "released": state["released"],
                           "lux": state["lux"]}, f)
            os.replace(args.record + ".tmp", args.record)

    def gone(conn, sender, path, iface, signal, params):
        name, _old, new = params.unpack()
        if not new and name in state["claims"]:
            state["claims"].discard(name)
            record()

    def on_call(conn, sender, path, iface, method, params, invocation):
        if method == "ClaimLight":
            state["claims"].add(sender)
            state["claimed"] += 1
        elif method == "ReleaseLight":
            state["claims"].discard(sender)
            state["released"] += 1
        record()
        invocation.return_value(None)

    def on_get(conn, sender, path, iface, prop):
        return {"HasAmbientLight": GLib.Variant("b", True), "LightLevelUnit": GLib.Variant("s", args.unit),
                "LightLevel": GLib.Variant("d", state["lux"])}[prop]

    def on_bus(conn, name):
        bus["conn"] = conn
        conn.register_object(PATH, node.interfaces[0], on_call, on_get, None)
        conn.signal_subscribe("org.freedesktop.DBus", "org.freedesktop.DBus", "NameOwnerChanged",
                              "/org/freedesktop/DBus", None, Gio.DBusSignalFlags.NONE, gone)

    def on_name(conn, name):
        record()
        print("ready", flush=True)

    def on_lost(conn, name):
        print("couldn't take " + NAME, file=sys.stderr, flush=True)
        loop.quit()

    pending = {"text": b""}

    def on_input(_fd, _cond):
        chunk = os.read(sys.stdin.fileno(), 4096)
        if not chunk:
            loop.quit()
            return False
        pending["text"] += chunk
        *lines, pending["text"] = pending["text"].split(b"\n")
        for line in lines:
            parts = line.decode().split()
            if len(parts) == 2 and parts[0] == "lux" and "conn" in bus:
                state["lux"] = float(parts[1])
                record()
                bus["conn"].emit_signal(None, PATH, "org.freedesktop.DBus.Properties", "PropertiesChanged",
                                        GLib.Variant("(sa{sv}as)", (IFACE, {"LightLevel": GLib.Variant("d", state["lux"])}, [])))
        return True

    Gio.bus_own_name(Gio.BusType.SESSION, NAME, Gio.BusNameOwnerFlags.NONE, on_bus, on_name, on_lost)
    GLib.io_add_watch(sys.stdin.fileno(), GLib.PRIORITY_DEFAULT, GLib.IOCondition.IN | GLib.IOCondition.HUP, on_input)
    try:
        loop.run()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
