import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5Support

PlasmoidItem {
    id: root

    property var info: null
    property var updated: null
    readonly property real worst: info && info.limits.length
        ? Math.max.apply(null, info.limits.map(function (l) { return l.pct })) : 0
    readonly property string command: "python3 " + Qt.resolvedUrl("../code/backend.py").toString().replace("file://", "")

    Plasmoid.status: PlasmaCore.Types.ActiveStatus
    toolTipMainText: "Token Stats"
    toolTipSubText: info ? "Claude " + Math.round(worst) + " %" : "loading…"

    compactRepresentation: TrayIcon {
        pct: root.worst
        onClicked: root.expanded = !root.expanded
    }
    fullRepresentation: FullView {
        info: root.info
        updated: root.updated
        onRefreshRequested: root.refresh()
    }

    function refresh() {
        source.disconnectSource(command)
        source.connectSource(command)
    }

    P5Support.DataSource {
        id: source
        engine: "executable"
        connectedSources: [root.command]
        interval: 300000   // limits endpoint is rate limited, 5 minutes like the macOS app
        onNewData: function (sourceName, data) {
            if (!data["stdout"]) return
            try {
                root.info = JSON.parse(data["stdout"])
                root.updated = new Date()
            } catch (e) {
                console.warn("token stats: bad backend output", e)
            }
        }
    }
}
