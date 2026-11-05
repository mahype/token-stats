import QtQuick
import org.kde.kirigami as Kirigami

// Progress bar with pace mark; the hatched area is the gap between used share and elapsed share.
Item {
    id: meter
    property real pct: 0
    property real elapsed: -1
    property color tint: Kirigami.Theme.positiveTextColor
    implicitHeight: Kirigami.Units.gridUnit * 0.8

    readonly property real usedW: Math.min(pct, 100) / 100 * width
    readonly property real paceW: Math.min(Math.max(elapsed, 0), 1) * width

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
    }
    Canvas {
        visible: meter.elapsed >= 0
        x: Math.min(meter.usedW, meter.paceW)
        width: Math.abs(meter.usedW - meter.paceW)
        height: parent.height
        onWidthChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            ctx.strokeStyle = Qt.rgba(meter.tint.r, meter.tint.g, meter.tint.b, 0.55)
            ctx.lineWidth = 2
            ctx.beginPath()
            for (var x = -height; x < width + height; x += 5) { ctx.moveTo(x, height); ctx.lineTo(x + height, 0) }
            ctx.stroke()
        }
    }
    Rectangle {
        width: Math.max(meter.usedW, height)
        height: parent.height
        radius: height / 2
        color: meter.tint
    }
    Rectangle {
        visible: meter.elapsed >= 0
        x: meter.paceW - 1
        width: 2
        height: parent.height
        color: Qt.rgba(1, 1, 1, 0.7)
    }
}
