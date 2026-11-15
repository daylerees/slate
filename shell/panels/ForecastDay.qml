import QtQuick
import qs

// One day's weather: its name, its weather's icon, then the high and low. The calendar and
// the control centre each size it their own way. `today`: the day it is, as it is now (the
// weather and temperature at the moment), on the active colour so it stands out from the
// days to come
Rectangle {
    readonly property var pop: PanelHost.pop
    id: forecastDay
    property int day: 0              // days from today (an index into pop.forecast)
    property bool today: false
    property real gap: 3             // between its lines
    property real iconSize: 16
    property real tempSize: 11
    readonly property color fg: today ? pop.accentText : pop.text
    readonly property color faint: today ? Qt.rgba(pop.accentText.r, pop.accentText.g, pop.accentText.b, 0.7) : pop.dim
    radius: Config.corner(9)
    Column {
        anchors.centerIn: parent
        spacing: forecastDay.gap
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: forecastDay.today ? "Today" : Qt.formatDate(new Date(pop.forecast.time[forecastDay.day] + "T12:00"), "ddd")
            color: forecastDay.faint; font.pixelSize: 11
        }
        Icon {
            anchors.horizontalCenter: parent.horizontalCenter
            code: pop.weatherInfo(forecastDay.today && pop.weather ? pop.weather.weather_code : pop.forecast.weather_code[forecastDay.day]).icon
            color: forecastDay.fg
            font.pixelSize: forecastDay.iconSize
        }
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: forecastDay.today && pop.weather ? Math.round(pop.weather.temperature_2m) + "°"
                : Math.round(pop.forecast.temperature_2m_max[forecastDay.day]) + "° "
                  + "<font color='" + forecastDay.faint + "'>" + Math.round(pop.forecast.temperature_2m_min[forecastDay.day]) + "°</font>"
            textFormat: Text.StyledText
            color: forecastDay.fg
            font.pixelSize: forecastDay.tempSize
        }
    }
}
