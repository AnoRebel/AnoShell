pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "pet.js" as Pet

/**
 * The desktop pet (pet.*; spec desktop-pet): a duck, a cat or a dog on one screen, standing on the bottom of the area
 * the bars leave free, and on window tops where the compositor reports where windows are (Hyprland, sway).
 *
 * Windows, all on the Top layer, Normal exclusion (so inside the bars):
 *  - probe: the usable area's size, never drawn on or clicked;
 *  - strip: a box around the pet on its floor, moving with it; it draws the pet while it stands or walks and takes
 *    input only on its body (petting, carrying, right-click).
 *  - air: the whole usable area, no input, mapped only while the pet is carried or falls. The strip keeps the
 *    pointer grab during a carry (it stays put), so coordinates stay steady.
 * Hidden (nothing mapped, no ticking) while a window is fullscreen on that screen or the screen is locked.
 * Inspired by Anserin's desktop duck (reimplemented, original art).
 */
Scope {
    id: root
    readonly property var opts: Config.options?.pet ?? ({})
    readonly property string kind: Pet.kindOf(root.opts.kind)
    readonly property string preset: root.opts.colors?.[root.kind] ?? ""
    readonly property real size: Math.max(64, Math.min(256, root.opts.size ?? 128))
    // The configured screen, else the one focused when the pet appeared.
    property string _startScreen: ""
    readonly property var screen: Quickshell.screens.find(s => s.name === root.opts.screen)
        ?? Quickshell.screens.find(s => s.name === root._startScreen) ?? Quickshell.screens[0]
    readonly property string screenName: root.screen?.name ?? ""
    readonly property bool hidden: GlobalStates.screenLocked || (void CompositorService.fullscreenRevision, CompositorService.hasFullscreenOnScreen(root.screenName))
    property bool editorOpen: false

    IpcHandler {
        target: "pet"
        function act(name: string): void { actor.act(name) }
        function editor(): void { root.editorOpen = !root.editorOpen }
        // Where it is and what it does (area px; the area's origin in layout px where known).
        function state(): string {
            return JSON.stringify({ kind: root.kind, layer: root.layerMode, drawn: root.drawLayer, why: { panel: root._panelOver, maximised: root._maximised, moving: root._moving, windows: root._screenWindows.length, focus: root.focusGeo }, behaviour: actor.behaviour, mode: actor.mode, x: Math.round(actor.x0),
                y: Math.round(actor.y0), floor: actor.floorId, facing: actor.facing, hidden: root.hidden, ticking: actor.live, floors: root.floors.map(f => [f.id, Math.round(f.x1), Math.round(f.x2), Math.round(f.y)]), screen: root.screenName,
                area: [root.areaW, root.areaH], origin: root.reserved ? [root.originX, root.originY] : null })
        }
    }
    Connections {
        target: GlobalStates
        function onPetAction(name) { actor.act(name) }
    }

    // Usable area: its size from the probe; its top-left in layout coordinates where the backend can say.
    readonly property real areaW: probe.width
    readonly property real areaH: probe.height
    // Behind windows ("below") it stands only on the ground.
    readonly property bool windowFloors: (CompositorService.supports.windowGeometry ?? false) && !root.hidden && root.layerMode !== "below"
    // auto watches windows too (maximised, moving), where the compositor reports them.
    // (A window being moved only needs the focused one's geometry, which every window list has.)
    readonly property bool _wantWindows: !root.hidden && (root.windowFloors || root.layerMode === "auto")
    readonly property var reserved: CompositorService.reservedOf(root.screenName)
    readonly property real originX: (root.screen?.x ?? 0) + (root.reserved?.[0] ?? 0)
    readonly property real originY: (root.screen?.y ?? 0) + (root.reserved?.[1] ?? 0)
    // The compositor tracks windows only while someone holds a lease.
    property bool _leased: false
    function _lease() {
        if (root._wantWindows === root._leased) return
        root._leased = root._wantWindows
        root._leased ? CompositorService.acquireWindows("pet") : CompositorService.releaseWindows("pet")
    }
    on_WantWindowsChanged: root._lease()
    Component.onCompleted: { root._startScreen = CompositorService.focusedMonitorName; root._lease(); root.drawLayer = root._wantLayer }
    Component.onDestruction: if (root._leased) CompositorService.releaseWindows("pet")
    readonly property var floors: Pet.floors(root.windowFloors && root.reserved ? CompositorService.windowsOnOutput(root.screenName) : [],
        root.originX, root.originY, root.areaW, root.areaH, root.size)

    // ── Stacking (pet.layer; pet.js layerFor) ──
    // Top (over windows) or Bottom (on the desktop, behind them). Never over a
    // shell panel in any mode: in connected mode the frame draws panel bodies on
    // the Top layer too, and two Top surfaces stack by map order, so the pet goes
    // to Bottom while a registered panel overlaps it. Back 1 s after nothing holds.
    readonly property string layerMode: Pet.layerOf(root.opts.layer)
    readonly property real _offL: root.reserved?.[0] ?? PanelRegistry.inset(root.screenName, "left")
    readonly property real _offT: root.reserved?.[1] ?? PanelRegistry.inset(root.screenName, "top")
    readonly property bool _panelOver: Pet.panelOver(PanelRegistry.panels, root.screenName,
        { x: root._offL + actor.x0 - root.size * 0.6, y: root._offT + actor.y0 - root.size, w: root.size * 1.2, h: root.size })
    readonly property var _screenWindows: root._leased ? CompositorService.windowsOnOutput(root.screenName) : []
    readonly property bool _maximised: root.layerMode === "auto" && root.reserved !== null
        && Pet.maximisedOver(root._screenWindows, root.originX, root.originY, root.areaW, root.areaH, actor.x0)
    // A window being moved or resized: the focused one's geometry changing.
    property bool _moving: false
    property string _focusGeo: ""
    readonly property string focusGeo: {
        if (root.layerMode !== "auto") return ""
        const w = root._screenWindows.find(w => w.focused)
        return w ? `${w.id}|${w.x},${w.y},${w.width},${w.height}` : ""
    }
    onFocusGeoChanged: {
        const was = root._focusGeo; root._focusGeo = root.focusGeo
        if (was && root.focusGeo && was.split("|")[0] === root.focusGeo.split("|")[0]) { root._moving = true; movingEnd.restart() }
    }
    Timer { id: movingEnd; interval: 700; onTriggered: root._moving = false }
    // Hyprland sends no event while a window is dragged: ask it (a socket request,
    // no process) three times a second, only in auto with the pet shown.
    // ponytail: sway and mango report no moves at all, so there only the window list's own updates count.
    property var _lastGeo: null
    Timer {
        interval: 300
        repeat: true
        running: root.layerMode === "auto" && !root.hidden && CompositorService.compositor === "hyprland"
        onTriggered: CompositorService.focusedWindowGeometry(g => {
            const was = root._lastGeo; root._lastGeo = g
            if (g && was && g.id === was.id && (g.x !== was.x || g.y !== was.y || g.width !== was.width || g.height !== was.height)) {
                root._moving = true; movingEnd.restart()
            }
        })
    }
    readonly property string _wantLayer: Pet.layerFor(root.layerMode, { panel: root._panelOver, maximised: root._maximised, moving: root._moving })
    property string drawLayer: "top"
    on_WantLayerChanged: {
        if (root._wantLayer === "bottom") { backOnTop.stop(); root._toLayer("bottom") }
        else backOnTop.restart()
    }
    Timer { id: backOnTop; interval: 1000; onTriggered: root._toLayer(root._wantLayer) }
    // A layer surface keeps the layer it was made on (changing it live went one way
    // only): its windows are unmapped for a frame and come back on the new one. The
    // pet's place and pose live in the actor, so nothing jumps. Not mid-carry (the
    // grab would go): it waits for the release.
    property bool _remap: false
    function _toLayer(l) {
        if (l === root.drawLayer) return
        if (mouse.pressed) { layerRetry.restart(); return }
        root._remap = true
        root.drawLayer = l
        Qt.callLater(() => root._remap = false)
    }
    Timer { id: layerRetry; interval: 200; onTriggered: root._toLayer(root._wantLayer) }
    readonly property int wlLayer: root.drawLayer === "bottom" ? WlrLayer.Bottom : WlrLayer.Top

    PetActor {
        id: actor
        kind: root.kind
        size: root.size
        floors: root.floors
        areaWidth: root.areaW
        live: !root.hidden && root.areaH > 0
        soundOn: root.opts.sound ?? false
        chase: (root.opts.chase ?? true) && (CompositorService.supports.cursorPos ?? false)
        pointerFn: cb => {
            if (!CompositorService.cursorPos(c => cb(c ? { x: c.x - root.originX, y: c.y - root.originY } : null))) cb(null)
        }
        onLanded: handoff.restart()
        onModeChanged: if (actor.mode !== "act") root.inAir = true
    }

    // It appears in the middle of the ground once the area is measured.
    property bool _placed: false
    function _place() {
        if (root._placed || !(root.areaW > 0 && root.areaH > 0)) return
        actor.x0 = root.areaW / 2; actor.y0 = root.areaH; root._placed = true
    }
    onAreaWChanged: root._place()
    onAreaHChanged: root._place()

    // In the air (carried, falling, or just landed until the strip has moved under it).
    property bool inAir: false
    Timer { id: handoff; interval: 90; onTriggered: root.inAir = actor.mode !== "act" }

    PanelWindow {
        id: probe
        screen: root.screen
        visible: !root.hidden
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.namespace: "quickshell:pet-area"
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: 0
        anchors { top: true; bottom: true; left: true; right: true }
        mask: Region {}
    }

    // The strip along the floor.
    PanelWindow {
        id: strip
        screen: root.screen
        visible: !root.hidden && root.areaH > 0 && !root._remap
        color: "transparent"
        WlrLayershell.layer: root.wlLayer
        WlrLayershell.namespace: "quickshell:pet"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: 0
        anchors { top: true; left: true }
        // A box around the pet on its floor, moving with it (a box this size redraws far less than the whole floor);
        // while the pointer holds the pet it stays put, keeping the grab and steady coordinates.
        readonly property var floor: actor.floor()
        readonly property real stripW: Math.ceil(root.size * 1.7)
        readonly property real stripH: Math.ceil(root.size * 1.7)
        readonly property real wantLeft: Math.round(Math.max(0, Math.min(root.areaW - strip.stripW, actor.x0 - strip.stripW / 2)))
        readonly property real wantTop: Math.round(strip.floor.y - strip.stripH)
        property real left: 0
        property real top: 0
        function follow() { if (!mouse.pressed) { strip.left = strip.wantLeft; strip.top = strip.wantTop } }
        onWantLeftChanged: strip.follow()
        onWantTopChanged: strip.follow()
        Component.onCompleted: strip.follow()
        Connections { target: mouse; function onPressedChanged() { strip.follow() } }
        margins.left: strip.left
        margins.top: strip.top
        implicitWidth: strip.stripW
        implicitHeight: strip.stripH
        mask: Region { item: hit }

        readonly property real petX: actor.x0 - strip.left - root.size / 2
        readonly property real petY: actor.y0 - strip.top - root.size

        PetRig {
            id: rig
            visible: !root.inAir
            x: strip.petX; y: strip.petY
            size: root.size
            kind: root.kind; preset: root.preset
            p: actor.p; facing: actor.facing; t: actor.clock
            say: actor.say; hearts: actor.hearts
        }
        // Input on the body only; it stays where the pet was grabbed during a carry.
        Item {
            id: hit
            readonly property var box: Pet.bodyBox(root.size, actor.facing)
            property real heldX: 0
            x: (mouse.pressed ? hit.heldX : strip.petX) + hit.box.x
            y: strip.petY + hit.box.y
            width: root.inAir && !mouse.pressed ? 0 : hit.box.w
            height: hit.box.h
            MouseArea {
                id: mouse
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: mouse.carrying ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                preventStealing: true
                property bool carrying: false
                property real sx: 0
                property real sy: 0
                // Area px of a point in this item.
                function area(mx, my) {
                    return { x: strip.left + hit.x + mx, y: strip.top + hit.y + my }
                }
                onPressed: ev => {
                    hit.heldX = strip.petX
                    mouse.sx = ev.x; mouse.sy = ev.y
                    mouse.carrying = false
                    if (ev.button === Qt.RightButton) root.editorOpen = !root.editorOpen
                }
                onPositionChanged: ev => {
                    if (!(ev.buttons & Qt.LeftButton)) return
                    const a = mouse.area(ev.x, ev.y)
                    if (!mouse.carrying && Math.hypot(ev.x - mouse.sx, ev.y - mouse.sy) > 6) {
                        mouse.carrying = true
                        const g = mouse.area(mouse.sx, mouse.sy)
                        actor.grab(g.x, g.y)
                    }
                    if (mouse.carrying) actor.drag(a.x, a.y)
                }
                onReleased: ev => {
                    if (ev.button !== Qt.LeftButton) return
                    if (mouse.carrying) actor.release()
                    else if (Pet.onHead(root.kind, hit.box.x + ev.x, hit.box.y + ev.y, root.size, actor.facing)) actor.petIt()
                    else actor.act("look")
                    mouse.carrying = false
                }
                onCanceled: { if (mouse.carrying) actor.release(); mouse.carrying = false }
            }
        }
    }

    // The whole area, drawn only while the pet is in the air.
    PanelWindow {
        id: air
        screen: root.screen
        visible: !root.hidden && root.inAir && !root._remap
        color: "transparent"
        WlrLayershell.layer: root.wlLayer
        WlrLayershell.namespace: "quickshell:pet-air"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: 0
        anchors { top: true; bottom: true; left: true; right: true }
        mask: Region {}
        PetRig {
            x: actor.x0 - root.size / 2; y: actor.y0 - root.size
            size: root.size
            kind: root.kind; preset: root.preset
            p: actor.p; facing: actor.facing; t: actor.clock
            say: actor.say; hearts: actor.hearts
        }
    }

    // Right-click: the editor beside the pet.
    PanelWindow {
        id: editorWin
        screen: root.screen
        visible: root.editorOpen && !root.hidden
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell:pet-editor"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: 0
        anchors { top: true; left: true }
        implicitWidth: 380
        implicitHeight: card.implicitHeight
        // Where the pet was when it opened: above it when there's room, else beside it on the roomier side.
        property real px: 0
        property real py: 0
        Connections {
            target: root
            function onEditorOpenChanged() { if (root.editorOpen) { editorWin.px = actor.x0; editorWin.py = actor.y0 } }
        }
        readonly property bool above: editorWin.py - root.size - card.implicitHeight - 12 >= 8
        margins.left: Math.round(Math.max(8, Math.min(root.areaW - 388, editorWin.above ? editorWin.px - 190
            : editorWin.px > root.areaW / 2 ? editorWin.px - root.size / 2 - 392 : editorWin.px + root.size / 2 + 12)))
        margins.top: Math.round(Math.max(8, editorWin.above ? editorWin.py - root.size - card.implicitHeight - 12
            : Math.min(root.areaH - card.implicitHeight - 8, editorWin.py - card.implicitHeight)))
        Rectangle {
            id: card
            width: parent.width
            implicitHeight: col.implicitHeight + 24
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1
            border.width: 1; border.color: Appearance.colors.colOutlineVariant
            focus: true
            Keys.onEscapePressed: root.editorOpen = false
            Column {
                id: col
                x: 12; y: 12; width: parent.width - 24
                spacing: 6
                Item {
                    width: parent.width; height: 28
                    StyledText { anchors.verticalCenter: parent.verticalCenter; text: "Desktop pet"; font.pixelSize: Appearance.font.pixelSize.normal; font.weight: Font.DemiBold; color: Appearance.colors.colOnLayer1 }
                    RippleButton {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        implicitWidth: 28; implicitHeight: 28
                        buttonRadius: 14
                        onClicked: root.editorOpen = false
                        contentItem: MaterialSymbol { anchors.centerIn: parent; text: "close"; iconSize: 18; color: Appearance.colors.colOnLayer1 }
                    }
                }
                PetEditor { width: parent.width; showEnable: false }
            }
        }
    }
}
