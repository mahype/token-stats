import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import "../code/util.js" as U

ColumnLayout {
    id: view
    property var info: null
    property var updated: null
    signal refreshRequested()

    property string page: "limits"
    property int rangeDays: 7
    property int now: 0   // bumped by a timer so "resets in" and pace texts stay current

    spacing: 0
    Layout.preferredWidth: Kirigami.Units.gridUnit * 24
    Layout.preferredHeight: Kirigami.Units.gridUnit * 34

    function tint(pct) {
        return pct >= 100 ? Kirigami.Theme.negativeTextColor
             : pct >= 80 ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.positiveTextColor
    }

    // header: title and page switch
    RowLayout {
        Layout.fillWidth: true
        Layout.margins: Kirigami.Units.largeSpacing
        Kirigami.Heading { text: "Token Stats"; level: 2; Layout.fillWidth: true }
        RowLayout {
            spacing: 0
            PC3.Button { text: "Limits"; checkable: true; checked: view.page === "limits"; autoExclusive: true; onClicked: view.page = "limits" }
            PC3.Button { text: "Usage"; checkable: true; checked: view.page === "usage"; autoExclusive: true; onClicked: view.page = "usage" }
        }
    }
    PC3.TabBar {
        Layout.fillWidth: true
        PC3.TabButton { text: "● Claude"; checked: true }
    }
    Kirigami.Separator { Layout.fillWidth: true }

    PC3.ScrollView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        contentWidth: availableWidth
        ColumnLayout {
            width: parent.width
            spacing: Kirigami.Units.largeSpacing
            Loader {
                Layout.fillWidth: true
                Layout.margins: Kirigami.Units.largeSpacing
                sourceComponent: !view.info ? loading : view.page === "limits" ? limitsPage : usagePage
            }
        }
    }

    // footer
    Kirigami.Separator { Layout.fillWidth: true }
    RowLayout {
        Layout.fillWidth: true
        Layout.margins: Kirigami.Units.largeSpacing
        PC3.Label {
            Layout.fillWidth: true
            elide: Text.ElideRight
            opacity: 0.7
            text: (view.updated ? "updated " + Qt.formatTime(view.updated, "hh:mm") : "loading…")
                  + (view.info && view.info.error ? "  ·  ⚠ " + view.info.error : "")
        }
        PC3.ToolButton { icon.name: "view-refresh"; onClicked: view.refreshRequested() }
    }

    Component { id: loading; PC3.Label { text: "Loading…"; opacity: 0.7 } }

    Component {
        id: limitsPage
        ColumnLayout {
            spacing: Kirigami.Units.largeSpacing * 1.5
            readonly property real worst: Math.max(0, Math.max.apply(null, view.info.limits.map(function (l) { return l.pct })))
            RowLayout {
                Layout.fillWidth: true
                Kirigami.Heading { text: "Claude"; level: 3 }
                PC3.Label { text: view.info.plan; opacity: 0.7; font.family: "monospace" }
                Item { Layout.fillWidth: true }
                PC3.Label {
                    text: Math.round(worst) + " %"
                    font.bold: true
                    color: view.tint(worst)
                    leftPadding: 10; rightPadding: 10
                    background: Rectangle { radius: height / 2; color: "transparent"; border.width: 1; border.color: view.tint(worst) }
                }
            }
            Repeater {
                model: view.info.limits
                ColumnLayout {
                    id: row
                    required property var modelData
                    readonly property var st: { view.now; return U.limitState(modelData) }
                    Layout.fillWidth: true
                    spacing: 4
                    RowLayout {
                        Layout.fillWidth: true
                        Kirigami.Heading { text: row.modelData.title; level: 4 }
                        PC3.Label { text: row.modelData.sub; opacity: 0.7 }
                        Item { Layout.fillWidth: true }
                        Kirigami.Heading { text: Math.round(row.modelData.pct) + " %"; level: 4; color: view.tint(row.modelData.pct) }
                    }
                    Meter {
                        Layout.fillWidth: true
                        pct: row.modelData.pct
                        elapsed: row.st.elapsed
                        tint: view.tint(row.modelData.pct)
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        PC3.Label {
                            opacity: 0.7
                            text: {
                                if (!row.modelData.reset) return ""
                                var d = new Date(row.modelData.reset)
                                var soon = (d - Date.now()) < 86400000
                                return "Reset " + (soon ? Qt.formatTime(d, "hh:mm") : Qt.formatDateTime(d, "ddd hh:mm"))
                            }
                        }
                        Item { Layout.fillWidth: true }
                        PC3.Label {
                            visible: row.st.elapsed >= 0
                            color: view.tint(row.modelData.pct)
                            text: Math.abs(row.st.gap) < row.modelData.window * 0.02 ? "on pace"
                                  : row.st.gap > 0 ? U.duration(row.st.gap) + " ahead"
                                                   : U.duration(-row.st.gap) + " unused"
                        }
                    }
                }
            }
            Kirigami.Separator { Layout.fillWidth: true; visible: view.info.extra !== null }
            PC3.Label {
                visible: view.info.extra !== null
                text: view.info.extra || ""
                font.family: "monospace"
                padding: 8
                background: Rectangle { radius: 8; color: Kirigami.Theme.alternateBackgroundColor }
            }
        }
    }

    Component {
        id: usagePage
        ColumnLayout {
            id: usage
            spacing: Kirigami.Units.largeSpacing
            readonly property var agg: U.aggregate(view.info.usage, view.rangeDays, Qt.locale())
            RowLayout {
                Kirigami.Heading { text: "Claude"; level: 3 }
                PC3.Label { text: view.info.plan; opacity: 0.7; font.family: "monospace" }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 0
                Repeater {
                    model: [{ t: "Today", n: 1 }, { t: "7 days", n: 7 }, { t: "30 days", n: 30 },
                            { t: "This month", n: new Date().getDate() }]
                    PC3.ToolButton {
                        required property var modelData
                        text: modelData.t
                        checkable: true
                        autoExclusive: true
                        checked: view.rangeDays === modelData.n
                        onClicked: view.rangeDays = modelData.n
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing
                Repeater {
                    model: [{ t: "TOKENS", v: U.fmtTokens(usage.agg.total), s: U.fmtTokens(usage.agg.cache) + " of which cache" },
                            { t: "API VALUE", v: U.fmtMoney(usage.agg.value), s: "at list prices" }]
                    Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        implicitHeight: card.implicitHeight + 24
                        radius: 12
                        color: Kirigami.Theme.alternateBackgroundColor
                        ColumnLayout {
                            id: card
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 2
                            PC3.Label { text: modelData.t; opacity: 0.7; font.pointSize: Kirigami.Theme.smallFont.pointSize }
                            Kirigami.Heading { text: modelData.v; level: 1 }
                            PC3.Label { text: modelData.s; opacity: 0.7; font.pointSize: Kirigami.Theme.smallFont.pointSize }
                        }
                    }
                }
            }
            BarChart { Layout.fillWidth: true; visible: usage.agg.series.length > 1; series: usage.agg.series }
            Repeater {
                model: usage.agg.models
                ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 0
                    RowLayout {
                        Layout.fillWidth: true
                        Kirigami.Heading { text: modelData.model; level: 4; Layout.fillWidth: true }
                        Kirigami.Heading { text: modelData.priced ? U.fmtMoney(modelData.value) : "n/a"; level: 4 }
                    }
                    PC3.Label {
                        opacity: 0.7
                        text: U.fmtTokens(modelData.in) + " in · " + U.fmtTokens(modelData.out) + " out · " + U.fmtTokens(modelData.cache) + " cache"
                    }
                    Kirigami.Separator { Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.smallSpacing }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Kirigami.Heading {
                    text: (view.rangeDays === 1 ? "Today" : view.rangeDays + " days") + " · " + U.fmtTokens(usage.agg.total) + " tokens"
                    level: 4
                    Layout.fillWidth: true
                }
                Kirigami.Heading { text: U.fmtMoney(usage.agg.value); level: 4 }
            }
            PC3.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                opacity: 0.7
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                text: "Local token counts from the session logs × list price"
                      + (view.info.priceDate ? " (as of " + view.info.priceDate + ")" : "")
                      + ", incl. cache rates. No billing data, only what the same usage would cost via the API."
                      + (usage.agg.unpriced ? " Some models are missing from the price table." : "")
            }
        }
    }

    Timer { interval: 30000; running: true; repeat: true; onTriggered: view.now++ }
}
