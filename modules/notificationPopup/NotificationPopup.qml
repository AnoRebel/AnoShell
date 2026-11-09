import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services

/**
 * Floating notification popups. Appear at a configurable screen corner,
 * stack vertically with stagger animation, auto-dismiss on timeout,
 * swipe/click to dismiss. Per-screen aware.
 */
Scope {
    id: root

    readonly property string position: Config.options?.notifications?.position ?? "topRight"
    // topLeft | topCenter | topRight | bottomLeft | bottomCenter | bottomRight
    readonly property bool isTop: position.startsWith("top")
    readonly property bool isLeft: position.endsWith("Left")
    readonly property bool isRight: position.endsWith("Right")
    // Connected mode: the stack hangs flush from its edge and the frame paints
    // it as one fused body (cards drop their own fill, border and shadow).
    readonly property bool connected: PanelRegistry.enabled
    readonly property int edgeMargin: connected ? 0 : (Config.options?.notifications?.edgeMargin ?? 8)
    // Centred popups share the pill's spot when it is on the same edge: hang
    // below (or above) it instead of covering it.
    readonly property real pillClear: {
        const a = Config.options?.anoSpot
        if (isLeft || isRight || !(a?.enable ?? false) || (a?.position ?? "top") !== (isTop ? "top" : "bottom")) return 0
        return (a?.heightPx ?? 36) + (a?.floating || !connected ? 12 : 0)
    }

    PanelWindow {
        id: popupWindow
        // Stays up until the stack has retracted into its edge.
        visible: (Notifications.popupList.length > 0 || stackClip.height > 0.5) && !GlobalStates.screenLocked

        screen: Quickshell.screens.find(s => s.name === CompositorService.focusedMonitorName) ?? Quickshell.screens[0]

        WlrLayershell.namespace: "quickshell:notifPopup"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusiveZone: 0
        color: "transparent"

        implicitWidth: Math.max(280, Math.min(640, Config.options?.notifications?.popupWidth ?? 380))
        // Grows at once; shrinks only after the stack has retracted, so the
        // retract isn't cut off (following the spring would resize the surface
        // every frame instead).
        readonly property real _want: notifColumn.implicitHeight + root.edgeMargin * 2
        property real _winH: 0 // set by on_WantChanged (a binding would shrink at once)
        on_WantChanged: { if (_want >= _winH) { _winH = _want; shrink.stop() } else shrink.restart() }
        Component.onCompleted: _winH = _want
        Timer {
            id: shrink
            interval: 120
            onTriggered: { if (Math.abs(stackClip.height - stackClip.target) < 1) popupWindow._winH = popupWindow._want; else restart() }
        }
        implicitHeight: Math.min(_winH, (screen?.height ?? 1080) * 0.6)

        anchors {
            top: root.isTop
            bottom: !root.isTop
            left: root.isLeft
            right: root.isRight
        }

        margins {
            top: root.isTop ? root.edgeMargin + root.pillClear : 0
            bottom: !root.isTop ? root.edgeMargin + root.pillClear : 0
            left: root.isLeft ? root.edgeMargin : 0
            right: root.isRight ? root.edgeMargin : 0
        }

        mask: Region { item: stackClip }

        ConnectedSurfaceLease {
            key: "notifications"
            kind: "notifications"; edge: root.isTop ? "top" : "bottom"; priority: 7
            screenName: popupWindow.screen?.name ?? ""
            active: popupWindow.visible && stackClip.height > 0.5
            progress: stackClip.height / Math.max(1, notifColumn.implicitHeight + root.edgeMargin * 2)
            // Where the layer shell puts the window (pushed in by the bar, centred
            // for the *Center positions).
            readonly property point _o: PanelRegistry.windowOrigin(popupWindow)
            x: _o.x + stackClip.x
            y: _o.y + stackClip.y
            w: stackClip.width; h: stackClip.height
            // In a corner the stack meets the side band: fillet into it (as
            // StyledPopup does) instead of rounding on its own.
            readonly property string _sn: popupWindow.screen?.name ?? ""
            omitStartConnector: x <= PanelRegistry.inset(_sn, "left") + 0.5
            omitEndConnector: x + w >= (popupWindow.screen?.width ?? 0) - PanelRegistry.inset(_sn, "right") - 0.5
        }

        // Blur follows each rounded card (ext-background-effect-v1); the
        // compositor's rectangular layer-rule blur is opted out for this
        // namespace in the bundled hyprland.lua.
        BackgroundEffect.blurRegion: CompositorService.supports.blurProtocol && !root.connected && !GameMode.stopBlur ? cardsRegion : null
        Region {
            id: cardsRegion
            // Clipped to the window last: cards sliding in or out leave it,
            // and an offscreen region can blur the whole surface on Hyprland.
            regions: { notifRepeater.count; return Array.from({ length: notifRepeater.count }, (_, i) => notifRepeater.itemAt(i)?.blurShape).filter(r => !!r).concat([popupWindow.cardsClip]) }
        }
        property Region cardsClip: Region { intersection: Intersection.Intersect; width: popupWindow.width; height: popupWindow.height }

        // The stack grows out of its edge (pinned there) on a spring as cards
        // arrive and retracts as they leave; the frame follows this body.
        Item {
            id: stackClip
            clip: true
            readonly property real target: Notifications.popupList.length > 0 ? notifColumn.implicitHeight + root.edgeMargin * 2 : 0
            height: target
            Behavior on height { MotionSpring { token: stackClip.target > stackClip.height ? "liquid" : "settle" } }
            width: parent.width
            y: root.isTop ? 0 : parent.height - height
        ColumnLayout {
            id: notifColumn
            anchors {
                top: root.isTop ? parent.top : undefined
                bottom: !root.isTop ? parent.bottom : undefined
                left: root.isLeft ? parent.left : undefined
                right: root.isRight ? parent.right : undefined
                horizontalCenter: !root.isLeft && !root.isRight ? parent.horizontalCenter : undefined
                margins: root.edgeMargin
            }
            width: popupWindow.implicitWidth - root.edgeMargin * 2
            spacing: 6
            layoutDirection: Qt.LeftToRight

            // Staggered notification items
            Repeater {
                id: notifRepeater
                model: Notifications.popupList

                Item {
                    id: popupDelegate
                    required property var modelData
                    required property int index

                    Layout.fillWidth: true
                    implicitHeight: notifCard.implicitHeight
                    // No clip: it cut the card's drop shadow into straight edges.
                    // Explicit geometry: Region { item } ignores transforms and ancestor moves.
                    property Region blurShape: Region {
                        x: notifColumn.x + popupDelegate.x + notifCard.x; y: notifColumn.y + popupDelegate.y
                        width: notifCard.width; height: notifCard.height; radius: notifCard.radius
                    }

                    // Entry animation — slide in from edge + fade
                    property real slideOffset: root.isLeft ? -20 : root.isRight ? 20 : 0
                    property real entryOpacity: 0

                    Component.onCompleted: {
                        entryTimer.interval = index * 40 // Stagger each notification
                        entryTimer.start()
                    }
                    Timer {
                        id: entryTimer
                        onTriggered: { popupDelegate.slideOffset = 0; popupDelegate.entryOpacity = 1 }
                    }

                    opacity: entryOpacity
                    // Top/bottom stacks don't slide sideways: the card settles in instead.
                    scale: (root.isLeft || root.isRight) ? 1 : 0.96 + 0.04 * opacity
                    transformOrigin: root.isTop ? Item.Top : Item.Bottom
                    Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(250); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }
                    // The slide animates through notifCard's Behavior on x.

                    // Swipe to dismiss tracking
                    property real swipeX: 0
                    property bool swiping: false

                    // Notification card with shadow
                    SurfaceMaterial {
                        id: notifCard
                        surface: "notification"
                        width: parent.width
                        x: popupDelegate.swipeX + popupDelegate.slideOffset
                        implicitHeight: cardContent.implicitHeight + 20
                        radius: Appearance?.rounding.normal ?? 12
                        color: root.connected ? "transparent" : (Appearance?.colors.colLayer0 ?? "#1C1B1F")
                        border.width: root.connected ? 0 : Appearance.borders.width
                        border.color: Appearance.borders.color

                        // Subtle shadow (floating only)
                        layer.enabled: !root.connected && !GameMode.stopShadows
                        layer.effect: StyledDropShadow { radius: 12; verticalOffset: 3 }

                        // Hover glow
                        Rectangle {
                            anchors.fill: parent; radius: parent.radius
                            color: "transparent"
                            border.width: cardHover.containsMouse ? 1 : 0
                            border.color: Appearance?.colors.colPrimary ?? "#65558F"
                            Behavior on border.width { NumberAnimation { duration: AnimationConfig.scaledDuration(100) } }
                        }

                        RowLayout {
                            id: cardContent
                            anchors { fill: parent; margins: 10 }
                            spacing: 10

                            // App icon
                            Rectangle {
                                Layout.alignment: Qt.AlignTop
                                width: 32; height: 32; radius: 16
                                color: Appearance?.colors.colSecondaryContainer ?? "#E8DEF8"

                                StyledImage {
                                    anchors.centerIn: parent; width: 20; height: 20
                                    source: FileUtils.iconSource(modelData?.image || modelData?.appIcon || "")
                                    visible: source.toString().length > 0
                                }
                                MaterialSymbol {
                                    anchors.centerIn: parent; text: "notifications"; iconSize: 16
                                    visible: !parent.children[0].visible
                                    color: Appearance?.m3colors.m3onSecondaryContainer ?? "#1D1B20"
                                }
                            }

                            // Content
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 2

                                RowLayout {
                                    Layout.fillWidth: true
                                    StyledText {
                                        text: modelData?.summary ?? ""
                                        font.pixelSize: Appearance?.font.pixelSize.small ?? 14
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight; Layout.fillWidth: true
                                    }
                                    StyledText {
                                        text: modelData?.appName ?? ""
                                        font.pixelSize: Appearance.font.pixelSize.smallest; opacity: 0.4
                                    }
                                }

                                StyledText {
                                    text: StringUtils.stripImgTags(modelData?.body ?? "")
                                    font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
                                    wrapMode: Text.Wrap; maximumLineCount: 3
                                    elide: Text.ElideRight; Layout.fillWidth: true
                                    visible: text.length > 0
                                }

                                // Actions
                                RowLayout {
                                    spacing: 4; visible: (modelData?.actions?.length ?? 0) > 0
                                    Layout.fillWidth: true
                                    Repeater {
                                        model: modelData?.actions ?? []
                                        RippleButton {
                                            required property var modelData
                                            buttonText: modelData.text
                                            buttonRadius: 4; implicitHeight: 24
                                            colBackground: Appearance?.colors.colSecondaryContainer ?? "#E8DEF8"
                                            onClicked: Notifications.attemptInvokeAction(popupDelegate.modelData.notificationId, modelData.identifier)
                                        }
                                    }
                                }
                            }

                            // Dismiss X
                            ToolbarButton {
                                Layout.alignment: Qt.AlignTop
                                iconName: "close"; iconSize: 14
                                implicitWidth: 24; implicitHeight: 24
                                onClicked: Notifications.discardNotification(modelData.notificationId)
                            }
                        }

                        // Click to open sidebar
                        MouseArea {
                            id: cardHover
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton
                            z: -1 // Below dismiss button
                            onClicked: {
                                Notifications.timeoutNotification(modelData.notificationId)
                                GlobalStates.sidebarLeftOpen = true
                            }

                            // Swipe handling
                            property real pressX: 0
                            onPressed: mouse => { pressX = mouse.x; popupDelegate.swiping = true }
                            onPositionChanged: mouse => {
                                if (popupDelegate.swiping) {
                                    popupDelegate.swipeX = mouse.x - pressX
                                }
                            }
                            onReleased: {
                                popupDelegate.swiping = false
                                if (Math.abs(popupDelegate.swipeX) > 100) {
                                    Notifications.discardNotification(modelData.notificationId)
                                } else {
                                    popupDelegate.swipeX = 0
                                }
                            }
                        }
                        Behavior on x { enabled: !popupDelegate.swiping; NumberAnimation { duration: AnimationConfig.scaledDuration(200); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }
                    }
                }
            }
        }
        }
    }
}
