import QtQuick
import qs.modules.common
import qs.services
import "pet.js" as Pet

/**
 * The pet's life: it picks behaviours (pet.js), walks along its floor, is petted, carried, thrown and falls to the next
 * floor. Positions are px in its area (feet at x, y). Ticks at the display's rate while moving or changing pose, at
 * 15 per second at rest (8 asleep), and not at all while `live` is false. Used by the desktop pet and the editor's preview.
 */
Item {
    id: root
    property string kind: "duck"
    property real size: 128
    property var floors: [{ id: "ground", x1: 0, x2: 400, y: 200 }]
    property real areaWidth: 400
    property bool live: true
    property bool soundOn: false
    property bool chase: false
    // Asked now and then for the pointer: cb({x, y}) in area px, or nothing. Null: no chase.
    property var pointerFn: null

    // State.
    property real x0: 100
    property real y0: 200
    property real facing: 1
    property string mode: "act"       // act | carry | fall
    property string behaviour: "idle"
    property real duration: 3
    property real bt: 0               // s into the behaviour
    property real clock: 0            // s, for blinks, z's and hearts
    property string floorId: "ground"
    property var p: Pet.pose(root.kind, "idle", 0)
    property string say: ""
    property bool hearts: false
    property real targetX: 0
    readonly property real half: root.size * 0.5
    readonly property bool moving: root.mode !== "act" || Pet.walks(root.behaviour) || root._blend < 1 || root._squash > 0
    readonly property bool sleeping: root.behaviour === "sleep"

    property var _from: root.p
    property real _blend: 1
    property real _squash: 0
    property real _quietSince: Date.now()
    property real _sayUntil: 0
    property var _vel: ({ vx: 0, vy: 0 })
    property var _samples: []
    property real _grabDX: 0
    property real _grabDY: 0
    property real _chaseAt: Date.now() + 120000

    signal landed()

    function floor() { return root.floors.find(f => f.id === root.floorId) ?? root.floors[0] }
    function _start(name, duration) {
        root._from = root.p
        root._blend = 0
        root.behaviour = name
        root.duration = duration
        root.bt = 0
        root.hearts = name === "happy"
        if (Pet.walks(name)) {
            const f = root.floor(), span = Math.max(0, f.x2 - f.x1 - 2 * root.half)
            if (!(root.targetX >= 0)) root.targetX = Pet.clampTo(f, f.x1 + root.half + Math.random() * span, root.half)
            root.targetX = Pet.clampTo(f, root.targetX, root.half)
            if (Math.abs(root.targetX - root.x0) > 1) root.facing = root.targetX > root.x0 ? 1 : -1
        }
        if (name === "call") {
            root.say = Pet.CALLS[Pet.kindOf(root.kind)]
            root._sayUntil = root.clock + 1.6
            if (root.soundOn && !Notifications.silent) Sounds.play(Pet.SOUNDS[Pet.kindOf(root.kind)])
        }
    }
    function _next() {
        root.targetX = NaN
        const quiet = (Date.now() - root._quietSince) / 1000
        // Now and then, walk to the pointer when it's near the floor.
        if (root.chase && root.pointerFn && Date.now() > root._chaseAt) {
            root._chaseAt = Date.now() + 120000 + Math.random() * 180000
            root.pointerFn(ptr => {
                const f = root.floor()
                if (ptr && root.mode === "act" && Math.abs(ptr.y - f.y) < root.size * 1.5 && ptr.x >= f.x1 && ptr.x <= f.x2) {
                    root.targetX = ptr.x
                    root._start("walk", 0)
                }
            })
        }
        const b = Pet.pick(root.kind, Math.random(), Math.random(), quiet)
        root._start(b.name, b.duration)
    }
    // Try a behaviour now (the editor's buttons, IPC).
    function act(name) {
        if (root.mode !== "act" || !Pet.behaviours(root.kind).concat(["happy"]).includes(name)) return
        root._quietSince = Date.now()
        root.targetX = NaN
        root._start(name, name === "sleep" ? 8 : name === "happy" ? 1.8 : Pet.walks(name) ? 0 : 3)
    }
    function petIt() { root.act("happy") }

    // Carrying: grab at (px, py) area px; the pet hangs from the pointer and swings.
    function grab(px, py) {
        root._quietSince = Date.now()
        root._grabDX = px - root.x0
        root._grabDY = py - root.y0
        root._vel = { vx: 0, vy: 0 }
        root._samples = [{ x: px, y: py, t: Date.now() }]
        root.mode = "carry"
        root.say = ""
        root._start("carry", 1e9)
    }
    property real _ptrX: 0
    property real _ptrY: 0
    function drag(px, py) {
        root._ptrX = px; root._ptrY = py
        const now = Date.now()
        root._samples = root._samples.filter(s => now - s.t < 200).concat([{ x: px, y: py, t: now }])
    }
    function release() {
        if (root.mode !== "carry") return
        const v = Pet.throwVelocity(root._samples, Date.now())
        root._vel = { vx: v.vx, vy: Math.min(v.vy, 1200) }
        root.mode = "fall"
        root._start("fall", 1e9)
    }
    // The floor went away or moved: fall, or move with it.
    function fallNow() {
        if (root.mode !== "act") return
        root._vel = { vx: 0, vy: 0 }
        root.mode = "fall"
        root._start("fall", 1e9)
    }
    onFloorsChanged: {
        if (root.mode !== "act") return
        const f = root.floors.find(g => g.id === root.floorId)
        // The ground can't be walked off (the area resized): stay on it.
        if (f && f.id === "ground") { root.x0 = Pet.clampTo(f, root.x0, root.half); root.y0 = f.y; return }
        if (!f || root.x0 < f.x1 || root.x0 > f.x2) { root.fallNow(); return }
        // A window moving down drops it; the ground (the area measured, a bar added or removed) and a window moving up
        // carry it.
        if (f.y !== root.y0) {
            if (f.y > root.y0 && f.id !== "ground") root.fallNow()
            else root.y0 = f.y
        }
    }
    onKindChanged: root._start("idle", 1.5)

    function tick(dt) {
        dt = Math.min(dt, 0.1)
        root.clock += dt
        root.bt += dt
        if (root._squash > 0) root._squash = Math.max(0, root._squash - dt)
        if (root.say !== "" && root.clock > root._sayUntil) root.say = ""

        if (root.mode === "carry") {
            // A soft spring to the pointer, the body swinging with the motion.
            const tx = root._ptrX - root._grabDX * 0.3, ty = root._ptrY - root._grabDY * 0.3 + root.size * 0.55
            const ax = (tx - root.x0) * 160 - root._vel.vx * 18, ay = (ty - root.y0) * 160 - root._vel.vy * 18
            root._vel = { vx: root._vel.vx + ax * dt, vy: root._vel.vy + ay * dt }
            root.x0 = Math.max(root.half, Math.min(root.areaWidth - root.half, root.x0 + root._vel.vx * dt))
            root.y0 = Math.max(root.size, root.y0 + root._vel.vy * dt)
        } else if (root.mode === "fall") {
            const r = Pet.fall({ x: root.x0, y: root.y0, vx: root._vel.vx, vy: root._vel.vy }, dt, root.floors, root.areaWidth, root.half, root.size)
            root.x0 = r.s.x; root.y0 = r.s.y
            root._vel = { vx: r.s.vx, vy: r.s.vy }
            if (Math.abs(r.s.vx) > 30) root.facing = r.s.vx > 0 ? 1 : -1
            if (r.landed) {
                root.floorId = r.landed.id
                root.x0 = Pet.clampTo(r.landed, root.x0, root.half)
                root.mode = "act"
                root._squash = 0.28
                root._start("idle", 0.8)
                root.landed()
            }
        } else if (Pet.walks(root.behaviour)) {
            const step = Pet.speed(root.kind, root.behaviour, root.size) * dt, d = root.targetX - root.x0
            if (Math.abs(d) <= step) { root.x0 = root.targetX; root._next() }
            else root.x0 += Math.sign(d) * step
            if (root.behaviour === "sniff" && root.bt > root.duration) root._next()
        } else if (root.bt > root.duration) root._next()

        // Pose: eased from the last behaviour's, blinking, swinging when carried, squashed on landing.
        root._blend = Math.min(1, root._blend + dt / 0.3)
        const k = root._blend < 1 ? 0.5 - 0.5 * Math.cos(Math.PI * root._blend) : 1
        const q = Pet.mix(root._from, Pet.pose(root.kind, root.behaviour, root.bt), k)
        if (q.eye >= 0.99) q.eye *= Pet.blink(root.clock)
        if (root.mode === "carry") q.rot = Math.max(-35, Math.min(35, -root._vel.vx * 0.03)) * root.facing
        if (root._squash > 0) q.sq = 1 - 0.22 * Math.sin(Math.PI * root._squash / 0.28)
        root.p = q
    }

    // Moving: every frame. Resting: 15 per second; asleep, 8.
    FrameAnimation {
        running: root.live && root.moving
        onTriggered: root.tick(frameTime)
    }
    Timer {
        running: root.live && !root.moving
        interval: root.sleeping ? 125 : 66; repeat: true
        onTriggered: root.tick(interval / 1000)
    }
    Component.onCompleted: root._start("idle", 2)
}
