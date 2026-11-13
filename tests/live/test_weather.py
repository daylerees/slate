"""The weather (clock panel and control centre): a reply from the weather service is taken only
when it's a forecast. Anything else (nothing, with no network; or a reply that isn't one, as can
come while a VPN reconnects after sleep) leaves the weather there was, where it once left an
empty space in the control centre. Fed through the test hook, since the session has no network."""
import json

from live import LiveCase

FORECAST = {"current": {"temperature_2m": 9.5, "apparent_temperature": 7.1, "weather_code": 3},
            "daily": {"time": ["2026-11-13", "2026-11-14", "2026-11-15"], "weather_code": [3, 61, 0],
                      "temperature_2m_max": [11, 10, 8], "temperature_2m_min": [5, 4, 1]}}


class WeatherReplies(LiveCase):
    def setUp(self):
        super().setUp()
        self.ipc("test", "weather", "true")
        self.addCleanup(lambda: self.ipc("test", "weather", "false"))
        self.s.wait(lambda st: st["weather"]["now"] == 14.2, what="the test weather")

    def reply(self, body):
        return self.ipc("test", "weatherReply", body if isinstance(body, str) else json.dumps(body))

    def test_a_forecast_is_taken(self):
        self.assertEqual(self.reply(FORECAST), "true")
        self.assertEqual(self.s.state()["weather"], {"now": 9.5, "days": 3})

    def test_anything_else_keeps_what_there_was(self):
        # (" " is nothing and " []" a list: qs ipc drops an argument that's empty or just "[]")
        for body in (" ", "not json", "null", " []", {"error": True, "reason": "Too many requests"},
                     {"latitude": 51.5, "longitude": -3.6},                      # no current at all
                     {"current": {"time": "2026-11-13T10:30"}, "daily": FORECAST["daily"]},
                     {"current": FORECAST["current"]}):                          # no forecast
            with self.subTest(body=body):
                self.assertEqual(self.reply(body), "false")
                self.assertEqual(self.s.state()["weather"], {"now": 14.2, "days": 5})
