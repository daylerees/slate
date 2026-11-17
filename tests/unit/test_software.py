"""scripts/software.py: Slate Software's engine, with a pretend Flathub catalogue on disk and
Flatpak, the distros' update tools and slate-system stood in for: nothing is installed, removed
or fetched."""
import gzip
import importlib.util
import io
import json
import os
import sys
from contextlib import redirect_stdout
from unittest import mock

import slate
from slate import Case, run
from stubs import Stubs

SCRIPT = slate.path("shell", "scripts", "software.py")

CATALOGUE = """<?xml version="1.0" encoding="UTF-8"?>
<components version="0.8" origin="flathub">
  <component type="desktop-application">
    <id>org.example.Paint</id>
    <name>Paint</name><name xml:lang="de">Malen</name>
    <summary xml:lang="de">Bilder malen</summary><summary>Draw pictures</summary>
    <developer><name>Example Folk</name></developer>
    <description xml:lang="de"><p>Ein Malprogramm.</p></description>
    <description><p>A painting app.</p><p>With <em>layers</em>.</p><ul><li>Brushes</li><li>Colours</li></ul></description>
    <icon type="cached" width="64" height="64">org.example.Paint.png</icon>
    <icon type="cached" width="128" height="128">org.example.Paint.png</icon>
    <categories><category>Graphics</category></categories>
    <keywords><keyword>Draw</keyword><keyword xml:lang="de">Zeichnen</keyword></keywords>
    <url type="homepage">https://paint.example</url>
    <project_license>GPL-3.0</project_license>
    <screenshots><screenshot type="default"><caption xml:lang="de">Die Leinwand</caption><caption>The canvas</caption>
      <image type="source">https://shots.example/full.png</image>
      <image type="thumbnail" width="624" height="351">https://shots.example/624.png</image>
      <image type="thumbnail" width="752" height="423">https://shots.example/752.png</image>
    </screenshot></screenshots>
    <releases><release version="2.1" timestamp="1"/></releases>
    <bundle type="flatpak">app/org.example.Paint/x86_64/stable</bundle>
  </component>
  <component type="desktop-application">
    <id>com.example.Chat</id><name>Chat</name><summary>Talk to people</summary>
    <categories><category>Network</category></categories>
    <bundle type="flatpak">app/com.example.Chat/x86_64/stable</bundle>
  </component>
  <component type="runtime"><id>org.example.Platform</id><name>Platform</name>
    <bundle type="flatpak">runtime/org.example.Platform/x86_64/1</bundle></component>
  <component type="desktop-application"><id>org.example.NoBundle</id><name>Nothing to install</name></component>
</components>
"""


