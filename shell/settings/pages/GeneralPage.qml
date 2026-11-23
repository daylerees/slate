import QtQuick
import Quickshell
import Quickshell.Io
import "../.."
import ".."

Column {
    readonly property var win: SettingsHost.win
    id: generalCol
    spacing: 4
    PageTitle { text: "General" }
    // ---- Account: your picture (AccountsService) and name
    property string fullName: Quickshell.env("USER")
    Process {
        running: true
        command: ["getent", "passwd", Quickshell.env("USER")]
        stdout: StdioCollector { onStreamFinished: { const n = (text.split(":")[4] || "").split(",")[0]; if (n) generalCol.fullName = n; } }
    }
    GroupLabel { text: "Account" }
    Group {
        Item {
            width: parent.width; height: 88
            // Picture: hover greys it with a pencil; click to choose another
            Item {
                id: acctPic
                x: 16; width: 60; height: 60
                anchors.verticalCenter: parent.verticalCenter
                RoundImage {
                    id: acctImg
                    anchors.fill: parent; radius: Config.corner(width / 2)
                    fallback: true      // no account picture: the themed person icon
                    source: Config.avatarUrl
                    saturation: acctHover.hovered || Config.avatarBusy ? -1 : 0
                    brightness: acctHover.hovered || Config.avatarBusy ? -0.45 : 0
                    Behavior on saturation { NumberAnimation { duration: Config.ms(150) } }
                    Behavior on brightness { NumberAnimation { duration: Config.ms(150) } }
                }
                Text {
                    anchors.centerIn: parent
                    text: win.glyph(0xEB04)
                    color: "white"
                    font.family: win.bar.iconFont; font.pixelSize: 20
                    opacity: acctHover.hovered && !Config.avatarBusy ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Config.ms(150) } }
                }
                HoverHandler { id: acctHover }
                ClickTap { onTapped: win.avatarPicking = true }
            }
            Column {
                anchors { left: acctPic.right; leftMargin: 14; right: acctButtons.left; rightMargin: 16; verticalCenter: parent.verticalCenter }
                spacing: 2
                Text { width: parent.width; textFormat: Text.PlainText; text: generalCol.fullName; color: win.text; font.family: win.font; font.pixelSize: Config.text(15); font.weight: Font.Medium; elide: Text.ElideRight }
                Text {
                    width: Math.min(parent.width, win.detailMeasure)
                    text: Config.avatarBusy ? "Changing your picture…"
                        : Config.avatarError !== "" ? Config.avatarError
                        : "Your picture on the control center, lock screen and login screen"
                    color: Config.avatarError !== "" && !Config.avatarBusy ? win.danger : win.dim
                    font.family: win.font; font.pixelSize: Config.text(12)
                    wrapMode: Text.Wrap
                }
            }
            Row {
                id: acctButtons
                anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                Button { icon: 0xEB0A; label: "Change picture"; onClicked: win.avatarPicking = true }
            }
        }
    }
    GroupLabel { text: "Clipboard" }
    Group {
        SettingRow {
            label: "Clipboard history"
            settingKey: "clipboardHistory"
            detail: Config.s.clipboardHistory
                ? "Keep the last 100 things you copy, text and images (Super+V, or the bar's clipboard). Passwords copied from password managers are never kept"
                : "Off: nothing you copy is kept. Anything kept before stays until you clear it"
            SettingToggle { checked: Config.s.clipboardHistory; onToggled: v => Config.s.clipboardHistory = v }
        }
        Separator {}
        SettingRow {
            label: "Clear clipboard history"
            detail: Config.clipCount === 0 ? "It's empty"
                : Config.clipCount === 1 ? "Forget the 1 item it holds" : "Forget the " + Config.clipCount + " items it holds"
            Button {
                icon: 0xEB41; label: "Clear"; destructive: true
                enabled: Config.clipCount > 0
                opacity: enabled ? 1 : 0.5
                onClicked: Quickshell.execDetached(["python3", Quickshell.shellPath("scripts/clipstore.py"), "clear"])
            }
        }
    }
    GroupLabel { text: "Location" }
    Group {
        // In front of the groups below while its results are showing over them
        z: locPop.visible ? 5 : 0
        // Search a place by name as you type (Open-Meteo's free geocoding), then pick a result
        Column {
            id: loc
            width: parent.width
            property var results: []
            property string status: ""
            property int pick: 0
            onResultsChanged: pick = 0
            function search(q) {
                if (q.trim().length < 2) { results = []; status = ""; return; }
                status = "Searching…";
                geo.running = false;         // a newer search replaces one still going
                geo.command = ["curl", "-sf", "--max-time", "10", "https://geocoding-api.open-meteo.com/v1/search?count=6&format=json&name=" + encodeURIComponent(q.trim())];
                geo.running = true;
            }
            function choose(r) {
                if (!r) return;
                Config.s.latitude = r.latitude;
                Config.s.longitude = r.longitude;
                Config.s.locationName = r.name;
                results = []; status = ""; placeInput.text = ""; placeInput.focus = false;
            }
            // Searches a moment after you stop typing
            Timer { id: geoSoon; interval: 350; onTriggered: loc.search(placeInput.text) }
            // A search stopped for a newer one ends with nothing (and a failure code): that
            // says nothing about the newer one, so it's ignored
            Process {
                id: geo
                stdout: StdioCollector {
                    onStreamFinished: {
                        if (text.trim() === "") return;
                        try { loc.results = JSON.parse(text).results || []; } catch (e) { loc.results = []; }
                        loc.status = loc.results.length ? "" : "No places found";
                    }
                }
                onExited: code => { if (code !== 0 && !geo.running && !geoSoon.running) loc.status = "Slate couldn't search just now. Are you online?"; }
            }
            SettingRow {
                label: "Location"
                detail: Config.s.locationName !== "" ? "Weather and night light's sunset/sunrise use " + Config.s.locationName
                    : "Not set yet, so the weather is hidden. Search for your town or city to see it"
                FieldFrame {
                    id: placeField
                    field: placeInput
                    width: 240; height: 30
                    TextInput {
                        objectName: "locationSearch"
                        activeFocusOnTab: true          // Tab / Shift+Tab: the next or the box before
                        id: placeInput
                        anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                        verticalAlignment: TextInput.AlignVCenter
                        color: win.text; selectionColor: win.accent
                        font.family: win.font; font.pixelSize: Config.text(12)
                        onTextChanged: { if (text.trim().length >= 2) geoSoon.restart(); else { geoSoon.stop(); geo.running = false; loc.results = []; loc.status = ""; } }
                        Keys.onPressed: e => {
                            if (e.key === Qt.Key_Down) { loc.pick = Math.min(loc.results.length - 1, loc.pick + 1); e.accepted = true; }
                            else if (e.key === Qt.Key_Up) { loc.pick = Math.max(0, loc.pick - 1); e.accepted = true; }
                            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                                if (geoSoon.running) { geoSoon.stop(); loc.search(text); }      // Enter before the pause: search now
                                else loc.choose(loc.results[loc.pick]);
                                e.accepted = true;
                            }
                            else if (e.key === Qt.Key_Escape) { text = ""; focus = false; e.accepted = true; }
                        }
                    }
                    // Empty field: the place you've set (with a pin), or how to search
                    Row {
                        visible: placeInput.text === ""
                        anchors { left: parent.left; leftMargin: 10; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        spacing: 6
                        readonly property bool showsPlace: Config.s.locationName !== "" && !placeInput.activeFocus
                        Text {
                            visible: parent.showsPlace
                            anchors.verticalCenter: parent.verticalCenter
                            text: win.glyph(0xEAE8)                  // map pin
                            color: win.accent; font.family: win.bar.iconFont; font.pixelSize: 14
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - (parent.showsPlace ? 20 : 0)
                            textFormat: Text.PlainText        // never markup: a place's name, from the weather service
                            text: parent.showsPlace ? Config.s.locationName
                                : Config.s.locationName !== "" ? "Search for a new place" : "Search for your town or city"
                            color: parent.showsPlace ? win.text : win.dim
                            font.family: win.font; font.pixelSize: Config.text(12); font.weight: parent.showsPlace ? Font.Medium : Font.Normal
                            elide: Text.ElideRight
                        }
                    }

                    // Results, dropping down from the field over the page
                    Rectangle {
                        id: locPop
                        visible: placeInput.activeFocus && placeInput.text.trim().length >= 2 && (loc.results.length > 0 || loc.status !== "")
                        anchors { top: parent.bottom; topMargin: 6; right: parent.right }
                        width: 300
                        height: locPopCol.implicitHeight + 8
                        radius: Config.corner(12)
                        // Solid, so the page under it doesn't show through
                        color: win.popupFill
                        border.width: 1; border.color: win.outline
                        Shadow {}       // Slate's one shadow, as under every other menu
                        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: w => w.accepted = true }   // the page under it stays put
                        Column {
                            id: locPopCol
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 4 }
                            // Searching…, No places found, or couldn't search
                            Text {
                                visible: loc.results.length === 0 && loc.status !== ""
                                width: parent.width
                                topPadding: 10; bottomPadding: 10; leftPadding: 12
                                text: loc.status
                                color: win.dim; font.family: win.font; font.pixelSize: Config.text(12)
                            }
                            Repeater {
                                model: loc.results
                                delegate: Rectangle {
                                    id: placeRow
                                    required property var modelData
                                    required property int index
                                    readonly property bool chosen: index === loc.pick
                                    width: parent.width; height: placeCol.implicitHeight + 14
                                    radius: Config.corner(9)
                                    color: chosen ? win.accent : placeHover.hovered ? Config.hover : "transparent"
                                    Column {
                                        id: placeCol
                                        anchors { left: parent.left; leftMargin: 12; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                        spacing: 1
                                        Text {
                                            width: parent.width
                                            textFormat: Text.PlainText        // never markup: a place's name, from the weather service
                                            text: placeRow.modelData.name
                                            color: placeRow.chosen ? win.accentText : win.text; font.family: win.font; font.pixelSize: Config.text(13); font.weight: Font.Medium
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            width: parent.width
                                            visible: text !== ""
                                            textFormat: Text.PlainText        // never markup
                                            text: [placeRow.modelData.admin1, placeRow.modelData.country].filter(x => x).join(", ")
                                            color: placeRow.chosen ? Qt.rgba(win.accentText.r, win.accentText.g, win.accentText.b, 0.72) : win.dim; font.family: win.font; font.pixelSize: Config.text(11)
                                            elide: Text.ElideRight
                                        }
                                    }
                                    HoverHandler { id: placeHover }
                                    ClickArea { anchors.fill: parent; onClicked: loc.choose(placeRow.modelData) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    GroupLabel { text: "Night light" }
    Group {
        ToggleSetting {
            label: "Night light"
            detail: "Warmer screen colors that are kinder to your eyes at night. Also in the control center"
            key: "nightLight"
        }
        Separator {}
        SettingRow {
            label: "Warmth"
            settingKey: "nightLightTemperature"
            detail: "Color temperature: lower is warmer"
            ValueSlider { from: 2500; to: 6000; stepSize: 100; suffix: " K"; value: Config.s.nightLightTemperature; onMoved: v => Config.s.nightLightTemperature = v }
        }
        Separator {}
        DropdownSetting {
            label: "Schedule"
            settingKey: "nightLightSchedule"
            detail: {
                if (Config.s.nightLightSchedule === "sun") {
                    if (Config.s.locationName === "") return "Set your location above first";
                    const st = Config.sunTimes(new Date());
                    return "Today: on at " + Config.clockText(st.set) + ", off at " + Config.clockText(st.rise) + ". Switching by hand lasts until the next change";
                }
                if (Config.s.nightLightSchedule === "custom") return "Switching by hand lasts until the next change";
                return "Only when you switch it";
            }
            value: Config.s.nightLightSchedule
            options: [{ value: "manual", label: "Manual" }, { value: "sun", label: "Sunset to sunrise" }, { value: "custom", label: "Custom times" }]
            onPicked: v => Config.s.nightLightSchedule = v
        }
        Separator { visible: Config.s.nightLightSchedule === "custom" }
        ChoiceSetting {
            visible: Config.s.nightLightSchedule === "custom"
            label: "Turn on at"
            settingKey: "nightLightFrom"
            value: Config.s.nightLightFrom
            options: win.halfHours(16, 23.5)
            onPicked: v => Config.s.nightLightFrom = v
        }
        Separator { visible: Config.s.nightLightSchedule === "custom" }
        ChoiceSetting {
            visible: Config.s.nightLightSchedule === "custom"
            label: "Turn off at"
            settingKey: "nightLightTo"
            value: Config.s.nightLightTo
            options: win.halfHours(4, 10.5)
            onPicked: v => Config.s.nightLightTo = v
        }
    }
}
