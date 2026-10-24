pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.modules.common.functions

// Placeholder rows for a chapter / episode list while it's fetched: a number
// pill and a title (plus a subtitle line when `subtitle` is set), rippling
// top to bottom. Row height and divider inset match the real list. Fades out
// once `active` drops.
Rectangle {
    id: root

    property bool active: false
    property int rowHeight: 58
    property bool subtitle: true
    property int dividerInset: 72

    color: Appearance.m3colors.m3background
    clip: true
    opacity: root.active ? 1 : 0
    visible: root.opacity > 0
    Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(280); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }

    Column {
        anchors { left: parent.left; right: parent.right }

        Repeater {
            model: root.visible ? Math.ceil(root.height / root.rowHeight) : 0

            delegate: Item {
                id: row
                required property int index

                width: parent.width
                height: root.rowHeight

                Item {
                    id: content
                    anchors { fill: parent; leftMargin: 16; rightMargin: 16 }

                    Rectangle {
                        id: pill
                        anchors.verticalCenter: parent.verticalCenter
                        width: 44; height: 26; radius: 13
                        color: Appearance.m3colors.m3surfaceContainerHigh
                    }

                    Column {
                        anchors {
                            left: pill.right; leftMargin: 14
                            right: parent.right; rightMargin: 24
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 7

                        Rectangle {
                            // Varied so the rows don't read as a barcode.
                            width: parent.width * [0.62, 0.48, 0.7, 0.55, 0.4][row.index % 5]
                            height: 9; radius: 4.5
                            color: Appearance.m3colors.m3surfaceContainerHigh
                        }
                        Rectangle {
                            visible: root.subtitle
                            width: 64; height: 7; radius: 3.5
                            color: Appearance.m3colors.m3surfaceContainer
                        }
                    }
                }

                Rectangle {
                    anchors {
                        bottom: parent.bottom
                        left: parent.left; right: parent.right
                        leftMargin: root.dividerInset; rightMargin: 16
                    }
                    height: 1; color: Appearance.m3colors.m3outlineVariant; opacity: 0.2
                }

                SkeletonPulse {
                    target: content
                    delay: row.index * 90
                    running: root.visible
                }
            }
        }
    }
}
