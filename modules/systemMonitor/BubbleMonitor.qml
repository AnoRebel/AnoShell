import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * The full-screen Bubble Monitor: usage, temperature and the busiest processes (or open apps) as bubbles in a
 * starfield (BubbleWorld). It opens with a reveal growing from where it was opened (the sidebar's Bubble style button,
 * GlobalStates.bubbleMonitorOrigin; the middle otherwise). Click a bubble for its details; Esc closes the details,
 * then the monitor. `qs -c ano ipc call bubbleMonitor toggle`.
 */
Scope {
    id: root
    readonly property bool open: GlobalStates.bubbleMonitorOpen
    property string selected: ""
    onOpenChanged: if (!open) root.selected = ""

    IpcHandler {
        target: "bubbleMonitor"
        function toggle(): void { root.show(!GlobalStates.bubbleMonitorOpen) }
        function open(): void { root.show(true) }
        function close(): void { root.show(false) }
    }
    function show(on) {
        if (on && !GlobalStates.bubbleMonitorOpen) GlobalStates.bubbleMonitorOrigin = Qt.point(-1, -1)
        GlobalStates.bubbleMonitorOpen = on
    }

    PanelWindow {
        id: win
        visible: root.open || reveal.progress > 0
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell:bubbleMonitor"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        anchors { top: true; bottom: true; left: true; right: true }
        mask: root.open ? null : noInput
        Region { id: noInput; item: null }

        Shortcut { sequence: "Escape"; autoRepeat: false; onActivated: root.selected ? root.selected = "" : root.show(false) }

        Item {
            id: reveal
            anchors.fill: parent
            property real progress: root.open ? 1 : 0
            Behavior on progress { NumberAnimation { duration: AnimationConfig.scaledDuration(650); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }
            // The origin: a negative x counts from the right edge (the right sidebar's button).
            readonly property point origin: {
                const o = GlobalStates.bubbleMonitorOrigin
                if (o.x === -1 && o.y === -1) return Qt.point(width / 2, height / 2)
                return Qt.point(o.x < 0 ? width + o.x : o.x, o.y)
            }
            layer.enabled: progress < 1
            layer.effect: ShaderEffect {
                fragmentShader: Qt.resolvedUrl(Quickshell.shellPath("shaders/qsb/bubble_reveal.frag.qsb"))
                property real progress: reveal.progress
                property real widthPx: reveal.width
                property real heightPx: reveal.height
                property real cx: reveal.origin.x
                property real cy: reveal.origin.y
                property vector4d rim: Qt.vector4d(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.8)
            }

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    // Opaque: the theme's layer colours may be translucent.
                    GradientStop { readonly property color c: Qt.darker(Appearance.colors.colLayer0, 1.9); position: 0; color: Qt.rgba(c.r, c.g, c.b, 1) }
                    GradientStop { readonly property color c: Qt.darker(Appearance.m3colors.m3primaryContainer, 3.2); position: 1; color: Qt.rgba(c.r, c.g, c.b, 1) }
                }
            }

            BubbleWorld {
                id: world
                anchors.fill: parent
                full: true
                live: root.open
                onOpened: id => root.selected = id
            }

            // Top bar
            RowLayout {
                anchors { top: parent.top; left: parent.left; right: parent.right; margins: 24 }
                spacing: 12
                ColumnLayout {
                    spacing: 0
                    StyledText { text: "Bubble Monitor"; font.pixelSize: Appearance.font.pixelSize.huge; font.weight: Font.DemiBold; color: Appearance.colors.colOnLayer0 }
                    StyledText {
                        text: !SysMon.available ? "anod is not running: start the shell with \"ano start\" to see processes"
                            : `${SysMon.processCount} processes · ${SysMon.cores} cores · zoom ${Math.round(world.zoom * 100)}%`
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }
                Item { Layout.fillWidth: true }
                Row {
                    spacing: 4
                    Repeater {
                        model: [{ key: "processes", label: "Processes" }, { key: "apps", label: "Apps" }]
                        RippleButton {
                            required property var modelData
                            buttonText: modelData.label
                            toggled: SysMon.mode === modelData.key
                            onClicked: Config.setNestedValue("bubbleMonitor.mode", modelData.key)
                        }
                    }
                }
                ToolbarButton { iconName: "close"; iconSize: 20; toolTipText: "Close (Esc)"; onClicked: root.show(false) }
            }
            StyledText {
                anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; margins: 18 }
                text: "Drag empty space to look around · wheel to zoom · drag a bubble to carry it · click one for details"
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }

            // Details, sliding in from the right.
            Rectangle {
                id: details
                width: Math.min(400, parent.width * 0.32)
                anchors { top: parent.top; bottom: parent.bottom; margins: 16; topMargin: 84 }
                property real slide: root.selected ? 1 : 0
                x: parent.width - (width + 16) * slide
                Behavior on slide { NumberAnimation { duration: AnimationConfig.scaledDuration(380); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }
                radius: Appearance.rounding.windowRounding
                color: Appearance.colors.colLayer1
                border.width: 1; border.color: Qt.alpha(page.tone, 0.5)
                visible: slide > 0
                MouseArea { anchors.fill: parent } // clicks here don't reach the world

                DetailsPage {
                    id: page
                    anchors { fill: parent; margins: 18 }
                    id_: root.selected
                    live: root.open
                    source: { void world.dataRev; return world.entries[root.selected] ?? null }
                    onClose: root.selected = ""
                }
            }
        }
    }

    // ── A bubble's details ───────────────────────────────────────────────
    component DetailsPage: ColumnLayout {
        id: dp
        property string id_: ""
        property var source: null  // the bubble's live entry; `entry` keeps the last one after its bubble has gone
        property var entry: null
        onSourceChanged: if (dp.source) dp.entry = dp.source
        property bool live: false
        signal close()
        spacing: 10
        readonly property string kind: dp.entry?.kind ?? ""
        readonly property color tone: dp.entry?.tone ?? Appearance.colors.colSecondary
        readonly property int cores: Math.max(1, SysMon.cores || ResourceUsage.coreUsage.length || 1)
        property var proc: null   // the process's latest details (sysmon.proc)
        function refresh() {
            if (dp.kind !== "proc") { dp.proc = null; return }
            const pid = dp.entry.data.pid
            SysMon.details(pid, d => { if (dp.kind === "proc" && dp.entry?.data?.pid === pid) dp.proc = d })
        }
        onId_Changed: dp.entry = dp.source
        // A new bubble (not a new sample of the same one) starts from what the bubble knew.
        property string _shownId: ""
        onEntryChanged: {
            const id = dp.kind === "proc" ? `p${dp.entry.data.pid}` : ""
            if (id === dp._shownId) return
            dp._shownId = id
            dp.proc = id ? dp.entry.data : null
            dp.refresh()
        }
        Timer { running: dp.kind === "proc" && dp.live; interval: 1000; repeat: true; onTriggered: dp.refresh() }

        function mb(bytes) { return bytes >= 1073741824 ? `${(bytes / 1073741824).toFixed(1)} GB` : `${Math.round(bytes / 1048576)} MB` }
        function pct(share) { return `${(share * 100).toFixed(0)}%` }
        function speed(b) { return b < 1048576 ? `${(b / 1024).toFixed(0)} KB/s` : `${(b / 1048576).toFixed(1)} MB/s` }
        readonly property var history: {
            switch (dp.id_) {
            case "cpu": return ResourceUsage.cpuUsageHistory
            case "mem": return ResourceUsage.memoryUsageHistory
            case "temp": return ResourceUsage.temperatureHistory.map(t => Math.min(1, t / 100))
            }
            return (SysMon.history[dp.id_] ?? []).map(v => Math.min(1, v * dp.cores))
        }
        readonly property var facts: {
            const e = dp.entry
            if (!e) return []
            if (e.kind === "proc") {
                const p = dp.proc ?? e.data
                return [["CPU", dp.pct(p.cpu * dp.cores) + " of a core"], ["Memory", `${dp.mb(p.mem)} · ${(p.memShare * 100).toFixed(1)}%`],
                    ["Threads", String(p.threads)], ["User", p.user], ["PID", String(p.pid)],
                    ["State", p.paused ? "paused" : p.state], ["Started", Qt.formatDateTime(new Date(p.start), "ddd d MMM, hh:mm")]]
            }
            if (e.kind === "app") {
                const a = e.data
                return [["CPU", dp.pct(a.cpu * dp.cores) + " of a core"], ["Memory", `${dp.mb(a.mem)} · ${(a.memShare * 100).toFixed(1)}%`], ["Processes", String(a.procs)]]
            }
            switch (dp.id_) {
            case "cpu": return [["Use", dp.pct(ResourceUsage.cpuUsage)], ["Cores", String(dp.cores)], ["Max clock", ResourceUsage.maxAvailableCpuString]]
            case "mem": return [["Used", `${ResourceUsage.kbToGbString(ResourceUsage.memoryUsed)} of ${ResourceUsage.maxAvailableMemoryString}`],
                ["Swap", ResourceUsage.swapTotal > 0 ? `${ResourceUsage.kbToGbString(ResourceUsage.swapUsed)} of ${ResourceUsage.maxAvailableSwapString}` : "none"]]
            case "temp": return [["CPU", `${Math.round(ResourceUsage.temperature)}°C`]]
            case "net": return [["Down", dp.speed(ResourceUsage.networkDownloadSpeed)], ["Up", dp.speed(ResourceUsage.networkUploadSpeed)]]
            case "disk": return [["Used", `${(ResourceUsage.diskUsed / 1e9).toFixed(0)} of ${(ResourceUsage.diskSize / 1e9).toFixed(0)} GB`], ["Share", dp.pct(ResourceUsage.diskUsedPercentage)]]
            }
            return []
        }
        // Lists: per-core use, sensors, top processes. [{ title, rows: [{ name, value 0..1, text }] }]
        readonly property var lists: {
            const top = (procs, by) => procs.slice().sort((a, b) => by(b) - by(a)).slice(0, 6)
            switch (dp.id_) {
            case "cpu": return [
                { title: "Cores", rows: ResourceUsage.coreUsage.map((c, i) => ({ name: `Core ${i}`, value: c, text: dp.pct(c) })) },
                { title: "Busiest", rows: top(SysMon.procs, p => p.cpu).map(p => ({ name: p.name, value: Math.min(1, p.cpu * dp.cores), text: dp.pct(p.cpu * dp.cores) })) }]
            case "mem": return [{ title: "Largest", rows: top(SysMon.procs, p => p.mem).map(p => ({ name: p.name, value: p.memShare, text: dp.mb(p.mem) })) }]
            case "temp": return [{ title: "Sensors", rows: SysMon.sensors.map(s => ({ name: `${s.chip} · ${s.label}`, value: Math.min(1, s.c / 100), text: `${Math.round(s.c)}°C` })) }]
            }
            if (dp.kind === "app")
                return [{ title: "Its busiest processes", rows: (dp.entry.data.top ?? []).map(p => ({ name: p.name, value: Math.min(1, p.cpu * dp.cores), text: dp.pct(p.cpu * dp.cores) })) }]
            return []
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Rectangle {
                implicitWidth: 34; implicitHeight: 34; radius: 17
                color: Qt.alpha(dp.tone, 0.25); border.width: 2; border.color: dp.tone
                MaterialSymbol { anchors.centerIn: parent; text: dp.entry?.icon ?? (dp.kind === "app" ? "web_asset" : "settings"); iconSize: 18; color: dp.tone }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText { Layout.fillWidth: true; elide: Text.ElideRight; text: dp.entry?.label ?? ""; font.pixelSize: Appearance.font.pixelSize.larger; font.weight: Font.DemiBold }
                StyledText { text: dp.kind === "proc" ? "Process" : dp.kind === "app" ? "App" : "System"; font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colSubtext }
            }
            ToolbarButton { iconName: "close"; iconSize: 18; toolTipText: "Back (Esc)"; onClicked: dp.close() }
        }
        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Appearance.colors.colOutlineVariant }
        StyledText {
            visible: dp.kind === "proc" && dp.proc === null
            text: "This process has ended."
            color: Appearance.colors.colSubtext
        }
        Rectangle {
            Layout.fillWidth: true
            visible: dp.history.length > 1
            implicitHeight: 90
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer2
            Graph {
                anchors { fill: parent; margins: 4 }
                values: dp.history
                points: 60
                alignment: Graph.Alignment.Right
                slide: AnimationConfig.transitions
                color: dp.tone
                fillOpacity: 0.7
            }
        }
        GridLayout {
            Layout.fillWidth: true
            columns: 2; columnSpacing: 12; rowSpacing: 4
            Repeater {
                model: dp.facts.length * 2
                StyledText {
                    required property int index
                    readonly property var f: dp.facts[Math.floor(index / 2)]
                    Layout.fillWidth: index % 2 === 1
                    horizontalAlignment: index % 2 === 1 ? Text.AlignRight : Text.AlignLeft
                    elide: Text.ElideRight
                    text: f ? f[index % 2] : ""
                    color: index % 2 === 0 ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.family: index % 2 === 1 ? Appearance.font.family.mono : Appearance.font.family.main
                }
            }
        }
        StyledText {
            Layout.fillWidth: true
            visible: dp.kind === "proc" && !!dp.proc?.cmd
            text: dp.proc?.cmd ?? ""
            wrapMode: Text.WrapAnywhere
            maximumLineCount: 4
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.family: Appearance.font.family.mono
            color: Appearance.colors.colSubtext
        }
        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: listsCol.implicitHeight
            clip: true
            ColumnLayout {
                id: listsCol
                width: parent.width
                spacing: 10
                Repeater {
                    model: dp.lists
                    ColumnLayout {
                        id: list
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 4
                        StyledText { text: list.modelData.title; font.weight: Font.DemiBold; font.pixelSize: Appearance.font.pixelSize.smaller }
                        Repeater {
                            model: list.modelData.rows
                            RowLayout {
                                id: row
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 8
                                StyledText { Layout.preferredWidth: 130; elide: Text.ElideRight; text: row.modelData.name; font.pixelSize: Appearance.font.pixelSize.smaller }
                                Rectangle {
                                    Layout.fillWidth: true; implicitHeight: 4; radius: 2
                                    color: Appearance.colors.colLayer2
                                    Rectangle { width: parent.width * Math.max(0, Math.min(1, row.modelData.value)); height: parent.height; radius: 2; color: dp.tone }
                                }
                                StyledText { Layout.preferredWidth: 64; horizontalAlignment: Text.AlignRight; text: row.modelData.text; font.pixelSize: Appearance.font.pixelSize.smaller; font.family: Appearance.font.family.mono }
                            }
                        }
                    }
                }
            }
        }
    }
}
