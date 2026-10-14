import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.services

/**
 * Styled popup window anchored to a parent item. Used for bar module
 * hover popups (battery details, network list, etc.)
 * Provides consistent styling: rounded card, shadow, enter/exit animation.
 */
Item {
    id: root
    property bool shown: false
    property real popupWidth: 300
    property real popupHeight: 400
    property real popupMargin: 8
    // Hang the popup off the BOTTOM edge of the anchor (the bar icon) and grow
    // downward. The previous Edges.Top default anchored at the icon's top edge
    // growing upward — off the top of the screen for a top bar — so the
    // compositor clamped popups to arbitrary positions where they detached from
    // their icons and overlapped each other.
    property var anchorEdges: Edges.Bottom
    property var anchorGravity: Edges.Bottom
    // Item the popup anchors to. Defaults to this popup's own parent, but
    // callers should set it explicitly to the visible icon/widget — relying on
    // `parent` is fragile when the popup is nested inside Loaders.
    property Item anchorItem: root.parent

    // True while the pointer is over the popup card itself. Callers OR this
    // with their own hover state so moving the pointer from the bar icon onto
    // the popup keeps it open instead of flicker-closing (the popup is a
    // separate window, so the icon's MouseArea loses hover the moment the
    // pointer crosses into it).
    property bool popupHovered: false

    // Inline content sink for callers that declare children directly:
    //   StyledPopup { Rectangle {...} }
    // Those children land in the parking item and are reparented into the live
    // card once the popup window exists.
    default property alias content: contentHolder.data

    // Stable, ALREADY-VISIBLE, sized handle for callers that reparent an
    // existing item in (e.g. BarModulePopout). Pointing this at the real card
    // container — instead of a hidden parking item that then needs a second
    // reparent — is what makes the content actually render. Null until the
    // popup window has loaded.
    property Item contentParent: contentHolder

    Item {
        id: contentHolder
        visible: false   // parking spot for inline children before the window exists
    }

    // ── Connected-frame fusion ────────────────────────────────────────────────
    // While shown, publish the popup card's SCREEN-space rect to PanelRegistry so
    // the AnoScreen frame shader fuses it into the shell silhouette with concave
    // junction arcs (like the bar and sidebars). Inert when connected mode is off
    // (register no-ops). Priority 10 ranks it above the sidebars for the shader's
    // four chrome slots; bars are added ahead of the registry, so a popup can
    // never evict the bar.
    //
    // The card lives in its own PopupWindow, whose item origin is the popup — NOT
    // the screen — so mapToItem there gives popup-local coords the frame can't use.
    // Instead derive the rect from the ANCHOR item (the bar icon), which is a
    // normal item mappable to screen space: the popup sits directly below the icon
    // (top bar, gravity Bottom) and is horizontally centred on it.
    readonly property string _regKey: `popout:${root}`
    readonly property bool _regActive: root.shown && root.anchorItem !== null && PanelRegistry.enabled
    function _updateReg() {
        if (!root._regActive) {
            PanelRegistry.unregister(root._regKey)
            return
        }
        const w = root.anchorItem.QsWindow?.window
        if (!w) return
        // anchor item's position in its window (== screen for a top-anchored bar).
        const a = root.anchorItem.mapToItem(null, 0, 0)
        const cx = a.x + root.anchorItem.width / 2
        // Clamp to the screen so the registered rect matches where the compositor
        // actually places the popup: a popup centred near the screen edge gets
        // shifted inward to stay on-screen, and registering the un-clamped centre
        // drew the fusion arc offset from the real popup (calendar under the clock).
        const sw = w.width ?? 0
        const edgeGap = root.popupMargin
        let cardX = cx - root.popupWidth / 2
        cardX = Math.max(edgeGap, Math.min(cardX, sw - root.popupWidth - edgeGap))
        const cardY = a.y + root.anchorItem.height + root.popupMargin
        PanelRegistry.register(root._regKey, {
            "kind": "popout",
            "screenName": w.screen?.name ?? "",
            "edge": "top",
            "x": cardX, "y": cardY,
            "w": root.popupWidth, "h": root.popupHeight,
            "priority": 10,
            "surfaceRadius": Appearance?.rounding?.normal ?? 12
        })
    }
    on_RegActiveChanged: _updateReg()
    Component.onDestruction: PanelRegistry.unregister(root._regKey)

    // Keep the popup window alive for the lifetime of this component instead
    // of destroying it on every hide. A Loader tied to `shown` tore the
    // window (and the reparented content) down mid-animation, so the popup
    // flashed empty and vanished. Visibility is toggled on the window itself.
    Loader {
        id: popupLoader
        active: true
        anchors.fill: parent

        onItemChanged: {
            if (item) {
                // Expose the live card container as the content sink and pull
                // any inline children that were parked before load.
                root.contentParent = item.cardContent
                item.pullInlineContent()
                root._updateReg()
            }
        }

        sourceComponent: PopupWindow {
            id: popupWin
            visible: root.shown
            color: "transparent"
            implicitWidth: root.popupWidth + root.popupMargin * 2
            implicitHeight: root.popupHeight + root.popupMargin * 2

            // Expose the visible card content area so the outer Loader can route
            // both inline children and externally-reparented content into it.
            property alias cardContent: contentContainer

            function pullInlineContent() {
                for (let i = contentHolder.data.length - 1; i >= 0; --i) {
                    const child = contentHolder.data[i];
                    if (child && child.parent !== undefined)
                        child.parent = contentContainer;
                }
            }

            anchor {
                window: root.QsWindow.window
                item: root.anchorItem
                edges: root.anchorEdges
                gravity: root.anchorGravity
            }

            mask: Region { item: cardBg }

            Item {
                anchors { fill: parent; margins: root.popupMargin }

                // In connected mode the AnoScreen frame draws the shell's shadow +
                // the fused-in popout surface, so this popup must drop its own
                // chrome. The hand-drawn shadowRect below is a solid #44000000
                // rect bleeding 4px past the card; the compositor BLURS it into a
                // soft glow — the "halo" around the popout — and the 1px border
                // adds an outline. Both are floating-mode only.
                readonly property bool connectedMode: PanelRegistry.enabled

                // Shadow
                Rectangle {
                    id: shadowRect
                    visible: !parent.connectedMode
                    anchors.fill: parent; anchors.margins: -4
                    radius: cardBg.radius + 4
                    color: "#44000000"
                    z: -1
                }

                // Card
                Rectangle {
                    id: cardBg
                    anchors.fill: parent
                    // In connected mode the AnoScreen frame shader ALREADY paints
                    // this popout's fused surface (with the concave top join + its
                    // own rounded free corners). Painting cardBg's colLayer0 on top
                    // draws a SECOND, slightly-inset background — the "double
                    // background" whose offset edge read as a misaligned connector.
                    // Go transparent and let the frame surface show through; drop the
                    // border too (the frame is the outline). Floating mode keeps the
                    // full card. Same principle as BarWindow's drawChrome.
                    radius: Appearance?.rounding.normal ?? 12
                    color: parent.connectedMode ? "transparent" : (Appearance?.colors.colLayer0 ?? "#1C1B1F")
                    border.width: 0
                    border.color: Appearance?.colors.colLayer0Border ?? "#44444488"
                    clip: true

                    // Report hover so the caller can keep the popup open while
                    // the pointer is inside it (prevents flicker-close).
                    HoverHandler {
                        id: cardHover
                        onHoveredChanged: root.popupHovered = hovered
                    }

                    // The live, visible, sized content area. Reparented content
                    // and inline children both end up here.
                    Item {
                        id: contentContainer
                        anchors { fill: parent; margins: 12 }
                    }
                }

                // Entry animation — scale in from the top since the popup hangs
                // below its anchor icon. Uses the M3-expressive spring curve
                // (slight overshoot) for a fluid, lively pop instead of a flat
                // ease-out.
                opacity: root.shown ? 1 : 0
                scale: root.shown ? 1 : 0.88
                transformOrigin: Item.Top

                Behavior on opacity {
                    NumberAnimation {
                        duration: (Appearance?.animationCurves.expressiveEffectsDuration ?? 200) * (Appearance?.animSpeedMultiplier ?? 1)
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance?.animationCurves.emphasizedDecel ?? [0.05, 0.7, 0.1, 1, 1, 1]
                    }
                }
                Behavior on scale {
                    NumberAnimation {
                        duration: (Appearance?.animationCurves.expressiveFastSpatialDuration ?? 350) * (Appearance?.animSpeedMultiplier ?? 1)
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance?.animationCurves.expressiveFastSpatial ?? [0.42, 1.67, 0.21, 0.90, 1, 1]
                    }
                }
            }
        }
    }
}
