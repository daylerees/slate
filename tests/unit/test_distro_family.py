"""Which distro this is, and what follows from it.

Three places work out the distro family from /etc/os-release: install.sh, bin/slate-system
and scripts/slate_apps.py (Settings → App Theming). They have to give the same answer, or one
offers what another refuses: Artix was "arch" to App Theming, whose Install button then ran
slate-system --install, which knew it as "artix" and refused it. Here each is run on the same
os-release samples.

Then slate-system itself on those families, with every command it would run stubbed:
--install gets as far as asking for your password wherever its root half can install, and
the "finish by hand" notification names a command, or leaves the sentence out.

install.sh and slate-system read /etc/os-release by name, so they're run from the source with
that one path swapped for a sample's.
"""
import os
import shutil
import sys

import slate
from slate import Case, run
from stubs import Stubs

sys.path.insert(0, slate.path("shell", "scripts"))
import slate_apps  # noqa: E402

# name: (os-release, the family)
SAMPLES = {
    "arch": ('NAME="Arch Linux"\nPRETTY_NAME="Arch Linux"\nID=arch\nBUILD_ID=rolling\n', "arch"),
    "cachyos": ('NAME="CachyOS Linux"\nID=cachyos\nID_LIKE=arch\n', "arch"),
    "an arch derivative Slate hasn't heard of": ('ID=somethingos\nID_LIKE=arch\n', "arch"),
    "manjaro": ('ID=manjaro\nID_LIKE=arch\n', "arch"),
    # Artix says it's like Arch, but is its own family (no systemd, its own package list)
    "artix": ('NAME="Artix Linux"\nID=artix\nID_LIKE=arch\n', "artix"),
    "artix, like before id": ('ID_LIKE=arch\nID=artix\n', "artix"),
    "void": ('NAME="Void"\nID="void"\n', "void"),
    "void, single quotes": ("ID='void'\n", "void"),
    "gentoo": ('NAME=Gentoo\nID=gentoo\n', "gentoo"),
    "debian": ('PRETTY_NAME="Debian GNU/Linux 12 (bookworm)"\nID=debian\n', "debian"),
    "ubuntu": ('ID=ubuntu\nID_LIKE=debian\n', "debian"),
    "mint": ('ID=linuxmint\nID_LIKE="ubuntu debian"\n', "debian"),
    "fedora": ('ID=fedora\nVERSION_ID=42\n', "fedora"),
    "nobara": ('ID=nobara\nID_LIKE="rhel centos fedora"\n', "fedora"),
    "tumbleweed": ('ID="opensuse-tumbleweed"\nID_LIKE="opensuse suse"\n', "opensuse"),
    "leap": ('ID="opensuse-leap"\nID_LIKE="suse opensuse"\n', "opensuse"),
    "nixos": ('ID=nixos\n', "nixos"),
    "slackware": ('ID=slackware\n', ""),
    "nothing in it": ('', ""),
}

SLATE_SYSTEM = slate.path("shell", "bin", "slate-system")
OS_RELEASE = "/etc/os-release"


def swapped(src, sample):
    """A script's source, reading `sample` where it read /etc/os-release."""
    assert OS_RELEASE in src, "it doesn't read /etc/os-release any more: this test needs another way in"
    return src.replace(OS_RELEASE, sample)


class Family(Case):
    scratch = True

    def sample(self, text):
        p = os.path.join(self.h.dir, "os-release")
        with open(p, "w", encoding="utf-8") as f:
            f.write(text)
        return p

    def from_install_sh(self, sample):
        block = slate.read("install.sh").split("# ---- Which distro", 1)[1].split('\necho "${B}Slate installer', 1)[0]
        block = block.split("\n", 1)[1]        # (the rest of the heading's own line)
        code, out = run(["bash", "-c", swapped(block, sample) + '\nprintf "%s" "$family"'], env=self.h.env)
        self.assertEqual(code, 0, out)
        return out

    def from_slate_system(self, sample):
        fn = "family() {" + slate.read("shell", "bin", "slate-system").split("\nfamily() {", 1)[1].split("\n}\n", 1)[0] + "\n}\n"
        code, out = run(["bash", "-c", swapped(fn, sample) + 'printf "%s" "$(family)"'], env=self.h.env)
        self.assertEqual(code, 0, out)
        return out

    def test_all_three_agree(self):
        for name, (text, want) in SAMPLES.items():
            p = self.sample(text)
            with self.subTest(name):
                self.assertEqual(self.from_install_sh(p), want, f"{name}: install.sh")
                self.assertEqual(self.from_slate_system(p), want, f"{name}: slate-system")
                self.assertEqual(slate_apps.family(p), want, f"{name}: slate_apps.family()")

    def test_no_os_release(self):
        p = os.path.join(self.h.dir, "missing")
        self.assertEqual(self.from_install_sh(p), "")
        self.assertEqual(self.from_slate_system(p), "")
        self.assertEqual(slate_apps.family(p), "")

    def test_a_list_for_every_family(self):
        """Every family has its packaging list (NixOS: packaging/nixos.nix)."""
        for fam in sorted({want for _, want in SAMPLES.values()} - {"", "nixos"}):
            with self.subTest(fam):
                self.assertTrue(os.path.isfile(slate.path("packaging", fam + ".txt")))


