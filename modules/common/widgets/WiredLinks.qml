import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * WiredLinks — the "Wired & tethering" section of the network panels:
 * ethernet, USB tethering, Bluetooth tethering and mobile broadband
 * (Network.links), each with its state, IP, a "traffic" badge on the one
 * carrying the default route, and connect / disconnect. Hidden (zero
 * height) when there are none. The host gives it a background.
 */
ColumnLayout {
    id: root

    readonly property var kindLabels: ({ ethernet: "Ethernet", usb: "USB tethering", bluetooth: "Bluetooth tethering", mobile: "Mobile broadband" })

    visible: Network.links.length > 0
    spacing: 4

    StyledText {
        text: "Wired & tethering"
        font.pixelSize: Appearance?.font.pixelSize.small ?? 14
        font.weight: Font.DemiBold
        color: Appearance?.colors.colOnLayer1 ?? "#E6E1E5"
    }

    Repeater {
        model: Network.links
        delegate: RowLayout {
            id: row
            required property var modelData
            readonly property bool busy: Network.linkBusy === modelData.device
            Layout.fillWidth: true
            spacing: 8

            MaterialSymbol {
                text: row.modelData.icon; iconSize: 20
                fill: row.modelData.connected ? 1 : 0
                color: row.modelData.connected ? (Appearance?.colors.colPrimary ?? "#65558F") : (Appearance?.colors.colSubtext ?? "#CAC4D0")
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: row.modelData.title
                        font.pixelSize: Appearance?.font.pixelSize.small ?? 14
                        font.weight: row.modelData.connected ? Font.DemiBold : Font.Normal
                        color: Appearance?.colors.colOnLayer1 ?? "#E6E1E5"
                    }
                    // The link the default route goes through.
                    Rectangle {
                        visible: row.modelData.primary
                        implicitWidth: trafficLabel.implicitWidth + 10
                        implicitHeight: trafficLabel.implicitHeight + 2
                        radius: height / 2
                        color: Appearance?.colors.colPrimaryContainer ?? "#EADDFF"
                        StyledText {
                            id: trafficLabel
                            anchors.centerIn: parent
                            text: "Traffic"
                            font.pixelSize: Appearance?.font.pixelSize.smallest ?? 10
                            color: Appearance?.colors.colOnPrimaryContainer ?? "#21005D"
                        }
                        StyledToolTip { text: "Carries the default route" }
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: [root.kindLabels[row.modelData.kind], row.busy ? "working…" : row.modelData.state, row.modelData.ip].filter(s => s).join(" · ")
                    font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
                    font.family: row.modelData.ip ? (Appearance?.font.family.numbers ?? "monospace") : (Appearance?.font.family.main ?? "sans-serif")
                    color: Appearance?.colors.colSubtext ?? "#CAC4D0"
                }
            }
            RippleButton {
                implicitWidth: 28; implicitHeight: 28
                buttonRadius: Appearance?.rounding.full ?? 9999
                colBackground: "transparent"
                colBackgroundHover: Appearance?.colors.colLayer2 ?? "#2B2930"
                enabled: Network.linkBusy === ""
                opacity: enabled ? 1 : 0.5
                releaseAction: () => Network.setLinkConnected(row.modelData.device, !row.modelData.connected)
                contentItem: MaterialSymbol {
                    text: row.modelData.connected ? "link_off" : "link"; iconSize: 18
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    color: Appearance?.colors.colOnLayer1 ?? "#E6E1E5"
                }
                StyledToolTip { text: row.modelData.connected ? "Disconnect" : "Connect" }
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        visible: Network.linkError !== ""
        text: Network.linkError
        wrapMode: Text.Wrap
        font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
        color: Appearance?.colors.colError ?? "#F2B8B5"
    }
}
