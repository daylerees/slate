"""Base for the live tier's tests: the shared Slate session, reset before each test, and a
check after each one that Slate logged no new errors."""
import os

import slate
from session import Session, SessionError


class LiveCase(slate.Case):
    @classmethod
    def setUpClass(cls):
        cls.s = Session.shared()

    def setUp(self):
        super().setUp()
        self.s.reset()
        self.s.settle(0.3)
        self.s.new_log_errors()            # what came before this test isn't its fault
        self.addCleanup(self._check_log)

    def _check_log(self):
        errors = self.s.new_log_errors()
        if errors:
            path = self.log(self.id().split(".", 2)[-1] + ".log-errors.txt", "\n".join(errors))
            raise AssertionError(f"Slate logged {len(errors)} error(s): {errors[0][:200]}  [{path}]")

    def close_windows(self):
        """Close every app window and go back to workspace 1. The session is shared, so windows
        other tests opened are still about; tests that count windows or workspaces start here."""
        for _ in range(4):
            clients = [c for c in self.s.hyprctl("clients", json_out=True) if c.get("mapped")]
            if not clients:
                break
            for c in clients:
                self.s.hyprctl("dispatch", 'function() hl.dispatch(hl.dsp.window.close({ window = "address:%s" })) end' % c["address"])
            self.s.settle(0.7)
        self.s.hyprctl("dispatch", "function() hl.dispatch(hl.dsp.focus({ workspace = 1 })) end")
        self.s.settle(0.4)

    def ipc(self, *a, **kw):
        return self.s.ipc(*a, **kw)

    def wait(self, check, what="the expected state", timeout=8):
        return self.s.wait(check, timeout=timeout, what=what)

    def config(self, key, value):
        """Change a setting the way Settings does (config set), and wait for it to stick."""
        self.ipc("config", "set", key, value)
        want = str(value)
        for _ in range(40):
            if self.ipc("config", "get", key) == want:
                return
            self.s.settle(0.1)
        self.fail(f"config {key} didn't become {value}")

    def setting(self, key):
        return self.ipc("config", "get", key)

    def keep_setting(self, key):
        """Put a setting back as it was when the test ends."""
        old = self.setting(key)
        self.addCleanup(lambda: self.ipc("config", "set", key, old))
        return old

    def screenshot(self, name):
        return self.s.screenshot(os.path.join(slate.OUT, "live", name + ".png"))


__all__ = ["LiveCase", "Session", "SessionError"]
