import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects
import qs
import qs.modules.common
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
    readonly property string position: Config.options?.dock?.position ?? "bottom"
    readonly property bool isVertical: position === "left" || position === "right"
    readonly property bool isTop: position === "top"
    readonly property bool isLeft: position === "left"
    readonly property bool isPillStyle: (Config.options?.dock?.style ?? "pill") === "pill"
    readonly property bool isMacosStyle: (Config.options?.dock?.style ?? "pill") === "macos"
    readonly property real dockHeight: Config.options?.dock?.height ?? 56
    readonly property real iconSize: Config.options?.dock?.iconSize ?? 40
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
            if (entry) entry.execute()
            else Quickshell.execDetached([appId])
        }
    }

    // App ids are often not icon names (zen → zen-browser, brave-browser →
    // brave-desktop): ask the desktop entry first.
    // Reads the entry list so bindings re-run once desktop entries load (they
    // load asynchronously; a lookup before that returns null).
    function iconFor(appId) {
        void DesktopEntries.applications.values.length
        return DesktopEntries.heuristicLookup(appId)?.icon || appId
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
            visible: !GlobalStates.screenLocked && (Config.options?.dock?.enable ?? true)

            readonly property bool hoverToReveal: Config.options?.dock?.hoverToReveal ?? true
            property bool reveal: root.pinned
                || (hoverToReveal && dockHover.containsMouse)
                || (Config.options?.dock?.showOnDesktop !== false && !ToplevelManager.activeToplevel?.activated)

            color: "transparent"
            exclusiveZone: root.pinned ? dockHeight : 0
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
            implicitWidth: root.isVertical ? (dockHeight + 16) : 0
            implicitHeight: root.isVertical ? 0 : (dockHeight + 16)

            // The hidden dock keeps an input area only when hovering is what
            // reveals it; otherwise it is click-through until shown.
            mask: Region { item: (dockWindow.reveal || dockWindow.hoverToReveal) ? dockBg : null }

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
                    readonly property real gap: connected ? 0 : 8
                    property real shown: dockWindow.reveal ? 1 : 0
                    Behavior on shown { MotionSpring { token: dockWindow.reveal ? "liquid" : "settle" } }
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
                    border.width: connected ? 0 : 1
                    border.color: Appearance?.colors.colLayer0Border ?? "#44444488"

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
                    RowLayout {
                        id: dockLayout
                        anchors.centerIn: parent
                        spacing: root.isMacosStyle ? 2 : 6
                        layoutDirection: root.isVertical ? Qt.TopToBottom : Qt.LeftToRight

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
                                    Behavior on scale { NumberAnimation { duration: AnimationConfig.scaledDuration(120); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }
                                    Behavior on color { ColorAnimation { duration: AnimationConfig.scaledDuration(100) } }

                                    // Desktop icon from freedesktop
                                    IconImage {
                                        anchors.centerIn: parent
                                        implicitWidth: root.iconSize
                                        implicitHeight: root.iconSize
                                        source: `image://icon/${root.iconFor(modelData.appId)}`
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
