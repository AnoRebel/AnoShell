import QtQuick
import Quickshell
import Quickshell.Widgets
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.bar
import qs.modules.anoSpot
import qs.modules.anoScreen
import qs.services
import qs.modules.bar.modules
import "../bar/BarEdit.js" as BarEdit

/**
 * Settings' bar and pill preview (settings-wiring "Interactive previews in
 * Settings"): a miniature of the focused screen with the shell's own bar
 * content (classic style), the pill's faces and the dock, as configured.
 * Edited in place, written once when a drag ends:
 *   - drag a bar module: within its group or into another one;
 *   - drag the bar, the pill or the dock: to another edge;
 *   - click a bar group: groupClicked(id) (the page scrolls to it).
 * Nothing inside takes input of its own (no popouts, no actions).
 */
PreviewScreen {
    id: root
    signal groupClicked(string gid)

    // ── What's on screen ────────────────────────────────────────────────
    readonly property var barCfg: Config.options?.bars?.[0] ?? null
    readonly property bool classic: !BarStyle.pillBar && PanelGate.enabled("anoBar")
    readonly property string barEdge: barCfg?.edge ?? "top"
    readonly property bool barVertical: barEdge === "left" || barEdge === "right"
    readonly property real barThickness: barCfg?.height ?? Config.options?.bar?.layout?.height ?? (barVertical ? Appearance.sizes.verticalBarWidth : Appearance.sizes.barHeight)
    readonly property real barRadius: barCfg?.radius ?? Config.options?.bar?.layout?.radius ?? Appearance?.rounding.normal ?? 12
    readonly property bool barBackground: barCfg?.showBackground ?? Config.options?.bar?.showBackground ?? true
    readonly property real formMargin: (barContent.item?.edgeMargin ?? 0)
    readonly property bool connected: PanelRegistry.enabled
    readonly property real frameThickness: connected ? (Config.options?.appearance?.connectedCorners?.thickness ?? 7) : 0

    readonly property bool pillShown: PanelGate.enabled("anoSpot")
    readonly property string pillEdge: BarStyle.pillEdge
    readonly property bool pillVertical: pillEdge === "left" || pillEdge === "right"
    readonly property int pillThickness: Config.options?.anoSpot?.heightPx ?? 36
    readonly property bool dockShown: PanelGate.enabled("anoDock") && (Config.options?.dock?.enable ?? false)
    readonly property string dockEdge: BarStyle.dockEdge === "auto" ? "bottom" : BarStyle.dockEdge
    readonly property bool dockVertical: dockEdge === "left" || dockEdge === "right"
    readonly property real dockIcon: Config.options?.dock?.iconSize ?? 28

    // What a reserved edge pushes in by (the bar holds its edge).
    function inset(edge) { return root.classic && edge === root.barEdge ? root.barThickness + root.formMargin : root.frameThickness }

    // ── The classic bar ─────────────────────────────────────────────────
    Item {
        id: barArea
        visible: root.classic
        readonly property real m: root.formMargin + root.frameThickness * (root.connected ? 0 : 0)
        x: root.barEdge === "right" ? root.worldW - width - m : root.barEdge === "left" ? m : 0
        y: root.barEdge === "bottom" ? root.worldH - height - m : root.barEdge === "top" ? m : 0
        width: root.barVertical ? root.barThickness : root.worldW
        height: root.barVertical ? root.worldH : root.barThickness

        readonly property var bodies: (barContent.item?.bodyRects ?? [])
        readonly property bool plain: bodies.length <= 1 && !(bodies[0]?.island ?? false) && (barContent.item?.form ?? "full") === "full" && root.formMargin < 0.5

        // Body: a plain strip, or the shell's SDF bodies (islands, necks).
        Rectangle {
            anchors.fill: parent
            visible: root.barBackground && barArea.plain && !root.connected
            color: Appearance?.colors.colLayer0 ?? "#1C1B1F"
        }
        Loader {
            anchors.fill: parent
            z: -1
            asynchronous: true
            active: root.classic && root.barBackground && !barArea.plain && !root.connected
            sourceComponent: ConnectedFrame {
                cornerRadius: 0
                frameThickness: 0
                connectedRadius: root.barRadius
                surfaceRadius: root.barRadius
                surfaceColor: Appearance?.colors.colLayer0 ?? "#1C1B1F"
                surfaceOpacity: (Appearance?.colors.colLayer0 ?? Qt.rgba(0, 0, 0, 1)).a
                surfaces: barArea.bodies.map(b => ({ side: root.barEdge, x: b.x, y: b.y, w: b.w, h: b.h,
                    detached: b.island || root.formMargin > 0.5, neckK: 14, surfaceRadius: root.barRadius, progress: 1 }))
            }
        }
        // The bar's own content, fed the real config. Asynchronous: a deep tree
        // attached at once has crashed Qt before (BarWindow).
        Loader {
            id: barContent
            anchors.fill: parent
            // No input of its own: its wheel and click handlers run real
            // actions (volume, workspaces, brightness).
            enabled: false
            asynchronous: true
            active: root.classic && root.barCfg !== null
            sourceComponent: BarContent {
                barConfig: root.barCfg
                barIndex: 0
                isVertical: root.barVertical
                edge: root.barEdge
            }
        }
    }

    // Connected mode: the frame ring with the bar fused into it.
    Loader {
        anchors.fill: parent
        z: -1
        asynchronous: true
        active: root.connected
        sourceComponent: ConnectedFrame {
            frameThickness: root.frameThickness
            cornerRadius: Appearance?.rounding.screenRounding ?? 20
            surfaceColor: Appearance?.colors.colLayer0 ?? "#1C1B1F"
            surfaceOpacity: Config.options?.appearance?.connectedCorners?.opacity ?? 1
            surfaces: !root.classic ? [] : barArea.bodies.map(b => ({ side: root.barEdge,
                x: b.x + barArea.x, y: b.y + barArea.y, w: b.w, h: b.h,
                detached: b.island || root.formMargin > 0.5, neckK: 14, surfaceRadius: root.barRadius, progress: 1 }))
        }
    }

    // ── The pill ────────────────────────────────────────────────────────
    Rectangle {
        id: pill
        visible: root.pillShown
        readonly property real len: Math.max(root.pillThickness * 2, Math.min((faces.preferredLength ?? 200) + 18, 820))
        readonly property real gap: 6
        width: root.pillVertical ? root.pillThickness : len
        height: root.pillVertical ? len : root.pillThickness
        x: root.pillEdge === "left" ? root.inset("left") + gap : root.pillEdge === "right" ? root.worldW - width - root.inset("right") - gap : (root.worldW - width) / 2
        y: root.pillEdge === "top" ? root.inset("top") + gap : root.pillEdge === "bottom" ? root.worldH - height - root.inset("bottom") - gap : (root.worldH - height) / 2
        radius: Math.min(width, height) / 2
        color: Appearance?.colors.colLayer0 ?? "#1C1B1F"
        border.width: 1
        border.color: Appearance?.colors.colLayer0Border ?? "#33ffffff"
        AnoSpotFaces {
            id: faces
            anchors.fill: parent
            anchors.margins: 6
            vertical: root.pillVertical
            thickness: root.pillThickness
            maxLength: 800
            faces: ["status"]
            barMode: BarStyle.pillBar
        }
    }

    // ── The dock ────────────────────────────────────────────────────────
    Rectangle {
        id: dock
        visible: root.dockShown
        readonly property var apps: Config.options?.dock?.pinnedApps ?? []
        readonly property real len: apps.length * (root.dockIcon + 8) + 12
        width: root.dockVertical ? root.dockIcon + 16 : len
        height: root.dockVertical ? len : root.dockIcon + 16
        x: root.dockEdge === "left" ? root.inset("left") + 6 : root.dockEdge === "right" ? root.worldW - width - root.inset("right") - 6 : (root.worldW - width) / 2
        y: root.dockEdge === "top" ? root.inset("top") + 6 : root.dockEdge === "bottom" ? root.worldH - height - root.inset("bottom") - 6 : (root.worldH - height) / 2
        radius: Appearance?.rounding.large ?? 20
        color: Appearance?.colors.colLayer0 ?? "#1C1B1F"
        opacity: 0.95
        Grid {
            anchors.centerIn: parent
            spacing: 8
            columns: root.dockVertical ? 1 : Math.max(1, dock.apps.length)
            Repeater {
                model: dock.apps
                IconImage {
                    required property string modelData
                    implicitSize: root.dockIcon
                    source: FileUtils.appIcon(modelData)
                }
            }
        }
    }

    // ── Editing ─────────────────────────────────────────────────────────
    // A drop target edge, shown while something is dragged to another edge.
    Rectangle {
        id: edgeBand
        property string edge: ""
        visible: edge !== "" && drag.mode !== "module"
        readonly property real t: 64
        x: edge === "right" ? root.worldW - t : 0
        y: edge === "bottom" ? root.worldH - t : 0
        width: edge === "left" || edge === "right" ? t : root.worldW
        height: edge === "top" || edge === "bottom" ? t : root.worldH
        color: Appearance?.colors.colPrimary ?? "#D0BCFF"
        opacity: 0.25
        radius: 16
    }
    // The insertion marker for a module drag.
    Rectangle {
        id: slotMark
        visible: drag.mode === "module" && drag.slot !== null
        color: Appearance?.colors.colPrimary ?? "#D0BCFF"
        radius: 2
        width: root.barVertical ? root.barThickness - 8 : 4
        height: root.barVertical ? 4 : root.barThickness - 8
    }
    // What's being dragged, under the pointer.
    Rectangle {
        id: ghost
        visible: drag.active && drag.mode !== ""
        width: drag.mode === "module" ? 120 : 160
        height: 40
        radius: 20
        color: Appearance?.colors.colPrimaryContainer ?? "#4F378B"
        border.width: 1
        border.color: Appearance?.colors.colPrimary ?? "#D0BCFF"
        opacity: 0.92
        Text {
            anchors.centerIn: parent
            text: drag.mode === "module" ? BarModuleLoader.labelFor(drag.moduleId) : drag.mode === "bar" ? "Bar" : drag.mode === "pill" ? "Pill" : "Dock"
            color: Appearance?.colors.colOnPrimaryContainer ?? "#EADDFF"
            font.pixelSize: 18
            font.family: Appearance?.font.family.main ?? "sans-serif"
        }
    }

    function _nearestEdge(p) {
        const d = { top: p.y, bottom: root.worldH - p.y, left: p.x, right: root.worldW - p.x }
        return Object.keys(d).reduce((a, b) => d[a] <= d[b] ? a : b)
    }
    function _inRect(item, p) { return item.visible && p.x >= item.x && p.y >= item.y && p.x <= item.x + item.width && p.y <= item.y + item.height }

    MouseArea {
        id: drag
        anchors.fill: parent
        z: 100
        hoverEnabled: true // the miniature's own items get no hover (popouts, tooltips)
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        preventStealing: true

        property string mode: ""        // module | bar | pill | dock
        property string moduleId: ""
        property string fromGroup: ""
        property var slot: null
        property point start
        property bool active: false

        function world(mouse) { return Qt.point(mouse.x, mouse.y) } // this area lives in world coordinates

        onPressed: mouse => {
            const p = world(mouse)
            active = false; slot = null; mode = ""; moduleId = ""; fromGroup = ""
            start = p
            if (mouse.button !== Qt.LeftButton) return
            if (root._inRect(pill, p)) { mode = "pill"; return }
            if (root._inRect(dock, p)) { mode = "dock"; return }
            if (root.classic && root._inRect(barArea, p) && barContent.item) {
                const hit = barContent.item.previewHit(p.x - barArea.x, p.y - barArea.y)
                if (hit?.id) { mode = "module"; moduleId = hit.id; fromGroup = hit.gid }
                else { mode = "bar"; fromGroup = hit?.gid ?? "" }
            }
        }
        onPositionChanged: mouse => {
            if (!pressed || mode === "") return
            const p = world(mouse)
            if (!active && Math.hypot(p.x - start.x, p.y - start.y) < 12) return
            active = true
            ghost.x = p.x - ghost.width / 2
            ghost.y = p.y - ghost.height / 2
            if (mode === "module") {
                // Off the bar (more than its thickness away): no slot, a cancel.
                const near = root.barVertical ? Math.abs(p.x - (barArea.x + barArea.width / 2)) < root.barThickness * 2
                                              : Math.abs(p.y - (barArea.y + barArea.height / 2)) < root.barThickness * 2
                slot = near ? barContent.item.previewSlot(p.x - barArea.x, p.y - barArea.y) : null
                if (slot) {
                    const pos = root._slotPos(slot)
                    slotMark.x = pos.x - slotMark.width / 2 + barArea.x
                    slotMark.y = pos.y - slotMark.height / 2 + barArea.y
                }
            } else {
                edgeBand.edge = root._nearestEdge(p)
            }
        }
        onReleased: mouse => {
            const wasActive = active, m = mode, e = edgeBand.edge, s = slot, id = moduleId, from = fromGroup
            active = false; mode = ""; slot = null; edgeBand.edge = ""
            if (!wasActive) {
                if ((m === "bar" || m === "module") && from) root.groupClicked(from)
                return
            }
            if (m === "module" && s) root._moveModule(id, from, s.gid, s.before)
            else if (m === "bar" && e && e !== root.barEdge) Config.setNestedValue("bars.0.edge", e)
            else if (m === "pill" && e && e !== root.pillEdge) BarStyle.moveEdge("pill", e)
            else if (m === "dock" && e && e !== root.dockEdge) BarStyle.moveEdge("dock", e)
        }
        onCanceled: { active = false; mode = ""; slot = null; edgeBand.edge = "" }
        onWheel: w => w.accepted = false // the page scrolls
    }

    // Where the slot marker sits: between the modules around the slot.
    function _slotPos(slot) {
        const c = barContent.item
        const v = root.barVertical
        const groups = BarEdit.editable(root.barCfg)
        const g = groups.find(x => x.id === slot.gid)
        const list = g?.modules ?? []
        const end = g?.zone === "end"
        // The neighbour on screen: before `before` in list order is to the
        // right of the slot for an end zone.
        const nextId = end ? list[slot.before - 1] : list[slot.before]
        const prevId = end ? list[slot.before] : list[slot.before - 1]
        const rect = id => c.previewModuleRect(slot.gid, id)
        const n = nextId ? rect(nextId) : null, pr = prevId ? rect(prevId) : null
        const along = n && pr ? ((v ? pr.y + pr.h : pr.x + pr.w) + (v ? n.y : n.x)) / 2
                    : n ? (v ? n.y : n.x) - 4 : pr ? (v ? pr.y + pr.h : pr.x + pr.w) + 4 : (v ? root.worldH / 2 : root.worldW / 2)
        return v ? Qt.point(root.barThickness / 2, along) : Qt.point(along, root.barThickness / 2)
    }

    function _moveModule(id, fromId, toId, before) {
        const groups = BarEdit.editable(root.barCfg)
        const from = groups.find(g => g.id === fromId)?.modules ?? []
        const i = from.indexOf(id)
        if (i < 0) return
        const at = fromId === toId && i < before ? before - 1 : before
        if (fromId === toId && at === i) return
        Config.setNestedValue("bars.0.groups", BarEdit.moveModule(groups, id, fromId, toId, at))
    }
}
