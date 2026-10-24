import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

/**
 * Removable drives (bar module "drives", services/Drives.qml): shown while a
 * drive is plugged in; the popout lists drives and partitions with mount,
 * unmount, open and eject, and says when data is still being written.
 * Left-click pins it.
 */
Item {
    id: root
    property bool vertical: false
    visible: Drives.any
    implicitWidth: visible ? icon.implicitWidth + 8 : 0
    implicitHeight: visible ? (vertical ? icon.implicitHeight + 8 : Appearance.sizes.barHeight) : 0
    property bool pinned: false
    readonly property bool shown: (ma.containsMouse || root.pinned) && Drives.any
    onShownChanged: Drives.watch(shown)
    Component.onDestruction: if (shown) Drives.watch(false)
    readonly property bool anyWriting: Object.keys(Drives.writing).length > 0 || Object.keys(Drives.busy).length > 0

    MaterialSymbol {
        id: icon; anchors.centerIn: parent
        text: root.anyWriting ? "sync" : "usb"
        iconSize: Appearance?.font.pixelSize.larger ?? 20
        color: Appearance?.colors.colOnLayer1 ?? "#E6E1E5"
        RotationAnimation on rotation {
            running: root.anyWriting; from: 360; to: 0; duration: AnimationConfig.scaledDuration(1200) || 1200; loops: Animation.Infinite
            onRunningChanged: if (!running) icon.rotation = 0
        }
    }
    MouseArea {
        id: ma; anchors.fill: parent; hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: root.pinned = !root.pinned
    }

    BarModulePopout {
        shown: root.shown
        popupWidth: 320; popupHeight: col.implicitHeight + 24

        ColumnLayout {
            id: col; anchors.fill: parent; spacing: 10

            RowLayout {
                spacing: 10
                MaterialSymbol { text: "usb"; iconSize: 24; fill: 1; color: Appearance.colors.colPrimary }
                StyledText { text: "Drives"; font.pixelSize: Appearance.font.pixelSize.normal; font.weight: Font.DemiBold; Layout.fillWidth: true }
            }

            Repeater {
                model: Drives.drives
                ColumnLayout {
                    id: drive
                    required property var modelData
                    readonly property string busy: Drives.busy[modelData.name] ?? ""
                    readonly property var w: Drives.writing[modelData.name] ?? null
                    Layout.fillWidth: true
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        MaterialSymbol { text: drive.modelData.tran === "mmc" ? "sd_card" : "usb"; iconSize: 18; color: Appearance.colors.colOnLayer1 }
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 0
                            StyledText { text: drive.modelData.model; elide: Text.ElideRight; Layout.fillWidth: true; font.weight: Font.Medium }
                            StyledText {
                                Layout.fillWidth: true
                                text: drive.busy ? `${drive.busy.charAt(0).toUpperCase()}${drive.busy.slice(1)}…`
                                    : drive.w ? `Writing ${Drives.formatSize(drive.w.rate)}/s · not safe to remove`
                                    : Drives.formatSize(drive.modelData.size)
                                color: drive.w || drive.busy ? Appearance.colors.colWarning : Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smaller
                            }
                        }
                        RippleButton {
                            implicitHeight: 30
                            enabled: !drive.busy
                            buttonText: "Eject"
                            onClicked: Drives.eject(drive.modelData)
                        }
                    }
                    // While it writes or ejects: what the system still has to write out
                    // (system-wide: the kernel doesn't count it per disk).
                    StyledText {
                        visible: (drive.busy === "ejecting" || !!drive.w) && Drives.pendingBytes > 0
                        Layout.leftMargin: 26
                        text: `${Drives.formatSize(Drives.pendingBytes)} waiting to be written`
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }

                    Repeater {
                        model: drive.modelData.parts
                        RowLayout {
                            id: part
                            required property var modelData
                            readonly property bool mounted: modelData.mountpoints.length > 0
                            Layout.fillWidth: true; Layout.leftMargin: 26; spacing: 6
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 0
                                StyledText {
                                    Layout.fillWidth: true; elide: Text.ElideRight
                                    text: part.modelData.label || part.modelData.name
                                    font.pixelSize: Appearance.font.pixelSize.small
                                }
                                StyledText {
                                    Layout.fillWidth: true; elide: Text.ElideRight
                                    text: [part.modelData.fstype, Drives.formatSize(part.modelData.size), part.mounted ? "mounted" : ""].filter(x => x).join(" · ")
                                    color: Appearance.colors.colSubtext
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                }
                            }
                            RippleButton {
                                visible: part.mounted
                                implicitHeight: 26
                                buttonText: "Open"
                                onClicked: DefaultApps.launch(["xdg-open", part.modelData.mountpoints[0]])
                            }
                            RippleButton {
                                visible: !!part.modelData.fstype
                                enabled: !drive.busy
                                implicitHeight: 26
                                buttonText: part.mounted ? "Unmount" : "Mount"
                                onClicked: part.mounted ? Drives.unmount(part.modelData) : Drives.mount(part.modelData)
                            }
                        }
                    }
                }
            }

            StyledText {
                visible: Drives.lastError.length > 0
                Layout.fillWidth: true; wrapMode: Text.Wrap
                text: Drives.lastError
                color: Appearance.colors.colError
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
        }
    }
}
