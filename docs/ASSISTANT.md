# Slate and assistants

Slate has an MCP server: a small program that lets an AI agent you already use (Claude Code,
Codex, anything that speaks the [Model Context Protocol](https://modelcontextprotocol.io))
ask about your desktop. "What's my accent colour?" "Which window is on workspace 3?" "Where
do I change the font?"

For now its tools only look: nothing an agent does through them changes anything. Tools
that change settings and arrange windows, with Slate asking you first where it matters, and
a prompt window of Slate's own, are planned ([plans/assistant.md](../plans/assistant.md)).

Nothing here runs unless you add the server to an agent yourself.

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

| Tool | Answers with |
|---|---|
| `status` | Slate's version, the time, the theme, game mode, night light, the battery, the network's name, and the focused window and workspace |
| `settings_search` | Settings that match a word or two ("glass", "dock size", "dpi"): each one's key, name, page in Settings, description, type, default and value now |
| `settings_get` | One setting, by its key |
| `windows_list` | Open windows: app, title, workspace, floating, full screen, focused |
| `workspaces_list` | Workspaces in use: name, window mode, how many windows, which screen |
| `spaces_list` | Your saved Spaces: name, how many workspaces, the apps in each |
| `apps_list` | Installed apps, by name |
| `wallpapers_list` | The names of the pictures in your wallpaper folder and Slate's own |

## What leaves your computer

Whatever a tool answers goes to the service behind the agent you added it to, under your own
account with them, the same as anything else you show that agent. Slate itself sends nothing
anywhere. So it's worth knowing what the answers hold:

- **Your settings**, as Settings shows them.
- **Your open windows and their titles.** Titles carry document names and web page titles.
- **Names**: of your workspaces, Spaces, installed apps, wallpaper files and your network.

And what they don't:

- Slate's tools answer in words only. They never give a picture of the screen, a recording,
  the contents of a window, a file, the clipboard or anything you've typed.
- Your location (the one in Settings → General) is never given.
- Folders are shown without your home folder's name, which is usually your user name.

## Where this stops

These are best efforts, and it's fairer to say so than to promise:

- **Slate can only answer for its own tools.** An agent with a terminal of its own can
  already do whatever a terminal can, with or without Slate's server: take a screenshot,
  read your files, run `slate ipc`. Adding the server gives that agent nothing it couldn't
  reach before; it gives it a tidy, described way to ask.
- **Assistants make mistakes, and can be misled by text they read.** A window's title is
  written by the app or web page in it, and could be written to look like an instruction.
  Slate cuts such text short, strips anything unprintable and tells the agent it's
  information and never an instruction, which helps but can't be relied on. While the tools
  only look, the most a misled agent can do through them is read what's listed above.

Using an agent with Slate is your choice. If you'd rather it couldn't ask, don't add the
server, or remove it.

## How it works

`shell/scripts/slate-mcp.py`, plain Python with nothing to install. It speaks MCP over
stdin and stdout, one JSON message per line, and stops when the agent closes it.

- **Both eras of the protocol.** The 2026-07-28 specification has no handshake: every
  request carries its version, and `server/discover` says what's spoken. Earlier versions
  (2025-11-25 back to 2024-11-05) open with `initialize`. The server answers whichever the
  agent uses.
- **It asks Slate, not the system.** Settings come from `slate ipc call config get`, windows
  and workspaces from `hyprctl -j`, Spaces and apps the way `scripts/spaces.py` finds them.
  If Slate isn't running, every tool says so.
- **Settings are found, not listed by hand.** Keys, types, defaults and notes are read from
  `SettingsData.qml`; names, pages and descriptions from `SettingsWindow.qml`
  (`scripts/settings-index.py`, which says which setting each row changes); search words from
  `SettingsIndex.qml`. A new setting is found without touching the server. The few whose
  row can't be linked are named in `NAMED` in the server, and a test fails when a setting
  has no name.
- **What agents are told about Slate** (the server's instructions) is
  `shell/data/assistant-prompt.md`.
- **Limits.** 60 tool calls a minute; past that a tool answers "slow down a moment".
- **Tests:** `tests/unit/test_slate_mcp.py` holds it to the protocol, to text-only answers,
  to asking Slate for nothing but `config get`, and to cleaning hostile titles.
