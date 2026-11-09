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
    property int nightLightTemperature: 4000 // kelvin: lower is warmer
    property string nightLightSchedule: "manual"   // manual, sun (sunset to sunrise) or custom
    property string nightLightFrom: "20:00"  // custom schedule
    property string nightLightTo: "07:00"
    property string locationName: ""         // Settings → General → Location; "" = not set
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
    property bool iconTileColour: false       // the tile behind an icon in a deep shade of the icon's own colour (icons not filling their shape)
    property string folderColour: "default"    // file manager folders: default, auto (from the wallpaper) or a Papirus colour
    property bool roundedScreenCorners: true  // rounded screen corners + curves under the bar
    property int windowBorderSize: 3          // px, around windows on workspaces with more than one (0 = none)
    property int inactiveDim: 50              // %, how much windows without focus are dimmed (0 = off)
    // ---- Keyboard & Mouse (Settings → Keyboard & Mouse). "" / -1 / -2 = not set here: whatever
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
    property string focusFollowsMouse: ""     // on / off (Settings → Windows)
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
    property bool keepEmptyWorkspace: false   // Settings → Workspaces: always an empty workspace after the last one in use
    property string windowMode: "tiling"       // tiling, or floating (every window floats, like a traditional desktop)
    property string titleButtons: "right"     // floating windows' title bar buttons: left or right
    property int windowGap: 6                 // px between tiled windows (edges get 2 more; 0 = none)
    property int soloWindowGap: 0             // px around a window alone on its workspace (0 = fills the screen)
    property string fontFamily: "Geist"       // interface font for the whole shell
    property string codeFontFamily: "Geist Mono"   // monospaced font, for theming apps (bundled)

    // Bar
    property string barPosition: "top"        // top, bottom, left or right
    property string dockPosition: "bottom"    // bottom, top, left or right (never the bar's edge)
    property bool barAutoHide: false          // hide when one window fills the screen
    property bool barHoverDescriptions: false // describe hovered items in the title area (off to start with)
    // What the bar shows (Settings → Menu Bar)
    property bool barShowApps: true           // apps (launcher) button
    property bool barShowSpaces: true         // Spaces (saved workspaces) button
    // Spaces (Settings → Spaces): how windows opened from a space are marked
    property bool spaceBorders: true          // a top border in the space's colour
    property bool spaceBadges: true           // the space's icon in the window's corner
    property bool spaceSwitcherBadges: true   // its icon on the window in Super+Tab and Super+Down
    property bool spaceBarTint: true          // the focused window's icon on the bar sits on its colour
    property bool barShowWorkspaces: true     // workspace dots
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
    property bool barStatusCollapsed: false   // Wi-Fi, volume, battery… as one button that opens to show them
    property bool barShowPower: true          // power button
    property string barClockFormat: "12h"     // 12h or 24h
    property bool barClockSeconds: false
    property bool barClockDate: true          // e.g. "Sat 7 Nov" before the time

    // Dock
    property real dockIconSize: 40
    property real dockMagnification: 1.75
    property real dockSpread: 3.0
    property bool dockAutoHide: true          // hide when the workspace has windows
    property real dockPreviewDelay: 0.6       // seconds paused on an app before its window previews show (0 = off)
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

    // Switchers
    property bool switcherPreviews: true
    property bool switcherAppIcons: true      // app icon on each window's preview in Super+Tab
    property bool wrapWorkspaces: true        // Super+Left/Right and the overview go from the last workspace to the first
    property bool overviewAppIcons: false     // app icon on each window in Super+Down
    property bool overviewPreviews: true      // live pictures of the windows in Super+Down (off: their outlines and app icons)
    property real overviewCardWidth: 728

    // Notifications
    property real notificationSeconds: 5
    property int notificationMaxToasts: 4

    // Screensaver (Settings → Screensaver): starts after this many idle minutes (0 = never)
    property int screensaverMinutes: 5
    property string screensaverStyle: "drift"    // drift, slideshow, videos or black
    property string screensaverVideoFolder: ""   // videos for the Videos style ("" = ~/Videos/Screensaver)
    property string screensaverVideoQuality: "auto"  // Get scenery videos: auto (for the screen), 2160p, 1440p or 1080p
    property bool screensaverClock: true         // the clock on drift and slideshow
    property int screensaverSlideSeconds: 20     // slideshow: each picture's time
    property bool screensaverLock: false         // waking it locks the screen
    // Glass (Settings → Appearance → Glass): see-through surfaces with Hyprland's blur behind
    property bool glass: false
    property real glassOpacity: 0.5           // how much of a surface's colour is kept (0.3–0.95)
    property int glassBlur: 10                // Hyprland's blur size while glass is on; 0 = Hyprland's own
    property bool glassShine: true            // a thin light rim on glass surfaces
    property real glassGlossTint: 1           // how much colour the sheen takes from what it's on (0 = white)
    property real glassGloss: 0.5             // how much glossy sheen (bar containers, hover highlights, tooltips): 0 = none, 1 = full, up to 2
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

    // Hot corners: none, lock, launcher, overview, control, notifications, screenoff
    property string hotCornerTopLeft: "none"
    property string hotCornerTopRight: "none"
    property string hotCornerBottomLeft: "none"
    property string hotCornerBottomRight: "none"
    property int hotCornerDelay: 500            // ms to rest in the corner
    property string notificationPosition: "top-right"   // top/bottom + left/center/right
}
