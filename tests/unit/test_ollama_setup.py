"""scripts/ollama-setup.py, Settings → Assistant's Set up Ollama: which package for which
distro and graphics card (and that the root half takes exactly those), which model for how much
memory, the graphics card read from /sys, the setting up's steps as Settings sees them, and the
download's progress from Ollama's own API. No real network, password or Ollama."""
import http.server
import importlib.util
import json
import os
import re
import threading

import slate
from slate import Case


def load():
    spec = importlib.util.spec_from_file_location("ollama_setup", slate.path("shell", "scripts", "ollama-setup.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


GIB = 1 << 30


class Choices(Case):
    def setUp(self):
        super().setUp()
        self.mod = load()

    def test_the_root_half_takes_exactly_these(self):
        """Every package Settings can choose is one bin/slate-system-root installs for that
        family, and it installs nothing Settings wouldn't choose. slate-system's own check
        lets them all through too."""
        src = slate.read("shell", "bin", "slate-system-root")
        allowed = set(re.findall(r"\b(arch|fedora|opensuse):(ollama[\w-]*)", src.split("--ollama ]")[1].split("\nfi\n")[0]))
        chosen = {(fam, pkg) for fam, by_gpu in self.mod.PACKAGES.items() for pkg in by_gpu.values()}
        self.assertEqual(chosen, allowed)
        user = re.search(r"\[\[ \"\$1\" =~ (\S+) \]\]", slate.read("shell", "bin", "slate-system").split("ollama() {")[1]).group(1)
        for _, pkg in chosen:
            self.assertTrue(re.fullmatch(user, pkg), pkg)

    def test_packages(self):
        for fam, gpu, want in (("arch", "nvidia", "ollama-cuda"), ("arch", "amd", "ollama-vulkan"), ("arch", "none", "ollama"),
                               ("opensuse", "nvidia", "ollama-vulkan"), ("fedora", "amd", "ollama"),
                               ("debian", "nvidia", ""), ("void", "none", ""), ("artix", "none", ""), ("nixos", "none", ""), ("", "none", "")):
            with self.subTest(fam=fam, gpu=gpu):
                self.assertEqual(self.mod.choose_package(fam, gpu), want)

    def test_the_model_that_fits(self):
        for ram, vram, want in ((0, 0, "qwen3:1.7b"),                 # (nothing known: the smallest)
                                (8 * GIB, 0, "qwen3:1.7b"),
                                (16 * GIB, 0, "qwen3:4b"),
                                (32 * GIB, 0, "qwen3:8b"),
                                (128 * GIB, 0, "qwen3:8b"),          # (on the processor: never bigger)
                                (16 * GIB, 8 * GIB, "qwen3:8b"),
                                (16 * GIB, 12 * GIB, "qwen3:14b"),
                                (32 * GIB, 16 * GIB, "qwen3:14b"),
                                (16 * GIB, 2 * GIB, "qwen3:4b")):     # (a sliver of its own: the memory decides)
            with self.subTest(ram=ram, vram=vram):
                self.assertEqual(self.mod.fits(ram, vram)[0], want)


class GraphicsCard(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        self.mod = load()
        self.mod.nvidia_memory = lambda: 8 * GIB
        self.sys = os.path.join(self.h.dir, "sys")

    def card(self, n, vendor, vram=None):
        d = os.path.join(self.sys, "class", "drm", "card%d" % n, "device")
        os.makedirs(d)
        with open(os.path.join(d, "vendor"), "w") as f:
            f.write(vendor + "\n")
        if vram is not None:
            with open(os.path.join(d, "mem_info_vram_total"), "w") as f:
                f.write(str(vram))
        # (and the connectors beside it, which aren't cards)
        os.makedirs(os.path.join(self.sys, "class", "drm", "card%d-eDP-1" % n), exist_ok=True)

    def test_none(self):
        self.assertEqual(self.mod.gpu(self.sys), ("none", 0))

    def test_built_in_intel(self):
        self.card(0, "0x8086")
        self.assertEqual(self.mod.gpu(self.sys), ("intel", 0))

    def test_a_card_of_its_own_wins(self):
        self.card(0, "0x8086")
        self.card(1, "0x1002", 16 * GIB)
        self.assertEqual(self.mod.gpu(self.sys), ("amd", 16 * GIB))

    def test_nvidia_says_its_memory(self):
        self.card(0, "0x1002", 512 << 20)       # (AMD built in: a sliver set aside)
        self.card(1, "0x10de")
        self.assertEqual(self.mod.gpu(self.sys), ("nvidia", 8 * GIB))

    def test_others_are_left_out(self):
        self.card(0, "0x1af4")                  # (a virtual machine's)
        self.assertEqual(self.mod.gpu(self.sys), ("none", 0))


class Steps(Case):
    """setup: what Settings sees in the state file, step by step, with slate-system and Ollama
    stood in for."""
    scratch = True

    def setUp(self):
        super().setUp()
        self.mod = load()
        self.mod.STATE = os.path.join(self.h.dir, "state", "ollama-setup.json")
        self.mod.HERE = os.path.join(self.h.dir, "slate")
        os.makedirs(os.path.join(self.mod.HERE, "bin"))
        self.calls = os.path.join(self.h.dir, "calls")
        self.saved = []
        save = self.mod.save
        self.mod.save = lambda st: (self.saved.append(dict(st)), save(st))
        self.mod.wait = lambda secs: True
        self.pulled = []

        def pull(model, heard):
            self.pulled.append(model)
            heard({"got": 1, "size": 4})
            heard({"got": 4, "size": 4})
            heard({"done": True})
            return 0
        self.mod.pull = pull
        self.bin("slate", 0)
        self.bin("slate-system", 0)

    def bin(self, name, code, say=""):
        p = os.path.join(self.mod.HERE, "bin", name)
        with open(p, "w") as f:
            f.write('#!/bin/sh\necho "%s $*" >> "%s"\n%sexit %d\n' % (name, self.calls, 'echo "%s" >&2\n' % say if say else "", code))
        os.chmod(p, 0o755)

    def ran(self):
        with open(self.calls) as f:
            return f.read().splitlines()

    def state(self):
        with open(self.mod.STATE) as f:
            return json.load(f)

    def test_installs_then_downloads_then_chooses(self):
        self.assertEqual(self.mod.setup("ollama-cuda", "qwen3:8b"), 0)
        self.assertEqual([s["step"] for s in self.saved][:3], ["installing", "starting", "downloading"])
        self.assertEqual(self.state()["step"], "done")
        self.assertIn("at", self.state(), "Settings can't tell a step cut short")
        self.assertEqual(self.ran(), ["slate-system --ollama ollama-cuda",
                                      "slate ipc call config set assistantLocalModel qwen3:8b"])
        self.assertEqual(self.pulled, ["qwen3:8b"])

    def test_already_running_only_downloads(self):
        self.assertEqual(self.mod.setup("-", "qwen3:4b"), 0)
        self.assertNotIn("installing", [s["step"] for s in self.saved])
        self.assertEqual(self.ran(), ["slate ipc call config set assistantLocalModel qwen3:4b"])

    def test_the_password_prompt_closed(self):
        self.bin("slate-system", 126)
        self.assertEqual(self.mod.setup("ollama", "qwen3:4b"), 1)
        st = self.state()
        self.assertEqual((st["step"], st["problem"]), ("failed", "The password prompt was closed, so nothing changed."))
        self.assertEqual(self.pulled, [])

    def test_the_install_failing_says_so(self):
        self.bin("slate-system", 1, "error: target not found: ollama")
        self.assertEqual(self.mod.setup("ollama", "qwen3:4b"), 1)
        self.assertIn("Slate couldn't install Ollama", self.state()["problem"])
        self.assertIn("target not found", self.state()["problem"])

    def test_not_starting_says_so(self):
        self.mod.wait = lambda secs: False
        self.assertEqual(self.mod.setup("ollama", "qwen3:4b"), 1)
        self.assertIn("didn't start", self.state()["problem"])
        self.assertEqual(self.pulled, [])

    def test_the_download_failing_chooses_nothing(self):
        self.mod.pull = lambda model, heard: (heard({"error": "Ollama couldn't download it: no space"}), 1)[1]
        self.assertEqual(self.mod.setup("-", "qwen3:4b"), 1)
        self.assertEqual((self.state()["step"], self.state()["problem"]), ("failed", "Ollama couldn't download it: no space"))
        self.assertFalse(os.path.exists(self.calls), "a model was chosen anyway")

    def test_odd_names_are_refused(self):
        for package, model in (("kitty", "qwen3:4b"), ("ollama", "qwen3 4b"), ("ollama", "--insecure"), ("ollama;id", "qwen3")):
            with self.subTest(package=package, model=model):
                self.assertEqual(self.mod.setup(package, model), 1)
                self.assertEqual(self.state()["step"], "failed")
        self.assertFalse(os.path.exists(self.calls))


class PretendPull(http.server.BaseHTTPRequestHandler):
    lines = []

    def log_message(self, *a):
        pass

    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length") or 0))
        self.send_response(200)
        self.end_headers()
        for d in PretendPull.lines:
            self.wfile.write((json.dumps(d) + "\n").encode())


class Pull(Case):
    def setUp(self):
        super().setUp()
        self.mod = load()
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), PretendPull)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        os.environ["SLATE_OLLAMA_URL"] = "http://127.0.0.1:%d" % server.server_address[1]
        self.addCleanup(os.environ.pop, "SLATE_OLLAMA_URL", None)

    def pull(self, lines):
        PretendPull.lines = lines
        heard = []
        code = self.mod.pull("qwen3:4b", heard.append)
        return code, heard

    def test_progress_over_every_part(self):
        code, heard = self.pull([{"status": "pulling manifest"},
                                 {"status": "pulling a", "digest": "a", "total": 100, "completed": 50},
                                 {"status": "pulling b", "digest": "b", "total": 300, "completed": 0},
                                 {"status": "success"}])
        self.assertEqual(code, 0)
        self.assertEqual(heard[-1], {"done": True})
        self.assertEqual(heard[0]["size"], 0, "(the first word, before any part)")

    def test_ollamas_error_is_passed_on(self):
        code, heard = self.pull([{"status": "pulling manifest"}, {"error": "pull model manifest: file does not exist"}])
        self.assertEqual(code, 1)
        self.assertIn("file does not exist", heard[-1]["error"])

    def test_ending_early(self):
        code, heard = self.pull([{"status": "pulling manifest"}])
        self.assertEqual(code, 1)
        self.assertIn("stopped before", heard[-1]["error"])

    def test_not_a_model_name(self):
        self.assertEqual(self.mod.pull("../../x", lambda d: None), 1)
