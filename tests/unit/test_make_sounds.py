"""tools/make-sounds.py: Slate's sounds in shell/sounds/ are what it makes, never edited by hand.

Makes every sound into a scratch folder and checks each is the same, byte for byte, as the
one in shell/sounds/, and that every sound there (but the volume tick, which is older) is made
by it. Then Nova's answer (answered)
in particular: mono 48 kHz 16-bit like the others, short, quieter than the notification, and
starting and ending at silence (no click at either end) after a rounded onset.
"""
import importlib.util
import math
import os
import struct
import tempfile
import wave
import unittest

import slate
from slate import Case

SOUNDS = slate.path("shell", "sounds")
NOT_MADE = {"volume-tick.wav"}         # (older than the generator, and not made by it)


def load():
    spec = importlib.util.spec_from_file_location("make_sounds", slate.path("tools", "make-sounds.py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def samples(p):
    with wave.open(p) as w:
        n = w.getnframes() * w.getnchannels()
        return (w.getnchannels(), w.getsampwidth(), w.getframerate()), struct.unpack("<%dh" % n, w.readframes(w.getnframes()))


class MakeSounds(Case):
    @classmethod
    def setUpClass(cls):
        cls.dir = tempfile.mkdtemp(prefix="slate-sounds-")
        m = load()
        m.OUT = cls.dir
        m.print = lambda *a, **k: None
        for make in (m.notification, m.click, m.welcome, m.goodbye, m.swish, m.attention, m.answered):
            make()

    @classmethod
    def tearDownClass(cls):
        for f in os.listdir(cls.dir):
            os.remove(os.path.join(cls.dir, f))
        os.rmdir(cls.dir)

    def test_every_sound_is_the_generators(self):
        made = sorted(os.listdir(self.dir))
        self.assertEqual(made, sorted(f for f in os.listdir(SOUNDS) if f.endswith(".wav") and f not in NOT_MADE),
                         "shell/sounds/ and what tools/make-sounds.py makes differ")
        for f in made:
            with open(os.path.join(self.dir, f), "rb") as a, open(os.path.join(SOUNDS, f), "rb") as b:
                self.assertTrue(a.read() == b.read(), f"shell/sounds/{f} isn't what tools/make-sounds.py makes: run it again")

    def test_novas_answer(self):
        fmt, s = samples(os.path.join(self.dir, "answered.wav"))
        self.assertEqual(fmt, (1, 2, 48000))
        self.assertLess(len(s) / 48000, 0.6, "longer than a short, soft tone")
        self.assertEqual((s[0], s[-1]), (0, 0), "doesn't start and end at silence")
        # A rounded onset: nothing close to full in the first few milliseconds
        top = max(abs(x) for x in s)
        self.assertLess(max(abs(x) for x in s[:int(48000 * 0.004)]), top * 0.6, "it starts with a tap")
        _, note = samples(os.path.join(self.dir, "notification.wav"))
        rms = lambda xs: math.sqrt(sum(x * x for x in xs) / len(xs))
        self.assertLess(top, max(abs(x) for x in note), "louder than the notification")
        self.assertLess(rms(s), rms(note), "louder than the notification")

    def test_settings_to_try(self):
        """Other versions to hear come from the same generator, by its settings."""
        m = load()
        m.OUT = self.dir
        m.print = lambda *a, **k: None
        m.answered("try.wav", notes=((0.0, 1046.50, 0.6), (0.085, 783.99, 1.0)), length=0.5)
        fmt, s = samples(os.path.join(self.dir, "try.wav"))
        os.remove(os.path.join(self.dir, "try.wav"))
        self.assertEqual((fmt, len(s), s[-1]), ((1, 2, 48000), 24000, 0))