class SlateSystem(Case):
    """bin/slate-system as it would run on each distro: a copy that reads a sample os-release,
    beside the real packaging lists, with the package managers, pkexec and notify-send stubbed."""
    scratch = True

    # family: what its "finish by hand" command starts with
    BY_HAND = {"arch": "sudo pacman -S --needed ", "artix": "sudo pacman -S --needed ", "void": "sudo xbps-install -S ",
               "debian": "sudo apt install ", "fedora": "sudo dnf install ", "opensuse": "sudo zypper install "}

    def setUp(self):
        super().setUp()
        self.s = Stubs(self.h)
        self.os_release = os.path.join(self.h.dir, "os-release")
        root = os.path.join(self.h.dir, "slate")
        os.makedirs(os.path.join(root, "bin"))
        shutil.copytree(slate.path("packaging"), os.path.join(root, "packaging"))
        self.script = os.path.join(root, "bin", "slate-system")
        with open(self.script, "w", encoding="utf-8") as f:
            f.write(swapped(slate.read("shell", "bin", "slate-system"), self.os_release))
        os.chmod(self.script, 0o755)
        self.script = os.path.realpath(self.script)      # (as its own readlink -f gives it to pkexec)

    def on(self, name):
        with open(self.os_release, "w", encoding="utf-8") as f:
            f.write(SAMPLES[name][0])

    def test_install_reaches_the_password_prompt(self):
        """Wherever the root half can install packages, --install hands them to pkexec."""
        for name in ("arch", "artix", "void", "debian", "fedora", "tumbleweed"):
            with self.subTest(name):
                self.on(name)
                self.s.add("pkexec", stdout="")
                before = len(self.s.calls("pkexec"))
                code, out = run([self.script, "--install", "kitty", "foot"], env=self.s.env, timeout=10)
                self.assertEqual(code, 0, out)
                self.assertEqual(self.s.calls("pkexec")[before:], [[self.script, "--as-root", "kitty", "foot"]])

    def test_install_refused_where_it_cant(self):
        """Gentoo (emerge is yours), NixOS (your configuration) and anything unknown: said so,
        before any password prompt."""
        self.s.add("pkexec", stdout="")
        for name, words in (("gentoo", "don't know how to install packages here"), ("nixos", "on NixOS"),
                            ("slackware", "don't know how to install packages here")):
            with self.subTest(name):
                self.on(name)
                code, out = run([self.script, "--install", "kitty"], env=self.s.env, timeout=10)
                self.assertNotEqual(code, 0)
                self.assertIn(words, out)
        self.assertEqual(self.s.calls("pkexec"), [])

    def not_installed(self, name):
        """--prompt where packages are missing, Install is pressed and the password prompt is
        cancelled: the body of the "Not installed" notification."""
        self.on(name)
        # Nothing is installed, as far as each distro's own query says
        for query in ("pacman", "xbps-query", "dpkg", "rpm"):
            self.s.add(query, stdout="", code=1)
        self.s.add("pkexec", stdout="", code=126)                                # (cancelled)
        self.s.add("notify-send", by_args={"install=Install": "install\n", "": ""})
        code, out = run([self.script, "--prompt"], env=self.s.env, timeout=120)
        self.assertEqual(code, 0, out)
        last = self.s.calls("notify-send")[-1]
        self.assertEqual(last[-2], "Not installed", last)
        return last[-1]

    def test_finish_by_hand_names_a_command(self):
        for name in ("arch", "artix", "void", "debian", "fedora", "tumbleweed"):
            with self.subTest(name):
                fam = SAMPLES[name][1]
                body = self.not_installed(name)
                start = "To finish by hand, run: " + self.BY_HAND[fam]
                self.assertTrue(body.startswith(start), f"{name}: {body!r}")
                # (and the packages after it: the first required one in its list)
                first = next(l.split("#")[0].strip() for l in slate.read("packaging", fam + ".txt").splitlines()
                             if l.strip() and l.strip()[0] not in "#?" and not l.startswith("copr:"))
                self.assertIn(" " + first, body[len(start) - 1:] + " ")

    def test_never_run_followed_by_nothing(self):
        """Whatever the family, the sentence has a command after it or isn't there."""
        src = slate.read("shell", "bin", "slate-system")
        self.assertNotIn('"To finish by hand, run: $cmd"\n', src.replace('hint="To finish by hand, run: $cmd"\n', ""),
                         "said even when there's no command to give")
        self.assertIn('[ -n "$cmd" ] && hint="To finish by hand, run: $cmd"', src)
