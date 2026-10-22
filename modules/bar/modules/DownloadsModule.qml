import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

/**
 * Downloads (bar/pill module "downloads", services/Downloads.qml): shown while
 * a browser downloads into the download folder, and after, until the finished
 * entries are dismissed. The popout lists each with its size and rate;
 * finished ones open the file or its folder. Left-click pins it.
 */
Item {
    id: root
    property bool vertical: false
    visible: Downloads.any
    implicitWidth: visible ? row.implicitWidth + 8 : 0
    implicitHeight: visible ? (vertical ? row.implicitHeight + 8 : Appearance.sizes.barHeight) : 0
    property bool pinned: false
    readonly property bool shown: (ma.containsMouse || root.pinned) && Downloads.any

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 4
        MaterialSymbol {
            text: Downloads.downloading ? "download" : "download_done"
            iconSize: Appearance?.font.pixelSize.larger ?? 20
            color: Downloads.downloading ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
        }
        StyledText {
            visible: Downloads.downloading && !root.vertical
            text: Downloads.rate > 0 ? `${Drives.formatSize(Downloads.rate)}/s` : Drives.formatSize(Downloads.active.reduce((s, f) => s + f.size, 0))
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colOnLayer1
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
        popupWidth: 340; popupHeight: col.implicitHeight + 24

        ColumnLayout {
            id: col; anchors.fill: parent; spacing: 10

            RowLayout {
                spacing: 10
                MaterialSymbol { text: "download"; iconSize: 24; fill: 1; color: Appearance.colors.colPrimary }
                StyledText { text: "Downloads"; font.pixelSize: Appearance.font.pixelSize.normal; font.weight: Font.DemiBold; Layout.fillWidth: true }
                RippleButton {
                    visible: Downloads.finished.length > 0
                    implicitHeight: 28
                    buttonText: "Clear"
                    onClicked: Downloads.clear("")
                }
            }

            Repeater {
                model: Downloads.active
                RowLayout {
                    id: act
                    required property var modelData
                    Layout.fillWidth: true; spacing: 8
                    MaterialSymbol { text: "downloading"; iconSize: 18; color: Appearance.colors.colPrimary }
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 0
                        StyledText { text: act.modelData.name; elide: Text.ElideMiddle; Layout.fillWidth: true; font.weight: Font.Medium }
                        StyledText {
                            Layout.fillWidth: true
                            // browsers keep the total to themselves: what has come, and how fast
                            text: act.modelData.rate > 0 ? `${Drives.formatSize(act.modelData.size)} · ${Drives.formatSize(act.modelData.rate)}/s`
                                : `${Drives.formatSize(act.modelData.size)} · stalled`
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.smaller
                        }
                    }
                }
            }

            Repeater {
                model: Downloads.finished
                RowLayout {
                    id: fin
                    required property var modelData
                    Layout.fillWidth: true; spacing: 6
                    MaterialSymbol { text: "check_circle"; iconSize: 18; color: Appearance.colors.colOnLayer1 }
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 0
                        StyledText { text: fin.modelData.name; elide: Text.ElideMiddle; Layout.fillWidth: true }
                        StyledText {
                            text: `${Drives.formatSize(fin.modelData.size)} · ${Qt.formatTime(new Date(fin.modelData.at * 1000), Config.options?.time?.format ?? "hh:mm")}`
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.smallest
                        }
                    }
                    RippleButton { implicitHeight: 26; buttonText: "Open"; onClicked: Downloads.open(fin.modelData.path) }
                    RippleButton { implicitHeight: 26; buttonText: "Folder"; onClicked: Downloads.showFolder(fin.modelData.path) }
                }
            }
        }
    }
}
