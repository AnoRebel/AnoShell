import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common

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

                // Shadow
                Rectangle {
                    id: shadowRect
                    anchors.fill: parent; anchors.margins: -4
                    radius: cardBg.radius + 4
                    color: "#44000000"
                    z: -1
                }

                // Card
                Rectangle {
                    id: cardBg
                    anchors.fill: parent
                    radius: Appearance?.rounding.normal ?? 12
                    color: Appearance?.colors.colLayer0 ?? "#1C1B1F"
                    border.width: 1
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
