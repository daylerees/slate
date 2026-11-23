import QtQuick
import "../.."
import ".."

Column {
    readonly property var win: SettingsHost.win
    id: barPane
    spacing: 4
    PageTitle { text: "Menu Bar" }
    // ---- Arranging the bar: done on the bar itself, with a panel beside it (BarEditor.qml)
    GroupLabel { text: "Layout" }
    Group {
        SettingRow {
            label: "Arrange the menu bar"
            detail: "Drag things along the bar itself, put them together in containers, add space between them, and take off what you don't use. "
                + "Settings steps out of the way while you do, and comes back when you press Done"
            Button { label: "Edit layout"; onClicked: Config.barArranging = true }
        }
    }
    GroupLabel { text: "Position & behavior" }
    Group {
        SettingRow {
            label: "Position"
            settingKey: "barPosition"
            defaultText: { const d = Config.defaultOf("barPosition"); return d.charAt(0).toUpperCase() + d.slice(1); }
            detail: "Click an edge. The dock is at the " + Config.s.dockPosition + "; if you pick its edge, it moves to the opposite one. On the left or right, the status icons drop their text and the window title turns to run along the bar"
            EdgePicker { accent: win.accent; bar: true; edge: Config.s.barPosition; onPicked: e => Config.moveBar(e) }
        }
        Separator {}
        ToggleSetting {
            label: "Auto-hide"
            detail: "Slides the bar out of your way when a single window fills the screen; it comes back when you switch workspace or reach for the bar's edge"
            key: "barAutoHide"
        }
        Separator {}
        ToggleSetting {
            label: "Monochrome tray icons"
            detail: "Draws the tray's app icons in one color, like the rest of the bar, even with the Colorful look on"
            key: "barTrayMono"
        }
    }
    // (only with glass on: Appearance → Glass)
    GroupLabel { visible: Config.s.glass; text: "Glass" }
    Group {
        visible: Config.s.glass
        ToggleSetting {
            label: "Blur"
            detail: "What's behind the bar is blurred, like frosted glass. Off, you see straight through it"
            key: "barBlur"
        }
        Separator {}
        SettingRow {
            label: "Background opacity"
            settingKey: "barOpacity"
            detail: "How solid the bar's background is: 100% can't be seen through, lower is clearer"
            ValueSlider { per: 100; from: 0; to: 100; stepSize: 1; suffix: "%"; value: Math.round((Config.s.barOpacity < 0 ? Config.barGlassOpacity : Config.s.barOpacity) * 100); onMoved: v => Config.s.barOpacity = v / 100 }
        }
        Separator {}
        SettingRow {
            label: "Contents opacity"
            settingKey: "barItemOpacity"
            detail: "How solid the containers on the bar are, with everything in them: their icons, text and dividers. At 0% they're gone"
            ValueSlider { per: 100; from: 0; to: 100; stepSize: 1; suffix: "%"; value: Math.round(Config.barItemOpacity * 100); onMoved: v => Config.s.barItemOpacity = v / 100 }
        }
        Separator {}
        SettingRow {
            label: "Hover opacity"
            settingKey: "barItemHoverOpacity"
            detail: "How solid a container is while the pointer's over it, with everything in it: its icons, text, highlight and dividers"
            ValueSlider { per: 100; from: 0; to: 100; stepSize: 1; suffix: "%"; value: Math.round(Config.barItemHoverOpacity * 100); onMoved: v => Config.s.barItemHoverOpacity = v / 100 }
        }
        Separator {}
        ToggleSetting {
            label: "Panel blur"
            detail: "What's behind the panels that open from the bar is blurred. Off, you see straight through them"
            key: "barPanelBlur"
        }
        Separator {}
        SettingRow {
            label: "Panel opacity"
            settingKey: "barPanelOpacity"
            detail: Config.s.barPanelBlur ? "How solid the panels that open from the bar are: 100% can't be seen through, lower is clearer"
                : "How solid the panels that open from the bar are. With their blur off they stay mostly solid, so they can be read: 0% is as clear as they go"
            ValueSlider { per: 100; from: 0; to: 100; stepSize: 1; suffix: "%"; value: Math.round(Config.s.barPanelOpacity * 100); onMoved: v => Config.s.barPanelOpacity = v / 100 }
        }
    }
}
