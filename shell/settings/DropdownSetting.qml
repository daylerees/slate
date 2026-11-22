import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import ".."

// A setting with a dropdown menu of choices (opens over the page; see win.drop)
Item {
    readonly property var win: SettingsHost.win
    id: dropdown
    property string label
    // (a screen reader: a list to choose from, by its label, saying what's chosen)
    Accessible.role: Accessible.ComboBox
    Accessible.name: label
    Accessible.description: current ? (current.label || "") : ""
    property string detail: ""
    width: parent ? parent.width : 0
    height: ddRow.height
    property var options: []
    property var value
    signal picked(var value)
    property string settingKey: ""          // (as SettingRow's: the changed-from-default mark)
    // (as SettingRow's: the setting this one only works with)
    property string needs: ""
    property bool needsMet: true
    property string needsPage: ""
    property string needsLabel: ""
    readonly property var current: options.find(o => o.value === value) ?? null
    // Shown when the value isn't one of the options (it isn't offered in the list itself)
    property string noneLabel: ""
    // A search box at the top of the open list, filtering it as you type (long lists)
    property bool searchable: false
    // Across the whole row, with no name beside it (a picker that is the row: App Rules' Choose an
    // app); its list opens as wide
    property bool wide: false
    property alias button: ddButton
    SettingRow {
      id: ddRow
      // (wide: the button is the row, so no name or description beside it; the dropdown keeps its
      // label, for the tests and for what search finds)
      label: dropdown.wide ? "" : dropdown.label
      detail: dropdown.wide ? "" : dropdown.detail
      settingKey: dropdown.settingKey
      needs: dropdown.needs; needsMet: dropdown.needsMet
      needsPage: dropdown.needsPage; needsLabel: dropdown.needsLabel
      defaultText: {
          const d = dropdown.settingKey !== "" ? Config.defaultOf(dropdown.settingKey) : undefined;
          const o = d === undefined ? null : dropdown.options.find(x => x.value === d);
          return o ? o.label : "";
      }
      Rectangle {
        id: ddButton
        readonly property bool open: win.drop.owner === dropdown
        // As wide as its choice needs, up to a bit under half the row (long names shorten in the middle)
        readonly property real naturalWidth: ddText.implicitWidth + 44 + (ddFolder.visible ? ddFolder.width + 8 : 0) + (ddApp.visible ? ddApp.width + 8 : 0)
            + (ddIcon.visible ? ddIcon.width + 8 : 0)
        width: dropdown.wide ? dropdown.width - 32 : Math.max(150, Math.min(naturalWidth, dropdown.width * 0.45)); height: 32; radius: Config.corner(8)
        color: "transparent"
        HoverFill { base: win.control; hovered: ddButton.open || ddHover.hovered; radius: ddButton.radius }
        border.width: open ? 1 : 0; border.color: win.accent
        Behavior on color { ColorAnimation { duration: Config.ms(100) } }
        // Options can carry a folder colour (folder: "#hex"): a little folder in it before the label
        FolderSwatch {
            id: ddFolder
            visible: !!dropdown.current && !!dropdown.current.folder
            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
            colour: dropdown.current && dropdown.current.folder ? dropdown.current.folder : "transparent"
        }
        // ...or an app's own icon (app: its desktop id or window class), as the dock draws it
        AppTile {
            id: ddApp
            visible: !ddFolder.visible && !!dropdown.current && !!dropdown.current.app
            anchors { left: parent.left; leftMargin: 9; verticalCenter: parent.verticalCenter }
            width: 18; height: 18
            app: dropdown.current && dropdown.current.app ? dropdown.current.app : ""
        }
        // ...or an icon (icon: a glyph code)
        Text {
            id: ddIcon
            visible: !ddFolder.visible && !ddApp.visible && !!dropdown.current && !!dropdown.current.icon
            anchors { left: parent.left; leftMargin: 11; verticalCenter: parent.verticalCenter }
            text: visible ? win.glyph(dropdown.current.icon) : ""
            color: win.text; font.family: win.bar.iconFont; font.pixelSize: 16
        }
        Text {
            id: ddText
            readonly property Item lead: ddFolder.visible ? ddFolder : ddApp.visible ? ddApp : ddIcon.visible ? ddIcon : null
            anchors { left: lead ? lead.right : parent.left; leftMargin: lead ? 8 : 12; verticalCenter: parent.verticalCenter }
            width: Math.min(implicitWidth, ddButton.width - x - 32)
            textFormat: Text.PlainText        // never markup: an option can be a device's, an app's or a file's name
            text: dropdown.current ? dropdown.current.label : dropdown.noneLabel !== "" ? dropdown.noneLabel : String(dropdown.value)
            color: win.text; font.family: (dropdown.current && dropdown.current.font) || win.font; font.pixelSize: Config.text(12); font.weight: Font.Medium
            elide: Text.ElideMiddle      // device names differ at the end: keep it in view
        }
        Text {
            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
            text: win.glyph(0xEA5F)                      // chevron down
            rotation: ddButton.open ? 180 : 0
            Behavior on rotation { NumberAnimation { duration: Config.ms(120) } }
            color: win.dim; font.family: win.bar.iconFont; font.pixelSize: 16
        }
        HoverHandler { id: ddHover }
        ClickTap { onTapped: { if (!win.drop.reopening(dropdown)) win.drop.owner = ddButton.open ? null : dropdown; } }
      }
    }
}
