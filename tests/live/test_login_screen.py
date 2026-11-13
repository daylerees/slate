"""The login screen logs in through greetd: a wrong password is refused, the right one
starts the chosen session. Runs the real login screen (built from greeter/files, like
slate-greeter-install) in the test session, against a fake greetd."""
import json
import os
import re
import shutil
import socket
import struct
import subprocess
import threading
import time

import slate
from live import LiveCase
from session import in_container, log_errors

PASSWORD = "correct horse"
BROKEN = "lose the connection"
REFUSED = {"type": "error", "error_type": "error", "description": "unable to send message: Connection refused (os error 111)"}


class FakeGreetd(threading.Thread):
    """greetd's IPC: a 4-byte native-endian length, then JSON. Asks for a password, accepts
    PASSWORD, and records every request. Like the real greetd, a refused password ends the
    attempt there and then, so cancelling it afterwards gets "Connection refused" (the login
    screen used to show that instead of "Wrong password"). BROKEN plays greetd losing its
    worker partway through an attempt: a real connection problem."""

    def __init__(self, path):
        super().__init__(daemon=True)
        self.path = path
        self.requests = []
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.bind(path)
        self.sock.listen(4)

    def run(self):
        while True:
            try:
                conn, _ = self.sock.accept()
            except OSError:
                return
            threading.Thread(target=self.serve, args=(conn,), daemon=True).start()

    def serve(self, conn):
        ended = False       # the attempt was refused, so greetd's worker for it is gone
        with conn:
            while True:
                head = conn.recv(4)
                if len(head) < 4:
                    return
                (n,) = struct.unpack("=I", head)
                body = b""
                while len(body) < n:
                    chunk = conn.recv(n - len(body))
                    if not chunk:
                        return
                    body += chunk
                req = json.loads(body)
                self.requests.append(req)
                t = req.get("type")
                if t == "create_session":
                    reply = {"type": "auth_message", "auth_message_type": "secret", "auth_message": "Password:"}
                elif t == "post_auth_message_response" and req.get("response") == PASSWORD:
                    reply = {"type": "success"}
                elif t == "post_auth_message_response" and req.get("response") == BROKEN:
                    reply = REFUSED
                elif t == "post_auth_message_response":
                    reply = {"type": "error", "error_type": "auth_error", "description": "pam_authenticate: AUTH_ERR"}
                    ended = True
                elif t == "cancel_session" and ended:
                    reply, ended = REFUSED, False
                else:
                    reply = {"type": "success"}
                data = json.dumps(reply).encode()
                conn.sendall(struct.pack("=I", len(data)) + data)

    def stop(self):
        self.sock.close()

    def of_type(self, t):
        return [r for r in self.requests if r.get("type") == t]


def build_greeter(dest):
    """The login screen's files, laid out as slate-greeter-install installs them."""
    src = slate.SHELL
    for line in open(os.path.join(src, "greeter", "files")):
        parts = re.sub(r"#.*", "", line).split()
        if len(parts) < 2 or parts[0] in ("-", "+"):
            continue
        name, file = parts[0], parts[1]
        os.makedirs(os.path.dirname(os.path.join(dest, name)) or dest, exist_ok=True)
        shutil.copy(os.path.join(src, file), os.path.join(dest, name))


class LoginScreen(LiveCase):
    def test_login(self):
        h = self.s.h
        code = os.path.join(h.dir, "greeter")
        build_greeter(code)
        data = os.path.join(h.dir, "greeter-data")
        os.makedirs(data)
        sessions = os.path.join(h.dir, "share", "wayland-sessions")
        os.makedirs(sessions)
        with open(os.path.join(sessions, "slate.desktop"), "w") as f:
            f.write("[Desktop Entry]\nName=Slate\nExec=slate-session --test\nDesktopNames=Hyprland\n")
        sock = os.path.join(self.s.h.runtime, "greetd.sock")
        greetd = FakeGreetd(sock)
        greetd.start()
        self.addCleanup(greetd.stop)

        env = dict(self.s.env, GREETD_SOCK=sock, SLATE_GREETER_TEST="1", SLATE_GREETER_DATA=data,
                   XDG_DATA_DIRS=os.path.join(h.dir, "share"), USER="tester")
        log = open(os.path.join(self.s.out, "login-screen.log"), "w")
        p = subprocess.Popen(["qs", "-p", code], env=env, stdout=log, stderr=subprocess.STDOUT)
        self.addCleanup(lambda: p.poll() is None and p.kill())

        def ipc(*a):
            return slate.run(["qs", "-p", code, "ipc", "call", "greeter"] + list(a), env=env)

        for _ in range(100):
            if p.poll() is not None:
                self.fail(f"the login screen exited ({p.returncode}); see tests/out/live/login-screen.log")
            if "greeter" in slate.run(["qs", "-p", code, "ipc", "show"], env=env)[1]:
                break
            time.sleep(0.2)
        else:
            self.fail("the login screen didn't start")
        time.sleep(1)       # its session list

        with self.subTest("wrong password"):
            ipc("submit", "not it")
            for _ in range(50):
                if greetd.of_type("post_auth_message_response"):
                    break
                time.sleep(0.1)
            time.sleep(0.5)
            self.assertEqual(greetd.of_type("post_auth_message_response")[0]["response"], "not it")
            self.assertFalse(greetd.of_type("start_session"), "started a session with the wrong password")
            self.assertIsNone(p.poll(), "the login screen quit after a wrong password")
            # (greetd's reply to Quickshell's cancel comes after the refusal: give it time)
            time.sleep(0.5)
            self.assertEqual(ipc("message")[1].strip(), "Wrong password")

        with self.subTest("a real connection problem"):
            ipc("submit", BROKEN)
            for _ in range(50):
                if any(r.get("response") == BROKEN for r in greetd.of_type("post_auth_message_response")):
                    break
                time.sleep(0.1)
            time.sleep(1)
            shown = ipc("message")[1].strip()
            self.assertTrue(shown.startswith("Slate couldn't reach the login service"), shown)
            self.assertNotIn("os error", shown)
            self.assertFalse(greetd.of_type("start_session"))

        with self.subTest("right password"):
            ipc("submit", PASSWORD)
            for _ in range(60):
                if greetd.of_type("start_session"):
                    break
                time.sleep(0.1)
            starts = greetd.of_type("start_session")
            self.assertTrue(starts, "no session was started")
            self.assertEqual(starts[0]["cmd"], ["slate-session", "--test"])
            self.assertIn("XDG_SESSION_DESKTOP=slate", starts[0].get("env", []))
            self.assertEqual(greetd.of_type("create_session")[-1]["username"], "tester")

        with open(os.path.join(self.s.out, "greetd-requests.json"), "w") as f:
            json.dump(greetd.requests, f, indent=1)

        with self.subTest("no errors logged"):
            log.flush()
            errors = log_errors(open(log.name, encoding="utf-8", errors="replace").read())
            self.assertFalse(errors, errors[0][:200] if errors else "")


class HostLights(LiveCase):
    def test_the_hosts_keyboard_lights_arent_seen(self):
        """The container shares the host's /sys, and the lock and login screens read the Caps
        Lock light from it: turning Caps Lock on during a run changed their screenshots. The
        lights are hidden (tests/run), so nothing on the host can show through."""
        if not in_container():
            self.skipTest("only in the test container")
        self.assertEqual(os.listdir("/sys/class/leds"), [])
