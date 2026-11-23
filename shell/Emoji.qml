// The emoji list (data/emoji.json: [[emoji, name, keywords, category], ...]), read once for the
// emoji picker and the launcher's ":" search. A big file (140 KB): read the first time either
// asks (want()), not at every start, and parsed once for both (each read it itself before)

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property var list: []
    property bool wanted: false
    property int reads: 0                        // (the tests: how many times it was parsed)
    function want() { wanted = true; }
    FileView {
        path: root.wanted ? Quickshell.shellPath("data/emoji.json") : ""
        blockLoading: true
        onLoaded: { try { root.list = JSON.parse(text()); root.reads++; } catch (e) {} }
    }
}
