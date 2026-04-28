import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

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

    // Auto-hide hover tracking
    property bool mustShow: hoverArea.containsMouse

    WlrLayershell.namespace: `quickshell:bar:${barConfig?.id ?? barIndex}`

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: autoHide && !mustShow ? 0 : barThickness + globalMargin

    // Anchoring based on edge
    anchors {
        top: (edge === "top" || isVertical)
        bottom: (edge === "bottom" || isVertical)
        left: (edge === "left" || !isVertical)
        right: (edge === "right" || !isVertical)
    }

    implicitWidth: isVertical ? effectiveThickness : undefined
    implicitHeight: isVertical ? undefined : effectiveThickness

    margins {
        top: (edge !== "top" && !isVertical) ? 0 : globalMargin
        bottom: (edge !== "bottom" && !isVertical) ? 0 : globalMargin
        left: (edge !== "left" && isVertical) ? 0 : globalMargin
        right: (edge !== "right" && isVertical) ? 0 : globalMargin
    }

    mask: Region { item: hoverMask }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true

        Item {
            id: hoverMask
            anchors.fill: barContent
        }

        // Background
        Rectangle {
            id: barBackground
            anchors {
                fill: barContent
            }
            visible: barRoot.showBackground
            color: Appearance?.colors.colLayer0 ?? "#1C1B1F"
            radius: barRoot.barRadius
            border.width: 1
            border.color: Appearance?.colors.colLayer0Border ?? "#44444488"

            Behavior on color {
                animation: Appearance?.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        // Content
        BarContent {
            id: barContent
            barConfig: barRoot.barConfig
            isVertical: barRoot.isVertical
            edge: barRoot.edge

            anchors {
                top: !barRoot.isBottom ? parent.top : undefined
                bottom: barRoot.isBottom || barRoot.isVertical ? parent.bottom : undefined
                left: !barRoot.isRight ? parent.left : undefined
                right: barRoot.isRight || !barRoot.isVertical ? parent.right : undefined
            }

            implicitWidth: barRoot.isVertical ? barRoot.barThickness : undefined
            implicitHeight: barRoot.isVertical ? undefined : barRoot.barThickness

            // Auto-hide slide
            property real hideOffset: barRoot.autoHide && !barRoot.mustShow ? -barRoot.barThickness : 0
            Behavior on hideOffset {
                NumberAnimation {
                    duration: Appearance?.animation.elementMoveFast.duration ?? 200
                    easing.type: Easing.OutCubic
                }
            }

            anchors.topMargin: edge === "top" ? hideOffset : 0
            anchors.bottomMargin: edge === "bottom" ? hideOffset : 0
            anchors.leftMargin: edge === "left" ? hideOffset : 0
            anchors.rightMargin: edge === "right" ? hideOffset : 0
        }

        // Round corner decorators (for edge-hugging bars)
        Loader {
            active: barRoot.showBackground && globalMargin === 0
            anchors {
                left: !barRoot.isVertical ? parent.left : undefined
                right: !barRoot.isVertical ? parent.right : undefined
                top: (edge === "top") ? barContent.bottom : undefined
                bottom: (edge === "bottom") ? barContent.top : undefined
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
