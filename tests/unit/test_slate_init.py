"""bin/slate-init: the one place that knows which init system and login service a computer
has. With systemd it must run exactly the commands Slate always has; without it (Artix, Void,
Gentoo: elogind and OpenRC, runit or dinit) the matching ones; and where nothing can do a
thing, it must say so rather than guess. Each system is a scratch root (SLATE_INIT_ROOT) and
stand-in commands on PATH; nothing real is called."""
import os

import slate
from slate import Case, run
from stubs import Stubs

SCRIPT = slate.path("shell", "bin", "slate-init")
LOGIN1 = "org.freedesktop.DBus.NameHasOwner org.freedesktop.login1"
ACTIVATABLE = "ListActivatableNames"


class InitCase(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        self.s = Stubs(self.h)
        self.root = os.path.join(self.h.dir, "root")
        os.makedirs(self.root)
        self.s.env["SLATE_INIT_ROOT"] = self.root
        self.s.add("pgrep", code=1)                    # nothing running, unless a test says so
        self.s.add("gdbus", by_args={LOGIN1: "(false,)\n", ACTIVATABLE: "(['org.freedesktop.UPower'],)\n"})

    def mk(self, *paths):
        for p in paths:
            os.makedirs(os.path.join(self.root, p.lstrip("/")), exist_ok=True)

    def system(self, init, logind=False, timedate=False):
        """A computer run by this init system, with elogind (or not)."""
        if init == "systemd":
            self.mk("/run/systemd/system")
            for c in ("systemctl", "systemd-inhibit", "timedatectl"):
                self.s.add(c)
        elif init == "openrc":
            self.mk("/run/openrc", "/etc/init.d")
        elif init == "runit-void":
            self.mk("/run/runit", "/etc/sv")
        elif init == "runit-artix":
            self.mk("/run/runit", "/etc/runit/sv")
        elif init == "dinit":
            self.s.add("pgrep", by_args={"-x dinit": ""}, code=1)
        if logind:
            names = "(['org.freedesktop.UPower'%s],)\n" % (", 'org.freedesktop.timedate1'" if timedate else "")
            self.s.add("gdbus", by_args={LOGIN1: "(true,)\n", ACTIVATABLE: names})
            self.s.add("loginctl")
            self.s.add("elogind-inhibit")

    def go(self, *args):
        return run(["bash", SCRIPT] + list(args), env=self.s.env)

    def info(self):
        code, out = self.go("info")
        self.assertEqual(code, 0, out)
        return dict(l.split("=", 1) for l in out.splitlines())


class Systemd(InitCase):
    """Nothing may change for the systems Slate already runs on."""

    def setUp(self):
        super().setUp()
        self.system("systemd")

    def test_info(self):
        self.assertEqual(self.info(), {"init": "systemd", "logind": "systemd", "suspend": "yes", "power": "yes",
                                       "inhibit": "yes", "timedate": "yes"})

    def test_power_commands_are_systemctl(self):
        for action in ("suspend", "reboot", "poweroff"):
            with self.subTest(action):
                self.assertEqual(self.go(action)[0], 0)
        self.assertEqual(self.s.calls("systemctl"), [["suspend"], ["reboot"], ["poweroff"]])

    def test_goes_by_what_runs_not_what_is_installed(self):
        """loginctl exists with systemd too: it's never used there."""
        self.s.add("loginctl")
        self.s.add("elogind-inhibit")
        self.go("suspend")
        self.go("inhibit", "--what=sleep", "true")
        self.assertEqual(self.s.calls("loginctl"), [])
        self.assertEqual(self.s.calls("elogind-inhibit"), [])

    def test_inhibit(self):
        args = ["--what=sleep", "--mode=delay", "--who=Slate", "--why=Lock the screen before sleep", "gdbus", "monitor"]
        self.assertEqual(self.go("inhibit", *args)[0], 0)
        self.assertEqual(self.s.calls("systemd-inhibit"), [args])

    def test_services(self):
        self.s.add("systemctl", by_args={"is-active --quiet bluetooth.service": "", "cat ": ""}, code=3)
        self.assertEqual(self.go("service-active", "bluetooth")[0], 0)
        self.assertEqual(self.go("service-active", "network")[0], 1)
        self.assertEqual(self.go("service-hint", "bluetooth")[1], "sudo systemctl enable --now bluetooth.service\n")
        self.s.add("systemctl")
        self.assertEqual(self.go("service-enable", "printing")[0], 0)
        self.assertEqual(self.s.calls("systemctl")[-1], ["enable", "--now", "cups.service", "cups.socket"])

    def test_display_manager(self):
        self.s.add("systemctl", stdout="sddm.service\n")
        self.assertEqual(self.go("display-manager")[1], "sddm\n")
        self.s.add("systemctl", stdout="display-manager.service\n")
        self.assertEqual(self.go("display-manager")[1], "none\n")

    def test_timedate(self):
        self.s.add("timedatectl", by_args={"show": "Timezone=Europe/London\nNTP=yes\nCanNTP=yes\n", "list-timezones": "Africa/Abidjan\nEurope/London\n"})
        self.assertEqual(self.go("timedate", "show")[1], "Timezone=Europe/London\nNTP=yes\nCanNTP=yes\nCanSet=yes\n")
        self.assertEqual(self.go("timedate", "zones")[1], "Africa/Abidjan\nEurope/London\n")
        self.go("timedate", "set-zone", "Europe/Paris")
        self.go("timedate", "set-ntp", "false")
        self.assertEqual(self.s.calls("timedatectl")[-2:], [["set-timezone", "Europe/Paris"], ["set-ntp", "false"]])


class Elogind(InitCase):
    """Without systemd, with elogind: the same things through loginctl and elogind-inhibit."""

    def test_info(self):
        self.system("openrc", logind=True)
        self.assertEqual(self.info(), {"init": "openrc", "logind": "elogind", "suspend": "yes", "power": "yes",
                                       "inhibit": "yes", "timedate": "no"})

    def test_elogind_seen_running(self):
        """…even if the bus can't be asked."""
        self.system("openrc")
        self.s.add("pgrep", by_args={"-x elogind": ""}, code=1)
        self.assertEqual(self.info()["logind"], "elogind")

    def test_power_commands_are_loginctl(self):
        self.system("runit-void", logind=True)
        for action in ("suspend", "reboot", "poweroff"):
            self.assertEqual(self.go(action)[0], 0)
        self.assertEqual(self.s.calls("loginctl"), [["suspend"], ["reboot"], ["poweroff"]])

    def test_inhibit(self):
        self.system("dinit", logind=True)
        args = ["--what=handle-lid-switch", "--who=Slate", "--why=x", "sleep", "infinity"]
        self.go("inhibit", *args)
        self.assertEqual(self.s.calls("elogind-inhibit"), [args])

    def test_timedate_service(self):
        """openrc-settingsd and the like provide the same D-Bus service systemd does."""
        self.system("openrc", logind=True, timedate=True)
        self.assertEqual(self.info()["timedate"], "yes")
        names = "(['org.freedesktop.timedate1'],)\n"
        self.s.add("gdbus", by_args={LOGIN1: "(true,)\n", ACTIVATABLE: names, "Get org.freedesktop.timedate1 Timezone": "(<'Europe/Paris'>,)\n",
                                     "Get org.freedesktop.timedate1 NTP": "(<true>,)\n", "Get org.freedesktop.timedate1 CanNTP": "(<true>,)\n"})
        self.assertEqual(self.go("timedate", "show")[1], "Timezone=Europe/Paris\nNTP=yes\nCanNTP=yes\nCanSet=yes\n")
        self.assertEqual(self.go("timedate", "set-zone", "Europe/Rome")[0], 0)
        self.assertIn("org.freedesktop.timedate1.SetTimezone", self.s.calls("gdbus")[-1])

    def test_timedate_without_the_service(self):
        """The zone is still read (from /etc/localtime) and the zones listed; setting says no."""
        self.system("openrc", logind=True)
        zi = os.path.join(self.root, "usr/share/zoneinfo")
        os.makedirs(os.path.join(zi, "Europe"))
        open(os.path.join(zi, "Europe", "Paris"), "w").close()
        with open(os.path.join(zi, "tzdata.zi"), "w") as f:
            f.write("# version 2026a\nZ Europe/Paris 0:9:21 - LMT 1891 Mar 16\nL Europe/Paris Europe/Monaco\nR x 1 2\n")
        os.makedirs(os.path.join(self.root, "etc"), exist_ok=True)
        os.symlink(os.path.join(zi, "Europe", "Paris"), os.path.join(self.root, "etc", "localtime"))
        self.assertEqual(self.go("timedate", "show")[1], "Timezone=Europe/Paris\nNTP=no\nCanNTP=no\nCanSet=no\n")
        self.assertEqual(self.go("timedate", "zones")[1], "Europe/Monaco\nEurope/Paris\n")
        self.assertEqual(self.go("timedate", "set-zone", "Europe/Rome")[0], 1)


class Services(InitCase):
    """Slate doesn't switch services on without systemd: it says which command does."""

    def test_openrc(self):
        self.system("openrc", logind=True)
        open(os.path.join(self.root, "etc/init.d/bluetooth"), "w").close()
        self.s.add("rc-service", by_args={"bluetooth status": ""}, code=3)
        self.assertEqual(self.go("service-active", "bluetooth")[0], 0)
        self.assertEqual(self.go("service-active", "printing")[0], 1)
        self.assertEqual(self.go("service-hint", "bluetooth")[1], "sudo rc-update add bluetooth default && sudo rc-service bluetooth start\n")
        self.assertEqual(self.go("service-hint", "printing")[1], "sudo rc-update add cupsd default && sudo rc-service cupsd start\n")
        self.assertEqual(self.go("service-enable", "bluetooth")[0], 2, "only systemd is switched on for you")

    def test_runit_on_void(self):
        self.system("runit-void", logind=True)
        self.mk("/etc/sv/bluetoothd")
        self.s.add("sv", by_args={"status /var/service/NetworkManager": "run: /var/service/NetworkManager: (pid 1) 5s\n"}, stdout="down: x: 1s\n")
        self.assertEqual(self.go("service-active", "network")[0], 0)
        self.assertEqual(self.go("service-active", "bluetooth")[0], 1)
        self.assertEqual(self.go("service-hint", "bluetooth")[1], "sudo ln -s /etc/sv/bluetoothd /var/service/\n")

    def test_swapping_login_managers(self):
        self.system("openrc", logind=True)
        self.assertEqual(self.go("service-swap-hint", "sddm", "greetd")[1], "sudo rc-update del sddm default && sudo rc-update add greetd default\n")

    def test_runit_on_artix(self):
        self.system("runit-artix", logind=True)
        self.assertEqual(self.go("service-hint", "greetd")[1], "sudo ln -s /etc/runit/sv/greetd /run/runit/service/\n")

    def test_dinit(self):
        self.system("dinit", logind=True)
        self.s.add("dinitctl", by_args={"status greetd": "Service: greetd\n    State: STARTED\n"}, code=1)
        self.assertEqual(self.go("service-active", "greetd")[0], 0)
        self.assertEqual(self.go("service-hint", "network")[1], "sudo dinitctl enable NetworkManager\n")
        self.assertEqual(self.go("display-manager")[1], "greetd\n")

    def test_unknown_init(self):
        self.assertEqual(self.info()["init"], "unknown")
        self.assertEqual(self.go("service-active", "bluetooth")[0], 2)
        self.assertEqual(self.go("service-hint", "bluetooth")[1], "\n")
        self.assertEqual(self.go("display-manager")[1], "unknown\n")


class Nothing(InitCase):
    """seatd alone, say: no login service. Slate still runs; these just aren't offered."""

    def setUp(self):
        super().setUp()
        self.system("openrc")

    def test_info(self):
        i = self.info()
        self.assertEqual((i["logind"], i["suspend"], i["power"], i["inhibit"]), ("none", "no", "no", "no"))

    def test_power_says_it_cannot(self):
        code, out = self.go("suspend")
        self.assertEqual(code, 1)
        self.assertIn("needs systemd or elogind", out)

    def test_inhibit_just_runs_the_command(self):
        self.s.add("gdbus", by_args={LOGIN1: "(false,)\n", "monitor": "watching\n"})
        code, out = self.go("inhibit", "--what=sleep", "--mode=delay", "--who=Slate", "--why=x", "gdbus", "monitor", "--system")
        self.assertEqual((code, out), (0, "watching\n"))

    def test_usage(self):
        code, out = self.go("frobnicate")
        self.assertEqual(code, 2)
        self.assertIn("slate-init info", out)
