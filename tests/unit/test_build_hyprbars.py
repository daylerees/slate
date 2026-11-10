"""bin/slate-build-hyprbars: builds the optional Hyprbars plugin for the installed Hyprland,
names each build for its Hyprland, keeps a record beside it, and reports what Slate needs to
know (--status). Run against a small git repository standing in for hyprland-plugins, with
make, g++, pkg-config and hyprctl stubbed; nothing is compiled or downloaded."""
import fcntl
import json
import os
import shutil
import stat

import slate
from slate import Case, run
from stubs import Stubs

SCRIPT = slate.path("shell", "bin", "slate-build-hyprbars")
COMMIT = "11cbc6c577b84ffb1edf4df3fc5b6128c3ae6947"
NEWER = "ffee00112233445566778899aabbccddeeff0011"

# make -C <dir> all: "builds" hyprbars.so there, unless told to fail
MAKE = """#!/bin/sh
[ -n "$STUB_MAKE_FAILS" ] && { echo "hyprbars.cpp: error: no member named foo" >&2; exit 2; }
echo "plugin built from $(git -C "$2" describe --tags --always 2>/dev/null)" > "$2/hyprbars.so"
"""


class BuildCase(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        slate.need("git")
        slate.need("flock")
        self.s = Stubs(self.h)
        self.env = self.s.env
        self.out = os.path.join(self.h.data, "slate", "plugins")
        self.state = os.path.join(self.h.state, "slate", "hyprbars-build.json")
        self.sig = COMMIT + "_1794313951_949994311"
        self.env.update(HYPRLAND_INSTANCE_SIGNATURE=self.sig, SLATE_HYPRBARS_WAIT="0",
                        SLATE_HYPRBARS_SYSTEM=os.path.join(self.h.dir, "no-system", "hyprbars.so"),
                        GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_SYSTEM="/dev/null")
        # hyprland-plugins, with a release for Hyprland 0.57
        self.repo = os.path.join(self.h.dir, "hyprland-plugins")
        os.makedirs(os.path.join(self.repo, "hyprbars"))
        with open(os.path.join(self.repo, "hyprbars", "Makefile"), "w") as f:
            f.write("all:\n")
        git = ["git", "-C", self.repo, "-c", "user.name=t", "-c", "user.email=t@example.invalid"]
        for cmd in (["init", "-q", "-b", "main"], ["add", "."], ["commit", "-q", "-m", "hyprbars"], ["tag", "v0.57.0"]):
            self.ok(git + cmd, env=self.env)
        self.env["SLATE_HYPRBARS_REPO"] = self.repo
        self.s.add("g++")
        p = os.path.join(self.s.dir, "make")
        with open(p, "w") as f:
            f.write(MAKE)
        os.chmod(p, os.stat(p).st_mode | stat.S_IXUSR)
        self.hyprland(running=("0.57.2", COMMIT), installed=("0.57.2", COMMIT))

    def hyprland(self, running=None, installed=None, loaded=None):
        """Which Hyprland is running and which is installed, and whether hyprbars is loaded."""
        if running is not None:
            self.running = running
        if installed is not None:
            self.installed = installed
        if loaded is not None:
            self.loaded = loaded
        loaded = getattr(self, "loaded", False)
        self.s.add("hyprctl", by_args={
            "version": json.dumps({"version": self.running[0], "commit": self.running[1], "tag": "v" + self.running[0]}) + "\n",
            "plugin list": ('[{"name": "hyprbars", "author": "Vaxry"}]\n' if loaded else "[]\n")})
        inc = os.path.join(self.h.dir, "include")
        os.makedirs(inc, exist_ok=True)
        if self.installed:
            with open(os.path.join(inc, "version.h"), "w") as f:
                f.write(f'#pragma once\n#define GIT_COMMIT_HASH    "{self.installed[1]}"\n#define GIT_TAG "v{self.installed[0]}"\n')
            self.s.add("pkg-config", by_args={"--modversion": self.installed[0] + "\n", "--cflags-only-I": f"-I{inc}/protocols -I{inc}\n"})
        else:
            self.s.add("pkg-config", code=1)

    def build(self):
        return run(["bash", SCRIPT], env=self.env)

    def status(self):
        code, out = run(["bash", SCRIPT, "--status"], env=self.env)
        self.assertEqual(code, 0, out)
        return dict(l.split("=", 1) for l in out.splitlines() if "=" in l)

    def last(self):
        with open(self.state) as f:
            return json.load(f)

    def plant(self, name, record=None):
        os.makedirs(self.out, exist_ok=True)
        p = os.path.join(self.out, name)
        with open(p, "w") as f:
            f.write("an older build")
        if record is not None:
            with open(p[:-3] + ".json", "w") as f:
                json.dump(record, f)
        return p

    def builds(self):
        return sorted(n for n in os.listdir(self.out)) if os.path.isdir(self.out) else []

    def note_loaded(self, path):
        d = os.path.join(self.h.runtime, "hypr", self.sig)
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, "slate-hyprbars"), "w") as f:
            f.write(path)


