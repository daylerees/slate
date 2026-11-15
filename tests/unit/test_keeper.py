"""Slate comes back by itself after a crash (bin/slate's keeper, `slate _keep`): `slate` starts
the keeper, which starts Quickshell and waits on it. A crash starts it again and says so once
it's back; what was asked for (slate stop, restart --full, a clean exit, SIGTERM, the session
ending) doesn't; and a crash loop stops after a few tries with a message on screen.

Quickshell, hyprctl and notify-send are stand-ins here (a script that does what the test's
plan says, one line per start: run, kill, segv, exit N), so nothing real is started."""
import os
import shutil
import signal
import time

import slate
from slate import Case, run

QS = r'''#!/bin/sh
d="$STUB_DIR"
case "$1" in
    --version) echo "Quickshell 0.3.2"; exit 0 ;;
    list)   # running copies, as Quickshell lists them
        for f in "$d"/running/*; do
            [ -e "$f" ] || continue; p=${f##*/}
            kill -0 "$p" 2>/dev/null && echo "  Process ID: $p"
        done
        exit 0 ;;
esac
case " $* " in *" ipc "*) exit 0 ;; esac
n=$(cat "$d/launches" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" >"$d/launches"
env | grep -E '^(QT_SCALE_FACTOR|QS_DISABLE_CRASH_HANDLER)=' >"$d/env.$n"
step=$(sed -n "${n}p" "$d/plan" 2>/dev/null); step=${step:-run}
ulimit -c 0
case "$step" in
    kill) kill -KILL $$ ;;
    segv) kill -SEGV $$ ;;
    exit*) exit "${step#exit }" ;;
esac
mkdir -p "$d/running"; : >"$d/running/$$"; : >"$XDG_RUNTIME_DIR/slate-ready"
exec sleep 120
'''
HYPRCTL = r'''#!/bin/sh
d="$STUB_DIR"
printf '%s\n' "$*" >>"$d/hyprctl.log"
case "$1" in
    version) [ ! -e "$d/session-gone" ] ;;
    notify) [ ! -e "$d/no-hyprland-notify" ] ;;
esac
'''
# systemd-coredump's record of the crash, with what mustn't reach a bug report (the command line
# with the home folder in it, the user, the computer's name)
COREDUMPCTL = r'''#!/bin/sh
printf '%s\n' "$*" >>"$STUB_DIR/coredumpctl.log"
cat <<END
           PID: 4242 (quickshell)
           UID: 1000 (somebody)
        Signal: 11 (SEGV)
     Timestamp: Sun 2026-11-15 14:19:43 UTC (1s ago)
  Command Line: qs -n -p $HOME/.config/slate --log-times
    Executable: /usr/bin/quickshell
      Hostname: my-secret-laptop
       Storage: /var/lib/systemd/coredump/core.quickshell.1000.zst (present)
       Message: Process 4242 (quickshell) of user 1000 dumped core.

                Stack trace of thread 4242:
                #0  0x00007f0000000001 QQuickItem::update (libQt6Quick.so.6 + 0x1234)
                #1  0x00007f0000000002 n/a ($HOME/.config/slate/plugin.so + 0x10)
END
'''
NOTIFY = r'''#!/bin/sh
printf '%s\n' "$*" >>"$STUB_DIR/notify.log"
'''


