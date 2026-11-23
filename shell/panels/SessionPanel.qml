import QtQuick
import Quickshell
import qs

// ---- Session -----------------------------------------------------------
Column {
    required property var pop
    id: sessionView
    width: 220
    spacing: 6
    Repeater {
        // (only what this computer can do: without systemd or elogind, nothing can
        // suspend, restart or shut down for Slate. Config.system)
        model: [
            { id: "lock", label: "Lock", code: 0xEAE2, confirm: false },
            { id: "lock_and_suspend", label: "Suspend", code: 0xF228, confirm: false },
            { id: "logout", label: "Log out", code: 0xEBA8, confirm: true },
            { id: "reboot", label: "Restart", code: 0xEB13, confirm: true },
            { id: "shutdown", label: "Shut down", code: 0xEB0D, confirm: true }
        ].filter(a => a.id === "lock_and_suspend" ? Config.canSuspend : (a.id === "reboot" || a.id === "shutdown") ? Config.canPowerOff : true)
        delegate: RowButton {
            required property var modelData
            width: sessionView.width
            height: 40
            danger: modelData.id === "shutdown"
            onClicked: {
                pop.close();
                if (modelData.confirm && pop.powerConfirm) pop.powerConfirm.ask(modelData.id);
                else if (modelData.id === "lock") pop.slate(["lock", "lock"]);
                else if (modelData.id === "lock_and_suspend")   // lock first, then sleep
                    Quickshell.execDetached(["sh", "-c", "\"$0\" ipc call lock lock; sleep 0.6; \"$1\" suspend", Quickshell.shellPath("bin/slate"), Quickshell.shellPath("bin/slate-init")]);
                else Config.sessionAction(modelData.id);
            }
            Icon {
                id: sessionIcon
                code: parent.modelData.code
                color: parent.modelData.id === "shutdown" ? pop.danger : pop.text
                anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
            }
            Label {
                anchors { left: sessionIcon.right; leftMargin: 12; verticalCenter: parent.verticalCenter }
                text: parent.modelData.label
            }
        }
    }
}