class Build(BuildCase):
    def test_named_for_its_hyprland(self):
        code, out = self.build()
        self.assertEqual(code, 0, out)
        self.assertEqual(self.builds(), ["hyprbars-0.57.2-11cbc6c577b8.json", "hyprbars-0.57.2-11cbc6c577b8.so"])
        with open(os.path.join(self.out, "hyprbars-0.57.2-11cbc6c577b8.json")) as f:
            rec = json.load(f)
        self.assertEqual((rec["version"], rec["commit"]), ("0.57.2", COMMIT))
        self.assertIs(rec["patched"], False, "Slate's patch can't apply to the stand-in source")
        with open(os.path.join(self.out, "hyprbars-0.57.2-11cbc6c577b8.so")) as f:
            self.assertIn("v0.57.0", f.read(), "not built from the release for this Hyprland")
        self.assertEqual(self.last(), {"state": "built", "for": "0.57.2", "error": ""})
        self.assertIn("hyprctl reload", out)
        st = self.status()
        self.assertEqual((st["build"], st["next"], st["any"], st["state"], st["stateFor"]), ("yes", "yes", "yes", "built", "0.57.2"))

    def test_for_the_installed_hyprland_not_the_running_one(self):
        """Hyprland updated but not restarted: the new build sits beside the running one's."""
        self.build()
        self.hyprland(installed=("0.58.0", NEWER))
        st = self.status()
        self.assertEqual((st["build"], st["next"]), ("yes", "no"))
        code, out = self.build()
        self.assertEqual(code, 0, out)
        self.assertIn("after your next restart", out)
        self.assertNotIn("hyprctl reload", out)
        self.assertEqual([n for n in self.builds() if n.endswith(".so")],
                         ["hyprbars-0.57.2-11cbc6c577b8.so", "hyprbars-0.58.0-ffee00112233.so"])
        st = self.status()
        self.assertEqual((st["build"], st["next"], st["running"], st["installed"]), ("yes", "yes", "0.57.2", "0.58.0"))

    def test_older_builds_go(self):
        self.plant("hyprbars-0.56.0-aaaaaaaaaaaa.so", {"version": "0.56.0", "commit": "a" * 40})
        self.plant("hyprbars.so", {"version": "0.56.0", "commit": "a" * 40})
        self.assertEqual(self.build()[0], 0)
        self.assertEqual([n for n in self.builds() if n.endswith(".so")], ["hyprbars-0.57.2-11cbc6c577b8.so"])

    def test_the_loaded_build_stays(self):
        """Hyprland keeps asking for the file it loaded: a rebuild never deletes it."""
        old = self.plant("hyprbars.so")
        self.hyprland(loaded=True)
        self.note_loaded(old)
        self.assertEqual(self.build()[0], 0)
        self.assertIn("hyprbars.so", self.builds())

    def test_no_headers(self):
        self.hyprland(installed=())
        code, out = self.build()
        self.assertEqual(code, 1)
        self.assertIn("headers aren't installed", out)
        self.assertEqual(self.last()["state"], "failed")
        self.assertIn("headers", self.last()["error"])
        self.assertEqual(self.builds(), [])

    def test_missing_compiler(self):
        os.remove(os.path.join(self.s.dir, "g++"))
        self.s.add("g++", missing=True)
        code, out = run(["bash", SCRIPT], env=self.s.env)
        self.assertEqual(code, 1)
        self.assertEqual(self.last()["error"], "Needs g++, which isn't installed")

    def test_does_not_compile(self):
        code, out = run(["bash", SCRIPT], env=dict(self.env, STUB_MAKE_FAILS="1"))
        self.assertEqual(code, 1)
        self.assertEqual(self.last()["state"], "failed")
        self.assertIn("doesn't compile for Hyprland 0.57.2", self.last()["error"])
        self.assertEqual(self.builds(), [])

    def test_no_connection(self):
        self.env["SLATE_HYPRBARS_REPO"] = os.path.join(self.h.dir, "nowhere")
        code, out = self.build()
        self.assertEqual(code, 1)
        self.assertEqual(self.last(), {"state": "failed", "for": "0.57.2", "error": "No internet connection"})

    def test_offline_with_the_source_kept(self):
        """The source is kept between builds: with the release already there, no connection is needed."""
        self.assertEqual(self.build()[0], 0)
        shutil.rmtree(self.repo)
        shutil.rmtree(self.out)
        code, out = self.build()
        self.assertEqual(code, 0, out)
        self.assertEqual(self.last()["state"], "built")

    def test_one_at_a_time(self):
        lock = os.path.join(self.h.runtime, "slate-hyprbars-build.lock")
        with open(lock, "w") as f:
            fcntl.flock(f, fcntl.LOCK_EX)
            code, out = self.build()
            self.assertEqual(code, 3)
            self.assertIn("already building", out)
            os.makedirs(os.path.dirname(self.state), exist_ok=True)
            with open(self.state, "w") as g:
                json.dump({"state": "building", "for": "0.57.2", "error": ""}, g)
            self.assertEqual(self.status()["state"], "building")
        # (the build died without saying so)
        st = self.status()
        self.assertEqual((st["state"], st["error"]), ("failed", "The build was interrupted"))

    def test_unknown_option(self):
        code, out = run(["bash", SCRIPT, "--frobnicate"], env=self.env)
        self.assertEqual(code, 2)
        self.assertIn("slate build-hyprbars", out)


