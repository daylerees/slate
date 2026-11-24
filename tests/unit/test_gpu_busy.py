"""scripts/gpu-busy.sh: how busy each graphics card is, for the battery panel's System section.
Run on a stand-in /sys (SLATE_SYS), with nvidia-smi stood in for: nothing on this computer is
read, and no card is woken."""
import os

import slate
from slate import Case, run
from stubs import Stubs

SCRIPT = slate.path("shell", "scripts", "gpu-busy.sh")


class GpuBusy(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        self.s = Stubs(self.h)
        self.sys = os.path.join(self.h.dir, "sys")
        os.makedirs(os.path.join(self.sys, "class", "drm"))

    def card(self, n, vendor, bus, status="active", busy=None, connectors=()):
        """A card as /sys shows it: class/drm/cardN, its device a link to the PCI device."""
        dev = os.path.join(self.sys, "devices", "pci0000:00", bus)
        os.makedirs(os.path.join(dev, "power"), exist_ok=True)
        with open(os.path.join(dev, "vendor"), "w") as f:
            f.write(vendor + "\n")
        with open(os.path.join(dev, "power", "runtime_status"), "w") as f:
            f.write(status + "\n")
        if busy is not None:
            with open(os.path.join(dev, "gpu_busy_percent"), "w") as f:
                f.write("%d\n" % busy)
        card = os.path.join(self.sys, "class", "drm", "card%d" % n)
        os.makedirs(card)
        os.symlink(dev, os.path.join(card, "device"))
        for c in connectors:
            d = os.path.join(self.sys, "class", "drm", "card%d-%s" % (n, c))
            os.makedirs(d)
            os.symlink(dev, os.path.join(d, "device"))

    def go(self):
        code, out = run(["sh", SCRIPT], env=dict(self.s.env, SLATE_SYS=self.sys))
        self.assertEqual(code, 0, out)
        return out.splitlines()

    def test_an_amd_card_says_how_busy_it_is(self):
        self.card(0, "0x1002", "0000:03:00.0", busy=37, connectors=("DP-1", "HDMI-A-1"))
        self.assertEqual(self.go(), ["busy 37"], "one line per card, not per connector")

    def test_a_sleeping_card_isnt_asked(self):
        """A laptop's second card, powered down: asking would wake it, so it's only said to be
        asleep (its busy file isn't read)."""
        self.card(0, "0x1002", "0000:03:00.0", status="suspended", busy=99)
        self.assertEqual(self.go(), ["asleep"])

    def test_nvidia_through_nvidia_smi(self):
        self.s.add("nvidia-smi", stdout="12\n")
        self.card(0, "0x10de", "0000:01:00.0")
        self.assertEqual(self.go(), ["busy 12"])
        self.assertEqual(self.s.calls("nvidia-smi"),
                         [["--query-gpu=utilization.gpu", "--format=csv,noheader,nounits", "-i", "0000:01:00.0"]])

    def test_nvidia_asleep_or_without_nvidia_smi(self):
        self.s.add("nvidia-smi", stdout="12\n")
        self.card(0, "0x10de", "0000:01:00.0", status="suspended")
        self.assertEqual(self.go(), ["asleep"])
        self.assertEqual(self.s.calls("nvidia-smi"), [], "a sleeping card was woken to ask")
        self.s.add("nvidia-smi", missing=True)
        os.remove(os.path.join(self.sys, "devices", "pci0000:00", "0000:01:00.0", "power", "runtime_status"))
        self.assertEqual(self.go(), [])

    def test_intel_and_nothing_say_nothing(self):
        """Intel's graphics don't say how busy they are without root tools: no line, so the
        panel hides the row."""
        self.assertEqual(self.go(), [])
        self.card(0, "0x8086", "0000:00:02.0")
        self.assertEqual(self.go(), [])

    def test_an_intel_laptop_with_an_amd_card(self):
        self.card(0, "0x8086", "0000:00:02.0")
        self.card(1, "0x1002", "0000:03:00.0", busy=5)
        self.assertEqual(self.go(), ["busy 5"])
