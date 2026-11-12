// Tints an app icon with the theme's accent colour (Settings → Icons → Tint app icons).
// Use on an image:  layer.enabled: Config.iconTint > 0;  layer.effect: IconTint {}

import QtQuick
import QtQuick.Effects

MultiEffect {
    colorization: Config.iconTint
    colorizationColor: Config.accent
}