class Status(BuildCase):
    def test_nothing_built(self):
        st = self.status()
        self.assertEqual(st, {"running": "0.57.2", "runningCommit": COMMIT, "installed": "0.57.2", "installedCommit": COMMIT,
                              "loaded": "no", "build": "no", "next": "no", "any": "no", "system": "no", "removed": "no",
                              "state": "", "stateFor": "", "error": ""})
        self.assertFalse(os.path.exists(self.out), "--status made something")

    def test_stale(self):
        self.plant("hyprbars-0.57.1-acc1aa000000.so", {"version": "0.57.1", "commit": "acc1aa0" + "0" * 33})
        st = self.status()
        self.assertEqual((st["any"], st["build"], st["loaded"]), ("yes", "no", "no"))

    def test_same_version_other_commit(self):
        self.plant("hyprbars.so", {"version": "0.57.2", "commit": NEWER})
        self.assertEqual(self.status()["build"], "no")

    def test_old_build_adopted_when_loaded(self):
        """A build from before builds were named: once it's seen loaded, it's for this Hyprland."""
        old = self.plant("hyprbars.so")
        self.assertEqual(run(["bash", SCRIPT, "--adopt"], env=self.env)[0], 0)
        self.assertEqual(self.builds(), ["hyprbars.so"], "adopted without being loaded")
        self.assertEqual(self.status()["build"], "no")
        self.hyprland(loaded=True)
        self.assertEqual(self.status()["build"], "yes")
        self.assertEqual(run(["bash", SCRIPT, "--adopt"], env=self.env)[0], 0)
        with open(old[:-3] + ".json") as f:
            rec = json.load(f)
        self.assertEqual((rec["version"], rec["commit"]), ("0.57.2", COMMIT))
        # …and it's out of date once Hyprland is another one
        self.hyprland(running=("0.58.0", NEWER), loaded=False)
        st = self.status()
        self.assertEqual((st["build"], st["any"]), ("no", "yes"))

    def test_linked_build_is_someone_elses(self):
        """NixOS links the plugin Nix built to where Slate looks: it's kept in step by Nix, so
        it's never adopted (which would stop it loading after the next update) or removed."""
        target = os.path.join(self.h.dir, "nix-store", "libhyprbars.so")
        os.makedirs(os.path.dirname(target))
        open(target, "w").close()
        os.makedirs(self.out)
        os.symlink(target, os.path.join(self.out, "hyprbars.so"))
        self.hyprland(loaded=True)
        self.assertEqual(run(["bash", SCRIPT, "--adopt"], env=self.env)[0], 0)
        self.assertEqual(self.builds(), ["hyprbars.so"])
        st = self.status()
        self.assertEqual((st["system"], st["any"], st["build"]), ("yes", "no", "yes"))
        self.assertEqual(run(["bash", SCRIPT, "--remove"], env=self.env)[0], 0)
        self.assertTrue(os.path.islink(os.path.join(self.out, "hyprbars.so")))

    def test_distro_package(self):
        p = self.env["SLATE_HYPRBARS_SYSTEM"]
        os.makedirs(os.path.dirname(p))
        open(p, "w").close()
        st = self.status()
        self.assertEqual((st["system"], st["any"]), ("yes", "no"))


