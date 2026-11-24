"""Night light's screen shader leaves yours alone: with it off, Slate cleared Hyprland's screen
shader at every start and every reload of Hyprland's config, wiping one you set yourself
(hyprshade, your own hypr/ files). Now it takes away only the shader it put there, and puts
back the one it replaced."""
import os

from live import LiveCase

SHADER = """#version 300 es
precision highp float;
in vec2 v_texcoord;
uniform sampler2D tex;
out vec4 fragColor;
void main() { fragColor = texture(tex, v_texcoord); }
"""


class NightLightShader(LiveCase):
    def shader(self):
        return self.s.hyprctl("getoption", "decoration:screen_shader").splitlines()[0].replace("str:", "").strip()

    def setUp(self):
        super().setUp()
        self.keep_setting("nightLight")
        self.keep_setting("nightLightSchedule")
        self.config("nightLightSchedule", "manual")
        self.config("nightLight", "false")
        self.own = os.path.join(self.s.h.home, "my-shader.frag")
        with open(self.own, "w") as f:
            f.write(SHADER)
        self.addCleanup(lambda: self.s.hyprctl("eval", 'hl.config({ decoration = { screen_shader = "" } })'))
        self.s.settle(0.5)
        self.s.hyprctl("eval", 'hl.config({ decoration = { screen_shader = "%s" } })' % self.own)
        self.wait(lambda st: self.shader() == self.own, "your own shader in place")

    def test_off_leaves_your_shader_alone(self):
        self.ipc("test", "nightLightApply")
        self.s.settle(0.8)
        self.assertEqual(self.shader(), self.own, "night light, off, wiped your own screen shader")

    def test_on_then_off_puts_yours_back(self):
        self.config("nightLight", "true")
        self.wait(lambda st: self.shader().endswith("nightlight.frag"), "night light's shader")
        self.config("nightLight", "false")
        self.wait(lambda st: self.shader() == self.own, "your own shader back")
