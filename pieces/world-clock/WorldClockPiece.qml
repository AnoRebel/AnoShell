import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "zones.js" as Z

// Bundled piece: the time in several places. Offsets come from
// services/Chrono (the Clock panel's world clocks); the zones are this
// piece's setting, or the Clock panel's list when that's left empty.
// Chrono.now ticks once a minute, so the piece has no timer of its own.
// Wide and short: one column per place; otherwise one row each.
Item {
    id: root
    property var ctx
    property var settings: ({})

    readonly property var places: {
        const own = Z.parse(root.settings?.zones ?? "")
        return own.length ? own : Chrono.zones.map(z => ({ zone: z, label: Z.cityOf(z) }))
    }
    onPlacesChanged: Chrono.watchZones(root.places.map(p => p.zone))
    Component.onCompleted: Chrono.watchZones(root.places.map(p => p.zone))

    readonly property real now: Chrono.now
    readonly property int localOffset: -new Date(root.now).getTimezoneOffset()
    readonly property string timeFormat: Config.options?.time?.format ?? "hh:mm"
    readonly property bool columns: root.places.length > 0 && root.width >= root.height * 1.6
        && root.width / root.places.length >= 96

    function info(p) {
        const off = Chrono.offsets[p.zone]
        if (off === undefined) return { known: false, bad: !!Chrono.badZones[p.zone] }
        const phase = Z.phase(Z.hourIn(root.now, off))
        return {
            known: true,
            time: Qt.locale().toString(Chrono.zoneDate(p.zone, root.now), root.timeFormat),
            day: Z.dayOffset(root.now, off, root.localOffset),
            diff: Z.diffText(off, root.localOffset),
            icon: ({ day: "light_mode", twilight: "wb_twilight", night: "bedtime" })[phase],
            iconColor: phase === "day" ? Appearance.colors.colPrimary : phase === "twilight" ? Appearance.colors.colTertiary : Appearance.colors.colSubtext
        }
    }
    function dayText(d) { return d > 0 ? `+${d}` : d < 0 ? `−${-d}` : "" }

    ColumnLayout {
        anchors.centerIn: parent
        visible: root.places.length === 0
        width: parent.width
        spacing: 4
        MaterialSymbol { Layout.alignment: Qt.AlignHCenter; text: "public"; iconSize: 28; color: Appearance.colors.colSubtext }
        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: "No places yet: add zones in this piece's settings (Area/City=Label)"
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
    }

    // ── One column per place ──────────────────────────────────────────
    RowLayout {
        anchors.fill: parent
        visible: root.columns
        spacing: 8
        Repeater {
            model: root.columns ? root.places : []
            ColumnLayout {
                id: col
                required property var modelData
                readonly property var i: root.info(modelData)
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.alignment: Qt.AlignVCenter
                spacing: 2
                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    visible: col.i.known && root.height >= 110
                    text: col.i.icon ?? ""; fill: 1; iconSize: 20; color: col.i.iconColor ?? Appearance.colors.colSubtext
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: col.i.known ? col.i.time : col.i.bad ? "?" : "…"
                    font.pixelSize: Math.max(14, Math.min(root.height * 0.3, root.width / root.places.length / 3.2, 40))
                    font.family: Appearance.font.family.numbers
                    font.weight: Font.Light
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: col.modelData.label + (col.i.known && col.i.day ? ` ${root.dayText(col.i.day)}` : "")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
            }
        }
    }

    // ── One row per place ─────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        visible: !root.columns && root.places.length > 0
        spacing: 0
        Repeater {
            id: rows
            model: root.columns ? [] : root.places
            RowLayout {
                id: row
                required property var modelData
                readonly property var i: root.info(modelData)
                readonly property real rowH: root.height / Math.max(1, rows.count)
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 10
                MaterialSymbol {
                    visible: row.i.known
                    text: row.i.icon ?? ""; fill: 1
                    iconSize: Math.max(16, Math.min(row.rowH * 0.45, 24))
                    color: row.i.iconColor ?? Appearance.colors.colSubtext
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: row.modelData.label
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: row.rowH >= 40
                        elide: Text.ElideRight
                        text: row.i.bad ? `Unknown time zone “${row.modelData.zone}”`
                            : !row.i.known ? row.modelData.zone
                            : row.i.diff + (row.i.day > 0 ? " · tomorrow" : row.i.day < 0 ? " · yesterday" : "")
                        color: row.i.bad ? Appearance.colors.colError : Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                }
                StyledText {
                    visible: row.i.known && row.i.day !== 0 && row.rowH < 40
                    text: root.dayText(row.i.day ?? 0)
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
                StyledText {
                    text: row.i.known ? row.i.time : row.i.bad ? "?" : "…"
                    font.pixelSize: Math.max(14, Math.min(row.rowH * 0.5, 34))
                    font.family: Appearance.font.family.numbers
                    font.weight: Font.Light
                    color: Appearance.colors.colOnLayer1
                }
            }
        }
    }
}
