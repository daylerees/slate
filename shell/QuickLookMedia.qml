// Quick Look's player for a video or a song (QuickLook.qml): the picture (or, for a song, a
// note on a tile) with a bar along the bottom: play/pause, how far in, and a track to click
// or drag to a place. Loaded by QuickLook.qml through a Loader, never imported: it needs Qt
// Multimedia (qt6-multimedia, optional), and without it only this file fails to load, and
// Quick Look says what to install.
//   source: the file's URL; audio: a song (no picture); autoplay: start once it's ready
//   naturalSize: the video's own size, once known (0×0 until then, and for a song)
//   failed: it can't be played (Quick Look shows the file's details instead)

import QtQuick
import QtMultimedia

Item {
    id: media
    property url source
    property bool audio: false
    property bool autoplay: true
    property color textColor: "white"
    property color dimColor: "gray"
    property color tileColor: "black"
    property string fontFamily: ""
    property string iconFamily: ""
    readonly property size naturalSize: {
        const r = player.metaData.value(MediaMetaData.Resolution);
        return r && r.width > 0 ? Qt.size(r.width, r.height) : Qt.size(0, 0);
    }
    readonly property bool failed: player.error !== MediaPlayer.NoError
    readonly property bool playing: player.playbackState === MediaPlayer.PlayingState
    function toggle() { if (playing) player.pause(); else player.play(); }
    function stop() { player.stop(); }

    MediaPlayer {
        id: player
        source: media.source
        videoOutput: media.audio ? null : out
        audioOutput: AudioOutput {}
        onMediaStatusChanged: if (mediaStatus === MediaPlayer.LoadedMedia && media.autoplay) play()
    }
    Rectangle {
        anchors.fill: parent
        visible: !media.audio
        color: "black"
        radius: Config.corner(10)
    }
    VideoOutput {
        id: out
        visible: !media.audio
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectFit
    }
    // A click on the picture plays or pauses it
    ClickTap { enabled: !media.audio; hand: false; onTapped: media.toggle() }

    // A song: a note on a tile, above the bar
    Rectangle {
        visible: media.audio
        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 8 }
        width: 96; height: 96
        radius: Config.corner(20)
        color: media.tileColor
        Text {
            anchors.centerIn: parent
            text: String.fromCodePoint(0xEAFC)       // music
            color: media.textColor
            font.family: media.iconFamily; font.pixelSize: 44
        }
    }

    function clock(ms) {
        const s = Math.max(0, Math.floor(ms / 1000));
        const m = Math.floor(s / 60), h = Math.floor(m / 60);
        const two = n => (n < 10 ? "0" : "") + n;
        return h > 0 ? h + ":" + two(m % 60) + ":" + two(s % 60) : m + ":" + two(s % 60);
    }

    // The bar: play/pause, the time, and the track
    Rectangle {
        id: bar
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: media.audio ? 0 : 10 }
        height: 40
        radius: Config.corner(10)
        color: media.audio ? "transparent" : Qt.rgba(media.tileColor.r, media.tileColor.g, media.tileColor.b, 0.85)
        Rectangle {
            id: playButton
            anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
            width: 30; height: 30
            radius: Config.corner(15)
            color: playHover.hovered ? Config.hover : "transparent"
            HoverHandler { id: playHover }
            ClickTap { onTapped: media.toggle() }
            Text {
                anchors.centerIn: parent
                text: String.fromCodePoint(media.playing ? 0xF690 : 0xF691)     // pause / play (filled, as the dock's)
                color: media.textColor
                font.family: media.iconFamily; font.pixelSize: 18
            }
        }
        Text {
            id: time
            anchors { left: playButton.right; leftMargin: 8; verticalCenter: parent.verticalCenter }
            text: media.clock(player.position) + " / " + media.clock(player.duration)
            color: media.dimColor
            font.family: media.fontFamily; font.pixelSize: 12; font.features: { "tnum": 1 }
        }
        // The track: click or drag along it to go there
        Item {
            id: track
            anchors { left: time.right; leftMargin: 12; right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
            height: 18
            readonly property real done: player.duration > 0 ? Math.max(0, Math.min(1, player.position / player.duration)) : 0
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width; height: 4
                radius: Config.corner(2)
                color: Qt.rgba(media.textColor.r, media.textColor.g, media.textColor.b, 0.15)
                Rectangle {
                    width: parent.width * track.done; height: parent.height
                    radius: parent.radius
                    color: Config.accent
                }
            }
            MouseArea {
                anchors.fill: parent
                enabled: player.seekable
                function seek(x) { player.position = Math.max(0, Math.min(1, x / width)) * player.duration; }
                onPressed: m => seek(m.x)
                onPositionChanged: m => { if (pressed) seek(m.x); }
            }
        }
    }
}