class Remove(BuildCase):
    def remove(self):
        code, out = run(["bash", SCRIPT, "--remove"], env=self.env)
        self.assertEqual(code, 0, out)

    def test_not_loaded(self):
        self.build()
        self.plant("hyprbars.so")
        self.remove()
        self.assertEqual(self.builds(), [])
        self.assertFalse(os.path.exists(self.state))
        st = self.status()
        self.assertEqual((st["any"], st["build"], st["removed"], st["state"]), ("no", "no", "no", ""))

    def test_loaded_build_goes_after_hyprland_restarts(self):
        self.build()
        mine = os.path.join(self.out, "hyprbars-0.57.2-11cbc6c577b8.so")
        self.plant("hyprbars-0.58.0-ffee00112233.so", {"version": "0.58.0", "commit": NEWER})
        self.hyprland(loaded=True)
        self.note_loaded(mine)
        self.remove()
        self.assertEqual(self.builds(), ["hyprbars-0.57.2-11cbc6c577b8.json", "hyprbars-0.57.2-11cbc6c577b8.so", "removed"])
        st = self.status()
        self.assertEqual((st["any"], st["build"], st["next"], st["removed"], st["loaded"]), ("no", "no", "no", "yes", "yes"))
        # Hyprland has started again, without it
        self.hyprland(loaded=False)
        st = self.status()
        self.assertEqual((st["any"], st["removed"]), ("no", "no"))
        self.assertEqual(self.builds(), [])

    def test_building_again_clears_it(self):
        self.build()
        self.hyprland(loaded=True)
        self.note_loaded(os.path.join(self.out, "hyprbars-0.57.2-11cbc6c577b8.so"))
        self.remove()
        self.assertEqual(self.build()[0], 0)
        st = self.status()
        self.assertEqual((st["removed"], st["any"], st["build"]), ("no", "yes", "yes"))
