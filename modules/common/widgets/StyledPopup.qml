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
    // On a bottom/left/right bar it hangs off the icon's side facing the screen.
    readonly property string _barEdge: PanelRegistry.windowEdge(root.anchorItem?.QsWindow?.window) || "top"
    property var anchorEdges: root._barEdge === "bottom" ? Edges.Top
        : root._barEdge === "left" ? Edges.Right
        : root._barEdge === "right" ? Edges.Left : Edges.Bottom
    property var anchorGravity: root.anchorEdges
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

    // ── Growth + connected-frame fusion ───────────────────────────────────────
    // The card grows out of the edge it hangs from (pinned there) and retracts
    // into it: `reveal` 0..1 on a spring, retargetable mid-flight. The edge the
    // popup faces is the bar's edge: a popup hanging below its icon belongs to a
    // top bar, and so on.
    readonly property string edge: root.anchorEdges === Edges.Top ? "bottom"
        : root.anchorEdges === Edges.Right ? "left"
        : root.anchorEdges === Edges.Left ? "right" : "top"
    readonly property bool _vertical: root.edge === "top" || root.edge === "bottom"
    property real reveal: root.shown ? 1 : 0
    Behavior on reveal { MotionSpring { token: root.shown ? "liquid" : "settle" } }
    readonly property bool _open: root.shown || root.reveal > 0.005

    // While open, publish the card's SCREEN rect so the frame fuses it into the
    // bar with concave joins. The card lives in its own PopupWindow, whose item
    // origin is the popup, not the screen, so the rect is derived from the
    // ANCHOR item (the bar icon) instead. ponytail: assumes the bar window sits
    // flush on its screen edge (true unless another client reserves that edge).
    property rect _card: Qt.rect(0, 0, 0, 0)
    property string _screenName: ""
    // The popup hangs off the bar's OUTER edge, not the icon's: in connected
    // mode it sits flush there (no gap) so the frame joins it to the bar with
    // fillets instead of drawing a separate rounded island.
    readonly property real _gap: PanelRegistry.enabled ? 0 : root.popupMargin
    // Margin on the two sides across the bar: room for the floating card's
    // shadow, not needed when the frame paints it. Without it a card near a
    // screen end slides flush onto the frame band (the compositor keeps the
    // popup on the output) and the ends below fillet into it.
    readonly property real _side: PanelRegistry.enabled ? 0 : root.popupMargin
    property bool _flushStart: false
    property bool _flushEnd: false
    // Anchor rect relative to the icon, stretched across the bar's thickness.
    property rect _anchorRect: Qt.rect(0, 0, 1, 1)
    function _measure() {
        const w = root.anchorItem?.QsWindow?.window
        if (!root.anchorItem || !w) return
        const o = PanelRegistry.windowOrigin(w), ai = root.anchorItem.mapToItem(null, 0, 0)
        const iw = root.anchorItem.width, ih = root.anchorItem.height
        root._anchorRect = root._vertical ? Qt.rect(0, -ai.y, Math.max(1, iw), Math.max(1, w.height))
                                          : Qt.rect(-ai.x, 0, Math.max(1, w.width), Math.max(1, ih))
        const a = Qt.point(o.x + ai.x, o.y + ai.y)
        const sw = w.screen?.width ?? w.width ?? 0, sh = w.screen?.height ?? w.height ?? 0
        const m = root._side, g = root._gap, pw = root.popupWidth, ph = root.popupHeight
        const sn = w.screen?.name ?? ""
        let x, y
        if (root._vertical) {
            // Centred on the icon, clamped on-screen like the compositor does.
            x = Math.max(m, Math.min(a.x + iw / 2 - pw / 2, sw - pw - m))
            y = root.edge === "top" ? o.y + w.height + g : o.y - g - ph
            root._flushStart = PanelRegistry.enabled && x <= PanelRegistry.inset(sn, "left") + 0.5
            root._flushEnd = PanelRegistry.enabled && x + pw >= sw - PanelRegistry.inset(sn, "right") - 0.5
        } else {
            y = Math.max(m, Math.min(a.y + ih / 2 - ph / 2, sh - ph - m))
            x = root.edge === "left" ? o.x + w.width + g : o.x - g - pw
            root._flushStart = PanelRegistry.enabled && y <= PanelRegistry.inset(sn, "top") + 0.5
            root._flushEnd = PanelRegistry.enabled && y + ph >= sh - PanelRegistry.inset(sn, "bottom") - 0.5
        }
        root._card = Qt.rect(x, y, pw, ph)
        root._screenName = sn
        popupLoader.item?.anchor.updateAnchor()
    }
    onShownChanged: if (shown) _measure()
    // Follow the bar while open (auto-hide, form changes, other edges' zones).
    Connections {
        target: PanelRegistry
        enabled: root.shown
        function onRevisionChanged() { root._measure() }
    }
    onPopupWidthChanged: if (shown) _measure()
    onPopupHeightChanged: if (shown) _measure()

    ConnectedSurfaceLease {
        key: `popout:${root}`
        kind: "popout"; edge: root.edge; priority: 10
        omitStartConnector: root._flushStart; omitEndConnector: root._flushEnd
        screenName: root._screenName
        active: root._open && root.anchorItem !== null
        progress: root.reveal
        surfaceRadius: Appearance?.rounding?.normal ?? 12
        readonly property real _r: Math.max(0, root.reveal)
        w: root._vertical ? root._card.width : root._card.width * _r
        h: root._vertical ? root._card.height * _r : root._card.height
        x: root.edge === "right" ? root._card.x + root._card.width - w : root._card.x
        y: root.edge === "bottom" ? root._card.y + root._card.height - h : root._card.y
    }

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
            }
        }

        sourceComponent: PopupWindow {
            id: popupWin
            visible: root._open
            color: "transparent"
            implicitWidth: root.popupWidth + (root._vertical ? root._side * 2 : root.popupMargin + root._gap)
            implicitHeight: root.popupHeight + (root._vertical ? root.popupMargin + root._gap : root._side * 2)

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
                rect: root._anchorRect
                edges: root.anchorEdges
                gravity: root.anchorGravity
            }

            mask: Region { item: body }

            Item {
                id: area
                anchors {
                    fill: parent; margins: root.popupMargin
                    // bar side: _gap; far side: popupMargin (spring overshoot room); across: _side
                    topMargin: root.edge === "top" ? root._gap : root.edge === "bottom" ? root.popupMargin : root._side
                    bottomMargin: root.edge === "bottom" ? root._gap : root.edge === "top" ? root.popupMargin : root._side
                    leftMargin: root.edge === "left" ? root._gap : root.edge === "right" ? root.popupMargin : root._side
                    rightMargin: root.edge === "right" ? root._gap : root.edge === "left" ? root.popupMargin : root._side
                }

                // In connected mode the AnoScreen frame paints this popout's
                // fused surface, shadow included, so the popup drops its own
                // background, shadow and border (they read as a halo/outline).
                readonly property bool connectedMode: PanelRegistry.enabled

                // The growing body, pinned to the anchor edge. A small overshoot
                // is allowed into the popup margin; clipping hides the rest.
                Item {
                    id: body
                    readonly property real _r: Math.max(0, Math.min(root.reveal, 1 + root.popupMargin / Math.max(1, root._vertical ? area.height : area.width)))
                    width: root._vertical ? area.width : area.width * _r
                    height: root._vertical ? area.height * _r : area.height
                    x: root.edge === "right" ? area.width - width : 0
                    y: root.edge === "bottom" ? area.height - height : 0
                    clip: true

                    Rectangle {
                        id: shadowRect
                        visible: !area.connectedMode
                        anchors.fill: parent; anchors.margins: -4
                        radius: bg.radius + 4
                        color: "#44000000"
                        z: -1
                    }
                    Rectangle {
                        id: bg
                        anchors.fill: parent
                        visible: !area.connectedMode
                        radius: Appearance?.rounding.normal ?? 12
                        color: Appearance?.colors.colLayer0 ?? "#1C1B1F"
                    }

                    // Full-size content, fixed relative to the anchor edge and
                    // uncovered as the body grows (no relayout per frame).
                    Item {
                        id: cardBg
                        width: area.width; height: area.height
                        x: root.edge === "right" ? body.width - width : 0
                        y: root.edge === "bottom" ? body.height - height : 0
                        // Content fades in once the shape has started to grow.
                        opacity: Math.max(0, Math.min(1, (root.reveal - 0.25) / 0.5))

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
                }
            }
        }
    }
}
