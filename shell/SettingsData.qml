// Every Slate setting and its default. Config keeps two: one tied to settings.json (the
// values in use) and one left untouched, so a settings page can restore its defaults.

import QtQuick
import Quickshell.Io

JsonAdapter {

    // Colour, theme and wallpaper (Settings → Appearance)
    property string accent: "#8fb3e8"
    property bool accentFromWallpaper: false
    property real accentBoldness: 0.6         // Settings → Appearance → Accent boldness: the wallpaper accent in dark mode, 0 (as picked) to 1 (bold)
    property bool lightMode: false           // light variant in use (set by themeMode)
    property string themeMode: ""            // dark, light or auto (light by day); "" = from lightMode
    property bool toneFromWallpaper: false   // tint the dark UI colours from the wallpaper
    property real toneBoldness: 0.5          // Settings → Appearance → Tint boldness: how much colour backgrounds take (0.5 = the standard amount)
    property string wallpaper: ""            // image shown on the desktop, lock screen and login screen
    property string wallpaperFolder: ""      // empty = ~/Pictures
    property bool wallpaperHideSmall: true   // Settings → Appearance: leave out images too small to be wallpapers
    property bool wallpaperShowSlate: true   // …and show the wallpapers that come with Slate (shell/wallpapers) beside your folder's
    property string wallpaperMinSize: "1280x720"   // the smallest size shown (width x height)
    property string wallpaperChange: "off"   // Settings → Appearance → Change wallpaper: off, login, or every N minutes ("15", "60"…)
    // Slate's sounds (Settings → Sound), each at its own volume: % (0 = off). -1 = not set yet,
    // so it comes from the on/off switches and single effects volume of earlier versions (below)
    property int tickVolume: -1               // volume keys: a short tick at the new volume
    property int notificationVolume: -1       // a soft chime when a notification pops up
    property int clickVolume: -1              // a barely-there tap on Slate's buttons and menus
    property int swishVolume: -1              // switching workspaces and windows
    property int welcomeVolume: -1            // logging in (once per session)
    property int goodbyeVolume: -1            // logging out, restarting, shutting down
    property int attentionVolume: -1          // confirmations, password prompts and warnings
    // Earlier versions' sound settings: only read to fill in the volumes above
    property bool volumeSound: true
    property bool notificationSound: true
    property bool clickSound: false
    property bool swishSound: false
    property bool welcomeSound: true
    property bool goodbyeSound: true
    property int soundEffectsVolume: 100
    property bool nightLight: false          // warm the screen colours (control centre toggle)
    // The control centre's quick switches, in order (Settings → Control Centre): eight of
    // Config.controlSwitchList
    property var controlSwitches: ["wifi", "bt", "airplane", "caffeine", "night", "dnd", "perf", "gamemode"]
    // Airplane mode (AirplaneMode.qml): Wi-Fi, Bluetooth and mobile broadband off together;
    // airplaneRestore: which of "wifi" and "bt" it turned off, to turn back on after
    property bool airplaneMode: false
    property var airplaneRestore: []
    property int nightLightTemperature: 4000 // kelvin: lower is warmer
    property string nightLightSchedule: "manual"   // manual, sun (sunset to sunrise) or custom
    property string nightLightFrom: "20:00"  // custom schedule
    property string nightLightTo: "07:00"
    property string locationName: ""         // Settings → General → Location; "" = not set
    property string temperatureUnit: "celsius"   // the weather's temperatures: celsius or fahrenheit
    property string dateFormat: "dmy"        // how dates are written: dmy (Sat 7 Nov), mdy (Sat, Nov 7) or ymd (2026-11-07)
    property string weekStart: "monday"      // the calendar's first day: monday, sunday or saturday
    property real latitude: 0                // for weather and sunset/sunrise
    property real longitude: 0
    property string mainDisplay: ""           // Settings → Displays → Main display (monitor description; "" = the first)
    property string logLevel: "normal"        // Settings → Debug → Log detail: normal, detailed or everything (applied when Slate starts)
    property real uiScale: 1                  // Settings → Appearance → Interface size: scales all of Slate (applied when Slate starts)
    property string workspaceShape: "square"  // workspace indicators: square (rounded) or circle
    property string iconShape: "tile"          // Settings → Appearance → App icons: tile, squircle, circle, square or original
    property bool iconFill: false             // icons crop their own borders and grow to fill the shape (off, the default: whole and smaller, on slate)
    property bool tintIcons: false            // tint app icons with the accent colour
    property int iconTintStrength: 60         // %, how strongly
    property bool gameMode: false             // game mode (the bar's game mode panel): costly effects off, see Config.gameMode
    property bool iconTileColour: true        // the tile behind an icon in a deep shade of the icon's own colour (icons not filling their shape)
    property string folderColour: "default"    // file manager folders: default, auto (from the wallpaper) or a Papirus colour
    property bool roundedScreenCorners: true  // rounded screen corners + curves under the bar
    property bool shadows: true               // shadows under everything raised: Slate's surfaces and floating windows (Settings → Appearance → Shadows)
    property real shadowDarkness: 0.7         // how dark at their darkest, 0–1 (light mode: half that; glass: kept below where Hyprland blurs)
    property real shadowSoftness: 2           // px of soft edge (0: hard)
    property real shadowSpread: 0             // px the full darkness reaches past the surface
    property real shadowDistance: 3           // px from the surface
    property int shadowDirection: 0           // degrees the shadow falls, clockwise from straight down
    property bool roundedElements: true       // rounded corners on everything Slate draws, and on windows (off: all hard squares; app icons and workspace dots keep their own shapes)
    property int windowBorderSize: 3          // px, around windows on workspaces with more than one (0 = none)
    property int inactiveDim: 50              // %, how much windows without focus are dimmed (0 = off)
    // ---- Input (Settings → Input). "" / -1 / -2 = not set here: whatever
    // Hyprland's config (and your ~/.config/slate/hypr/hyprland.lua) sets is left alone
    property string kbLayouts: ""             // xkb layouts, comma-separated, e.g. "gb,us"
    property string kbVariants: ""            // their variants, comma-separated ("" for each = the usual)
    property string kbSwitch: ""              // switching layouts: alt_shift, ctrl_space, caps or none
    property string capsLock: ""              // Caps Lock: default, ctrl, escape or off
    property int keyRepeatDelay: 500          // ms before a held key repeats (0 or less: Hyprland's own)
    property int keyRepeatRate: 16            // repeats per second (0 or less: Hyprland's own)
    property real mouseSpeed: -2              // -1 … 1 (0 = the device's own speed)
    property string mouseAccel: ""            // adaptive or flat
    property string mouseNaturalScroll: ""    // on / off
    property real touchpadScrollSpeed: -1     // 0.1 … 2 (1 = normal)
    property string touchpadNaturalScroll: "" // on / off
    property string touchpadTapToClick: ""    // on / off
    property string touchpadIgnoreWhileTyping: "" // on / off
    property int cursorSize: 0                // px (0 = not set here)
    property string focusFollowsMouse: "on"   // on / off (Settings → Windows); "" leaves it to Hyprland's own config
    property string animations: ""            // normal, fast or off (Settings → Appearance)
    // How much colour the interface uses (Settings → Appearance → Colour): "monotone" (the
    // accent and greys) or "colourful" (pastels: each Settings page its own colour…)
    property string colourStyle: "colourful"
    // How switching workspace looks: slidefade, slidefadevert, slide, slidevert, crossfade or none
    property string workspaceAnimation: "slidefade"
    // ---- Default apps (Settings → Default Apps): desktop entry ids ("" = not set here)
    property string defaultTerminal: ""
    property string defaultBrowser: ""
    property string defaultFileManager: ""
    property string defaultEditor: ""
    property string defaultCalculator: ""
    // ---- Power (Settings → Power)
    property string lidAction: ""             // "" (the system's), suspend, lock, screenoff or nothing
    property string powerKeyAction: ""        // "" (the system's), menu, suspend, poweroff, lock or nothing
    property string profileOnBattery: ""      // "" (leave it), power-saver, balanced or performance
    property string profileOnAC: ""
    property bool reopenAppsAfterRestart: true  // the restart dialog's switch: open your apps again after restarting, where they were
    // ---- Sound, startup, screenshots
    property var themedApps: []               // Settings → App Theming: app ids that follow Slate's colours (none until switched on)
    property var startupApps: []              // desktop entry ids opened at each login
    property string screenshotFolder: ""      // "" = ~/Pictures/Screenshots
    property string screenshotName: "default" // default, compact or gnome (see scripts/screenshot.sh)
    property string screenshotAfter: "edit"   // edit (swash, when installed) or save
    property bool clipboardHistory: true      // keep a history of what you copy (Super+V)
    property bool keepEmptyWorkspace: true    // Settings → Workspaces: always an empty workspace after the last one in use
    property string windowMode: "tiling"       // tiling (dwindle), master, scrolling, monocle, or floating (every window floats, like a traditional desktop)
    property string titleButtons: "left"      // floating windows' title bar buttons: left or right
    property string titleBarStyle: "slate"    // floating windows' title bars: slate (Slate's own, on the window in front), or hyprbars (the optional plugin, on every floating window)
    property int windowGap: 6                 // px between tiled windows (edges get 2 more; 0 = none)
    property int soloWindowGap: 0             // px around a window alone on its workspace (0 = fills the screen)
    property string fontFamily: "Geist"       // interface font for the whole shell
    property string codeFontFamily: "Geist Mono"   // monospaced font, for theming apps (bundled)

    // Bar
    property string barPosition: "top"        // top, bottom, left or right
    property string dockPosition: "bottom"    // bottom, top, left or right (never the bar's edge)
    // What's on the bar and in what order (Settings → Menu Bar, by dragging on the bar itself):
    // a list, along the bar, of containers ({ items: [ids], tuck?, tuckIcon?, tuckFrom? }),
    // "title" (the active window, bare) and "space" (a flexible space). [] = Slate's own
    // arrangement (Config.barLayoutDefault). See plans/menu-bar-layout.md
    property var barLayout: []
    property bool barBlur: true               // with glass: what's behind the bar is blurred (off: seen straight through it)
    property real barOpacity: 0.75            // with glass: the bar's background, 0 clear … 1 solid
    property bool barPanelBlur: true          // with glass: what's behind the bar's panels is blurred
    property real barPanelOpacity: 0.8        // with glass: the panels' background, 0 clear … 1 solid (the bar's own colour)
    property var barOverflow: []              // the order things leave a bar that's short of room, first to go first ([] = Slate's own)
    property var barStay: ["power", "clock", "control"]   // …and the ones that never leave it
    property real barItemOpacity: 0.8         // with glass: the containers on the bar, what's in them too, 0 gone … 1 solid
    property real barItemHoverOpacity: 0.8    // ...and while the pointer's over one
    property bool barAutoHide: false          // hide when one window fills the screen
    // What the bar shows (Settings → Menu Bar)
    property bool barShowControl: true        // the control centre's button (Slate's mark)
    property bool barShowClock: true          // the clock
    property bool barShowApps: true           // apps (launcher) button
    property bool barShowSpaces: true         // Spaces (saved workspaces) button
    property bool barShowAssistant: true      // Nova, the assistant's button (only while the assistant is switched on)
    // Spaces (Settings → Spaces): how windows opened from a space are marked
    property bool spaceBorders: true          // a top border in the space's colour
    property bool spaceBadges: true           // the space's icon in the window's corner
    property bool spaceSwitcherBadges: true   // its icon on the window in Super+Tab and Super+Down
    property bool spaceBarTint: true          // the focused window's icon on the bar sits on its colour
    property bool barShowWorkspaces: true     // workspace dots
    property bool barShowWindowMode: true     // ...with the workspace's window mode before them (click to change it)
    property bool barShowTitle: true          // focused window's title
    property bool barShowTitleIcon: true      // …with its app's icon before it
    property bool barShowTray: true           // app tray icons
    property bool barShowNotifications: true
    property bool barShowClipboard: false     // clipboard history, with how many items it holds
    property bool barShowScreenshot: false    // screenshot buttons (area, window, screen)
    property bool barShowWifi: true
    property bool barShowKeyboard: true       // keyboard layout switcher (when there's more than one layout)
    property bool barShowBluetooth: true      // Bluetooth (on computers with an adapter)
    property bool barShowVolume: true
    property bool barShowBattery: true
    property bool barShowGameMode: false     // game mode, with the status icons (off to start with)
    property bool barValueClipboard: true     // how many items are in the clipboard history
    property bool barValueGameMode: true      // On or Off beside the game mode icon
    property bool barValueWifi: true          // the network name beside the Wi-Fi icon
    property bool barValueKeyboard: true      // the active layout's code (GB, FR…) beside the keyboard icon
    property bool barValueBluetooth: true     // how many devices are connected, beside the Bluetooth icon
    property bool barValueVolume: true        // the volume % beside its icon
    property bool barValueBattery: true       // the battery % beside its icon
    property bool barTrayCollapsed: false     // the tray as one button that opens to show its icons
    property bool barTrayMono: false          // tray icons in one colour, as the bar's own, even in the Colourful look (off to start with)
    property bool barStatusCollapsed: false   // Wi-Fi, volume, battery… as one button that opens to show them
    property bool barShowPower: true          // power button
    property string barClockFormat: "12h"     // 12h or 24h
    property bool barClockSeconds: false
    property bool barClockDate: true          // e.g. "Sat 7 Nov" before the time

    // Dock
    property real dockIconSize: 40
    property string dockHoverEffect: "magnify"   // pointing at the dock: magnify, tilt (icons turn to face the pointer), both, fade, fademagnify, glow (a ring and glow in the icon's colour), glowmagnify, raise (just the icon under the pointer lifts) or none
    property real dockMagnification: 1.75
    property real dockSpread: 3.0
    // The launcher's and Nova's windows with glass: a blur and a background opacity of their
    // own, 0 clear … 1 solid (below 0: as Appearance's glass opacity has it)
    property bool launcherBlur: true
    property real launcherOpacity: 0.75
    property bool assistantBlur: true
    property real assistantOpacity: 0.75
    property bool notificationBlur: true      // with glass: what's behind a notification is blurred (off: seen straight through it)
    property real notificationOpacity: 0.8    // with glass: a notification's background, 0 clear … 1 solid
    property real notificationHoverOpacity: 0.8   // ...and while the pointer's on it
    property bool dockBlur: true              // with glass: what's behind the dock is blurred (off: seen straight through it)
    property real dockOpacity: 0.6            // with glass: the dock's background, 0 clear … 1 solid
    property real dockIconOpacity: 1.0        // with glass: its icons, and what's drawn on its buttons, 0 gone … 1 solid
    property real dockTileOpacity: 1.0        // with glass: the tiles behind its icons and its buttons, 0 gone … 1 solid
    property bool dockAutoHide: true          // hide when the workspace has windows
    property bool dockShowLauncher: true      // the Apps button at the start of the dock
    property bool dockPreviews: true          // pausing on an app in the dock shows its windows
    property real dockPreviewDelay: 0.2       // …after this many seconds (0 = at once)
    property bool dockBadges: true            // unread counts and progress on app icons
    property bool dockDivider: true           // a line between pinned apps and the others
    property bool dockShowMedia: true         // what's playing, after the Apps button, with its controls
    property bool dockMediaArt: true          // its album art
    property bool dockShowDownloads: true     // a Downloads stack before the waste basket
    property bool dockShowTrash: true         // the waste basket at the end of the dock

    // Launcher
    property string launcherLayout: "list"     // Settings → Launcher → Layout: list or grid
    property int launcherColumns: 6            // grid: apps across
    property int launcherRows: 4               // grid: rows shown at once (more scroll)
    property bool launcherDescriptions: true
    property bool launcherSortByUsage: true
    property bool launcherWrap: true           // arrow keys go round from the last result to the first
    property bool launcherRecent: true         // the apps opened most recently first, before you type
    property bool launcherFuzzy: true          // initials and small slips find apps too
    property bool launcherWindows: true        // open windows, by title
    property bool launcherActions: true        // apps' own actions (New Private Window…)
    property bool launcherToggles: true        // Wi-Fi, Bluetooth, Do Not Disturb, night light, game mode
    property bool launcherFiles: true          // recent files and folders in your home
    property bool launcherConvert: true        // units and dates ("5 km in miles", "today + 30 days")
    property bool launcherCommands: true       // "> command" runs it
    property bool launcherEmoji: true          // ":name" finds emoji
    property bool launcherWeb: true            // a last result to search the web
    property string launcherSearchEngine: "duckduckgo"   // duckduckgo, google, bing, brave, startpage, ecosia

    // Switchers
    property bool switcherPreviews: true
    property bool switcherAppIcons: true      // app icon on each window's preview in Super+Tab
    property bool workspaceSwitchName: true   // the indicator shown as you switch workspace (Super+Left/Right) names the one you land on
    property bool wrapWorkspaces: false       // Super+Left/Right and the overview go from the last workspace to the first
    property bool overviewAppIcons: false     // app icon on each window in Super+Down
    property bool overviewPreviews: true      // live pictures of the windows in Super+Down (off: their outlines and app icons)
    property real overviewCardWidth: 728
    property int overviewGridSize: 3          // the overview's grid (Moving between workspaces: Grid): columns, and rows shown
    // Their animations: moving through the cards (slide, hop, wheel, tilt, orbit, deck, fan or
    // instant; the overview also grid) and going to the one picked (Super+Tab: crossfade, workspace or instant; Super+Down: zoom, fade, workspace
    // or instant; "workspace" is the Workspace switching animation)
    property string switcherMoveAnimation: "slide"
    property string switcherPickAnimation: "crossfade"
    property string overviewMoveAnimation: "slide"
    property string overviewPickAnimation: "zoom"

    // Notifications
    property real notificationSeconds: 5
    property int notificationMaxToasts: 4

    // Screensaver (Settings → Screensaver): starts after this many idle minutes (0 = never)
    property int screensaverMinutes: 5
    property string screensaverStyle: "black"    // drift, slideshow, videos or black
    property string screensaverVideoFolder: ""   // videos for the Videos style ("" = ~/Videos/Screensaver)
    property string screensaverVideoQuality: "auto"  // Get scenery videos: auto (for the screen), 2160p, 1440p or 1080p
    property bool screensaverClock: true         // the clock on drift and slideshow
    property int screensaverSlideSeconds: 20     // slideshow: each picture's time
    property bool screensaverLock: false         // waking it locks the screen
    // Glass (Settings → Appearance → Glass): see-through surfaces with Hyprland's blur behind
    property bool glass: false
    property real glassOpacity: 0.5           // how much of a surface's colour is kept (0.3–0.95)
    property int glassBlur: 10                // Hyprland's blur size while glass is on; 0 = Hyprland's own
    property real glassGlossTint: 1           // how much colour the sheen takes from what it's on (0 = white)
    property real glassGloss: 1.0             // how much glossy sheen (bar containers, hover highlights, tooltips): 0 = none, up to 2. Settings shows it as 0–100%, so this default reads 50%
    // Blur (Settings → Appearance → Blur): Hyprland's blur behind see-through windows and glass
    property bool fastBlur: true              // blur only the wallpaper (Hyprland's xray): much less work
    property int blurPasses: 2                // 1–4 (2 = Medium); 0 = Hyprland's own
    // The welcome has been seen (shown the first time Slate starts; again from Settings → About)
    property bool welcomeShown: false
    // Updates (Settings → Updates): look for new versions daily, with a notification
    property bool updateCheck: true
    // Keyboard shortcuts (Settings → Shortcuts): slate, hyprland or hyprland-extras
    property string keyset: "slate"
    // Lock & idle (minutes; 0 = never)
    property bool lockBeforeSleep: true
    property bool lockScreenPowerMenu: false    // power button on the lock screen
    property int idleLockMinutes: 10
    property int idleScreenOffMinutes: 15
    property int idleSuspendMinutes: 0
    property bool idleRespectInhibitors: true   // wait while video/apps keep the screen awake

    // Assistants (docs/ASSISTANT.md): AI agents using Slate's MCP server (slate mcp). None of
    // these can be changed through the server itself
    property bool assistantEnabled: false       // let assistants use Slate's tools at all (off to start with)
    property int assistantRisksAccepted: 0      // the version of the risks you accepted when switching on (0 = never); both are needed
    property string assistantAgent: ""          // which agent answers Nova: claude, custom… ("" = none: one has to be chosen)
    property string assistantModel: ""          // its model ("" = the agent's own default)
    property string assistantCommand: ""        // a command of your own (the "custom" agent): run as typed, the prompt on its stdin
    property bool assistantCommandBare: false   // …given just what you typed, without what Slate adds
    property var assistantAgentsAccepted: []    // agents that keep tools of their own that you've said yes to
    property bool assistantKeepChat: true       // Nova's conversation is still there after Slate restarts (kept on this computer only)
    property bool assistantAskChanges: false    // ask before every change, not only the ones that can't be undone
    property bool assistantSeeTitles: true      // window titles are given (off: app names only)
    property bool assistantSeeNotifications: false  // recent notifications can be read

    // Hot corners: none, lock, launcher, overview, control, notifications, screenoff
    property string hotCornerTopLeft: "none"
    property string hotCornerTopRight: "none"
    property string hotCornerBottomLeft: "none"
    property string hotCornerBottomRight: "none"
    property int hotCornerDelay: 500            // ms to rest in the corner
    property string notificationPosition: "top-right"   // top/bottom + left/center/right
}
