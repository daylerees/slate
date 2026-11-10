# Plan: sounds for Chalk

Status: **for later** (2026-11-10), nothing built. It follows the assistant
([assistant.md](assistant.md)), whose first version adds no sounds of its own. What's said
about Slate's sounds was **checked** in this repository (`tools/make-sounds.py`,
`Config.soundSettings`, the Sounds section of `CLAUDE.md`).

## The idea

In its first version Chalk uses the sounds Slate already has: summoning it is a press (click),
its questions play attention, and an answer that arrives while the window is away is a
notification. This plan gives Chalk a voice of its own for the one moment none of those
covers: **the answer arriving while you're waiting for it.** A second sound, for Chalk
starting to listen, belongs to voice input and is planned here but held back until then.

## The moments

| Moment | Today | Proposed |
|---|---|---|
| You summon the prompt window | click, from the bar button | No change. A "listening" sound on top of a click would be two sounds for one press |
| You send a prompt | Nothing | Nothing: you pressed Enter, you know |
| Chalk is working | Nothing | Nothing. No ticking, no loop: Slate is calm |
| Slate asks you something on Chalk's behalf | attention (`PowerConfirm`) | No change |
| **The answer arrives, window showing** | Nothing | **answered**: the new sound |
| The answer arrives, window away | notification | No change, and *not* answered as well: one moment, one sound |
| Something went wrong | Nothing | Nothing. Nothing alarming; the window says what happened |
| Chalk starts listening (voice, later) | No such thing yet | **listening**, when voice input exists: there it tells you the microphone is open, which is worth a sound |

So: one new sound now, **answered**, and one reserved, **listening**.

## The sound

The family is soft, rounded and calm, and each generator in `tools/make-sounds.py` builds its
sound from sine partials with gentle onsets (`notification`, `click`, `welcome`, `goodbye`,
`swish`, `attention`). **answered** is written the same way, as `def answered():`.

A starting point for the ear, not a specification: **two soft taps, the second a little
higher**, like chalk touching slate twice. About a quarter of a second in all, quieter than
the notification, with a rounded onset so there's no scratch or click to it: the idea of
chalk, never the squeak. It has to sit apart from the two sounds it could be mistaken for:
lower and shorter than notification (which means "something arrived from elsewhere"), and
plainly not attention (which means "Slate needs you").

**listening**, when its time comes: a single rising tap, the first half of answered, so the
pair read as question and reply.

Sounds are made by the generator and never edited by hand, and **a new sound is played for you
to approve before it's committed**: expect a few rounds.

## Design

- **Playing it.** `Config.playSound("answered", "answered")` in `Assistant.qml`, when a run's
  `done` event arrives *and* the prompt window is showing. If the window is away, the
  notification carries the moment and its own sound. Errors and Stop play nothing.
- **Not for instant answers.** If the answer arrives within about a second of sending, it
  plays nothing: you never looked away. (The second is a guess to tune by ear.)
- **Settings.** As every sound: an entry in `Config.soundSettings`
  (`answered: ["answeredVolume", ""]`, following attention's form, so it plays at the effects
  volume until set), `answeredVolume` in `SettingsData.qml`, a `SoundSetting` slider on
  Settings → Sound labelled **Chalk's answer** (0 = off), a search entry in `SettingsIndex.qml`
  ("chalk assistant answer sound"), and a line on the site. The key joins the assistant
  server's refuse list only if it starts with `assistant`, which it doesn't: it's a sound
  volume like the others and Chalk may change it when asked ("make your sound quieter").
- **Game mode.** Silent: an answer isn't worth interrupting a game. The override is at the
  point of playing, never a change to the saved setting.
- **Lock and login screens.** Silent, as always: the prompt window closes when the screen
  locks, and the login screen has no sounds.
- **Test mode.** `Config.playSound` already does nothing in test mode.
- **Other distros.** A `.wav` in `shell/sounds/`, played the way the others are. Nothing to
  install.
- **Do Not Disturb.** Plays as normal: Do Not Disturb is about notifications, and you asked
  Chalk yourself.

## Tests

- **Static** (`tests/static/test_consistency.py`; **checked**: nothing there covers sounds
  today, so this adds it for every sound, not just the new one): each entry in
  `Config.soundSettings` has a file in `shell/sounds/`, a volume key in `SettingsData.qml`, a
  slider on Settings → Sound and a search entry; no QML file calls `pw-play` or makes a
  `SoundEffect` of its own.
- **Unit, `tests/unit/test_make_sounds.py`** (**checked**: there's no test of the generators
  today, so this adds one for all of them): `answered` writes a file of the expected length and format, peaks below the
  limit, starts and ends at silence (no click at either end), and is the same bytes on every
  run.
- **Live, `tests/live/test_assistant.py`**: `state().assistant` gains `lastSound`; a run that
  finishes with the window showing sets it to "answered"; with the window away it stays
  empty and a notification exists; an instant answer, an error, Stop and game mode each leave
  it empty.
- No new visual scene: nothing on screen changes except one slider on Settings → Sound, whose
  existing picture is re-approved.

## Docs and the site

- `site/features.html`: "Chalk's answer" in the list of sounds, and the Sound settings list.
- `CLAUDE.md`: a row in the Sounds table: "Chalk answering while you wait | answered |
  `Config.playSound("answered", "answered")` in `Assistant.qml`; nothing when the window is
  away (that's a notification)".
- `docs/ASSISTANT.md`: one line.

## Order of work

1. The generator, and a few versions for you to hear and choose between. Nothing is committed
   until one is approved.
2. The setting, the slider, the search entry, the play call; install, reload, try it with real
   prompts until the timing feels right (the one-second rule especially).
3. Tests, the Sound page's baseline, the site and docs. `feat(assistant): a sound when
   Chalk answers`.
4. **listening**, only with voice input, as part of that work.

## Open questions

- **One sound or two?** Suggested: **answered now, listening with voice**. Opening the window
  already clicks.
- **Should answered play when the window is away, instead of the notification sound?**
  Suggested: **no**. A notification is a notification whoever sent it.
- **A different sound when Chalk couldn't do it?** Suggested: **no**. Two sounds to learn, and
  the second would be a kind of alarm.
- **What the slider is called.** Suggested: **Chalk's answer**.
- **How short is "instant"?** Suggested: **one second**, tuned by ear.
