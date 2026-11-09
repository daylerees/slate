// A live picture from a webcam (Settings → Webcam). In a file of its own, loaded only while
// the preview is shown: it needs Qt Multimedia, which is optional, so without it just the
// preview is missing rather than Settings failing to load.

import QtQuick
import QtMultimedia

Item {
    id: root
    property string device: ""          // /dev/videoN
    property bool active: true
    readonly property bool showing: camera.active && camera.error === Camera.NoError
    readonly property string problem: camera.error !== Camera.NoError ? camera.errorString : ""

    MediaDevices { id: media }
    CaptureSession {
        camera: Camera {
            id: camera
            cameraDevice: media.videoInputs.find(d => String(d.id) === root.device) ?? media.defaultVideoInput
            active: root.active
        }
        videoOutput: out
    }
    VideoOutput {
        id: out
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectCrop
        // Mirrored, as you'd see yourself in a mirror (what apps show you of yourself)
        transform: Scale { origin.x: out.width / 2; xScale: -1 }
    }
}
