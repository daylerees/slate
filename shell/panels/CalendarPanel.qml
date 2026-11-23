import QtQuick
import Quickshell
import qs

// ---- Calendar ----------------------------------------------------------
Column {
    required property var pop
    id: cal
    width: 280
    spacing: 10
    SystemClock { id: calClock; precision: SystemClock.Minutes }
    readonly property date today: Config.clockDate(calClock.date)
    property int monthOffset: 0
    readonly property date shownMonth: new Date(today.getFullYear(), today.getMonth() + monthOffset, 1)
    // Days from last month before the 1st, in a week that starts on the day chosen
    // (Settings → Region → Week starts on)
    readonly property int leadDays: (shownMonth.getDay() - Config.weekStartDay + 7) % 7

    // Weather, when a location is set (Settings → General → Location) and it has loaded
    readonly property bool hasWeather: Config.s.locationName !== "" && pop.weather !== null

    Column {
        id: timeCol
        width: parent.width
        spacing: 2
        Label { text: Qt.formatTime(cal.today, pop.timeFormat); font.pixelSize: Config.text(22) }
        Label { width: parent.width; elide: Text.ElideRight; text: Config.dateText(cal.today, "long"); color: pop.dim; font.pixelSize: Config.text(12) }
    }
    Divider {}
    Item {
        width: parent.width; height: 26
        Label {
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatDate(cal.shownMonth, "MMMM yyyy")
            font.pixelSize: Config.text(14)
        }
        Row {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 4
            Repeater {
                model: [{ code: 0xEA60, d: -1 }, { code: 0xEA61, d: 1 }]
                delegate: RowButton {
                    required property var modelData
                    width: 28; height: 26
                    onClicked: cal.monthOffset += modelData.d
                    Icon { anchors.centerIn: parent; code: parent.modelData.code; font.pixelSize: 15 }
                }
            }
        }
    }
    Grid {
        id: monthGrid
        columns: 7
        readonly property real cell: cal.width / 7
        // Weekday initials, from the week's first day
        Repeater {
            model: { const d = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]; return d.slice(Config.weekStartDay).concat(d.slice(0, Config.weekStartDay)); }
            delegate: Label {
                required property string modelData
                width: monthGrid.cell; height: 22
                horizontalAlignment: Text.AlignHCenter
                text: modelData
                color: pop.dim
                font.pixelSize: Config.text(11)
            }
        }
        Repeater {
            model: 42
            delegate: Item {
                required property int index
                readonly property date day: new Date(cal.shownMonth.getFullYear(), cal.shownMonth.getMonth(), index - cal.leadDays + 1)
                readonly property bool inMonth: day.getMonth() === cal.shownMonth.getMonth()
                readonly property bool isToday: day.toDateString() === cal.today.toDateString()
                width: monthGrid.cell; height: 32
                Rectangle {
                    anchors.centerIn: parent
                    width: 28; height: 28; radius: Config.corner(14)
                    color: parent.isToday ? pop.accent : "transparent"
                }
                Label {
                    anchors.centerIn: parent
                    text: parent.day.getDate()
                    color: parent.isToday ? pop.accentText : parent.inMonth ? pop.text : Config.tint("#4f5866")
                    font.pixelSize: Config.text(12)
                }
            }
        }
    }
    // The weather: today as it is now, standing out, then the next three days; and under
    // them what it's doing, and where
    Divider { visible: cal.hasWeather && pop.forecast !== null }
    Row {
        visible: cal.hasWeather && pop.forecast !== null
        width: parent.width
        spacing: 6
        Repeater {
            model: pop.forecast ? Math.min(4, pop.forecast.time.length) : 0
            delegate: ForecastDay {
                required property int index
                day: index
                today: index === 0
                width: (cal.width - 18) / 4; height: 64
                color: today ? pop.accent : pop.card
            }
        }
    }
    Label {
        visible: cal.hasWeather && pop.forecast !== null
        width: parent.width
        elide: Text.ElideRight
        text: pop.weather ? pop.weatherInfo(pop.weather.weather_code).text + " now · " + Config.s.locationName : ""
        color: pop.dim; font.pixelSize: Config.text(11)
    }
    // Reset to the current month each time the panel opens
    Connections { target: pop; function onCurrentChanged() { if (pop.current === "calendar") cal.monthOffset = 0; } }
}
