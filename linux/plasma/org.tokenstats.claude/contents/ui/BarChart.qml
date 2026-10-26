import QtQuick
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

Item {
    id: chart
    property var series: []   // [{label, tokens, last}]
    implicitHeight: Kirigami.Units.gridUnit * 6

    readonly property real peak: Math.max(1, Math.max.apply(null, series.map(function (s) { return s.tokens })))
    readonly property int every: series.length <= 8 ? 1 : Math.max(1, Math.floor(series.length / 7))

    Row {
        anchors.fill: parent
        spacing: chart.series.length <= 12 ? Kirigami.Units.smallSpacing : 2
        Repeater {
            model: chart.series
            Item {
                required property var modelData
                required property int index
                width: (chart.width - (chart.series.length - 1) * parent.spacing) / chart.series.length
                height: chart.height
                Rectangle {
                    width: parent.width
                    height: Math.max(modelData.tokens > 0 ? 2 : 0, modelData.tokens / chart.peak * (parent.height - labelItem.height - 4))
                    anchors.bottom: labelItem.top
                    anchors.bottomMargin: 4
                    radius: 3
                    color: modelData.last ? Kirigami.Theme.highlightColor
                                          : Qt.darker(Kirigami.Theme.highlightColor, 1.6)
                }
                PC3.Label {
                    id: labelItem
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: index % chart.every === 0 || modelData.last
                    text: modelData.label
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    font.bold: modelData.last
                    opacity: modelData.last ? 1 : 0.6
                }
            }
        }
    }
}
