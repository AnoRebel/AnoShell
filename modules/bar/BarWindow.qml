import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.anoScreen
import "."
import "BarLayout.js" as BarLayout

/**
 * BarWindow — A single bar instance on a given screen edge.
 * Supports top/bottom/left/right edges, auto-hide, and configurable margins.
 */
PanelWindow {
    id: barRoot
    required property var barConfig
    required property int barIndex

    // Edge config
    readonly property string edge: barConfig?.edge ?? "top"
    readonly property bool isVertical: edge === "left" || edge === "right"
    readonly property bool isBottom: edge === "bottom"
    readonly property bool isRight: edge === "right"
    readonly property bool autoHide: barConfig?.autoHide ?? Config.options?.bar?.autoHide?.enable ?? false
    readonly property bool showBackground: barConfig?.showBackground ?? Config.options?.bar?.showBackground ?? true
    readonly property real globalMargin: Config.options?.appearance?.bezel ?? 0

    // Sizing (configurable per-bar → global fallback → Appearance default)
    readonly property real barThickness: barConfig?.height ?? Config.options?.bar?.layout?.height ?? (isVertical ? Appearance.sizes.verticalBarWidth : Appearance.sizes.barHeight)
    readonly property real barRadius: barConfig?.radius ?? Config.options?.bar?.layout?.radius ?? Appearance?.rounding.normal ?? 12
    readonly property real effectiveThickness: barThickness + (showBackground ? globalMargin * 2 : 0) + formMargin

    // Bar form (BarContent/BarLayout): floating forms (fit, islands) sit off
    // the edge by formMargin, which springs so switching forms is continuous.
    readonly property real _formMarginTarget: barContentLoader.item?.edgeMargin ?? 0
    property real formMargin: _formMarginTarget
    Behavior on formMargin { MotionSpring { token: "liquid" } }
    readonly property string form: barContentLoader.item?.form ?? "full"

    // The bar's bodies (attached segments + islands) in window coordinates.
    readonly property var bodies: (barContentLoader.item?.bodyRects ?? []).map(r => ({
        x: r.x + barContentLoader.x, y: r.y + barContentLoader.y, w: r.w, h: r.h,
        island: r.island, id: r.id, sep: r.sep }))
    // One edge-to-edge body: the classic bar, drawn by the plain Rectangle path.
    readonly property bool plainBody: bodies.length <= 1 && !(bodies[0]?.island ?? false)
        && form === "full" && formMargin < 0.5

    // Auto-hide hover tracking: stays shown for bar.autoHide.delay after the
    // pointer leaves, so brushing past the edge doesn't flicker it away.
    property bool mustShow: hoverArea.containsMouse || hideDelay.running
    Timer {
        id: hideDelay
        interval: Config.options?.bar?.autoHide?.delay ?? 1000
    }
    Connections {
        target: hoverArea
        function onContainsMouseChanged() { if (!hoverArea.containsMouse) hideDelay.restart() }
    }

    // Hide the bar while a window is fullscreen on this bar's screen (unless the
    // pointer is over the bar). Compositor-agnostic via CompositorService. When
    // hidden the bar slides out AND drops its exclusive zone, so a fullscreen app
    // truly gets the whole screen. Toggle: bar.hideOnFullscreen (default on).
    readonly property bool hideOnFullscreen: Config.options?.bar?.hideOnFullscreen ?? true
    readonly property string _screenName: barRoot.screen?.name ?? ""
    readonly property bool screenFullscreen: {
        void CompositorService.fullscreenRevision
        return hideOnFullscreen && CompositorService.hasFullscreenOnScreen(_screenName)
    }
    // Treated exactly like auto-hide: revealed on hover, hidden otherwise.
    readonly property bool effectiveHidden: (autoHide || screenFullscreen) && !mustShow

    // In connected mode the AnoScreen frame shader paints this bar's fill, its
    // concave junction arcs into the screen frame, and the whole silhouette's M3
    // shadow. Drawing our own background/border/shadow/corners on top of that
    // re-creates the floating pill outline the mode exists to remove — so all
    // per-widget chrome is FLOATING-MODE ONLY.
    readonly property bool connectedMode: PanelRegistry.enabled
    readonly property bool drawChrome: showBackground && !connectedMode

    // Index, not the bar's id: bars are keyed by index (BarManager), so when a
    // bar is removed the next one moves into this window, and a layer surface
    // can't change its namespace after creation.
    WlrLayershell.namespace: `quickshell:bar:${barIndex}`
    // Overlay (above Top) so the bar always draws above the connected-corners
    // frame (AnoScreen, on Top). Two same-layer surfaces order by commit time,
    // which let the frame cover the bar content until a hover event; Overlay makes
    // the bar deterministically win.
    WlrLayershell.layer: WlrLayer.Overlay

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    // Reserve the top space only once the (async) bar content has actually
    // loaded — otherwise the exclusion zone appears a frame or two before the
    // bar visuals, so the desktop reflows to make room while the strip is still
    // blank (the "top space removed, then bar appears" flicker). Gating on
    // contentLoaded makes the reserved space and the bar appear together.
    readonly property bool contentLoaded: barContentLoader.status === Loader.Ready
    // The target margin, not the spring: an animating zone would make the
    // compositor re-lay out every tiled window on each frame.
    exclusiveZone: effectiveHidden || !contentLoaded ? 0 : barThickness + globalMargin + _formMarginTarget

    // Anchoring based on edge
    anchors {
        top: (edge === "top" || isVertical)
        bottom: (edge === "bottom" || isVertical)
        left: (edge === "left" || !isVertical)
        right: (edge === "right" || !isVertical)
    }

    // Only the thickness axis needs an implicit size; the other axis is
    // governed by the 3-edge layershell anchors. (undefined → int warns
    // in Quickshell 0.3.0; 0 is overridden by the anchors anyway.)
    implicitWidth: isVertical ? effectiveThickness : 0
    implicitHeight: isVertical ? 0 : effectiveThickness

    margins {
        top: (edge !== "top" && !isVertical) ? 0 : globalMargin
        bottom: (edge !== "bottom" && !isVertical) ? 0 : globalMargin
        left: (edge !== "left" && isVertical) ? 0 : globalMargin
        right: (edge !== "right" && isVertical) ? 0 : globalMargin
    }

    // Input only where the bar is drawn: gaps between islands click through.
    // While hidden, the slid-out content keeps the old hover strip behaviour.
    mask: barRoot.effectiveHidden || barRoot.plainBody ? hoverRegion : bodyRegion
    Region { id: hoverRegion; item: hoverMask }
    Region {
        id: bodyRegion
        BodyRegion { b: barRoot.bodies[0] }
        BodyRegion { b: barRoot.bodies[1] }
        BodyRegion { b: barRoot.bodies[2] }
        BodyRegion { b: barRoot.bodies[3] }
        BodyRegion { b: barRoot.bodies[4] }
        BodyRegion { b: barRoot.bodies[5] }
        BodyRegion { b: barRoot.bodies[6] }
        BodyRegion { b: barRoot.bodies[7] }
    }
    component BodyRegion: Region {
        property var b
        intersection: Intersection.Combine
        x: b ? b.x : 0; y: b ? b.y : 0
        width: b ? b.w : 0; height: b ? b.h : 0
    }

    // How a body joins the frame: islands and floating forms keep their own
    // rect and meet the edge through a liquid neck instead of being clamped.
    function _detached(b) { return b.island || barRoot.formMargin > 0.5 }
    readonly property real _neckBase: Math.max(8, (barContentLoader.item?.groupGap ?? 10) * 1.4)
    // An island's neck thins to nothing as it finishes separating; bodies
    // that float off the edge keep the full neck to the frame.
    function _neckK(b) { return b.island ? BarLayout.neckK(barRoot._neckBase, b.sep) : barRoot._neckBase }

    // Connected mode: the frame paints every body, following the auto-hide
    // slide (hideOffset ≤ 0 pushes it out). Body 0 carries the reserved space.
    // Recomputed a turn after anything it depends on changes, not as a binding:
    // reading the window's own geometry inside its binding re-entered it (a
    // binding loop) at startup.
    property point _origin: Qt.point(0, 0)
    function _updateOrigin() { barRoot._origin = PanelRegistry.windowOrigin(barRoot) }
    onWidthChanged: Qt.callLater(_updateOrigin)
    onHeightChanged: Qt.callLater(_updateOrigin)
    onScreenChanged: Qt.callLater(_updateOrigin)
    onExclusiveZoneChanged: Qt.callLater(_updateOrigin)
    Connections {
        target: PanelRegistry
        function onRevisionChanged() { Qt.callLater(barRoot._updateOrigin) }
    }
    // Fixed slots, switched on and off: an Instantiator would destroy and
    // recreate every lease when the body count changes, leaving the frame
    // without a bar for a frame.
    BarLease { index: 0 }
    BarLease { index: 1 }
    BarLease { index: 2 }
    BarLease { index: 3 }
    BarLease { index: 4 }
    BarLease { index: 5 }
    BarLease { index: 6 }
    BarLease { index: 7 }
    component BarLease: ConnectedSurfaceLease {
        property int index
        readonly property var _b: barRoot.bodies[index] ?? null
        key: `bar:${barRoot.barConfig?.id ?? barRoot.barIndex}:${barRoot._screenName}:${index}`
        kind: "bar"; edge: barRoot.edge; priority: _b?.island ? 19 : 20
        screenName: barRoot._screenName
        // Slot 0 stays published without a body so the bar's reserved space
        // never lapses (the band's exclusion would reappear under the bar).
        active: barRoot.visible && (_b !== null || index === 0)
        detached: _b ? barRoot._detached(_b) : false
        neckK: _b ? barRoot._neckK(_b) : undefined
        surfaceRadius: _b?.island ? barRoot.barRadius : undefined
        x: barRoot._origin.x + (_b?.x ?? 0); y: barRoot._origin.y + (_b?.y ?? 0)
        w: _b?.w ?? 0; h: _b?.h ?? 0
        progress: 1 + barContentLoader.hideOffset / Math.max(1, barRoot.barThickness)
        reserve: index === 0 ? barRoot.exclusiveZone : 0
    }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        // Track hover for auto-hide only — must NOT consume button presses, or
        // it eats every click before it reaches the modules nested inside
        // (workspaces, tray icons, sidebar buttons all became unclickable).
        acceptedButtons: Qt.NoButton

        Item {
            id: hoverMask
            anchors.fill: barContentLoader
        }

        // Material 3 elevation shadow behind the bar (SDF shader; no-op when
        // appearance.shadows.enable is false). Declared BEFORE the background so
        // it renders underneath it. In connected mode the frame shader draws the
        // shadow for the whole fused silhouette instead.
        Loader {
            active: barRoot.drawChrome && barRoot.plainBody && (Config.options?.appearance?.shadows?.enable ?? false)
            anchors.fill: barBackground
            sourceComponent: ElevationShadow {
                level: 2
                direction: barRoot.edge === "bottom" ? "bottom" : "top"
                targetColor: "transparent"   // the Rectangle above paints the fill
                targetRadius: barRoot.barRadius
            }
        }

        // Background
        Rectangle {
            id: barBackground
            anchors {
                fill: barContentLoader
            }
            // Kept as a geometry anchor even when unpainted: the shadow Loader and
            // the corner decorators anchor to it.
            visible: barRoot.drawChrome && barRoot.plainBody
            color: Appearance?.colors.colLayer0 ?? "#1C1B1F"
            radius: barRoot.barRadius
            border.width: 1
            border.color: Appearance?.colors.colLayer0Border ?? "#44444488"

            Behavior on color {
                animation: Appearance?.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        // Content
        //
        // Loaded asynchronously: the bar's content is a deep item tree (3
        // sections × RowLayout × Repeater × module Loaders, plus the center
        // BarGroup). Attaching that whole tree synchronously while the
        // layershell PanelWindow itself is still acquiring its surface drives
        // a recursive QQuickItemPrivate::refWindow() → null QQuickItem::window()
        // segfault in Quickshell 0.3.0 / Qt 6.11 (intermittent, ~70% of cold
        // starts). Deferring instantiation to a later event-loop turn lets the
        // window finish attaching first, so the content tree attaches to an
        // already-windowed root. The Loader itself is a cheap, shallow item.
        Loader {
            id: barContentLoader
            asynchronous: true
            active: true

            anchors {
                top: !barRoot.isBottom ? parent.top : undefined
                bottom: barRoot.isBottom || barRoot.isVertical ? parent.bottom : undefined
                left: !barRoot.isRight ? parent.left : undefined
                right: barRoot.isRight || !barRoot.isVertical ? parent.right : undefined
            }

            // A Loader's implicit size is read-only (derived from the loaded
            // item), so drive the thickness axis with explicit width/height.
            // The other axis is governed by the 3-edge anchors above.
            width: barRoot.isVertical ? barRoot.barThickness : undefined
            height: barRoot.isVertical ? undefined : barRoot.barThickness

            // Auto-hide / fullscreen-hide slide
            property real hideOffset: barRoot.effectiveHidden ? -(barRoot.barThickness + barRoot.formMargin) : 0
            Behavior on hideOffset {
                NumberAnimation {
                    duration: Appearance?.animation.elementMoveFast.duration ?? 200
                    easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                }
            }

            anchors.topMargin: edge === "top" ? hideOffset + barRoot.formMargin : 0
            anchors.bottomMargin: edge === "bottom" ? hideOffset + barRoot.formMargin : 0
            anchors.leftMargin: edge === "left" ? hideOffset + barRoot.formMargin : 0
            anchors.rightMargin: edge === "right" ? hideOffset + barRoot.formMargin : 0

            sourceComponent: BarContent {
                barConfig: barRoot.barConfig
                barIndex: barRoot.barIndex
                isVertical: barRoot.isVertical
                edge: barRoot.edge
            }
        }

        // Floating mode, any form but the plain strip: the same SDF shader as
        // the connected frame draws the bodies with liquid necks and rounded
        // ends (BarSurface), with no frame ring. Async: a ShaderEffect must
        // not attach while the layer surface is still being created.
        Loader {
            z: -1
            anchors.fill: parent
            asynchronous: true
            active: barRoot.drawChrome && !barRoot.plainBody
            sourceComponent: ConnectedFrame {
                anchors.fill: parent
                cornerRadius: 0
                frameThickness: 0
                connectedRadius: barRoot.barRadius
                surfaceRadius: barRoot.barRadius
                surfaceColor: Appearance?.colors.colLayer0 ?? "#1C1B1F"
                surfaceOpacity: (Appearance?.colors.colLayer0 ?? Qt.rgba(0, 0, 0, 1)).a
                surfaces: barRoot.bodies.map(b => ({
                    side: barRoot.edge, x: b.x, y: b.y, w: b.w, h: b.h,
                    detached: barRoot._detached(b), neckK: barRoot._neckK(b),
                    surfaceRadius: barRoot.barRadius, progress: 1 }))
            }
        }

        // Round corner decorators (for edge-hugging bars). Connected mode draws
        // the bar→frame junction arcs in the shader, so these would double up.
        Loader {
            active: barRoot.drawChrome && barRoot.plainBody && globalMargin === 0
            anchors {
                left: !barRoot.isVertical ? parent.left : undefined
                right: !barRoot.isVertical ? parent.right : undefined
                top: (edge === "top") ? barContentLoader.bottom : undefined
                bottom: (edge === "bottom") ? barContentLoader.top : undefined
            }
            height: active ? Appearance.rounding.screenRounding : 0
            sourceComponent: Item {
                RoundCorner {
                    anchors.left: parent.left
                    implicitSize: Appearance.rounding.screenRounding
                    color: barBackground.color
                    corner: barRoot.isBottom ? RoundCorner.CornerEnum.BottomLeft : RoundCorner.CornerEnum.TopLeft
                }
                RoundCorner {
                    anchors.right: parent.right
                    implicitSize: Appearance.rounding.screenRounding
                    color: barBackground.color
                    corner: barRoot.isBottom ? RoundCorner.CornerEnum.BottomRight : RoundCorner.CornerEnum.TopRight
                }
            }
        }
    }
}
