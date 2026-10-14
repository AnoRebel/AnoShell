import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "."

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
    readonly property real effectiveThickness: barThickness + (showBackground ? globalMargin * 2 : 0)

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

    WlrLayershell.namespace: `quickshell:bar:${barConfig?.id ?? barIndex}`
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
    exclusiveZone: effectiveHidden || !contentLoaded ? 0 : barThickness + globalMargin

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

    mask: Region { item: hoverMask }

    // Connected mode: the frame paints this bar, flush to its edge and full
    // length, following the auto-hide slide (hideOffset ≤ 0 pushes it out).
    ConnectedSurfaceLease {
        key: `bar:${barRoot.barConfig?.id ?? barRoot.barIndex}:${barRoot._screenName}`
        kind: "bar"; edge: barRoot.edge; priority: 20
        screenName: barRoot._screenName
        active: barRoot.visible
        readonly property real _off: barContentLoader.hideOffset
        readonly property real _sw: barRoot.screen?.width ?? 0
        readonly property real _sh: barRoot.screen?.height ?? 0
        readonly property real _th: barRoot.barThickness
        x: barRoot.edge === "left" ? _off : barRoot.edge === "right" ? _sw - _th - _off : 0
        y: barRoot.edge === "top" ? _off : barRoot.edge === "bottom" ? _sh - _th - _off : 0
        w: barRoot.isVertical ? _th : _sw
        h: barRoot.isVertical ? _sh : _th
        progress: 1 + _off / Math.max(1, _th)
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
            active: barRoot.drawChrome && (Config.options?.appearance?.shadows?.enable ?? false)
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
            visible: barRoot.drawChrome
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
            property real hideOffset: barRoot.effectiveHidden ? -barRoot.barThickness : 0
            Behavior on hideOffset {
                NumberAnimation {
                    duration: Appearance?.animation.elementMoveFast.duration ?? 200
                    easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                }
            }

            anchors.topMargin: edge === "top" ? hideOffset : 0
            anchors.bottomMargin: edge === "bottom" ? hideOffset : 0
            anchors.leftMargin: edge === "left" ? hideOffset : 0
            anchors.rightMargin: edge === "right" ? hideOffset : 0

            sourceComponent: BarContent {
                barConfig: barRoot.barConfig
                isVertical: barRoot.isVertical
                edge: barRoot.edge
            }
        }

        // Round corner decorators (for edge-hugging bars). Connected mode draws
        // the bar→frame junction arcs in the shader, so these would double up.
        Loader {
            active: barRoot.drawChrome && globalMargin === 0
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
