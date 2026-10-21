import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

// Screen time (screenTime.enable): today's total, the top apps with bars
// (click one for its top window titles), and the last 7 days.
Rectangle {
    id: root
    implicitHeight: col.implicitHeight + 20
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1

    property var day: ({ total: 0, apps: [] })
    property var week: []
    property string openApp: ""
    readonly property bool live: GlobalStates.sidebarRightOpen

    function fmt(secs) {
        const m = Math.round(secs / 60)
        return m < 60 ? `${m} min` : `${Math.floor(m / 60)} h ${m % 60} min`
    }
    // "org.gnome.Nautilus" → "Nautilus", "kitty" → "Kitty"
    function appName(id) {
        const last = String(id).split(".").pop()
        return last.charAt(0).toUpperCase() + last.slice(1)
    }
    function refresh() {
        if (!Anod.available) return
        Anod.call("screentime.day", {}, (r, e) => { if (!e && r) root.day = r })
        Anod.call("screentime.week", {}, (r, e) => { if (!e && r) root.week = r })
    }
    onLiveChanged: if (live) refresh()
    Component.onCompleted: refresh()
    Connections { target: ScreenTime; function onUpdated() { if (root.live) root.refresh() } }

    ColumnLayout {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            MaterialSymbol { text: "hourglass_top"; iconSize: 20; color: Appearance.colors.colOnLayer1 }
            StyledText { Layout.fillWidth: true; text: "Screen time"; font.weight: Font.DemiBold }
            StyledText {
                text: root.fmt(root.day.total ?? 0)
                font.weight: Font.DemiBold
                color: Appearance.colors.colPrimary
            }
        }
        StyledText {
            visible: (root.day.apps ?? []).length === 0
            text: !Anod.available ? "Needs anod (ano doctor)" : ScreenTime.idle ? "Idle: not counting" : "Nothing yet today"
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
        }

        // Top apps
        Repeater {
            model: root.day.apps ?? []
            delegate: ColumnLayout {
                required property var modelData
                readonly property real share: (modelData.secs ?? 0) / Math.max(1, root.day.apps[0]?.secs ?? 1)
                Layout.fillWidth: true
                spacing: 3
                RowLayout {
                    Layout.fillWidth: true
                    StyledText { Layout.fillWidth: true; elide: Text.ElideRight; text: root.appName(modelData.name); font.pixelSize: Appearance.font.pixelSize.small }
                    StyledText { text: root.fmt(modelData.secs); font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colSubtext }
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 6; radius: 3
                    color: Appearance.colors.colLayer2
                    Rectangle {
                        height: parent.height; radius: 3
                        width: parent.width * share
                        color: Appearance.colors.colPrimary
                        Behavior on width { MotionSpring { token: "snappy" } }
                    }
                }
                // Its top window titles
                Repeater {
                    model: root.openApp === modelData.name ? (modelData.titles ?? []) : []
                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.leftMargin: 8
                        StyledText { Layout.fillWidth: true; elide: Text.ElideRight; text: modelData.name || "(no title)"; font.pixelSize: Appearance.font.pixelSize.smallest; color: Appearance.colors.colSubtext }
                        StyledText { text: root.fmt(modelData.secs); font.pixelSize: Appearance.font.pixelSize.smallest; color: Appearance.colors.colSubtext }
                    }
                }
                TapHandler { onTapped: root.openApp = root.openApp === modelData.name ? "" : modelData.name }
            }
        }

        // The last 7 days
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            visible: root.week.length === 7
            spacing: 6
            readonly property int peak: Math.max(1, ...root.week.map(d => d.secs ?? 0))
            Repeater {
                model: root.week
                delegate: ColumnLayout {
                    id: dayCol
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    spacing: 2
                    Item {
                        Layout.fillWidth: true
                        implicitHeight: 44
                        Rectangle {
                            anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
                            width: Math.min(18, parent.width - 4)
                            height: Math.max(2, parent.height * (dayCol.modelData.secs ?? 0) / dayCol.parent.peak)
                            radius: 3
                            color: dayCol.index === 6 ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                            Behavior on height { MotionSpring { token: "snappy" } }
                        }
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Qt.formatDate(new Date(dayCol.modelData.name + "T12:00:00"), "ddd").slice(0, 2)
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }
    }
}
