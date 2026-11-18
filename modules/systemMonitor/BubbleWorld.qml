import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "bubbles.js" as B

/**
 * The bubble view: metric bubbles (CPU, memory, temperature, network, disk) with ring gauges, and a bubble for each of
 * the busiest processes (or open apps, bubbleMonitor.mode) sized by CPU use, drifting, knocking softly into each other,
 * with sparks between close ones. `full`: the Bubble Monitor's, with a starfield, panning (drag empty space), zoom
 * (wheel, 30–100%), carrying bubbles and clicking one (opened(id)). Samples and moves only while `live`.
 */
Item {
    id: world
    property bool full: false
    property bool live: visible
    property real zoom: 0.7
    property real panX: 0
    property real panY: 0
    signal opened(string id)

    // World size in world units; the sidebar's is smaller so its bubbles read at its size.
    readonly property real worldW: world.full ? 2400 : 1200
    readonly property real worldH: world.full ? 1500 : Math.max(400, 1200 * world.height / Math.max(1, world.width))
    readonly property real k: world.full ? world.zoom : world.width / world.worldW
    readonly property real cx: world.width / 2
    readonly property real cy: world.height / 2

    ServiceLease { service: ResourceUsage; name: world.full ? "bubbleMonitor" : "bubbleStyle"; active: world.live }
    ServiceLease { service: SysMon; name: world.full ? "bubbleMonitor" : "bubbleStyle"; active: world.live }

    // ── Data ─────────────────────────────────────────────────────────────
    property var nodes: []          // physics nodes (bubbles.js), mutated in place
    property var byId: ({})
    property var entries: ({})      // id → what the bubble shows
    property var ids: []            // the Repeater's model: changes only when bubbles come or go
    property int dataRev: 0
    property int frame: 0

    function speed(b) {
        if (b < 1024) return `${Math.round(b)} B/s`
        if (b < 1048576) return `${(b / 1024).toFixed(0)} KB/s`
        return `${(b / 1048576).toFixed(1)} MB/s`
    }
    function sync() {
        const cores = Math.max(1, SysMon.cores || ResourceUsage.coreUsage.length || 1)
        const e = {}
        const t = ResourceUsage.temperature
        const net = ResourceUsage.networkDownloadSpeed + ResourceUsage.networkUploadSpeed
        e.cpu = { kind: "metric", icon: "memory", label: "CPU", text: `${Math.round(ResourceUsage.cpuUsage * 100)}%`, value: ResourceUsage.cpuUsage, tone: Appearance.colors.colPrimary }
        e.mem = { kind: "metric", icon: "memory_alt", label: "Memory", text: `${Math.round(ResourceUsage.memoryUsedPercentage * 100)}%`, value: ResourceUsage.memoryUsedPercentage, tone: Appearance.colors.colTertiary }
        if (!isNaN(t)) e.temp = { kind: "metric", icon: "device_thermostat", label: "Temp", text: `${Math.round(t)}°`, value: Math.min(1, t / 100), tone: t >= 85 ? Appearance.colors.colError : Appearance.colors.colWarning }
        e.net = { kind: "metric", icon: "swap_vert", label: "Network", text: world.speed(ResourceUsage.networkDownloadSpeed), value: Math.min(1, Math.log10(1 + net) / 8), tone: Appearance.colors.colInfo }
        if (!isNaN(ResourceUsage.diskSize)) e.disk = { kind: "metric", icon: "hard_drive", label: "Disk", text: `${Math.round(ResourceUsage.diskUsedPercentage * 100)}%`, value: ResourceUsage.diskUsedPercentage, tone: Appearance.colors.colSecondary }
        if (SysMon.mode === "apps") {
            for (const a of SysMon.apps)
                e[`a${a.app}`] = { kind: "app", label: String(a.app).split(".").pop(), text: `${(a.cpu * cores * 100).toFixed(0)}%`, share: a.cpu * cores, data: a }
        } else {
            for (const p of SysMon.procs)
                e[`p${p.pid}`] = { kind: "proc", label: p.name, text: `${(p.cpu * cores * 100).toFixed(0)}%`, share: p.cpu * cores, paused: p.paused, data: p }
        }
        const small = world.full ? 30 : 30, big = world.full ? 90 : 80
        for (const id in e) {
            const target = e[id].kind === "metric" ? 72 : B.radiusFor(e[id].share, small, big)
            let n = world.byId[id]
            if (!n) {
                n = B.node(id, target, world.worldW, world.worldH)
                world.byId[id] = n
                world.nodes.push(n)
            }
            n.target = target
            n.dying = false
        }
        for (const n of world.nodes) if (!e[n.id]) { n.target = 0; n.dying = true; if (world.entries[n.id]) e[n.id] = world.entries[n.id] }
        world.entries = e
        const ids = world.nodes.map(n => n.id)
        if (ids.join("\n") !== world.ids.join("\n")) world.ids = ids
        world.dataRev++
        settle.restart()
    }
    function prune() {
        const gone = world.nodes.filter(n => n.dying && n.r < 2)
        if (gone.length === 0) return
        for (const n of gone) delete world.byId[n.id]
        world.nodes = world.nodes.filter(n => !gone.includes(n))
        world.ids = world.nodes.map(n => n.id)
    }
    Connections {
        target: SysMon
        function onProcsChanged() { world.sync() }
        function onAppsChanged() { world.sync() }
        function onModeChanged() { world.sync() }
    }
    Connections {
        target: ResourceUsage
        function onCpuUsageChanged() { world.sync() }
    }
    onLiveChanged: if (live) sync()
    Component.onCompleted: sync()

    // ── Motion ───────────────────────────────────────────────────────────
    property real _t: 0
    property var sparkList: []
    property real _lastKnock: 0
    // With continuous motion off, the bubbles still move for a moment after each change to settle, then stop.
    Timer { id: settle; interval: 3000 }
    FrameAnimation {
        running: world.live && world.visible && (AnimationConfig.continuous || settle.running)
        onTriggered: {
            world._t += frameTime
            const knocks = B.step(world.nodes, world.worldW, world.worldH, frameTime, world._t)
            world.sparkList = B.sparks(world.nodes, world.full ? 70 : 40, 10)
            world.prune()
            world.frame++
            if (knocks.length > 0 && world.full && (Config.options?.bubbleMonitor?.sound ?? false) && Date.now() - world._lastKnock > 140) {
                world._lastKnock = Date.now()
                Sounds.play("bubble")
            }
        }
    }

    // ── Drawing ──────────────────────────────────────────────────────────
    function toView(x, y) { return Qt.point(world.cx + (x - world.panX) * world.k, world.cy + (y - world.panY) * world.k) }
    function toWorld(px, py) { return Qt.point((px - world.cx) / world.k + world.panX, (py - world.cy) / world.k + world.panY) }

    Loader {
        anchors.fill: parent
        active: world.full
        sourceComponent: Item {
            StarLayer { anchors.fill: parent; depth: 0.25; count: 70; size: 1.2; alpha: 0.35 }
            StarLayer { anchors.fill: parent; depth: 0.6; count: 40; size: 2; alpha: 0.6 }
        }
    }

    // Sparks: a flickering line between close bubbles.
    Repeater {
        model: 10
        Rectangle {
            id: spark
            required property int index
            readonly property var s: { void world.frame; return world.sparkList[spark.index] ?? null }
            visible: !!spark.s
            readonly property point pa: spark.s ? world.toView(spark.s.a.x, spark.s.a.y) : Qt.point(0, 0)
            readonly property point pb: spark.s ? world.toView(spark.s.b.x, spark.s.b.y) : Qt.point(0, 0)
            readonly property real len: Math.hypot(pb.x - pa.x, pb.y - pa.y)
            x: pa.x; y: pa.y - height / 2
            width: len; height: Math.max(1, 2 * (spark.s?.strength ?? 0))
            transformOrigin: Item.Left
            rotation: Math.atan2(pb.y - pa.y, pb.x - pa.x) * 180 / Math.PI
            opacity: spark.s ? spark.s.strength * (0.55 + 0.45 * Math.sin(world._t * 23 + spark.index * 1.7)) : 0
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 0.5; color: Appearance.colors.colPrimary }
                GradientStop { position: 1; color: "transparent" }
            }
        }
    }

    Repeater {
        model: world.ids
        Item {
            id: bubble
            required property string modelData
            readonly property var n: world.byId[bubble.modelData] ?? null
            readonly property var e: { void world.dataRev; return world.entries[bubble.modelData] ?? ({}) }
            readonly property real r: { void world.frame; return (bubble.n?.r ?? 0) * world.k }
            readonly property point at: { void world.frame; return bubble.n ? world.toView(bubble.n.x, bubble.n.y) : Qt.point(0, 0) }
            readonly property real sq: { void world.frame; return bubble.n?.squash ?? 0 }
            readonly property color tone: bubble.e.tone ?? (bubble.e.kind === "app" ? Appearance.colors.colOnLayer0 : Appearance.colors.colSecondary)
            readonly property bool hot: (bubble.e.share ?? 0) > 0.5
            visible: bubble.r > 1
            x: bubble.at.x - bubble.r; y: bubble.at.y - bubble.r
            width: bubble.r * 2; height: bubble.r * 2
            transform: Scale { origin.x: bubble.r; origin.y: bubble.r; xScale: 1 + bubble.sq; yScale: 1 - bubble.sq }
            opacity: bubble.e.paused ? 0.5 : 1

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: Qt.alpha(bubble.tone, bubble.e.kind === "metric" ? 0.16 : 0.22)
                border.width: Math.max(1, bubble.r * 0.04)
                border.color: bubble.hot ? Appearance.colors.colError : Qt.alpha(bubble.tone, 0.7)
            }
            // A highlight, so they read as bubbles.
            Rectangle {
                x: bubble.r * 0.45; y: bubble.r * 0.3
                width: bubble.r * 0.5; height: bubble.r * 0.28
                radius: height / 2
                rotation: -30
                color: Qt.rgba(1, 1, 1, 0.12)
            }
            CircularProgress {
                visible: bubble.e.kind === "metric"
                anchors.fill: parent
                implicitSize: bubble.width
                lineWidth: Math.max(2, bubble.r * 0.09)
                value: bubble.e.value ?? 0
                colPrimary: bubble.tone
                colSecondary: "transparent"
                enableAnimation: true
            }
            Column {
                anchors.centerIn: parent
                visible: bubble.r > 14
                spacing: 0
                MaterialSymbol {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: !!bubble.e.icon && bubble.r > 26
                    text: bubble.e.icon ?? ""
                    iconSize: Math.min(28, bubble.r * 0.38)
                    color: bubble.tone
                }
                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(implicitWidth, bubble.r * 1.6)
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                    text: bubble.e.label ?? ""
                    font.pixelSize: Math.max(8, Math.min(16, bubble.r * 0.24))
                    color: Appearance.colors.colOnLayer0
                }
                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: bubble.r > 20
                    text: bubble.e.paused ? "paused" : (bubble.e.text ?? "")
                    font.pixelSize: Math.max(8, Math.min(14, bubble.r * 0.2))
                    font.family: Appearance.font.family.mono
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }

    // ── Hands (full screen) ──────────────────────────────────────────────
    MouseArea {
        anchors.fill: parent
        enabled: world.full
        hoverEnabled: false
        property var held: null
        property point last
        property real lastT: 0
        property real moved: 0
        onPressed: mouse => {
            const p = world.toWorld(mouse.x, mouse.y)
            held = B.hit(world.nodes, p.x, p.y)
            if (held) { held.held = true; held.vx = 0; held.vy = 0 }
            last = Qt.point(mouse.x, mouse.y); lastT = Date.now(); moved = 0
        }
        onPositionChanged: mouse => {
            const dx = mouse.x - last.x, dy = mouse.y - last.y
            moved += Math.abs(dx) + Math.abs(dy)
            const dt = Math.max(1, Date.now() - lastT) / 1000
            if (held) {
                const p = world.toWorld(mouse.x, mouse.y)
                held.vx = (p.x - held.x) / dt; held.vy = (p.y - held.y) / dt
                held.x = p.x; held.y = p.y
            } else {
                world.panX = Math.max(-world.worldW / 2, Math.min(world.worldW / 2, world.panX - dx / world.k))
                world.panY = Math.max(-world.worldH / 2, Math.min(world.worldH / 2, world.panY - dy / world.k))
            }
            last = Qt.point(mouse.x, mouse.y); lastT = Date.now()
            settle.restart()
        }
        onReleased: {
            if (held) {
                held.held = false
                held.vx = Math.max(-900, Math.min(900, held.vx)); held.vy = Math.max(-900, Math.min(900, held.vy))
                if (moved < 6 && !held.dying) world.opened(held.id)
            }
            held = null
        }
        onWheel: wheel => {
            const before = world.toWorld(wheel.x, wheel.y)
            world.zoom = Math.max(0.3, Math.min(1, world.zoom * Math.pow(1.1, wheel.angleDelta.y / 120)))
            const after = world.toWorld(wheel.x, wheel.y)
            world.panX += before.x - after.x
            world.panY += before.y - after.y
        }
    }

    // Stars on a repeating 512 px tile, moved by `depth` of the pan.
    component StarLayer: Canvas {
        id: layer
        property real depth: 0.5
        property int count: 50
        property real size: 1.5
        property real alpha: 0.5
        readonly property real ox: -world.panX * world.k * layer.depth
        readonly property real oy: -world.panY * world.k * layer.depth
        onOxChanged: requestPaint()
        onOyChanged: requestPaint()
        onWidthChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            ctx.fillStyle = Qt.rgba(1, 1, 1, layer.alpha)
            const tile = 512
            let seed = Math.round(layer.depth * 1000)
            const rnd = () => { seed = (seed * 16807) % 2147483647; return seed / 2147483647 }
            const stars = []
            for (let i = 0; i < layer.count; i++) stars.push([rnd() * tile, rnd() * tile, (0.4 + rnd() * 0.6) * layer.size])
            const sx = ((layer.ox % tile) + tile) % tile - tile, sy = ((layer.oy % tile) + tile) % tile - tile
            for (let tx = sx; tx < width; tx += tile)
                for (let ty = sy; ty < height; ty += tile)
                    for (const s of stars) { ctx.beginPath(); ctx.arc(tx + s[0], ty + s[1], s[2], 0, Math.PI * 2); ctx.fill() }
        }
    }
}