def load():
    spec = importlib.util.spec_from_file_location("slate_software", SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class SoftwareCase(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        self.s = Stubs(self.h)
        self.flatpak({})
        self.mod = load()
        self.sys_fp = os.path.join(self.h.dir, "var-lib-flatpak")
        active = os.path.join(self.sys_fp, "appstream", "flathub", "x86_64", "active")
        os.makedirs(os.path.join(active, "icons", "128x128"))
        with gzip.open(os.path.join(active, "appstream.xml.gz"), "wt") as f:
            f.write(CATALOGUE)
        self.icon = os.path.join(active, "icons", "128x128", "org.example.Paint.png")
        open(self.icon, "w").close()
        self.mod.SYSTEM_FLATPAK = self.sys_fp
        self.mod.USER_FLATPAK = os.path.join(self.h.dir, "no-user-flatpak")
        self.mod.CACHE = os.path.join(self.h.dir, "cache")
        self.env = mock.patch.dict(os.environ, {"PATH": self.s.env["PATH"]})
        self.env.start()
        self.addCleanup(self.env.stop)

    def hide(self, name):
        """As if `name` isn't installed (and this test's PATH follows: never the real one)."""
        self.s.add(name, missing=True)
        os.environ["PATH"] = self.s.env["PATH"]

    def flatpak(self, by_args, code=0):
        base = {"--default-arch": "x86_64\n"}
        base.update(by_args)
        self.s.add("flatpak", by_args=base, code=code)

    def act(self, *argv):
        out = io.StringIO()
        with redirect_stdout(out):
            code = self.mod.main(list(argv))
        return code, out.getvalue().splitlines()


class Catalogue(SoftwareCase):
    def test_apps_only_with_their_details(self):
        apps = self.mod.catalogue()
        self.assertEqual([a["id"] for a in apps], ["com.example.Chat", "org.example.Paint"], "runtimes and apps with nothing to install are left out; sorted by name")
        paint = apps[1]
        self.assertEqual((paint["name"], paint["summary"], paint["developer"], paint["categories"], paint["keywords"]),
                         ("Paint", "Draw pictures", "Example Folk", ["Graphics"], "draw"))
        self.assertEqual(paint["icon"], self.icon)
        self.assertEqual(apps[0]["icon"], "", "no icon: none named")

    def test_kept_until_the_catalogue_changes(self):
        self.mod.catalogue()
        with open(os.path.join(self.mod.CACHE, "catalogue.json")) as f:
            kept = json.load(f)
        kept["apps"][0]["name"] = "From the cache"
        with open(os.path.join(self.mod.CACHE, "catalogue.json"), "w") as f:
            json.dump(kept, f)
        self.assertEqual(self.mod.catalogue()[0]["name"], "From the cache")
        src = self.mod.appstream_files()[0]
        os.utime(src, (1, 1))
        self.assertEqual(self.mod.catalogue()[0]["name"], "Chat", "a changed catalogue wasn't read again")

    def test_no_flatpak_catalogue(self):
        self.mod.SYSTEM_FLATPAK = os.path.join(self.h.dir, "nothing")
        self.assertEqual(self.mod.catalogue(), [])

    def test_one_app(self):
        self.flatpak({"list": "org.example.Paint\tPaint\t2.0\tsystem\n"})
        a = self.mod.app("org.example.Paint")
        # (in the catalog's own language: Flathub's lists some apps' translations first)
        self.assertEqual(a["summary"], "Draw pictures")
        self.assertEqual(a["description"], ["A painting app.", "With layers.", "• Brushes\n• Colours"])
        self.assertEqual(a["screenshots"], [{"thumb": "https://shots.example/752.png", "full": "https://shots.example/full.png",
                                             "caption": "The canvas"}])
        self.assertEqual((a["homepage"], a["license"], a["latest"]), ("https://paint.example", "GPL-3.0", "2.1"))
        self.assertEqual((a["installed"], a["version"], a["installation"]), (True, "2.0", "system"))
        self.assertIsNone(self.mod.app("org.example.Nothing"))


class Lists(SoftwareCase):
    def test_installed(self):
        self.flatpak({"list": "org.example.Paint\tPaint\t2.0\tsystem\ncom.example.Chat\tChat\t1\tuser\n"})
        self.assertEqual(self.mod.installed(), [{"id": "org.example.Paint", "name": "Paint", "version": "2.0", "installation": "system"},
                                                {"id": "com.example.Chat", "name": "Chat", "version": "1", "installation": "user"}])

    def test_app_updates_from_each_installation(self):
        self.flatpak({"--system --updates": "org.example.Paint\tPaint\t2.1\n", "--user --updates": "com.example.Chat\tChat\t1.1\n"})
        self.assertEqual(self.mod.app_updates(), [{"id": "org.example.Paint", "name": "Paint", "version": "2.1", "installation": "system"},
                                                  {"id": "com.example.Chat", "name": "Chat", "version": "1.1", "installation": "user"}])


class SystemUpdates(SoftwareCase):
    def on(self, fam):
        self.mod.family = lambda: fam
        self.hide("pkcon")

    def test_arch(self):
        self.on("arch")
        self.s.add("checkupdates", stdout="linux 6.1-1 -> 6.2-1\nfirefox 140.0-1 -> 141.0-1\n")
        self.assertEqual(self.mod.system_updates(), ("checkupdates", [{"name": "linux", "from": "6.1-1", "to": "6.2-1"},
                                                                      {"name": "firefox", "from": "140.0-1", "to": "141.0-1"}], ""))

    def test_arch_nothing_to_update(self):
        self.on("arch")
        self.s.add("checkupdates", code=2)
        self.assertEqual(self.mod.system_updates(), ("checkupdates", [], ""))

    def test_arch_without_checkupdates(self):
        self.on("arch")
        self.hide("checkupdates")
        tool, ups, problem = self.mod.system_updates()
        self.assertEqual((tool, ups), ("", []))
        self.assertIn("pacman-contrib", problem)

    def test_debian(self):
        self.on("debian")
        self.s.add("apt", stdout="Listing...\nfirefox/stable 141.0 amd64 [upgradable from: 140.0]\n")
        self.assertEqual(self.mod.system_updates()[1], [{"name": "firefox", "from": "140.0", "to": "141.0"}])

    def test_fedora(self):
        self.on("fedora")
        self.s.add("dnf", stdout="firefox.x86_64   141.0-1.fc41   updates\n", code=100)
        self.assertEqual(self.mod.system_updates()[1], [{"name": "firefox", "from": "", "to": "141.0-1.fc41"}])

    def test_opensuse(self):
        self.on("opensuse")
        self.s.add("zypper", stdout="S | Repository | Name    | Current | Available | Arch\nv | Main       | firefox | 140.0   | 141.0     | x86_64\n")
        self.assertEqual(self.mod.system_updates()[1], [{"name": "firefox", "from": "140.0", "to": "141.0"}])

    def test_nixos_says_so(self):
        self.on("nixos")
        self.assertIn("configuration", self.mod.system_updates()[2])


class Discover(SoftwareCase):
    def reply(self, ids):
        body = json.dumps({"hits": [{"app_id": i} for i in ids]}).encode()
        resp = mock.MagicMock()
        resp.__enter__.return_value.read.return_value = body
        return resp

    def test_lists_kept_for_six_hours(self):
        asked = []
        def fake(req, timeout=None):
            asked.append(req.full_url)
            return self.reply(["org.example.Paint", "bad id; rm", "com.example.Chat"])
        with mock.patch("urllib.request.urlopen", fake):
            got = self.mod.discover()
            again = self.mod.discover()
        self.assertEqual(got["popular"], ["org.example.Paint", "com.example.Chat"], "a name that isn't an app id got through")
        self.assertEqual(len(asked), 3 + len(self.mod.CATEGORIES), "asked again within six hours")
        self.assertTrue(all(u.startswith("https://flathub.org/api/v2/collection/") for u in asked))
        self.assertIn("https://flathub.org/api/v2/collection/category/Game?page=1&per_page=16", asked)
        self.assertEqual(got["categories"]["Game"], ["org.example.Paint", "com.example.Chat"])
        self.assertEqual(again["popular"], got["popular"])
        self.assertEqual(again["categories"], got["categories"])

    def test_offline_keeps_the_last(self):
        with mock.patch("urllib.request.urlopen", lambda req, timeout=None: self.reply(["org.example.Paint"])):
            self.mod.discover()
        with open(os.path.join(self.mod.CACHE, "discover.json")) as f:
            kept = json.load(f)
        kept["at"] = 0
        with open(os.path.join(self.mod.CACHE, "discover.json"), "w") as f:
            json.dump(kept, f)
        def offline(req, timeout=None):
            raise OSError("no network")
        with mock.patch("urllib.request.urlopen", offline):
            got = self.mod.discover()
        self.assertTrue(got["offline"])
        self.assertEqual(got["popular"], ["org.example.Paint"])


class Actions(SoftwareCase):
    def test_install_for_everyone(self):
        self.flatpak({"install": "Installing 1/1… ███ 40%\rInstalling 1/1… ██████ 100%\nInstallation complete.\n"})
        code, lines = self.act("install", "org.example.Paint")
        self.assertEqual(code, 0, lines)
        self.assertEqual(lines, ["progress 40", "progress 100", "ok"])
        self.assertIn(["install", "--system", "-y", "flathub", "org.example.Paint"], self.s.calls("flatpak"))

    def test_progress_from_steps_without_a_terminal(self):
        """Away from a terminal, Flatpak and pacman draw no bars, only steps: those are the
        progress (it sat at 0% before). It never goes backwards."""
        flatpak_says = "Looking for updates…\nUpdating 1/4…\nUpdating 2/4… 50%\nUpdating 3/4…\nUpdating 4/4…\nUpdates complete.\n"
        got = [int(l.split()[1]) for l in self.mod.progress_lines(flatpak_says.splitlines())]
        self.assertEqual(got, [0, 37, 50, 75], "(and 100 once it's done: follow)")
        pacman_says = [":: Starting full system upgrade...", "resolving dependencies...",
                       "Packages (4) linux-6.2-1  mesa-2-1  vim-9-1  zsh-5-1", "Total Download Size:  120.00 MiB",
                       ":: Retrieving packages...", " downloading linux-6.2-1-x86_64.pkg.tar.zst...",
                       " downloading mesa-2-1-x86_64.pkg.tar.zst...", " downloading vim-9-1-x86_64.pkg.tar.zst...",
                       " downloading zsh-5-1-x86_64.pkg.tar.zst...", "(4/4) checking keys in keyring",
                       "(4/4) checking package integrity", "(1/4) upgrading linux", "(2/4) upgrading mesa",
                       "(3/4) upgrading vim", "(4/4) upgrading zsh", ":: Running post-transaction hooks...", "(1/2) Updating icon cache"]
        got = [int(l.split()[1]) for l in self.mod.progress_lines(pacman_says)]
        self.assertEqual(got, sorted(got), "went backwards")
        self.assertEqual(got[:4], [10, 20, 30, 40], "downloads: the first 40%")
        self.assertEqual(got[4:], [55, 70, 85], "upgrades: the rest (hooks don't count)")

    def test_only_an_app_id(self):
        for bad in ("org.example.Paint; rm -rf ~", "--user", "paint", "../x"):
            with self.subTest(bad):
                code, lines = self.act("install", bad)
                self.assertEqual((code, lines), (1, ["error That isn't an app's name"]))
        self.assertFalse([c for c in self.s.calls("flatpak") if "install" in c])

    def test_password_prompt_closed(self):
        self.flatpak({"install": ["error: Flatpak system operation Deploy not allowed for user. Not authorized\n", 1]})
        self.assertEqual(self.act("install", "org.example.Paint"), (1, ["error canceled"]))

    def test_remove_from_where_it_is(self):
        self.flatpak({"list": "com.example.Chat\tChat\t1\tuser\n", "uninstall": "Uninstall complete.\n"})
        self.assertEqual(self.act("remove", "com.example.Chat"), (0, ["progress 100", "ok"]))
        self.assertIn(["uninstall", "--user", "-y", "com.example.Chat"], self.s.calls("flatpak"))

    def test_update_apps_in_each_installation(self):
        self.flatpak({"--system --updates": "org.example.Paint\tPaint\t2.1\n", "--user --updates": "com.example.Chat\tChat\t1.1\n",
                      "update": "Updating… 100%\n"})
        self.assertEqual(self.act("update-apps")[1][-1], "ok")
        calls = [c for c in self.s.calls("flatpak") if c and c[0] == "update"]
        self.assertEqual(calls, [["update", "--system", "-y", "org.example.Paint"],
                                 ["update", "--user", "-y", "com.example.Chat"]])

    def test_system_through_slate_system(self):
        fake = os.path.join(self.h.dir, "slate-code")
        os.makedirs(os.path.join(fake, "bin"))
        log = os.path.join(self.h.dir, "asked")
        with open(os.path.join(fake, "bin", "slate-system"), "w") as f:
            f.write('#!/bin/sh\necho "$*" > "%s"\necho "(1/3) upgrading 50%%"\n' % log)
        os.chmod(os.path.join(fake, "bin", "slate-system"), 0o755)
        self.mod.SLATE = fake
        self.assertEqual(self.act("update-system")[1], ["progress 16", "progress 100", "ok"])
        with open(log) as f:
            self.assertEqual(f.read().strip(), "--upgrade")

    def test_without_flatpak_says_what_to_install(self):
        self.hide("flatpak")
        self.assertEqual(self.act("install", "org.example.Paint")[1], ["error Flatpak isn't installed (install the flatpak package)"])
        self.assertEqual(json.loads(run([sys.executable, SCRIPT, "status"], env=self.s.env)[1]),
                         {"flatpak": False, "flathub": False, "catalogue": False})


class Jobs(SoftwareCase):
    """`job`: an action run as a process of its own, keeping how it's going in a private file
    Slate follows (so a reload of Slate can't cut it off or lose it)."""
    def test_progress_and_result_in_a_private_file(self):
        self.flatpak({"install": "Installing 1/1… 40%\rInstalling 1/1… 100%\n"})
        run_dir = os.path.join(self.h.dir, "run")
        os.makedirs(run_dir)
        env = dict(os.environ, XDG_RUNTIME_DIR=run_dir)
        code, out = run([sys.executable, SCRIPT, "job", "t1", "install", "org.example.Paint"], env=env)
        self.assertEqual(code, 0, out)
        path = os.path.join(run_dir, "slate", "software-job.json")
        with open(path) as f:
            state = json.load(f)
        self.assertEqual({k: state[k] for k in ("token", "what", "id", "progress", "done", "result")},
                         {"token": "t1", "what": "install", "id": "org.example.Paint", "progress": 100, "done": True, "result": "ok"})
        self.assertEqual(os.stat(path).st_mode & 0o777, 0o600)
        self.assertEqual(os.stat(os.path.dirname(path)).st_mode & 0o777, 0o700)

    def test_only_known_actions(self):
        code, out = run([sys.executable, SCRIPT, "job", "t1", "rm", "-rf"], env=dict(os.environ, XDG_RUNTIME_DIR=self.h.dir))
        self.assertNotEqual(code, 0)


class Daily(SoftwareCase):
    """`daily`: what the once-a-day look finds, and never on a metered connection."""
    def nm(self, value):
        self.s.add("gdbus", stdout="(<uint32 %d>,)\n" % value)

    def test_counts(self):
        self.nm(2)          # not metered
        self.flatpak({"--system --updates": "org.example.Paint\tPaint\t2.1\n", "--user --updates": ""})
        self.mod.system_updates = lambda: ("checkupdates", [{"name": "linux", "from": "1", "to": "2"}, {"name": "mesa", "from": "1", "to": "2"}], "")
        self.assertEqual(self.mod.daily(), {"apps": 1, "system": 2})

    def test_metered_waits(self):
        for value in (1, 3):            # metered, or guessed so
            with self.subTest(value):
                self.nm(value)
                self.mod.system_updates = lambda: self.fail("looked on a metered connection")
                self.assertEqual(self.mod.daily(), {"metered": True})

    def test_without_networkmanager(self):
        self.hide("gdbus")
        self.mod.system_updates = lambda: ("", [], "")
        self.assertEqual(self.mod.daily(), {"apps": 0, "system": 0})
