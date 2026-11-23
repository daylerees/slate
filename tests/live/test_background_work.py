"""Background work that has nothing to do stays idle: Hyprland's blur is read back only after the
blur changed (not after every push), the keyboard layouts only when their sources changed, Night
light's timer only with a schedule, the speech check only with Nova's voice on, and Slate's
settings aren't pushed to Hyprland while the wallpaper switcher is showing wallpapers."""
import os

from live import LiveCase


class BackgroundWork(LiveCase):
    def settled(self):
        """The state once nothing is on its way to Hyprland."""
        return self.wait(lambda st: not st["hypr"]["busy"], "Slate's settings to reach Hyprland", timeout=15)

    def test_a_push_that_leaves_the_blur_alone_doesnt_read_it(self):
        self.keep_setting("defaultFileManager")
        self.keep_setting("blurPasses")
        self.settled()
        reads = self.s.state()["hypr"]["blurReads"]
        pushes = self.s.state()["hypr"]["pushes"]
        self.config("defaultFileManager", "foot")
        st = self.wait(lambda st: not st["hypr"]["busy"] and st["hypr"]["pushes"] > pushes, "a push", timeout=15)
        self.s.settle(1.2)             # (the reading back would have started 600 ms after the push)
        self.assertEqual(self.s.state()["hypr"]["blurReads"], reads, "a push with no blur change read the blur again")
        # ...and one that changes it does
        self.config("blurPasses", "3" if self.setting("blurPasses") != "3" else "4")
        self.wait(lambda st: st["hypr"]["blurReads"] > reads, "the blur to be read after it changed", timeout=15)

    def test_keyboard_layouts_are_read_once_for_a_change_not_in_a_loop(self):
        self.keep_setting("kbLayouts")
        self.settled()
        reads = self.s.state()["hypr"]["kbReads"]
        self.config("kbLayouts", "gb,us")
        self.wait(lambda st: st["hypr"]["kbReads"] > reads, "the layouts to be read", timeout=10)
        self.s.settle(2.5)
        self.assertEqual(self.s.state()["hypr"]["kbReads"], reads + 1, "reading the layouts started another reading")

    def test_night_light_checks_the_time_only_with_a_schedule(self):
        self.keep_setting("nightLightSchedule")
        self.config("nightLightSchedule", "manual")
        self.wait(lambda st: not st["idle"]["nightTimer"], "the timer to be off with no schedule")
        self.config("nightLightSchedule", "custom")
        self.wait(lambda st: st["idle"]["nightTimer"], "the timer to run with a custom schedule")

    def test_the_speech_check_waits_for_the_voice_switch(self):
        self.keep_setting("assistantVoice")
        self.config("assistantVoice", "false")
        self.s.settle(0.5)
        checks = self.s.state()["novaVoice"]["checks"]
        self.s.settle(1.5)
        self.assertEqual(self.s.state()["novaVoice"]["checks"], checks, "the speech check ran with voice off")
        self.config("assistantVoice", "true")
        self.wait(lambda st: st["novaVoice"]["checks"] > checks, "the check when voice is switched on")

    def test_settings_dont_reach_hyprland_while_wallpapers_are_shown(self):
        self.keep_setting("defaultFileManager")
        self.addCleanup(lambda: self.ipc("wallpaperSwitcher", "cancel"))
        self.settled()
        pushes = self.s.state()["hypr"]["pushes"]
        self.ipc("wallpaper", "switcher")
        self.wait(lambda st: st["wallpaperSwitcher"]["open"], "the wallpaper switcher")
        self.config("defaultFileManager", "foot")
        self.s.settle(1.5)
        st = self.s.state()
        self.assertEqual(st["hypr"]["pushes"], pushes, "a push went to Hyprland while the switcher was open")
        self.assertTrue(st["hypr"]["busy"], "the held push wasn't counted as still to come")
        self.ipc("wallpaperSwitcher", "cancel")
        self.wait(lambda st: not st["hypr"]["busy"] and st["hypr"]["pushes"] > pushes,
                  "the held push after the switcher closed", timeout=15)


class Idle(LiveCase):
    """Work that runs without a reason, found in a review: the space badges' positions polled
    twice a second with only the bar's tint on (which never needs them), and a script started on
    every window close to refresh GTK apps, with none waiting."""

    def idle(self):
        return self.s.state()["idle"]

    def test_space_tint_alone_doesnt_poll_window_positions(self):
        for k in ("spaceBorders", "spaceBadges", "spaceBarTint"):
            self.keep_setting(k)
        self.config("spaceBorders", "false")
        self.config("spaceBadges", "false")
        self.config("spaceBarTint", "true")
        self.s.settle(0.6)
        before = self.idle()["spacePolls"]
        self.s.settle(2.2)
        self.assertEqual(self.idle()["spacePolls"], before, "window positions polled for the bar's tint alone")

    def test_a_window_closing_starts_nothing_with_no_gtk_app_waiting(self):
        flag = os.path.join(self.s.h.cache, "slate", "gtk4-refresh")
        if os.path.exists(flag):
            os.remove(flag)
        before = self.idle()["gtkRefreshes"]
        self.s.hyprctl("eval", 'hl.exec_cmd("foot")')
        self.wait(lambda st: True, "")
        self.s.settle(1.2)
        self.s.hyprctl("dispatch", "function() local w = hl.get_active_window(); if w then hl.dispatch(hl.dsp.window.close({ window = 'address:' .. w.address })) end end")
        self.s.settle(2.0)
        self.assertEqual(self.idle()["gtkRefreshes"], before, "a window closing started the GTK refresh with nothing waiting")
        # ...and with one waiting, it does
        os.makedirs(os.path.dirname(flag), exist_ok=True)
        open(flag, "w").close()
        self.addCleanup(lambda: os.path.exists(flag) and os.remove(flag))
        self.s.hyprctl("eval", 'hl.exec_cmd("foot")')
        self.s.settle(1.2)
        self.s.hyprctl("dispatch", "function() local w = hl.get_active_window(); if w then hl.dispatch(hl.dsp.window.close({ window = 'address:' .. w.address })) end end")
        self.wait(lambda st: st["idle"]["gtkRefreshes"] > before, "the GTK refresh with an app waiting", timeout=6)
