import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import ".."

// The shadow under a pop-up (dropdown menus, the place search's results): use it as
// layer.effect: PopupShadow {}
MultiEffect {
    shadowEnabled: Config.shadowsOn
    shadowColor: Config.shadowColour
    shadowOpacity: 0.4
    shadowBlur: Config.shadowEffectBlur
    shadowHorizontalOffset: Config.shadowDX
    shadowVerticalOffset: Config.shadowDY
    blurMax: 32
}
