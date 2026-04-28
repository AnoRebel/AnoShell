import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * Notification display component — reusable notification list that can be
 * embedded in sidebars, control panel, or standalone overlay.
 * Shows grouped notifications with app headers, action buttons, dismiss.
 * Configurable max items, compact mode, and group collapsing.
 */
Item {
    id: root
    property bool compact: false
    property int maxItems: compact ? 5 : -1
    property bool showHeader: true
    property bool showClearAll: true

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
                StyledText { text: `${Notifications.list.length}`; font.pixelSize: 12; opacity: 0.4 }
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
            active: Notifications.list.length === 0; visible: active
            sourceComponent: ColumnLayout {
                spacing: 8; Layout.topMargin: 20
                MaterialSymbol { text: "notifications_none"; iconSize: 36; opacity: 0.2; Layout.alignment: Qt.AlignHCenter }
                StyledText { text: "No notifications"; font.pixelSize: 14; opacity: 0.4; Layout.alignment: Qt.AlignHCenter }
            }
        }

        // Grouped notification list
        Repeater {
            model: Notifications.appNameList

            ColumnLayout {
                required property string modelData
                Layout.fillWidth: true; spacing: 4

                // App group header
                RowLayout {
                    spacing: 6
                    Rectangle { width: 3; height: 14; radius: 1.5; color: Appearance?.colors.colPrimary ?? "#65558F" }
                    StyledText {
                        text: modelData
                        font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
                        font.weight: Font.DemiBold
                        color: Appearance?.colors.colPrimary ?? "#65558F"
                        Layout.fillWidth: true
                    }
                    StyledText {
                        text: `${Notifications.groupsByAppName[modelData]?.notifications?.length ?? 0}`
                        font.pixelSize: 10; opacity: 0.3
                    }
                }

                // Notifications in group
                Repeater {
                    model: {
                        const notifs = Notifications.groupsByAppName[modelData]?.notifications ?? []
                        return root.maxItems > 0 ? notifs.slice(0, root.maxItems) : notifs
                    }

                    NotificationItem {
                        required property var modelData
                        notification: modelData
                        compact: root.compact
                        Layout.fillWidth: true
                        onDismissed: id => Notifications.discardNotification(id)
                        onActionInvoked: (id, identifier) => Notifications.attemptInvokeAction(id, identifier)
                    }
                }
            }
        }
    }
}
