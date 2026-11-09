import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import "reorder.js" as Reorder

/**
 * Multi-style dock — supports "pill" and "macos" styles.
 * Shows pinned apps + running apps from ToplevelManager.
 * Configurable position (top/bottom/left/right), auto-hide on hover,
 * show-on-desktop-only option, and app icon click-to-activate/launch.
 *
 * Ported from inir with simplification for compositor-agnostic use.
 */
Scope {
    id: root
    property bool pinned: Config.options?.dock?.pinnedOnStartup ?? false
    readonly property string position: BarStyle.dockEdge   // dock.position, "auto" resolved (opposite the pill-bar)
    readonly property bool isVertical: position === "left" || position === "right"
    readonly property bool isTop: position === "top"
    readonly property bool isLeft: position === "left"
    readonly property bool isPillStyle: (Config.options?.dock?.style ?? "pill") === "pill"
    readonly property bool isMacosStyle: (Config.options?.dock?.style ?? "pill") === "macos"
    readonly property real dockHeight: Config.options?.dock?.height ?? 44
    readonly property real iconSize: Config.options?.dock?.iconSize ?? 28
    readonly property var pinnedApps: Config.options?.dock?.pinnedApps ?? ["kitty", "nemo", "zen-browser", "brave-browser"]
    readonly property real globalMargin: Config.options?.appearance?.bezel ?? 0
    readonly property bool previews: Config.options?.dock?.previews ?? true

    // Running app list from ToplevelManager
    readonly property var runningAppIds: {
        const ids = new Set()
        for (const tl of ToplevelManager.toplevels.values) {
            if (tl.appId) ids.add(tl.appId)
        }
        return Array.from(ids)
    }

    // Merged list: pinned first, then running-only apps
    readonly property var dockItems: {
        const items = []
        // Pinned apps
        for (const appId of pinnedApps) {
            items.push({ appId: appId, pinned: true, running: runningAppIds.includes(appId) })
        }
        // Running but not pinned
        for (const appId of runningAppIds) {
            if (!pinnedApps.includes(appId)) {
                items.push({ appId: appId, pinned: false, running: true })
            }
        }
        return items
    }

    function activateApp(appId) {
        const tl = ToplevelManager.toplevels.values.find(t => t.appId === appId)
        if (tl) {
            CompositorService.focusWindow(tl)
        } else {
            // Not running: launch through its desktop entry when there is one
            // (the app id is often not the executable name).
            const entry = DesktopEntries.heuristicLookup(appId)
            if (entry) DefaultApps.launchEntry(entry)
            else DefaultApps.launch([appId], "", appId)
        }
    }

    Variants {
        model: {
            const screens = Quickshell.screens
            const list = Config.options?.dock?.screenList ?? []
            return (!list || list.length === 0) ? screens : screens.filter(s => list.includes(s.name))
        }

        PanelWindow {
            id: dockWindow
            required property var modelData
            screen: modelData
            visible: GlobalStates.shellSettled && !GlobalStates.screenLocked && (Config.options?.dock?.enable ?? false)

            readonly property bool hoverToReveal: Config.options?.dock?.hoverToReveal ?? true
            // Shows once the pointer has rested at the edge for dock.revealDelay
            // (a pass over it doesn't count); stays while the pointer is on it.
            property bool _rested: false
            Timer {
                id: restTimer
                interval: Config.options?.dock?.revealDelay ?? 150
                onTriggered: dockWindow._rested = dockHover.containsMouse
            }
            Connections {
                target: dockHover
                function onContainsMouseChanged() {
                    if (!dockHover.containsMouse) { restTimer.stop(); dockWindow._rested = false }
                    else if (dockWindow.reveal) dockWindow._rested = true
                    else restTimer.restart()
                }
            }
            readonly property bool screenFullscreen: {
                void CompositorService.fullscreenRevision
                return CompositorService.hasFullscreenOnScreen(modelData?.name ?? "")
            }
            // Never over a fullscreen window (pinned included: the dock is on
            // the overlay layer and would sit on top of a game).
            property bool reveal: !screenFullscreen && (root.pinned
                || (hoverToReveal && _rested) || _previewsOpen > 0
                || (Config.options?.dock?.showOnDesktop !== false && !ToplevelManager.activeToplevel?.activated))

            // Window previews open from this dock: they hold it up while the
            // pointer is on them (they are their own popup surface, so the
            // dock's hover area loses the pointer).
            property int _previewsOpen: 0

            // Dragging a pinned icon along the dock reorders the pins: the
            // dragged one follows the pointer, the ones it passes slide over,
            // and the order is written on release.
            property int dragFrom: -1
            property int dragTo: -1
            property real dragDelta: 0
            readonly property real slot: root.isVertical ? root.iconSize + 12 + dockLayout.rowSpacing
                                                         : root.iconSize + 8 + dockLayout.columnSpacing
            // The window list is leased while the dock shows, so it is already
            // filled when a preview opens.
            readonly property bool _wantWindows: visible && reveal && root.previews
            property bool _leased: false
            function _lease() {
                if (_wantWindows === _leased) return
                _leased = _wantWindows
                if (_leased) CompositorService.acquireWindows("dock"); else CompositorService.releaseWindows("dock")
            }
            on_WantWindowsChanged: _lease()
            Component.onCompleted: _lease()
            Component.onDestruction: if (_leased) CompositorService.releaseWindows("dock")

            color: "transparent"
            exclusiveZone: root.pinned && !screenFullscreen ? dockHeight : 0
            // Connected and hover-revealed, the window reaches the screen edge
            // itself (not pushed in by the frame band or a bar there), so the
            // pointer pushed against the edge finds the hover strip; the dock
            // still rests inside the band (edgeInset).
            readonly property bool edgeHover: PanelRegistry.enabled && !root.pinned && hoverToReveal
            WlrLayershell.exclusionMode: edgeHover ? ExclusionMode.Ignore : ExclusionMode.Normal
            readonly property real edgeInset: edgeHover ? PanelRegistry.inset(modelData?.name ?? "", root.position) + PanelRegistry.foreignInset(modelData?.name ?? "", root.position) : 0
            WlrLayershell.namespace: "quickshell:dock"
            // Overlay, like the bar: on Top it races the connected frame (also
            // Top) and the frame can paint over the dock's icons.
            WlrLayershell.layer: WlrLayer.Overlay

            anchors {
                top: root.isTop || root.isVertical
                bottom: !root.isTop || root.isVertical
                left: root.isLeft || !root.isVertical
                right: !root.isLeft || !root.isVertical
            }

            // Vertical bar fixes width, horizontal bar fixes height. 0 = let the
            // layout system pick the natural axis size.
            implicitWidth: root.isVertical ? (dockHeight + 16 + edgeInset) : 0
            implicitHeight: root.isVertical ? 0 : (dockHeight + 16 + edgeInset)

            // The hidden dock keeps an input area only when hovering is what
            // reveals it; otherwise it is click-through until shown.
            // Hidden, the dock has slid out of its window, so the hover target
            // is a thin strip on the edge where it rests (plus the dock itself
            // while it slides back, so the pointer doesn't drop off mid-way).
            mask: Region {
                item: (dockWindow.reveal || dockWindow.hoverToReveal) ? dockBg : null
                Region {
                    intersection: Intersection.Combine
                    // Not over a fullscreen window: it would take its clicks.
                    item: dockWindow.hoverToReveal && !dockWindow.screenFullscreen ? dockHotzone : null
                }
            }
            Item {
                id: dockHotzone
                readonly property real thick: 3
                x: root.isVertical ? (root.isLeft ? 0 : dockWindow.width - thick) : dockBg.x
                y: root.isVertical ? dockBg.y : (root.isTop ? 0 : dockWindow.height - thick)
                width: root.isVertical ? thick : dockBg.width
                height: root.isVertical ? dockBg.height : thick
            }

            MouseArea {
                id: dockHover
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton

                // Dock background. Emerges from its own edge on a spring (no
                // fade); in connected mode it sits flush on the edge and the
                // frame paints it, so it drops its own fill and border.
                SurfaceMaterial {
                    id: dockBg
                    surface: "dock"
                    readonly property bool connected: PanelRegistry.enabled
                    property real shown: dockWindow.reveal ? 1 : 0
                    Behavior on shown { id: shownMotion; MotionSpring { token: shownMotion.targetValue > 0.5 ? "liquid" : "settle" } }
                    readonly property real gap: (connected ? 0 : 8) + dockWindow.edgeInset
                    readonly property real hideShift: (1 - shown) * (root.dockHeight + gap)
                    width: root.isVertical ? root.dockHeight : dockLayout.implicitWidth + 24
                    height: root.isVertical ? dockLayout.implicitHeight + 24 : root.dockHeight
                    x: root.isVertical
                        ? (root.isLeft ? gap - hideShift : parent.width - width - gap + hideShift)
                        : (parent.width - width) / 2
                    y: root.isVertical
                        ? (parent.height - height) / 2
                        : (root.isTop ? gap - hideShift : parent.height - height - gap + hideShift)
                    radius: root.isPillStyle ? height / 2 : Appearance?.rounding.normal ?? 12
                    color: connected ? "transparent" : (Appearance?.colors.colLayer0 ?? "#1C1B1F")
                    border.width: connected ? 0 : Appearance.borders.width
                    border.color: Appearance.borders.color

                    ConnectedSurfaceLease {
                        id: dockLease
                        key: "dock:" + (dockWindow.modelData?.name ?? "")
                        kind: "dock"; edge: root.position; priority: 8
                        screenName: dockWindow.modelData?.name ?? ""
                        active: dockWindow.visible && dockBg.shown > 0.001
                        progress: dockBg.shown
                        surfaceRadius: root.isPillStyle ? Math.min(dockBg.width, dockBg.height) / 2 : undefined
                        // Where the layer shell actually puts the window: it is
                        // pushed in by the band and any bar on the same edge.
                        // Not a binding: see BarWindow._origin (binding loop).
                        property point _o: Qt.point(0, 0)
                        function _update() { _o = PanelRegistry.windowOrigin(dockWindow) }
                        readonly property Connections _watch: Connections {
                            target: PanelRegistry
                            function onRevisionChanged() { Qt.callLater(dockLease._update) }
                        }
                        readonly property Connections _watchWin: Connections {
                            target: dockWindow
                            function onWidthChanged() { Qt.callLater(dockLease._update) }
                            function onHeightChanged() { Qt.callLater(dockLease._update) }
                            function onExclusiveZoneChanged() { Qt.callLater(dockLease._update) }
                        }
                        x: _o.x + dockBg.x; y: _o.y + dockBg.y
                        // A pinned dock reserves its edge; insets (sidebars) count it.
                        reserve: dockWindow.exclusiveZone
                        w: dockBg.width; h: dockBg.height
                    }

                    // App items layout
                    // A row on top/bottom, a column on the sides. (A RowLayout
                    // can't stack vertically: Qt.TopToBottom isn't a
                    // LayoutDirection, so a side dock stayed a row.)
                    GridLayout {
                        id: dockLayout
                        anchors.centerIn: parent
                        columns: root.isVertical ? 1 : -1
                        rowSpacing: root.isMacosStyle ? 2 : 6
                        columnSpacing: root.isMacosStyle ? 2 : 6

                        Repeater {
                            model: root.dockItems

                            Item {
                                id: dockItem
                                required property var modelData
                                required property int index
                                Layout.preferredWidth: root.iconSize + 8
                                Layout.preferredHeight: root.iconSize + 12

                                readonly property bool dragged: dockWindow.dragFrom === dockItem.index
                                readonly property real _dragShift: dockItem.dragged ? dockWindow.dragDelta
                                    : Reorder.shift(dockItem.index, dockWindow.dragFrom, dockWindow.dragTo, dockWindow.slot)
                                z: dockItem.dragged ? 1 : 0
                                transform: Translate {
                                    x: root.isVertical ? 0 : dockItem._dragShift
                                    y: root.isVertical ? dockItem._dragShift : 0
                                    Behavior on x { enabled: !dockItem.dragged; MotionSpring { token: "snappy" } }
                                    Behavior on y { enabled: !dockItem.dragged; MotionSpring { token: "snappy" } }
                                }

                                // Magnification (dock.magnify): the icon under the
                                // pointer swells most, its neighbours less by distance,
                                // and each lifts off the edge as it grows. Off: only
                                // the hovered one grows a little.
                                readonly property real _pointer: dockHover.containsMouse
                                    ? (root.isVertical ? dockHover.mouseY : dockHover.mouseX) : -1e6
                                readonly property real _center: {
                                    void dockLayout.width; void dockLayout.height
                                    const p = dockItem.mapToItem(dockHover, dockItem.width / 2, dockItem.height / 2)
                                    return root.isVertical ? p.y : p.x
                                }
                                readonly property real magnify: {
                                    if (!(Config.options?.dock?.magnify ?? true)) return iconMA.containsMouse ? 1.15 : 1
                                    const reach = root.iconSize * 2.4
                                    const d = Math.abs(dockItem._pointer - dockItem._center)
                                    const t = Math.max(0, 1 - d / reach)
                                    return 1 + 0.35 * t * t * (3 - 2 * t) // smoothstep falloff
                                }
                                // Toward the screen's inside, away from the dock's edge.
                                readonly property real _lift: (dockItem.magnify - 1) * 18

                                // App icon
                                Rectangle {
                                    id: iconBg
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.top: parent.top
                                    width: root.iconSize + 4; height: root.iconSize + 4
                                    radius: root.isMacosStyle ? Appearance?.rounding.small ?? 8 : (root.iconSize + 4) / 2
                                    color: iconMA.containsMouse
                                        ? Appearance?.colors.colLayer1Hover ?? "#E5DFED"
                                        : "transparent"

                                    scale: iconMA.pressed ? 0.85 : dockItem.magnify
                                    Behavior on scale { MotionSpring { token: "snappy" } } // retargets as the pointer runs along the dock
                                    transform: Translate {
                                        x: root.isVertical ? (root.isLeft ? dockItem._lift : -dockItem._lift) : 0
                                        y: root.isVertical ? 0 : (root.isTop ? dockItem._lift : -dockItem._lift)
                                        Behavior on x { MotionSpring { token: "snappy" } }
                                        Behavior on y { MotionSpring { token: "snappy" } }
                                    }
                                    Behavior on color { ColorAnimation { duration: AnimationConfig.scaledDuration(100) } }

                                    // Desktop icon from freedesktop
                                    IconImage {
                                        anchors.centerIn: parent
                                        implicitWidth: root.iconSize
                                        implicitHeight: root.iconSize
                                        source: FileUtils.appIcon(modelData.appId)
                                    }

                                    MouseArea {
                                        id: iconMA
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: dockItem.dragged ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                                        preventStealing: true
                                        // Press position, in the layout (it doesn't move
                                        // with the icon, which follows the pointer).
                                        property point _press
                                        property bool _wasDrag: false
                                        function _endDrag() {
                                            dockWindow.dragFrom = -1; dockWindow.dragTo = -1; dockWindow.dragDelta = 0
                                        }
                                        onPressed: mouse => { _press = mapToItem(dockLayout, mouse.x, mouse.y); _wasDrag = false }
                                        onPositionChanged: mouse => {
                                            if (!pressed || !dockItem.modelData.pinned) return
                                            const p = mapToItem(dockLayout, mouse.x, mouse.y)
                                            const d = root.isVertical ? p.y - _press.y : p.x - _press.x
                                            if (!dockItem.dragged) {
                                                // Threshold: a click that wobbles stays a click.
                                                if (Math.abs(d) < 8 || dockWindow.dragFrom >= 0) return
                                                dockWindow.dragFrom = dockItem.index
                                            }
                                            dockWindow.dragDelta = d
                                            dockWindow.dragTo = Reorder.target(dockItem.index, d, dockWindow.slot, root.pinnedApps.length)
                                        }
                                        onReleased: {
                                            if (!dockItem.dragged) return
                                            _wasDrag = true
                                            const from = dockWindow.dragFrom, to = dockWindow.dragTo
                                            _endDrag()
                                            // Later: the write rebuilds the icons, this one included.
                                            if (to !== from) Qt.callLater(() => Config.setNestedValue("dock.pinnedApps", Reorder.move(root.pinnedApps, from, to)))
                                        }
                                        onCanceled: if (dockItem.dragged) _endDrag()
                                        onClicked: if (!_wasDrag) root.activateApp(modelData.appId)
                                    }

                                    StyledToolTip {
                                        text: modelData.appId
                                        // A running app's preview names its windows instead.
                                        visible: iconMA.containsMouse && !dockItem.hasPreview
                                    }
                                }

                                // Running indicator dot
                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.bottom
                                    width: modelData.running ? 6 : 0
                                    height: 4; radius: 2
                                    color: Appearance?.colors.colPrimary ?? "#65558F"
                                    visible: modelData.running
                                    Behavior on width { NumberAnimation { duration: AnimationConfig.scaledDuration(150) } }
                                }

                                // Window previews (dock.previews): the app's windows,
                                // live, after a rest on its icon; above the icon, or
                                // beside it on a side dock. Made only while hovered or
                                // open, kept a moment after it closes so it can retract.
                                readonly property bool hasPreview: root.previews && modelData.running
                                Timer { id: previewDwell; interval: 350; running: iconMA.containsMouse }
                                Timer { id: previewRetract; interval: 400 }
                                Loader {
                                    id: previewLoader
                                    anchors.fill: parent
                                    readonly property bool open: item?.effectiveShown ?? false
                                    onOpenChanged: {
                                        dockWindow._previewsOpen += open ? 1 : -1
                                        if (!open) previewRetract.restart()
                                    }
                                    Component.onDestruction: if (open) dockWindow._previewsOpen -= 1
                                    active: dockItem.hasPreview && (iconMA.containsMouse || open || previewRetract.running)
                                    sourceComponent: BarModulePopout {
                                        id: preview
                                        shown: iconMA.containsMouse && !iconMA.pressed && !previewDwell.running
                                        popupWidth: strip.implicitWidth + 24
                                        popupHeight: strip.implicitHeight + 24
                                        WindowStrip {
                                            id: strip
                                            active: preview.effectiveShown
                                            thumbW: 200; thumbH: 120
                                            closeOnMiddleClick: true
                                            maxWidth: root.isVertical ? 420 : (dockWindow.screen?.width ?? 1280) * 0.8
                                            Binding on windows {
                                                when: strip.active
                                                restoreMode: Binding.RestoreNone
                                                value: CompositorService.windows.filter(w => w.appId === dockItem.modelData.appId).slice(0, 6)
                                            }
                                            onActivated: preview.dismiss()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "dock"
        function toggle(): void { root.pinned = !root.pinned }
        function pin(): void { root.pinned = true }
        function unpin(): void { root.pinned = false }
    }
}