class Keeper(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        self.stubs = os.path.join(self.h.dir, "stubs")
        os.makedirs(os.path.join(self.stubs, "bin"))
        for name, text in (("qs", QS), ("hyprctl", HYPRCTL), ("notify-send", NOTIFY), ("coredumpctl", COREDUMPCTL)):
            p = os.path.join(self.stubs, "bin", name)
            with open(p, "w") as f:
                f.write(text)
            os.chmod(p, 0o755)
        # Slate's folder: bin/slate, and its settings (Interface size at 125%)
        self.dir = os.path.join(self.h.config, "slate")
        os.makedirs(os.path.join(self.dir, "bin"))
        self.slate = os.path.join(self.dir, "bin", "slate")
        shutil.copy(os.path.join(slate.SHELL, "bin", "slate"), self.slate)
        with open(os.path.join(self.dir, "settings.json"), "w") as f:
            f.write('{\n  "uiScale": 1.25\n}\n')
        self.env = dict(self.h.env, PATH=os.path.join(self.stubs, "bin") + ":" + self.h.env["PATH"],
                        STUB_DIR=self.stubs, SLATE_KEEP_PAUSE="0.1", SLATE_CRASH_TRIES="3",
                        # (crashes not going to systemd-coredump, unless a test says they do)
                        SLATE_CORE_PATTERN=self.core_pattern("core"))
        self.addCleanup(self.cleanup)

    def cleanup(self):
        run([self.slate, "stop"], env=self.env)
        for f in os.listdir(os.path.join(self.stubs, "running")) if os.path.isdir(os.path.join(self.stubs, "running")) else ():
            try:
                os.kill(int(f), signal.SIGKILL)
            except OSError:
                pass

    # ---- helpers ------------------------------------------------------------------------
    def core_pattern(self, text):
        p = os.path.join(self.h.dir, "core_pattern")
        with open(p, "w") as f:
            f.write(text + "\n")
        return p

    def reports(self):
        d = os.path.join(self.h.cache, "slate", "crashes")
        return sorted(os.path.join(d, f) for f in os.listdir(d)) if os.path.isdir(d) else []

    def plan(self, *steps):
        with open(os.path.join(self.stubs, "plan"), "w") as f:
            f.write("\n".join(steps) + "\n")

    def slate_cmd(self, *args):
        code, out = run([self.slate] + list(args), env=self.env, timeout=30)
        self.assertEqual(code, 0, out)

    def read(self, name):
        try:
            with open(os.path.join(self.stubs, name)) as f:
                return f.read()
        except FileNotFoundError:
            return ""

    def launches(self):
        return int(self.read("launches") or 0)

    def log(self):
        try:
            with open(os.path.join(self.h.cache, "slate.log")) as f:
                return f.read()
        except FileNotFoundError:
            return ""

    def keeper(self):
        """The keeper's process number, while it runs."""
        try:
            pid = int(open(os.path.join(self.h.runtime, "slate-keeper.pid")).read())
            os.kill(pid, 0)
            return pid
        except (OSError, ValueError):
            return None

    def running(self):
        """Quickshell stand-ins running now."""
        d = os.path.join(self.stubs, "running")
        out = []
        for f in os.listdir(d) if os.path.isdir(d) else ():
            try:
                os.kill(int(f), 0)
                with open(f"/proc/{f}/stat") as st:
                    if st.read().split()[2] != "Z":
                        out.append(int(f))
            except (OSError, ValueError):
                pass
        return out

    def until(self, check, what, timeout=10):
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            if check():
                return
            time.sleep(0.05)
        self.fail(f"timed out waiting for {what}; log:\n{self.log()}")

    def started(self, n=1):
        self.until(lambda: self.launches() >= n and len(self.running()) == 1, f"start {n}")
        return self.running()[0]

    def quiet_for(self, seconds=1.0):
        time.sleep(seconds)

    # ---- a crash ------------------------------------------------------------------------
    def test_a_crash_starts_slate_again_and_says_so(self):
        self.slate_cmd()
        first = self.started(1)
        os.kill(first, signal.SIGSEGV)
        self.started(2)
        self.until(lambda: "Slate restarted" in self.read("notify.log"), "the notification")
        note = self.read("notify.log")
        self.assertIn("Your apps and windows stayed open.", note)
        self.assertIn("x-slate-page:debug", note)
        log = self.log()
        self.assertIn("Slate stopped unexpectedly (signal SEGV", log)
        self.assertIn("starting it again", log)
        # (when and why, never what was running or where)
        self.assertNotIn(self.h.home, log)
        self.assertNotIn("qs ", log)
        self.assertTrue(self.keeper(), "the keeper stopped after one crash")
        # Started again the same way: at the Interface size, with Quickshell's own crash
        # handler off (it would start a second copy itself)
        for n in (1, 2):
            env = self.read(f"env.{n}")
            self.assertIn("QT_SCALE_FACTOR=1.25", env)
            self.assertIn("QS_DISABLE_CRASH_HANDLER=1", env)

    def test_killed_counts_as_a_crash(self):
        """SIGKILL from outside (running out of memory) is a crash: slate stop never lets the
        keeper see its own."""
        self.slate_cmd()
        os.kill(self.started(1), signal.SIGKILL)
        self.started(2)
        self.assertIn("signal KILL", self.log())

    def test_an_error_exit_counts_as_a_crash(self):
        self.plan("exit 3")
        self.slate_cmd()
        self.started(2)
        self.assertIn("exit code 3", self.log())

    # ---- what was asked for -------------------------------------------------------------
    def test_slate_stop_stops_it_for_good(self):
        self.slate_cmd()
        self.started(1)
        self.slate_cmd("stop")
        self.quiet_for()
        self.assertEqual(self.launches(), 1)
        self.assertEqual(self.running(), [])
        self.assertIsNone(self.keeper())
        self.assertEqual(self.read("notify.log"), "")
        self.assertNotIn("unexpectedly", self.log())

    def test_a_full_restart_starts_it_once(self):
        self.slate_cmd()
        self.started(1)
        self.slate_cmd("restart", "--full")
        self.started(2)
        self.quiet_for()
        self.assertEqual(self.launches(), 2)
        self.assertEqual(len(self.running()), 1)
        self.assertTrue(self.keeper())
        self.assertEqual(self.read("notify.log"), "")
        self.assertNotIn("unexpectedly", self.log())

    def test_asked_to_quit_from_outside(self):
        """SIGTERM or SIGHUP (qs kill, shutting down) and a clean exit end it quietly. (SIGINT
        too, but a program started in the background ignores it, the stand-in included.)"""
        for sig in (signal.SIGTERM, signal.SIGHUP, "exit 0"):
            with self.subTest(str(sig)):
                self.cleanup()
                for f in ("launches", "plan"):
                    if os.path.exists(os.path.join(self.stubs, f)):
                        os.remove(os.path.join(self.stubs, f))
                if sig == "exit 0":
                    self.plan("exit 0")
                    self.slate_cmd()
                    self.until(lambda: self.launches() == 1, "the start")
                else:
                    self.slate_cmd()
                    os.kill(self.started(1), sig)
                self.until(lambda: self.keeper() is None, "the keeper to stop")
                self.quiet_for(0.5)
                self.assertEqual(self.launches(), 1)
                self.assertEqual(self.read("notify.log"), "")

    def test_the_session_ending_isnt_a_crash(self):
        """Logging out: Hyprland goes, Slate goes with it, and nothing starts it again."""
        self.slate_cmd()
        first = self.started(1)
        open(os.path.join(self.stubs, "session-gone"), "w").close()
        os.kill(first, signal.SIGSEGV)
        self.until(lambda: self.keeper() is None, "the keeper to stop")
        self.quiet_for(0.5)
        self.assertEqual(self.launches(), 1)
        self.assertEqual(self.read("notify.log"), "")
        self.assertNotIn("notify", self.read("hyprctl.log"))
        self.assertIn("as the session ended", self.log())

    def test_one_slate_at_a_time(self):
        self.slate_cmd()
        keeper = None
        self.started(1)
        keeper = self.keeper()
        self.slate_cmd()
        self.slate_cmd("start")
        self.quiet_for(0.5)
        self.assertEqual(self.launches(), 1)
        self.assertEqual(self.keeper(), keeper)

    # ---- a crash loop -------------------------------------------------------------------
    def test_a_crash_loop_stops_trying_and_says_so(self):
        self.plan("kill", "kill", "segv")
        self.slate_cmd()
        self.until(lambda: self.keeper() is None and self.launches() == 3, "the keeper to give up")
        self.quiet_for(0.5)
        self.assertEqual(self.launches(), 3, "it kept trying")
        shown = self.read("hyprctl.log")
        self.assertIn("notify", shown)
        self.assertIn("Slate keeps stopping, so it hasn't been started again. Your apps and windows are still open.", shown)
        self.assertEqual(self.read("notify.log"), "", "said it was back when it wasn't")
        log = self.log()
        self.assertIn("3 times in 60 s: not starting it again by itself", log)
        # ...and `slate` tries again
        self.slate_cmd()
        self.started(4)
        self.assertTrue(self.keeper())

    def test_giving_up_without_hyprlands_notifications(self):
        open(os.path.join(self.stubs, "no-hyprland-notify"), "w").close()
        self.plan("kill", "kill", "kill")
        self.slate_cmd()
        self.until(lambda: self.keeper() is None and self.launches() == 3, "the keeper to give up")
        self.assertIn("Slate stopped", self.read("notify.log"))
        self.assertIn("-u critical", self.read("notify.log"))

    def test_crashes_far_apart_dont_add_up(self):
        """Only crashes within the window count towards giving up."""
        # (a one-second window, and a pause longer than that between a crash and the next start)
        self.env.update(SLATE_KEEP_WINDOW="1", SLATE_KEEP_PAUSE="1.1")
        self.plan("kill", "kill", "kill", "kill")
        self.slate_cmd()
        self.until(lambda: self.launches() >= 5 and len(self.running()) == 1, "start 5", timeout=20)
        self.assertTrue(self.keeper())
        self.assertNotIn("not starting it again", self.log())

    # ---- crash reports (Quickshell's own handler is off) --------------------------------
    def test_a_crash_leaves_a_report_with_the_backtrace(self):
        self.core_pattern("|/usr/lib/systemd/systemd-coredump %P %u %g %s %t %c %h")
        self.slate_cmd()
        first = self.started(1)
        os.kill(first, signal.SIGSEGV)
        self.until(lambda: self.reports(), "the crash report")
        path = self.reports()[0]
        self.until(lambda: os.path.getsize(path) > 0 and "Stack trace" in open(path).read(), "the report's backtrace")
        self.assertIn(f"info {first}", self.read("coredumpctl.log"), "asked about another process")
        text = open(path).read()
        self.assertIn("Slate stopped unexpectedly: signal SEGV", text)
        self.assertIn("Signal: 11 (SEGV)", text)
        self.assertIn("QQuickItem::update", text)
        self.assertIn("~/.config/slate/plugin.so", text)
        for private in (self.h.home, "Command Line", "somebody", "my-secret-laptop", "Storage"):
            self.assertNotIn(private, text)
        # Yours alone
        self.assertEqual(os.stat(path).st_mode & 0o777, 0o600)
        self.assertEqual(os.stat(os.path.dirname(path)).st_mode & 0o777, 0o700)

    def test_a_report_without_systemd_coredump(self):
        """Without it (Artix, Void, or turned off): when and how, and nothing waited for."""
        self.slate_cmd()
        os.kill(self.started(1), signal.SIGKILL)
        self.until(lambda: self.reports() and os.path.getsize(self.reports()[0]) > 0, "the crash report")
        text = open(self.reports()[0]).read()
        self.assertIn("Slate stopped unexpectedly: signal KILL", text)
        self.assertIn("(no backtrace", text)
        self.assertEqual(self.read("coredumpctl.log"), "")

    def test_only_the_last_few_reports_are_kept(self):
        d = os.path.join(self.h.cache, "slate", "crashes")
        os.makedirs(d)
        for n in range(6):
            p = os.path.join(d, f"crash-2026010{n}-000000-1{n}.txt")
            open(p, "w").close()
            os.utime(p, (1_700_000_000 + n, 1_700_000_000 + n))
        self.slate_cmd()
        first = self.started(1)
        os.kill(first, signal.SIGKILL)
        self.until(lambda: any(r.endswith(f"-{first}.txt") for r in self.reports()) and len(self.reports()) == 5,
                   "the oldest reports to go")
        self.assertNotIn(os.path.join(d, "crash-20260100-000000-10.txt"), self.reports())

    def test_exported_logs_carry_the_last_crash(self):
        """Settings → Debug → Export recent logs (bin/slate-logs) adds the latest report, with
        the home folder as ~."""
        self.core_pattern("|/usr/lib/systemd/systemd-coredump")
        self.slate_cmd()
        os.kill(self.started(1), signal.SIGSEGV)
        self.until(lambda: self.reports() and "Stack trace" in open(self.reports()[0]).read(), "the crash report")
        shutil.copy(os.path.join(slate.SHELL, "bin", "slate-logs"), os.path.join(self.dir, "bin", "slate-logs"))
        code, out = run(["sh", os.path.join(self.dir, "bin", "slate-logs")], env=self.env, timeout=60)
        self.assertEqual(code, 0, out)
        with open(out.strip().splitlines()[-1]) as f:
            text = f.read()
        self.assertIn("===== Slate's last crash =====", text)
        self.assertIn("QQuickItem::update", text)
        self.assertNotIn(self.h.home, text)
