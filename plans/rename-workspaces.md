# Plan: rename workspaces

Status: **proposed, not started** (written 2026-11-10).

## The idea

Give a workspace a name of your own ("Coding", "Music") from the window mode panel. The name
replaces "Workspace 3" everywhere Slate would otherwise show the number, stays for as long as
the workspace is around, and is saved and restored with a Space.

## Where workspaces are numbered today

Only five places show a number as text. All of them build the string by hand
(`"Workspace " + id`):

| Where | File |
|---|---|
| Window mode panel title | `Popouts.qml:1774` |
| Window mode segment's hover text on the bar | `Bar.qml:494` |
| Workspace dot's hover text on the bar | `Bar.qml:520` |
| Label under each card in the workspace switcher, Super+Down ("Workspace 1 · kitty and 3 others"; strip and grid) | `WorkspaceOverview.qml:800` |
| "New Space" picker cards in the Spaces panel | `Popouts.qml:1335` |

The workspace switcher is the one people will notice most: a named workspace reads
"Coding · kitty and 3 others" there. Its label is built from a plain copy of the workspace
(`{ id, name }`, line 178, because Hyprland deletes workspaces that go empty), so it switches
to `Config.workspaceLabel(card.modelData.id)` and updates live if you rename while it's open.

The rows of **dots** (the bar, under the window switcher, and the Super+Left/Right pill in
`OSD.qml`) have no number or text, so there's nothing to replace there and they stay as they
are. The shortcut descriptions in `binds.lua` ("Go to workspace 3") name the *key*, not the
workspace, and stay as they are.

## Design

### 1. Where the name lives

Copy how per-workspace window modes work (`Config.qml:1000-1032`), since the lifetime wanted
is the same:

- `$XDG_RUNTIME_DIR/slate/workspace-names-<HYPRLAND_INSTANCE_SIGNATURE>.json`, a map of id to
  name (`{"3": "Coding"}`), read through a `FileView` into `Config.workspaceNames`.
  It survives a Slate reload or restart, and starts empty with each new Hyprland session.
- `Config.setWorkspaceName(id, name)`: trims the name, cuts it to the limit, removes the key
  when it's empty (back to the number), writes the file.
- `Config.workspaceName(id)`: the name, or `""`.
- `Config.workspaceLabel(id)`: the name if there is one, otherwise `"Workspace " + id`. **Every
  place in the table above calls this**, so there's one rule and nothing to keep in step.
- IPC target `workspacename` in `shell.qml`, next to `workspacemode`: `set(id, name)`,
  `get(id)`. `spaces.py` and the tests use it.

Slate keeps the name itself; it doesn't call Hyprland's `renameworkspace`. Hyprland's own name
is what the Lua config and other tools match workspaces on, and it's lost the moment a
workspace empties, so it's the wrong place for this.

**Limit: 20 characters.** That fits the 300-wide panel title at 15px with the pencil beside
it, and the workspace switcher's label with " · kitty and 3 others" after it. Every place it's shown still
elides, in case of wide characters.

### 2. When the name goes away

