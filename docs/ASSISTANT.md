# Slate and assistants

Slate has an MCP server: a small program that lets an AI agent you already use (Claude Code,
Codex, anything that speaks the [Model Context Protocol](https://modelcontextprotocol.io))
ask about your desktop and do things on it. "Turn on glass." "Put Firefox on workspace 2."
"Which window is on workspace 3?" "Where do I change the font?"

It's off until you switch it on in Settings → Assistant, and Slate asks you before anything
that can't be undone.

Slate also has a way of its own to ask: **Nova**. Press Super+K (or the button on the menu
bar, or your keyboard's Copilot or assistant key), type what you want in a line, and the
agent you chose does it through the same tools.

## Nova, the prompt window

- **Asking.** One line, Enter sends. It reads like a chat: what you asked on the right in
  your accent colour, Nova's answers on the left as they're written, each with
  a short list of what was done: Slate's own record, in Slate's words, not the agent's
  account of itself. It scrolls once it's long. Point at a message and a copy button appears in its top right corner.
- **Undo.** A setting Nova changed has **Undo** at the end of its row, which puts back the
  value it had before, as Settings would (Slate does it itself, not the agent). It's there
  while the setting still has the value Nova gave it: change it again yourself and there's
  nothing to undo. Once it's put back, the row says "undone". The server sends the setting's
  key, the value before and the value it was given with the row (`tell()` for `settings_set`),
  and they're kept with the chat history.
- **How answers look.** Most answers are a sentence or two, but one can carry a little
  structure: steps as a list, a setting's name in bold, a command in a box with its own
  **Copy** button (it copies just the command). Pictures and links are never loaded or
  opened: see "Lists, bold and code in answers" below.
- **Following on.** There are no conversations to manage. What you type within five minutes
  of the last answer follows on from it ("and a bit bigger"); left longer, Nova quietly
  starts afresh with the agent, which also keeps each prompt small. Your history stays on
  show either way.
- **Chat history.** The last 100 messages are still there after Slate restarts or you log in
  again, in `~/.local/state/slate/assistant/chat.json`: on this computer only, in a folder
  only you can read, never sent anywhere and not part of `slate logs`. Settings → Assistant
  → **Clear chat history** empties it, and **Keep chat history** switches keeping off, which
  deletes what was kept; the history is then forgotten whenever Slate restarts.
- **Closing it.** Escape or a click outside hides the window and the work carries on: the
  bar button shows it, and a notification brings the answer when it's done. **Stop**, at the end of
  the box while Nova works, ends it, and so does Ctrl+C there (with nothing selected).
  Locking the screen stops it too.
- **Its sound.** An answer you waited for with the window open plays Nova's own sound, a soft
  bloom (`answered`, Settings → Sound → Nova's answer), once as the whole answer arrives. Not
  for one back within a second, with the window closed (the notification carries it), for an
  error or Stop, for the history, or in game mode.
- **Which agent answers** is in Settings → Assistant → Agent. Claude Code is the
  recommended one: for each prompt Slate switches off its own tools (shell, files, web) and
  every other MCP server, so it works through Slate's alone, and nothing in your own Claude
  Code setup is changed. **A command of your own** is run as you typed it; Slate can't limit
  what such a command does, so choosing it asks you first. Prompts use your own account with
  the agent, and count against it like any other.
- **What Slate adds to your words**: who the agent is here and how to behave, and a few
  lines about the moment (the time, the focused window and workspace). Settings → Assistant →
  **See what Slate adds** shows both, so nothing travels with your words that you can't read.
  It never holds your name, your computer's name or your home folder.
- **When it goes wrong**, the window says what happened and offers the one useful thing:
  Open Settings, Open a terminal (to sign in), or Try again.
- **Game mode.** The window opens as normal; the bar button's spinner and the typing dots keep still.

## Before you switch it on

These are best efforts, and it's fairer to say so than to promise. Using an assistant with
Slate is your choice, and what it does on your behalf is your responsibility.

- **What leaves your computer.** Whatever a tool answers (your settings, your open windows
  and their titles, the names of your workspaces, Spaces, apps and wallpapers) goes to the
  service behind the agent you chose, under your own account with them. Slate itself sends
  nothing anywhere.
- **What it can do.** It can change settings, move windows and open apps without asking.
  Slate asks you before anything that can't be undone.
- **What can go wrong.** Assistants make mistakes, and can be misled by text they read, like
  the title of a web page. Slate does its best to limit the harm, but it can't promise what
  an assistant will do, least of all one that has tools of its own.

## Switching it on

**Settings → Assistant → Let assistants use Slate.** Turning the switch on shows the points
above and asks; only **Switch on** switches it on, and Slate records that you accepted them.
Setting `assistantEnabled` some other way switches nothing on. If a later version of Slate
changes what the risks are, the assistant pauses until you've read the new ones there.
**Read the risks again** shows them at any time, with a button to switch off.

While it's off, every tool answers that assistants aren't switched on, and does nothing. The same
goes while Private Mode is on (a quick switch in the control centre): every tool says so, and
only you can turn it off. An assistant can't change Private Mode either.

The same page has:

| Setting | To start with | What it does |
|---|---|---|
| Ask before changing anything | off | Slate asks before every change, not only the ones that can't be undone |
| Window titles | on | Off: assistants get app names only, never window titles (titles carry document names and web page titles) |
| Notifications | off | On: assistants can read your recent notifications |

It also lists what the tools are, everything assistants did (Activity, with Clear), and the
lines below for adding Slate to an agent, each with a Copy button. An assistant can't change
any of these settings itself: Slate refuses.

## Adding it to an agent

The server is `slate mcp`. An agent starts it when it needs it; you never run it by hand.

```sh
# Claude Code
claude mcp add slate -- ~/.config/slate/bin/slate mcp

# Codex
codex mcp add slate -- ~/.config/slate/bin/slate mcp
```

Most other agents take a block like this in their settings (with the whole path in place of
`~`):

```json
{ "mcpServers": { "slate": { "command": "/home/you/.config/slate/bin/slate", "args": ["mcp"] } } }
```

`slate mcp --help` prints the same lines. To take it away again, remove it the same way
(`claude mcp remove slate`).

## What the tools are

**Looking.** These read, and never ask.

| Tool | Answers with |
|---|---|
| `status` | Slate's version, the time, the theme, game mode, Do Not Disturb, night light, volume, brightness, the battery, the network's name, and the focused window and workspace |
| `settings_search` | Settings that match a word or two ("glass", "dock size", "dpi"): each one's key, name, page in Settings, description, type, default and value now |
| `settings_get` | One setting, by its key |
| `windows_list` | Open windows: app, title, workspace, floating, full screen, focused |
| `workspaces_list` | Workspaces in use: name, window mode, how many windows, which screen |
| `spaces_list` | Your saved Spaces: name, how many workspaces, the apps in each |
| `apps_list` | Installed apps, by name |
| `wallpapers_list` | The names of the pictures in your wallpaper folder and Slate's own |
| `media_info` | What's playing: the app, title and artist |
| `notifications_list` | Your recent notifications. Only offered while Notifications is on in Settings → Assistant |

**Changing.** These can be undone, so they happen straight away, unless you've asked Slate
to ask about every change.

| Tool | Does |
|---|---|
| `settings_set` | Changes a setting, and answers with its value before and now |
| `settings_show` | Opens Settings at a setting or a page, for you to look at or change |
| `look_apply` | Switches to one of Slate's finished looks |
| `panel_open` | Opens one of the menu bar's panels |
| `bar_arrange` | Shows how the menu bar is arranged, or arranges it: what's on it and in which containers, how each collapses, the order things leave when it's short of room, what always stays, or Slate's own arrangement again. Nova's button keeps its place and its switch |
| `app_open` | Starts an installed app. Only an app: no file, address or command |
| `window_focus`, `window_move`, `window_state` | Goes to a window, moves it to a workspace, floats, tiles, maximises or full-screens it |
| `workspace_go`, `workspace_mode`, `workspace_rename` | Switches workspace, changes how one lays out its windows, names it |
| `space_restore`, `space_save` | Opens a saved Space, or saves workspaces as one (saving over a Space asks first) |
| `wallpaper_set`, `wallpaper_next` | Changes the wallpaper, to a picture from `wallpapers_list` only |
| `volume_set`, `brightness_set`, `media_control`, `do_not_disturb` | As named |
| `wifi` | With no action: whether Wi-Fi is on, the network it's on, and your saved networks in range (networks you haven't saved are never listed). Turns it on or off, connects to a saved network, or disconnects (either can cut off an agent that works over the internet, Nova included). Never a new network: that needs its password, from you |
| `bluetooth` | With no action: whether Bluetooth is on, and your paired devices (connected or not, and a connected one's battery). Turns it on or off, connects or disconnects a paired device. Never pairs a new one |
| `dock_pin` | With no arguments: the apps pinned to the dock. Pins an app (by its id from `apps_list`) at the end, or unpins one, as its menu on the dock does |
| `screenshot` | Takes a screenshot for you, as Print does. The assistant is told "Done": it never gets the picture, or where it was saved |
| `lock_screen`, `screensaver_start` | As named |

**Always asking.** These can't be undone or could lose work, so Slate asks you every time,
and no setting turns the question off.

| Tool | Slate asks |
|---|---|
| `window_close` | "Close Firefox?" |
| `space_delete` | "Delete “Work”?" |
| `waste_basket_empty` | "Empty the waste basket?", in the dock's own words (with how many things are in it); Slate empties it as the dock's Empty Waste Basket does |
| `settings_restore_defaults` | "Restore Dock defaults?": every setting on one Settings page back to how Slate starts out, as the page's Restore defaults does. Not for Assistant or Security: those are yours to restore |
| `session` | "Shut down?", "Restart?", "Log out?" or "Sleep?" |

There is no tool that runs a command, opens a file or a web address, types or clicks for
you, reads the clipboard, answers a password prompt, unlocks the screen, or installs or
updates anything.

## What Slate does to keep an assistant in bounds

- **Slate decides, not the agent.** Every tool call goes through Slate's own gate first,
  whichever agent made it: assistants switched on, the screen unlocked, the arguments
  checked. While the screen is locked, every tool is refused.
- **Questions are Slate's.** They appear in Slate's own confirmation window, with Cancel
  picked first, in fixed sentences filled with checked values. The assistant can't write
  the question. The name in brackets ("Your assistant (Claude Code)") is what the agent
  calls itself, which proves nothing.
- **A no is a no.** After a no, Slate doesn't ask about that tool again for ten minutes,
  and tells the assistant to leave it. At most five questions in any ten minutes. A
  question nobody answers is taken away after 45 seconds, and nothing happens. In game
  mode, questions are declined without interrupting you.
- **Settings it can't touch.** Its own permissions; anything that holds a command or
  reaches outside Slate (default apps, startup apps, launcher commands, clipboard history,
  log detail); folders; the lock settings; keyboard layouts and the shortcut set; your
  location; title bar style and the main display. Slate says where you can change each
  yourself. Everything else is checked against what that setting takes.
- **Only from the lists.** A window by the address of one that's open, an app by an
  installed app's id, a wallpaper from the folder, a Space that's saved. Nothing an
  assistant makes up reaches Hyprland or Slate.
- **Words only.** Slate's tools never give a picture of the screen, a recording, the
  contents of a window, a file, the clipboard or anything you've typed. Your location is
  never given, and folders are shown without your home folder's name.
- **Text from other programs is cleaned.** Window titles, notification text and names are
  cut to 200 characters, stripped of anything unprintable, and the agent is told they're
  information and never instructions. This helps; it isn't something to rely on.
- **Sixty tool calls a minute**, so a looping assistant is told to slow down.

Where this stops: **Slate can only answer for its own tools.** An agent with a terminal of
its own can do whatever a terminal can, with or without Slate's server: take a screenshot,
read your files, run `slate ipc` and skip Slate's questions altogether. So the wording here
is "Slate's tools never show the assistant your screen", not "the assistant can't see your
screen".

## What it did

Every tool call is written to `~/.local/state/slate/assistant/activity.jsonl`, one line
each: the time, which agent, the tool, its arguments (cut short), and how it ended (done,
declined, no answer, refused or failed), with a setting's value before it was changed. This
log holds tool calls only, never what you typed or what the agent answered (Nova's own
conversation is kept separately, if you leave that on: see above). The last
1,000 lines are kept, the log isn't part of `slate logs`, and Settings → Assistant → Activity
shows the latest 50 and clears it.

## How it works

`shell/scripts/slate-mcp.py`, plain Python with nothing to install. It speaks MCP over
stdin and stdout, one JSON message per line, and stops when the agent closes it.

- **Both eras of the protocol.** The 2026-07-28 specification has no handshake: every
  request carries its version, and `server/discover` says what's spoken. Earlier versions
  (2025-11-25 back to 2024-11-05) open with `initialize`. The server answers whichever the
  agent uses.
- **The gate has two halves.** The server checks and decides (tiers, the refuse list, the
  limits, the question's words); `AssistantGate.qml` in Slate answers `assistant status`,
  shows a question with `PowerConfirm` and holds the answer (`assistant confirm`, `answer`,
  `withdraw`). Leaving the session on a yes is done by Slate itself, so goodbye plays first.
- **It asks Slate, not the system.** Settings go through `slate ipc call config`, windows
  and workspaces through `hyprctl` with fixed dispatchers, Spaces and apps the way
  `scripts/spaces.py` does. If Slate isn't running, every tool says so.
- **Settings are found, not listed by hand.** Keys, types, defaults and notes are read from
  `SettingsData.qml`; names, pages and descriptions from `SettingsWindow.qml`
  (`scripts/settings-index.py`, which says which setting each row changes); search words from
  `SettingsIndex.qml`. What each text setting takes (`VALUES`) and each number's range
  (`RANGES`) are kept in the server, and a test fails when a new setting is in neither and
  isn't refused, so nothing can be set unchecked.
- **What agents are told about Slate** (the server's instructions) is
  `shell/data/assistant-prompt.md`.
- **The runner** (`shell/scripts/assistant.py`, for the prompt window that's coming) hands
  one prompt to the agent you chose and reads back its answer in one form whichever agent it
  is. It adds two things of Slate's own to what you typed: a briefing (who the agent is here
  and how to behave: the `[nova]` and `[shared]` parts of `assistant-prompt.md`) and a few
  lines on the moment (the time, the focused window and workspace, under the same switches as
  the tools, and never your name or home folder). The agent runs in an empty folder of its
  own and is stopped after two minutes.
- **Lists, bold and code in answers.** An answer is written by a model that may have been
  misled by something it read, so its words never reach a text item that reads markup. Qt's
  Markdown, styled and rich text all fetch any picture an answer names (checked on Qt 6.12:
  `![](https://…)`, `<img src=…>`, even a CSS background), which would send whatever is in
  the address to someone else's server without a click. Instead the runner reads a small
  subset of Markdown itself (`shell/scripts/safe_markdown.py`, plain Python) and sends it to
  the window as `{"type": "blocks", …}` events (at most ten a second as the answer grows, and
  once for the whole answer before `done`); the window draws them with its own items.

  | Markdown | Shown as |
  |---|---|
  | Paragraphs, line breaks, `**bold**`, `*italic*`, `` `code` `` | As written, code in the monospaced font on a faint plate |
  | Fenced code blocks | A code box (monospaced, not wrapped, scrolls sideways) with **Copy**, which copies just the code |
  | `-`, `*`, `+` and `1.` lists, one level of nesting | Bullets and numbers drawn by Slate; deeper nesting is drawn at that level |
  | `#` headings, any level | One bold line: answers are small |
  | Images | "[image: its description]". Nothing is fetched, ever |
  | Links | Their words, then the address in dim text: never clickable, but it can be selected and copied |
  | Raw HTML and entities | The characters, as typed: `<img src=…>` shows as exactly that |
  | Tables | Their rows as typed, in a monospaced box |
  | Quotes, rules, footnotes, task lists | Plain words, lightly tidied |

  The only markup the window's text items ever see is the few tags it writes itself (bold,
  italic, and a span for code or dim words) around words it has escaped. An unclosed mark
  while an answer is still arriving is plain characters, and an unclosed fence a code box
  still filling. Past 20,000 characters or 200 blocks it stops, with "…". The message's own
  copy button copies the answer as written, marks and all. A conversation kept from before
  (no blocks) shows its answers as plain text, as it always did. There's no setting: a command
  of your own is read the same way, since its output is no more trusted. The briefing tells
  Nova bold, a list or a code block can help, and never links, images or tables.
- **Agents** are in `shell/scripts/slate_agents.py`. Claude Code is run one prompt at a
  time with every tool of its own switched off and only Slate's server given (`--tools ""`,
  `--strict-mcp-config`, `--restricted`), for that run alone: nothing in your own Claude Code
  setup changes. "A command of your own" is run as typed with the prompt on its stdin and
  `SLATE_MCP_COMMAND`, `SLATE_MCP_CONFIG`, `SLATE_ASSISTANT_BRIEFING` and
  `SLATE_ASSISTANT_CONTEXT` in its environment; Slate can't limit what such a command does.
  To add an agent, write a class there beside `Claude` (how to find it, whether it's signed
  in, its command, how to read its output) and say honestly whether it's `confined`.
- **Tests:** `tests/unit/test_assistant.py` (the runner against a stand-in `claude` replaying
  a recorded stream), `tests/unit/test_safe_markdown.py` (the subset, hostile input, every
  cut of a streaming answer, the limits), `tests/unit/test_slate_mcp.py` (the protocol, the gate, every tool against a
  fake Slate, hostile input, the log) and `tests/live/test_assistant.py` (the questions in
  the real confirmation window, and the server against a real Slate).
