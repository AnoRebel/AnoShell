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
                || (hoverToReveal && _rested)
                || (Config.options?.dock?.showOnDesktop !== false && !ToplevelManager.activeToplevel?.activated))

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
                                required property var modelData
                                Layout.preferredWidth: root.iconSize + 8
                                Layout.preferredHeight: root.iconSize + 12

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

                                    scale: iconMA.pressed ? 0.85 : (iconMA.containsMouse ? 1.15 : 1)
                                    Behavior on scale { MotionSpring { token: "snappy" } } // retargets as the pointer runs along the dock
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
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.activateApp(modelData.appId)
                                    }

                                    StyledToolTip {
                                        text: modelData.appId
                                        visible: iconMA.containsMouse
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
