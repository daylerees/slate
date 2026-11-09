// The screensaver's Videos style (Settings → Screensaver): the videos in a folder, muted, in a
// shuffled order, each crossfading into the next (a single one loops). Loaded by
// Screensaver.qml through a Loader, never imported: it needs Qt Multimedia (qt6-multimedia,
// optional), and without it only this file fails to load, not the screensaver or Slate.
//   folder: the videos' folder (Config.screensaverVideoFolder)

import QtQuick
import QtMultimedia
import Qt.labs.folderlistmodel

Item {
    id: vids
    property string folder: ""
    readonly property int count: files.count
    // Ready once the folder's been read (empty or not), for the "no videos" note
    readonly property bool listed: files.status === FolderListModel.Ready

    FolderListModel {
        id: files
        folder: vids.folder ? "file://" + vids.folder : ""
        nameFilters: ["*.mp4", "*.webm", "*.mkv", "*.mov", "*.m4v", "*.MP4", "*.WEBM", "*.MKV", "*.MOV", "*.M4V"]
        showDirs: false
        onStatusChanged: if (status === FolderListModel.Ready) vids.begin()
    }

    // A shuffled order, so the same one doesn't always come first
    property var order: []
    property int at: 0
    function shuffled() {
        const l = [];
        for (let i = 0; i < files.count; i++) l.push(files.get(i, "filePath"));
        for (let i = l.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [l[i], l[j]] = [l[j], l[i]]; }
        return l;
    }
    function nextPath() {
        if (!order.length) return "";
        if (at >= order.length) { order = shuffled(); at = 0; }
        return order[at++];
    }

    // Two players: one shows while the other loads the next video, then they crossfade
    property bool onA: true
    function begin() {
        order = shuffled(); at = 0;
        if (!order.length) return;
        onA = true;
        a.player.source = "file://" + nextPath();
        a.player.play();
        if (order.length > 1) b.player.source = "file://" + nextPath();    // ready and waiting
    }
    // The one showing has finished: the waiting one takes over, then loads the one after
    function advance() {
        if (order.length <= 1) return;           // a single video loops instead
        const showing = onA ? a : b, waiting = onA ? b : a;
        waiting.player.play();
        onA = !onA;
        showing.player.stop();
        showing.player.source = "file://" + nextPath();
    }

    component Clip: Item {
        id: clip
        property alias player: mp
        anchors.fill: parent
        MediaPlayer {
            id: mp
            videoOutput: out
            loops: vids.order.length <= 1 ? MediaPlayer.Infinite : 1
            // Always silent, whatever the file has: leaving the audio output out didn't keep every
            // clip quiet, so it's set, muted, at nothing
            audioOutput: AudioOutput { muted: true; volume: 0 }
            onMediaStatusChanged: if (mediaStatus === MediaPlayer.EndOfMedia) vids.advance()
            onErrorOccurred: (err, text) => { console.warn("Screensaver video:", text, source); vids.advance(); }
        }
        VideoOutput {
            id: out
            anchors.fill: parent
            fillMode: VideoOutput.PreserveAspectCrop
        }
    }
    Clip { id: a; opacity: vids.onA ? 1 : 0; Behavior on opacity { NumberAnimation { duration: Config.ms(1500); easing.type: Easing.InOutQuad } } }
    Clip { id: b; opacity: vids.onA ? 0 : 1; Behavior on opacity { NumberAnimation { duration: Config.ms(1500); easing.type: Easing.InOutQuad } } }
    // A little darker, as the wallpaper styles are, so the clock reads on any scene
    Rectangle { anchors.fill: parent; color: "black"; opacity: 0.18 }
}
