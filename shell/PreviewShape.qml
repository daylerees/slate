// A live window preview's look, as a layer effect: rounded corners, and an inactive window's
// colours brought back up (Hyprland dims windows without focus, and live pictures of them come
// out dimmed too: see Config.undimGain). For the switcher, overview, dock and Spaces previews:
//   layer.enabled: true
//   layer.effect: PreviewShape { radius: 8; gain: Config.undimGain(window.activated, appId) }

import QtQuick

ShaderEffect {
    property real gain: 1          // 1: as it is
    property real radius: 0        // corner radius (the item's pixels)
    readonly property size size: Qt.size(width, height)
    fragmentShader: Qt.resolvedUrl("shaders/preview.frag.qsb")
}