"Held while the workspace is active": the name is dropped when Hyprland removes the workspace
(its last window closes and you've moved off it), so workspace 3 doesn't come back later
still called "Coding".

- A `Connections` on `Hyprland.workspaces` in `Config.qml` removes names whose id is no
  longer in the list.
- It mustn't run before Hyprland's list has loaded after a Slate reload, or a reload would
  wipe every name. Prune only once the list is non-empty, and never from a `testMode` start
  without workspaces.
- Window modes aren't cleaned up this way today (`{"3": "floating"}` outlives workspace 3).
  That stays as it is: a mode is a preference for the slot, a name describes what's in it.

### 3. The pencil on the window mode panel

- In `windowModePanel` (`Popouts.qml:1764`), the title becomes
  `PanelTitle { text: Config.workspaceLabel(wmView.ws) }` with an `Icon` straight after the
  text (not pushed to the right edge): Tabler "edit", `0xEA98`, the pencil on a square of
  paper. It's in `tabler.ttf` already and unused so far (the plain pencil `0xEB04` is the
  avatar's). Colour `pop.accent`, 16px, with a `ClickArea` so it clicks like everything
  else, and hover text "Rename this workspace".
- `PanelTitle`'s label needs a width cap so a 20-character name and the pencil never
  overflow; the label elides first.

### 4. The dialog

Reuse `PowerConfirm` rather than a card of its own, so it looks and behaves like every other
dialog. It has no text field yet, so add one as an optional part of a question:

- `confirmWith` spec gains `input: { text, placeholder, maxLength }`. When present, the
  dialog shows a text field between the body and the buttons, styled like the Spaces panel's
  name field (`Popouts.qml:1346`: card colour, gloss, accent border when focused), focused
  with the current name selected. Enter confirms, Escape cancels (the dialog already takes
  the keyboard: `PowerConfirm.qml:140`).
- `onConfirm` is given the text (alongside the option's answer, for questions that have both).
- The panel closes when the dialog opens, as it does for "Delete this Space".

The question itself, in Slate's voice:

- Title: **Name this workspace** (or **Rename "Coding"** when it has one)
- Body: "Pick a short name for workspace 3. It stays until the workspace closes, and is
  saved with a Space. Leave it empty to go back to the number."
- Placeholder: "Workspace 3"
- Buttons: **Rename** / **Cancel**

### 5. Spaces and the session

`spaces.py`, the same way `mode` travels today:

- `snapshot()` adds `"name"` to a workspace when it has one (read from the names file, like
  `workspace_modes()` at line 63).
- `save()` keeps it in the saved workspace. `session_save()` keeps it too, so names come back
  after a restart with "reopen my apps".
- `Restorer.restore_workspace()` calls `slate ipc call workspacename set <ws> <name>` for the
  workspace it opens on (a Space opens on new ids, so the name follows the windows, not the
  old number).
- Older `spaces.json` files have no `name`, which simply means "numbered". No migration.
- The "New Space" picker cards use `Config.workspaceLabel`, so you can see which workspace is
  which while choosing what to save.

### 6. Everything else

- **Sounds:** the pencil clicks (`ClickArea`). The dialog goes through `confirmWith`, which
  plays the attention sound today; see "Open questions".
- **Animations / game mode:** nothing new; the dialog and panel already respect both.
- **Other distros:** no new dependency.
- **Login and lock screens:** untouched.

## Work, roughly

1. `Config.qml`: names file, `workspaceNames`, `setWorkspaceName`, `workspaceName`,
   `workspaceLabel`, pruning. `shell.qml`: `workspacename` IPC; names in the test `state()`.
2. Swap the five strings for `Config.workspaceLabel(...)`.
3. `PowerConfirm.qml`: the optional `input` field.
4. `Popouts.qml`: the pencil and the rename question.
5. `spaces.py`: `name` in snapshot, save, session and restore.
6. Install, reload (a full restart isn't needed: no new files or inline components unless
   the text field becomes one), try it, iterate.
7. Tests:
   - unit (`tests/unit/test_spaces.py`, beside `WorkspaceModes`): name in the snapshot, saved
     with the Space and the session, set again on restore, absent when unnamed, old files
     without it still load.
   - live: `workspacename set/get`; the name shows in the panel title and `state()`; the
     dialog opens from the pencil, takes text, Enter renames, Escape leaves it alone, an
     empty name goes back to the number; a 40-character name is cut to 20; the name is
     dropped when the workspace closes and **kept across a Slate reload**.
   - static: a consistency check that no QML builds `"Workspace " +` by hand any more.
   - visual: a `panel-windowmode` scene with a named workspace, and a `rename-workspace`
     dialog scene; and a named workspace in the `overview` (workspace switcher) scene.
8. Docs and site: `site/features.html` (window mode at 217, Spaces at 249, overview at 263),
   `README.md` (Spaces, overview), `docs/ARCHITECTURE.md` (the names file and IPC beside the
   window mode notes at 98-108, and the Spaces format at 223-247).
9. One commit: `feat(workspaces): name your workspaces`.

## Open questions

- **How a named workspace reads.** Just "Coding", or "3 · Coding"? Suggested: just the name,
  as this plan assumes ("Coding · kitty and 3 others" in the workspace switcher); the dot's
  position already says which number it is.
- **The attention sound.** Renaming is something you asked for, not Slate asking you. Suggested:
  a question with an `input` opens silently (the pencil's click is enough).
- **Empty workspaces.** You can name the empty workspace you're standing on, but the name goes
  as soon as you leave it without opening anything. Fine, or should the pencil hide until the
  workspace has a window?
