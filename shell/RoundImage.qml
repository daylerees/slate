// Image with rounded corners (used by the control centre)
import QtQuick
import QtQuick.Effects

Item {
    id: ri
    property url source
    property real radius: 12
    property real saturation: 0          // -1 = greyscale
    property real brightness: 0          // below 0 dims it
    readonly property int status: img.status
    Image {
        id: img
        source: ri.source
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        visible: false
        smooth: true
        mipmap: true
    }
    Item {
        id: imgMask
        anchors.fill: parent
        visible: false
        layer.enabled: true
        Rectangle { anchors.fill: parent; radius: ri.radius }
    }
    MultiEffect {
        anchors.fill: parent; source: img; maskEnabled: true; maskSource: imgMask
        saturation: ri.saturation; brightness: ri.brightness
    }
}
