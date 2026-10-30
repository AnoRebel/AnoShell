import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

// Bundled piece: day, week, month and year as filling bars. Steps each
// minute, only while ctx.live (the idea is iNiR's day-progress widget).
Item {
    id: root
    property var ctx
    property var settings: ({})
    readonly property bool monday: root.settings?.weekStartsMonday ?? true

    property date now: new Date()
    Timer {
        running: root.ctx?.live ?? false
        repeat: true
        triggeredOnStart: true
        interval: 60000 - (root.now.getSeconds() * 1000 + root.now.getMilliseconds())
        onTriggered: root.now = new Date()
    }

    function frac(from, to) { return Math.max(0, Math.min(1, (root.now - from) / (to - from))) }
    readonly property var rows: {
        const d = root.now, y = d.getFullYear(), m = d.getMonth()
        const day0 = new Date(y, m, d.getDate())
        const back = root.monday ? (d.getDay() + 6) % 7 : d.getDay()
        const week0 = new Date(y, m, d.getDate() - back)
        return [
            { label: "Day", f: root.frac(day0, new Date(y, m, d.getDate() + 1)) },
            { label: "Week", f: root.frac(week0, new Date(y, m, d.getDate() - back + 7)) },
            { label: "Month", f: root.frac(new Date(y, m, 1), new Date(y, m + 1, 1)) },
            { label: "Year", f: root.frac(new Date(y, 0, 1), new Date(y + 1, 0, 1)) }
        ]
    }

    ColumnLayout {
        anchors { fill: parent; margins: 12 }
        spacing: 6
        Repeater {
            model: root.rows
            ColumnLayout {
                required property var modelData
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 2
                RowLayout {
                    Layout.fillWidth: true
                    StyledText { text: modelData.label; font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colSubtext; Layout.fillWidth: true }
                    StyledText { text: `${Math.floor(modelData.f * 100)}%`; font.pixelSize: Appearance.font.pixelSize.smaller; font.family: Appearance.font.family.numbers }
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 6
                    radius: 3
                    color: Appearance.colors.colLayer2
                    Rectangle {
                        width: parent.width * modelData.f
                        height: parent.height
                        radius: 3
                        color: Appearance.colors.colPrimary
                    }
                }
            }
        }
    }
}
