import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.widgets.shapes
import "root:modules/common/widgets/shapes/material-shapes.js" as MaterialShapes
import "root:modules/common/widgets/shapes/shapes/corner-rounding.js" as CornerRounding
import "root:modules/common/widgets/shapes/geometry/offset.js" as Offset
import qs.services

/**
 * BarModulePopout — Unified wrapper for bar module detail panels.
 * Automatically chooses between two rendering modes:
 *
 * 1. Standard mode (default): Uses StyledPopup (PopupWindow anchored to bar)
 * 2. Morph mode (when bar has morphingPanel: true): Uses BarWidgetPopout
 *    with ShapeCanvas polygon morphing
 *
 * Bar modules simply declare their popup content inside this component,
 * and the rendering mode is handled automatically based on bar config.
 *
 * Usage:
 *   // In a bar module:
 *   BarModulePopout {
 *       shown: root.hovered
 *       popupWidth: 260; popupHeight: 200
 *
 *       ColumnLayout {
 *           // ... popup content
 *       }
 *   }
 */
Item {
    id: root
    // Fill the host bar module so this item has the icon's geometry; the popup
    // anchors to it. Without a size it collapses to 0×0 at the module origin and
    // the popup lands in the screen corner detached from its icon.
    anchors.fill: parent ? parent : undefined

    // `shown` is the caller's request (typically the bar icon's hover state).
    // The popup actually stays visible a little longer — while the pointer is
    // travelling from the icon onto the popup, and while it hovers the popup
    // itself — so it doesn't flicker open/closed at the icon↔popup boundary.
    property bool shown: false
    property real popupWidth: 280
    property real popupHeight: 200

    // Stable unique id for this popout, used as its PanelRegistry key so the
    // connected-corners frame can fuse it into the shell silhouette. Derived from
    // the QML object address, which is stable for the instance's lifetime and
    // unique across modules — bar modules don't set objectName, and only one
    // popout is open at a time, so a per-instance identity is all the registry
    // needs. Override it if a module ever needs a meaningful key.
    property string popoutKey: `${root}`

    // Hover over the popup window itself (reported by the standard mode).
    property bool popupHovered: false
    // Grace period after the request drops before the popup hides, covering
    // the gap between the icon and the popup surface.
    property int closeDelay: 180

    readonly property bool effectiveShown: root.shown || root.popupHovered || _graceActive
    property bool _graceActive: false

    onShownChanged: {
        if (root.shown) {
            _closeTimer.stop()
            _graceActive = false
        } else {
            _graceActive = true
            _closeTimer.restart()
        }
    }
    onPopupHoveredChanged: {
        if (root.popupHovered) {
            _closeTimer.stop()
            _graceActive = false
        } else if (!root.shown) {
            _graceActive = true
            _closeTimer.restart()
        }
    }

    Timer {
        id: _closeTimer
        interval: root.closeDelay
        onTriggered: root._graceActive = false
    }

    default property alias content: contentContainer.data

    // Detect if this bar uses morphing panels
    readonly property bool useMorphing: {
        // Walk up to find the barConfig
        let parent = root.parent
        while (parent) {
            if (parent.hasOwnProperty("barConfig") && parent.barConfig?.morphingPanel)
                return true
            parent = parent.parent
        }
        return false
    }

    // Content container (children go here regardless of mode). It is reparented
    // into the active mode's content area; once parented somewhere real it must
    // fill that area and be visible, otherwise the popup shows an empty frame.
    Item {
        id: contentContainer
        anchors.fill: parent ? parent : undefined
        // Hidden only while still parked on `root` (before a mode reparents it).
        visible: parent !== root
    }

    // ═══ Mode 1: Standard StyledPopup ════════════════════════════════════
    Loader {
        id: standardLoader
        active: !root.useMorphing
        anchors.fill: parent

        sourceComponent: StyledPopup {
            id: styledPopup
            shown: root.effectiveShown
            popupWidth: root.popupWidth
            popupHeight: root.popupHeight
            // Anchor explicitly to the popout root (which fills the bar icon)
            // instead of letting StyledPopup guess via its own `parent`.
            anchorItem: root

            // Feed the popup's own hover state back up so the grace logic can
            // keep it open while the pointer is inside it.
            Binding {
                target: root
                property: "popupHovered"
                value: styledPopup.popupHovered
                when: standardLoader.active && standardLoader.item
            }

            // Reparent the caller's content into StyledPopup's live card sink.
            // contentParent points at the visible, sized card container once the
            // popup window has loaded, so the content renders directly with no
            // second hop or hidden parking item.
            Binding {
                target: contentContainer
                property: "parent"
                value: styledPopup.contentParent
                when: standardLoader.active && styledPopup.contentParent
            }
        }
    }

    // ═══ Mode 2: Morphing BarWidgetPopout ═════════════════════════════════
    Loader {
        id: morphLoader
        active: root.useMorphing
        anchors.fill: parent

        sourceComponent: Item {
            id: morphContainer

            property bool showPopout: root.effectiveShown
            property bool wasShown: false

            // Dynamic morph duration (from ilyamiro):
            //   - Fast initial open: 250ms
            //   - Smooth morph between panels: 500ms
            //   - Fast close: 250ms
            property int morphDuration: !wasShown && showPopout ? 250  // fast open
                : wasShown && !showPopout ? 250                        // fast close
                : 500                                                  // smooth morph

            onShowPopoutChanged: {
                Qt.callLater(() => { morphContainer.wasShown = morphContainer.showPopout })
                morphContainer._updateReg()
            }

            // ── Connected-frame fusion ────────────────────────────────────────
            // While open, publish the popout's screen-space rect so the frame
            // fuses it into the silhouette with concave junction arcs.
            property rect _rect: Qt.rect(0, 0, 0, 0)
            property string _screenName: ""
            function _updateReg() {
                const w = morphBg.Window.window
                if (!morphContainer.showPopout || !w) return
                const p = morphBg.mapToItem(null, 0, 0)
                morphContainer._rect = Qt.rect(p.x, p.y, morphBg.width, morphBg.height)
                morphContainer._screenName = w.screen?.name ?? ""
            }
            ConnectedSurfaceLease {
                key: `popout:${root.popoutKey}`
                kind: "popout"; edge: "top"; priority: 10
                active: morphContainer.showPopout && root.popoutKey.length > 0
                screenName: morphContainer._screenName
                x: morphContainer._rect.x; y: morphContainer._rect.y
                w: morphContainer._rect.width; h: morphContainer._rect.height
                surfaceRadius: Appearance?.rounding?.normal ?? 12
            }

            // Shape background
            ShapeCanvas {
                id: morphBg
                visible: morphContainer.showPopout
                z: 100

                x: -(root.popupWidth - (root.parent?.width ?? 50)) / 2
                y: (root.parent?.height ?? 40) + 8
                width: root.popupWidth
                height: root.popupHeight

                color: Appearance?.colors.colLayer0 ?? "#1C1B1F"
                // The polygon below is a normalized unit RECTANGLE meant to cover
                // this whole canvas, so it must stretch per-axis. ShapeCanvas
                // otherwise scales uniformly by min(w,h), which drew the shape as a
                // square inside the non-square popup and left a transparent strip
                // that the compositor blurred into a halo around the popout.
                stretchToFill: true
                // No border: the stroke is drawn in normalized space and scaled up
                // by the canvas transform, so a 0.002 hairline rendered as a soft,
                // uneven outline rather than a crisp edge.
                borderWidth: 0

                roundedPolygon: {
                    const r = (Appearance?.rounding?.normal ?? 12) / Math.max(root.popupWidth, root.popupHeight)
                    return MaterialShapes.customPolygon([
                        new MaterialShapes.PointNRound(new Offset.Offset(1, 1), new CornerRounding.CornerRounding(r)),
                        new MaterialShapes.PointNRound(new Offset.Offset(0, 1), new CornerRounding.CornerRounding(r)),
                        new MaterialShapes.PointNRound(new Offset.Offset(0, 0), new CornerRounding.CornerRounding(r)),
                        new MaterialShapes.PointNRound(new Offset.Offset(1, 0), new CornerRounding.CornerRounding(r)),
                    ], 1)
                }

                // Dynamic morph animation — speed adapts to context
                animation: NumberAnimation {
                    duration: morphContainer.morphDuration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: [0.42, 1.67, 0.21, 0.90, 1, 1] // M3 Expressive fast spatial
                }

                opacity: morphContainer.showPopout ? 1 : 0
                scale: morphContainer.showPopout ? 1 : 0.85
                transformOrigin: Item.Top

                // Opacity fade matches morph speed (200ms fast, 300ms smooth)
                Behavior on opacity { NumberAnimation { duration: morphContainer.morphDuration === 500 ? 300 : 200; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.standard } }
                Behavior on scale { NumberAnimation { duration: morphContainer.morphDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }

                // Content inside morph shape
                Item {
                    id: morphContentArea
                    anchors { fill: parent; margins: 12 }
                    visible: morphContainer.showPopout
                    opacity: morphContainer.showPopout ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(200); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }
                }
            }

            // Reparent content into morph area
            Binding {
                target: contentContainer
                property: "parent"
                value: morphContentArea
                when: morphLoader.active
            }
            Binding {
                target: contentContainer
                property: "visible"
                value: true
                when: morphLoader.active && morphContainer.showPopout
            }
        }
    }
}
