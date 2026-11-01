import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

/**
 * Phone through KDE Connect (bar module "kdeconnect", services/KdeConnect.qml,
 * needs kdeConnect.enable): the phone's battery while it's reachable; the
 * popout lists paired devices with ring, ping, clipboard and send a file.
 * Left-click pins it.
 */
Item {
    id: root
    property bool vertical: false
    readonly property var dev: KdeConnect.device
    visible: KdeConnect.enabled && (!!root.dev || KdeConnect.daemon === "hung")
    implicitWidth: visible ? row.implicitWidth + 8 : 0
    implicitHeight: visible ? (vertical ? row.implicitHeight + 8 : Appearance.sizes.barHeight) : 0
    property bool pinned: false
    readonly property bool shown: (ma.containsMouse || root.pinned) && root.visible

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 3
        opacity: root.dev?.reachable ? 1 : 0.5
        MaterialSymbol {
            text: KdeConnect.daemon === "hung" ? "mobile_off" : root.dev?.charging ? "mobile_charge" : "smartphone"
            iconSize: Appearance?.font.pixelSize.larger ?? 20
            color: KdeConnect.daemon === "hung" ? Appearance.colors.colError : (Appearance?.colors.colOnLayer1 ?? "#E6E1E5")
        }
        StyledText {
            visible: !root.vertical && (root.dev?.reachable ?? false) && (root.dev?.charge ?? -1) >= 0
            text: `${root.dev?.charge ?? 0}%`
            font.pixelSize: Appearance.font.pixelSize.small
            font.family: Appearance.font.family.numbers
        }
    }
    MouseArea {
        id: ma; anchors.fill: parent; hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.pinned = !root.pinned
    }

    BarModulePopout {
        shown: root.shown
        popupWidth: 380; popupHeight: col.implicitHeight + 24

        ColumnLayout {
            id: col; anchors.fill: parent; spacing: 10

            RowLayout {
                spacing: 10
                MaterialSymbol { text: "smartphone"; iconSize: 24; fill: 1; color: Appearance.colors.colPrimary }
                StyledText { text: "KDE Connect"; font.pixelSize: Appearance.font.pixelSize.normal; font.weight: Font.DemiBold; Layout.fillWidth: true }
            }
            StyledText {
                visible: KdeConnect.daemon === "hung" || KdeConnect.daemon === "missing"
                Layout.fillWidth: true; wrapMode: Text.Wrap
                text: KdeConnect.daemon === "hung" ? "kdeconnectd is running but not answering; restart it (systemctl --user restart or kill and start kdeconnectd)."
                    : "kdeconnectd isn't running."
                color: Appearance.colors.colError
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
            Repeater {
                model: KdeConnect.devices.filter(d => d.paired)
                ColumnLayout {
                    id: d
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 4
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        MaterialSymbol { text: d.modelData.type === "tablet" ? "tablet" : "smartphone"; iconSize: 18; color: Appearance.colors.colOnLayer1 }
                        StyledText { text: d.modelData.name; elide: Text.ElideRight; Layout.fillWidth: true; font.weight: Font.Medium }
                        StyledText {
                            text: !d.modelData.reachable ? "unreachable"
                                : d.modelData.charge >= 0 ? `${d.modelData.charge}%${d.modelData.charging ? " · charging" : ""}` : ""
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.smaller
                        }
                    }
                    RowLayout {
                        visible: d.modelData.reachable
                        Layout.leftMargin: 26; spacing: 6
                        RippleButton { implicitHeight: 28; buttonText: "Ring"; onClicked: KdeConnect.ring(d.modelData.id) }
                        RippleButton { implicitHeight: 28; buttonText: "Ping"; onClicked: KdeConnect.ping(d.modelData.id) }
                        RippleButton { implicitHeight: 28; buttonText: "Clipboard"; onClicked: KdeConnect.sendClipboard(d.modelData.id) }
                        RippleButton {
                            implicitHeight: 28; buttonText: "File…"
                            onClicked: KdeConnect.pickAndSend(d.modelData.id)
                        }
                    }
                }
            }
            StyledText {
                visible: KdeConnect.daemon === "ok" && KdeConnect.devices.filter(d => d.paired).length === 0
                text: "No paired devices. Pair from the KDE Connect app on your phone."
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
        }
    }
}
