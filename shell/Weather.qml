import QtQuick
import Quickshell
import Quickshell.Io
import qs

// The weather the clock panel and the control centre show, from Open-Meteo for Settings'
// location. Popouts.qml owns one (so it starts with the shell, and fetches while there's a
// place set), and hands what it holds on as its own `weather` and `forecast`.
Scope {
    // Weather from Open-Meteo for Settings' location (Config.s.latitude/longitude), every 30 min
    property var weather: null
    property var forecast: null       // daily: time[], weather_code[], temperature_2m_max[], temperature_2m_min[]
    Process {
        id: weatherFetch
        command: ["curl", "-sf", "--max-time", "10",
            "https://api.open-meteo.com/v1/forecast?latitude=" + Config.s.latitude + "&longitude=" + Config.s.longitude + "&current=temperature_2m,apparent_temperature,weather_code&daily=weather_code,temperature_2m_max,temperature_2m_min&forecast_days=5&timezone=auto" + (Config.fahrenheit ? "&temperature_unit=fahrenheit" : "")]
        stdout: StdioCollector { onStreamFinished: if (!take(text) && !Config.testMode) weatherRetry.restart() }
    }
    // A reply is taken only when it's a forecast: anything else (nothing at all with no
    // network, or something that isn't one, as can come while a VPN reconnects after sleep)
    // leaves the weather there was, rather than an empty space where it goes. True if taken.
    function take(text: string): bool {
        let j = null;
        try { j = JSON.parse(text); } catch (e) { return false; }
        if (!j || typeof j.current !== "object" || !j.current || typeof j.current.temperature_2m !== "number"
                || typeof j.daily !== "object" || !j.daily || !Array.isArray(j.daily.time)) return false;
        weather = j.current;
        forecast = j.daily;
        return true;
    }
    // After a fetch that didn't bring the weather, another soon, not in half an hour
    Timer { id: weatherRetry; interval: 2 * 60 * 1000; onTriggered: if (place !== "" && !weatherFetch.running) weatherFetch.running = true }
    // Only once a location is set (Settings → General → Location); again when it changes
    // (and when the temperature unit does: Settings → Region → Temperature)
    readonly property string place: Config.s.locationName === "" ? "" : Config.s.latitude + "," + Config.s.longitude + (Config.fahrenheit ? ",f" : "")
    // (not in tests: they have no network to count on, and give it weather of their own)
    onPlaceChanged: { weather = null; forecast = null; if (place !== "" && !Config.testMode) weatherFetch.running = true; }
    Timer { interval: 30 * 60 * 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: if (place !== "" && !Config.testMode) weatherFetch.running = true }
    function info(code) {
        if (code === 0) return { text: "Clear", icon: 0xEB30 };
        if (code <= 2) return { text: "Partly cloudy", icon: 0xEC6D };
        if (code === 3) return { text: "Overcast", icon: 0xEA76 };
        if (code <= 48) return { text: "Fog", icon: 0xECD9 };
        if (code <= 67 || (code >= 80 && code <= 82)) return { text: "Rain", icon: 0xEA72 };
        if (code <= 77 || code === 85 || code === 86) return { text: "Snow", icon: 0xEC0B };
        return { text: "Thunderstorm", icon: 0xEA74 };
    }
}
