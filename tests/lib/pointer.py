"""A real pointer for the live tests: presses, moves and lets go through Hyprland's virtual
pointer (wlr-virtual-pointer-unstable-v1), so Slate gets the same events a mouse gives it.
hyprctl's movecursor only moves the cursor: it gives no hover and no buttons, and a test hook
skips the part of a feature a real pointer goes through (the MouseArea, what lies on top of it).

Spoken straight over the Wayland socket (no client library in the container):

    with Pointer(session.env, width, height) as p:
        p.drag((100, 40), (300, 200))

Places are in the layout's pixels (one screen at 0, 0 in the tests)."""

import os
import socket
import struct
import time

BTN_LEFT = 0x110


def _string(s):
    b = s.encode() + b"\0"
    return struct.pack("<I", len(b)) + b + b"\0" * (-len(b) % 4)


class Pointer:
    def __init__(self, env, width, height):
        self.width, self.height = width, height
        path = os.path.join(env["XDG_RUNTIME_DIR"], env["WAYLAND_DISPLAY"])
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.connect(path)
        self.buf = b""
        self.next_id = 2
        self.at = (0, 0)
        registry = self._new()
        self._send(1, 1, struct.pack("<I", registry))            # wl_display.get_registry
        globals_ = {}
        for obj, op, body in self._roundtrip():
            if obj == registry and op == 0:                     # wl_registry.global
                name, n = struct.unpack_from("<II", body)
                iface = body[8:8 + n - 1].decode()
                globals_[iface] = (name, struct.unpack_from("<I", body, 8 + n + (-n % 4))[0])
        if "zwlr_virtual_pointer_manager_v1" not in globals_:
            raise RuntimeError("the compositor has no virtual pointer")
        name, _ = globals_["zwlr_virtual_pointer_manager_v1"]
        manager = self._new()
        self._send(registry, 0, struct.pack("<I", name) + _string("zwlr_virtual_pointer_manager_v1")
                   + struct.pack("<II", 1, manager))             # wl_registry.bind
        self.ptr = self._new()
        self._send(manager, 0, struct.pack("<II", 0, self.ptr))  # create_virtual_pointer(no seat)
        self._roundtrip()
        time.sleep(0.5)

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()

    def close(self):
        try:
            self._send(self.ptr, 8, b"")                         # destroy
            self._roundtrip()
        finally:
            self.sock.close()

    # ---- the wire ---------------------------------------------------------------------
    def _new(self):
        self.next_id += 1
        return self.next_id - 1

    def _send(self, obj, op, body):
        self.sock.sendall(struct.pack("<II", obj, ((8 + len(body)) << 16) | op) + body)

    def _roundtrip(self):
        """Every event up to a wl_display.sync's answer (so what was sent has been handled)."""
        cb = self._new()
        self._send(1, 0, struct.pack("<I", cb))
        events = []
        self.sock.settimeout(5)
        while True:
            while len(self.buf) < 8 or len(self.buf) < (struct.unpack_from("<I", self.buf, 4)[0] >> 16):
                chunk = self.sock.recv(65536)
                if not chunk:
                    raise RuntimeError("the compositor closed the connection")
                self.buf += chunk
            obj, word = struct.unpack_from("<II", self.buf)
            size = word >> 16
            body, self.buf = self.buf[8:size], self.buf[size:]
            if obj == 1 and (word & 0xFFFF) == 0:                 # wl_display.error
                raise RuntimeError(f"Wayland error: {body!r}")
            if obj == cb:
                return events
            events.append((obj, word & 0xFFFF, body))

    def _ms(self):
        return int(time.monotonic() * 1000) & 0xFFFFFFFF

    # ---- what a test does ---------------------------------------------------------------
    def move(self, x, y):
        x, y = max(0, min(self.width - 1, x)), max(0, min(self.height - 1, y))     # (on the screen)
        self._send(self.ptr, 1, struct.pack("<IIIII", self._ms(), int(x), int(y), self.width, self.height))
        self._send(self.ptr, 4, b"")                             # frame
        self._roundtrip()
        self.at = (x, y)

    def button(self, pressed, button=BTN_LEFT):
        self._send(self.ptr, 2, struct.pack("<III", self._ms(), button, 1 if pressed else 0))
        self._send(self.ptr, 4, b"")
        self._roundtrip()

    def drag(self, start, end, steps=12, pause=0.02):
        """Press at start, move to end in steps (as a hand does), let go."""
        self.move(*start)
        time.sleep(pause)
        self.button(True)
        time.sleep(pause)
        for i in range(1, steps + 1):
            self.move(start[0] + (end[0] - start[0]) * i / steps, start[1] + (end[1] - start[1]) * i / steps)
            time.sleep(pause)
        self.button(False)
        time.sleep(pause)
