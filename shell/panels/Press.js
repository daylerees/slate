// The panels' controls take the keyboard (CONVENTIONS: every control works by keyboard):
// Enter, Return or Space presses one (and Delete too, for something that can be dismissed).
//   import "Press.js" as Press
//   Keys.onPressed: e => Press.keys(e, () => save())            Delete as well: Press.keys(e, run, true)
.pragma library

function keys(e, run, withDelete) {
    const k = e.key;
    if (k !== Qt.Key_Return && k !== Qt.Key_Enter && k !== Qt.Key_Space && !(withDelete && k === Qt.Key_Delete)) return;
    run();
    e.accepted = true;
}
