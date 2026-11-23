// The package that gives an optional library, by its name on this distro (scripts/packages.py),
// for messages saying what to install. Made the first time a message asks, and asks once.
//   Packages.named("qtmultimedia")   " (the qt6-multimedia package)", or "" where it isn't known
//   (keys: qtmultimedia, poppler)

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property var names: ({})
    function named(key) { return names[key] ? " (the " + names[key] + " package)" : ""; }
    Process {
        running: true
        command: ["python3", Quickshell.shellPath("scripts/packages.py")]
        stdout: StdioCollector { onStreamFinished: { try { root.names = JSON.parse(text); } catch (e) {} } }
    }
}
