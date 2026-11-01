import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * Notification display component — reusable notification list that can be
 * embedded in sidebars, control panel, or standalone overlay.
 * Shows grouped notifications with app headers, action buttons, dismiss.
 * Configurable max items and compact mode. A group of 2+ is a stack (the
 * latest card with the older ones peeking out under it) until expanded.
 */
Item {
    id: root
    property bool compact: false
    property int maxItems: compact ? 5 : -1
    property bool showHeader: true
    property bool showClearAll: true

    // Expanded app groups (by app name); everything else is stacked.
    property var _expanded: ({})
    function toggleGroup(app) {
        const e = Object.assign({}, root._expanded)
        e[app] = !e[app]
        root._expanded = e
    }

    implicitHeight: notifLayout.implicitHeight

    ColumnLayout {
        id: notifLayout
        anchors { left: parent.left; right: parent.right; top: parent.top }
        spacing: 6

        // Header
        Loader {
            Layout.fillWidth: true
            active: root.showHeader
            visible: active
            sourceComponent: RowLayout {
                spacing: 8
                MaterialSymbol { text: "notifications"; iconSize: 20; color: Appearance?.colors.colPrimary ?? "#65558F" }
                StyledText { text: "Notifications"; font.pixelSize: Appearance?.font.pixelSize.normal ?? 16; font.weight: Font.DemiBold; Layout.fillWidth: true }
                StyledText { text: `${Notifications.list.length}`; font.pixelSize: Appearance.font.pixelSize.smaller; opacity: 0.4 }
                Loader {
                    active: root.showClearAll && Notifications.list.length > 0; visible: active
                    sourceComponent: ToolbarButton {
                        iconName: "delete_sweep"; iconSize: 18; toolTipText: "Clear all"
                        onClicked: Notifications.discardAllNotifications()
                    }
                }
            }
        }

        // Empty state
        Loader {
            Layout.fillWidth: true
            Layout.topMargin: 20
            active: Notifications.list.length === 0; visible: active
            sourceComponent: EmptyState {
                icon: "notifications_none"
                title: "No notifications"
                hint: Notifications.silent ? "Silent mode is on: new ones wait here without popping up" : "You're all caught up"
            }
        }

        // Grouped notification list
        Repeater {
            model: Notifications.appNameList

            ColumnLayout {
                id: group
                required property string modelData
                // Newest first.
                readonly property var notifs: (Notifications.groupsByAppName[modelData]?.notifications ?? []).slice().reverse()
                readonly property bool stackable: notifs.length > 1
                readonly property bool expanded: !stackable || root._expanded[modelData] === true
                Layout.fillWidth: true; spacing: 4

                // App group header
                RowLayout {
                    spacing: 6
                    Rectangle { width: 3; height: 14; radius: 1.5; color: Appearance?.colors.colPrimary ?? "#65558F" }
                    StyledText {
                        text: group.modelData
                        font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
                        font.weight: Font.DemiBold
                        color: Appearance?.colors.colPrimary ?? "#65558F"
                        Layout.fillWidth: true
                    }
                    StyledText {
                        text: `${group.notifs.length}`
                        font.pixelSize: Appearance.font.pixelSize.smallest; opacity: 0.3
                    }
                    ToolbarButton {
                        visible: group.stackable
                        iconName: group.expanded ? "unfold_less" : "unfold_more"; iconSize: 16
                        implicitWidth: 24; implicitHeight: 24
                        toolTipText: group.expanded ? "Stack" : "Expand"
                        onClicked: root.toggleGroup(group.modelData)
                    }
                    ToolbarButton {
                        iconName: "close"; iconSize: 14
                        implicitWidth: 24; implicitHeight: 24
                        toolTipText: "Dismiss group"
                        onClicked: group.notifs.forEach(n => Notifications.discardNotification(n.notificationId))
                    }
                }

                // Stacked: the newest card, with up to two older ones peeking
                // out under it. Clicking the peeks expands the group.
                Item {
                    id: stack
                    visible: !group.expanded
                    Layout.fillWidth: true
                    readonly property int peeks: Math.min(2, group.notifs.length - 1)
                    implicitHeight: topCard.implicitHeight + peeks * 6

                    Repeater {
                        model: stack.peeks
                        Rectangle {
                            required property int index
                            z: -1 - index
                            x: (index + 1) * 8
                            width: stack.width - (index + 1) * 16
                            height: 24
                            y: topCard.implicitHeight - height + (index + 1) * 6
                            radius: Appearance?.rounding.normal ?? 12
                            // A layer above the cards so the peeks read on any panel.
                            color: Appearance?.colors.colLayer2 ?? "#2B2930"
                            opacity: 0.9 - index * 0.3
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleGroup(group.modelData)
                    }
                    NotificationItem {
                        id: topCard
                        width: stack.width
                        notification: group.notifs[0] ?? null
                        compact: root.compact
                        visible: notification !== null
                        onDismissed: id => Notifications.discardNotification(id)
                        onActionInvoked: (id, identifier) => Notifications.attemptInvokeAction(id, identifier)
                    }
                }

                // Notifications in group — ListView (not Repeater) so the
                // built-in add/remove/displaced transitions animate
                // entrance/exit and the cascade on clear-all (where a
                // batch of items get dismissed in one tick of the model).
                // expressiveAnimations gates the transitions so users can
                // opt back to a snappy, no-frills feed.
                ListView {
                    id: notifList
                    visible: group.expanded
                    Layout.fillWidth: true
                    interactive: false  // host scroll lives at the parent layer
                    spacing: 4
                    implicitHeight: contentHeight
                    readonly property bool expressive: Config.options?.notifications?.expressiveAnimations ?? true

                    model: !group.expanded ? []
                        : root.maxItems > 0 ? group.notifs.slice(0, root.maxItems) : group.notifs

                    delegate: NotificationItem {
                        required property var modelData
                        width: ListView.view ? ListView.view.width : 0
                        notification: modelData
                        compact: root.compact
                        onDismissed: id => Notifications.discardNotification(id)
                        onActionInvoked: (id, identifier) => Notifications.attemptInvokeAction(id, identifier)
                    }

                    add: Transition {
                        enabled: notifList.expressive
                        ParallelAnimation {
                            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: AnimationConfig.scaledDuration(200); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel }
                            NumberAnimation { property: "scale"; from: 0.92; to: 1; duration: AnimationConfig.scaledDuration(200); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel }
                        }
                    }
                    remove: Transition {
                        enabled: notifList.expressive
                        ParallelAnimation {
                            NumberAnimation { property: "opacity"; to: 0; duration: AnimationConfig.scaledDuration(220); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedAccel }
                            // Slide trailing — gives the cascade direction.
                            NumberAnimation { property: "x"; to: 24; duration: AnimationConfig.scaledDuration(220); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedAccel }
                        }
                    }
                    // Items that shift up when one above them leaves — gives
                    // the cascade a continuous feel instead of jump-cuts.
                    displaced: Transition {
                        enabled: notifList.expressive
                        NumberAnimation { property: "y"; duration: AnimationConfig.scaledDuration(200); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel }
                    }
                }
            }
        }
    }
}
