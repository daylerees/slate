pragma Singleton

// The drink reminder and the focus timer (Settings → Timers), shown on the menu bar, the dock or
// both (drinkPlace, focusPlace), each with a panel (panels/DrinkPanel.qml, FocusPanel.qml).
//
// Drink: every drinkMinutes a gentle notification, "Time for a drink"; "I've had a drink" (the
// notification's button, the panel, a click on the dock tile) starts the next wait.
// Focus: a Pomodoro. focusMinutes of focus, then a short break (focusBreakMinutes) that starts by
// itself; after every focusRounds rounds a long one (focusLongBreakMinutes). After a break it
// waits for you to start the next round. With focusQuiet, Do Not Disturb is on while you focus
// (Notifications.qml: autoWhy "focus").
//
// Times are kept as when they end (ms since 1970), so a sleep or a restart of the clock costs
// nothing; `now` ticks only while something is counting (the input that makes it worth running).
//   slate ipc call timers drink        (I've had a drink)
//   slate ipc call timers focus start|pause|reset|skip

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property real now: Date.now()

    // ---- Drink -------------------------------------------------------------------------------
    readonly property bool drinkOn: Config.s.drinkReminder
    property real drinkDue: 0                   // when the next drink is due
    readonly property bool drinkOverdue: drinkOn && drinkDue > 0 && now >= drinkDue
    readonly property real drinkLeft: drinkOn && drinkDue > 0 ? Math.max(0, drinkDue - now) : 0
    // How much of the wait is left, 1 → 0 (the dock's ring)
    readonly property real drinkProgress: drinkOn && drinkDue > 0 ? Math.min(1, drinkLeft / (Config.s.drinkMinutes * 60000)) : 0
    property int drinksToday: 0
    property string drinksDay: ""
    property bool drinkTold: false              // (the notification for this wait has gone)
    function drank() {
        const day = new Date().toDateString();
        if (drinksDay !== day) { drinksDay = day; drinksToday = 0; }
        drinksToday++;
        restartDrink();
    }
    function restartDrink() {
        drinkDue = Date.now() + Config.s.drinkMinutes * 60000;
        drinkTold = false;
        tick();
    }
    onDrinkOnChanged: if (drinkOn) restartDrink(); else drinkDue = 0

    // ---- Focus -------------------------------------------------------------------------------
    readonly property bool focusOn: Config.s.focusTimer
    property string phase: "idle"               // idle, focus, break, long
    property bool paused: false
    property real endsAt: 0                     // when this phase ends (while running)
    property real leftWhenPaused: 0
    property int round: 0                       // focus rounds finished since the last long break
    property int roundsToday: 0
    property string roundsDay: ""
    readonly property real phaseLength: (phase === "focus" ? Config.s.focusMinutes
        : phase === "break" ? Config.s.focusBreakMinutes
        : phase === "long" ? Config.s.focusLongBreakMinutes : 0) * 60000
    readonly property real focusLeft: phase === "idle" ? 0 : paused ? leftWhenPaused : Math.max(0, endsAt - now)
    readonly property real focusProgress: phase === "idle" || phaseLength <= 0 ? 0 : Math.min(1, focusLeft / phaseLength)
    readonly property bool focusing: focusOn && phase === "focus" && !paused
    // Do Not Disturb while you focus, if asked (Notifications.qml reads it)
    readonly property bool focusQuiet: focusing && Config.s.focusQuiet
    function startPhase(p) {
        phase = p;
        paused = false;
        endsAt = Date.now() + phaseLength;
        tick();
    }
    function startFocus() { if (phase === "idle" || phase === "break" || phase === "long") startPhase("focus"); else if (paused) resume(); }
    function pause() { if (phase === "idle" || paused) return; leftWhenPaused = Math.max(0, endsAt - Date.now()); paused = true; }
    function resume() { if (!paused) return; endsAt = Date.now() + leftWhenPaused; paused = false; tick(); }
    function toggleFocus() { if (phase === "idle") startPhase("focus"); else if (paused) resume(); else pause(); }
    function resetFocus() { phase = "idle"; paused = false; endsAt = 0; round = 0; }
    // (the end of a phase, or skipping to it)
    function nextPhase() {
        if (phase === "focus") {
            round++;
            const day = new Date().toDateString();
            if (roundsDay !== day) { roundsDay = day; roundsToday = 0; }
            roundsToday++;
            const long = round >= Config.s.focusRounds;
            if (long) round = 0;
            startPhase(long ? "long" : "break");
            say(long ? "Time for a longer break" : "Time for a break",
                long ? "That's " + Config.s.focusRounds + " rounds done. Step away for " + Config.s.focusLongBreakMinutes + " minutes."
                     : "Nicely done. Rest for " + Config.s.focusBreakMinutes + " minutes.", "Skip the break", "skip");
        } else if (phase === "break" || phase === "long") {
            phase = "idle"; paused = false; endsAt = 0;
            say("Break's over", "Ready for the next round when you are.", "Start focusing", "start");
        }
    }
    onFocusOnChanged: if (!focusOn) resetFocus()

    // ---- The clock: only while something counts ------------------------------------------------
    readonly property bool counting: (drinkOn && drinkDue > 0) || (focusOn && phase !== "idle" && !paused)
    function tick() {
        now = Date.now();
        if (drinkOn && drinkDue > 0 && now >= drinkDue && !drinkTold) {
            drinkTold = true;
            say("Time for a drink", "A glass of water is a good idea.", "I've had a drink", "drank");
        }
        if (focusOn && phase !== "idle" && !paused && now >= endsAt) nextPhase();
    }
    // (every second while the focus timer runs, for its minutes and seconds; every half a minute
    // for the drink reminder alone)
    Timer {
        running: root.counting
        interval: root.focusOn && root.phase !== "idle" && !root.paused ? 1000 : 30000
        repeat: true
        onTriggered: root.tick()
    }
    // (after sleep the wait carries on from when it ends: catch up at once)
    Connections { target: Config; function onWoke() { root.tick(); } }

    // A notification with one button: notify-send waits, and prints the button's name if it's
    // pressed (one at a time: a newer one takes the place of the last's wait)
    function say(title, body, button, act) {
        said = title;
        if (Config.testMode) return;
        asking.running = false;
        asking.command = Config.notify(title, body, { page: "timers", actions: [act + "=" + button], wait: true });
        asking.running = true;
    }
    Process {
        id: asking
        stdout: SplitParser {
            onRead: line => {
                const what = line.trim();
                if (what === "drank") root.drank();
                else if (what === "start") root.startPhase("focus");
                else if (what === "skip") root.nextPhase();
            }
        }
    }
    property string said: ""                    // (the tests: the last notification's title)

    // Text for a time left: "24:13", or "45 min" for longer waits
    function clock(ms) {
        const s = Math.ceil(ms / 1000);
        if (s >= 3600) return Math.floor(s / 3600) + " h " + String(Math.floor(s % 3600 / 60)).padStart(2, "0") + " min";
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
    }
    function minutes(ms) { const m = Math.ceil(ms / 60000); return m + " min"; }

    IpcHandler {
        target: "timers"
        function drink(): void { root.drank(); }
        function focus(what: string): void {
            if (what === "start") root.startFocus();
            else if (what === "pause") root.pause();
            else if (what === "toggle") root.toggleFocus();
            else if (what === "reset") root.resetFocus();
            else if (what === "skip") root.nextPhase();
        }
        // (the tests: as if this many seconds had gone by)
        function testAhead(seconds: int): void {
            if (!Config.testMode) return;
            const ms = seconds * 1000;
            if (root.drinkDue > 0) root.drinkDue -= ms;
            if (root.phase !== "idle" && !root.paused) root.endsAt -= ms;
            root.tick();
        }
        function state(): string {
            return JSON.stringify({ drink: { on: root.drinkOn, overdue: root.drinkOverdue, left: Math.round(root.drinkLeft / 1000), today: root.drinksToday },
                                    focus: { on: root.focusOn, phase: root.phase, paused: root.paused, left: Math.round(root.focusLeft / 1000), round: root.round, quiet: root.focusQuiet },
                                    said: root.said });
        }
    }
}
