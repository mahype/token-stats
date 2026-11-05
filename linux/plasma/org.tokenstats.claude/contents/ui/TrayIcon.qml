import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

// Ring in the state colour with the percentage inside.
Item {
    id: icon
    property real pct: 0
    signal clicked()

    Layout.minimumWidth: Kirigami.Units.iconSizes.small
    Layout.minimumHeight: Kirigami.Units.iconSizes.small

    readonly property color tint: pct >= 100 ? Kirigami.Theme.negativeTextColor
                                  : pct >= 80 ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.positiveTextColor
    onPctChanged: ring.requestPaint()
    onTintChanged: ring.requestPaint()

    Canvas {
        id: ring
        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height)
        height: width
        onWidthChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            var lw = Math.max(2, width * 0.12), r = width / 2 - lw / 2 - 0.5
            ctx.lineWidth = lw
            ctx.strokeStyle = Qt.rgba(0.6, 0.6, 0.6, 0.45)
            ctx.beginPath(); ctx.arc(width / 2, height / 2, r, 0, 2 * Math.PI); ctx.stroke()
            ctx.strokeStyle = icon.tint
            ctx.beginPath()
            ctx.arc(width / 2, height / 2, r, -Math.PI / 2, -Math.PI / 2 + Math.min(icon.pct, 100) / 100 * 2 * Math.PI)
            ctx.stroke()
        }
    }
    PC3.Label {
        anchors.centerIn: parent
        text: Math.round(icon.pct)
        font.bold: true
        font.pixelSize: ring.width * (icon.pct >= 100 ? 0.3 : 0.38)
    }
    MouseArea {
        anchors.fill: parent
        onClicked: icon.clicked()
    }
}
