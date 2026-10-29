import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

// Bundled piece: picture (~/.face, or the picture setting), user name,
// uptime, a status line, and lock / settings / power.
Item {
    id: root
    property var ctx
    property var settings: ({})
    readonly property string user: Quickshell.env("USER") ?? ""
    readonly property string picture: {
        let p = (root.settings?.picture ?? "").trim()
        if (p.startsWith("~/")) p = Quickshell.env("HOME") + p.slice(1)
        return p || `${Quickshell.env("HOME")}/.face`
    }

    RowLayout {
        anchors.fill: parent
        spacing: 14
        ClippingRectangle {
            Layout.preferredWidth: Math.min(root.height, root.width * 0.35)
            Layout.preferredHeight: Layout.preferredWidth
            radius: width / 2
            color: Appearance.colors.colPrimaryContainer
            StyledText {
                anchors.centerIn: parent
                visible: avatar.status !== Image.Ready
                text: root.user.charAt(0).toUpperCase()
                font.pixelSize: parent.height * 0.45
                color: Appearance.colors.colOnPrimaryContainer
            }
            Image {
                id: avatar
                anchors.fill: parent
                source: root.picture ? `file://${root.picture}` : ""
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: width * 2; sourceSize.height: height * 2
                asynchronous: true
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            StyledText { text: root.user; font.pixelSize: Appearance.font.pixelSize.larger; font.weight: Font.DemiBold; elide: Text.ElideRight; Layout.fillWidth: true }
            StyledText { text: `Up ${DateTime.uptime}`; color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.smaller }
            StyledText {
                visible: text.length > 0
                text: root.settings?.status ?? ""
                color: Appearance.colors.colOnLayer1
                wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                Layout.fillWidth: true
            }
            Item { Layout.fillHeight: true }
            RowLayout {
                spacing: 4
                ProfileButton { glyph: "lock"; tip: "Lock"; onClicked: Quickshell.execDetached(["loginctl", "lock-session"]) }
                ProfileButton { glyph: "settings"; tip: "Settings"; onClicked: GlobalStates.settingsOpen = true }
                ProfileButton { glyph: "power_settings_new"; tip: "Power"; onClicked: GlobalStates.sessionOpen = true }
            }
        }
    }
    component ProfileButton: RippleButton {
        property string glyph
        property string tip
        implicitWidth: 34; implicitHeight: 34; buttonRadius: 17
        contentItem: MaterialSymbol { text: parent.glyph; iconSize: 20; horizontalAlignment: Text.AlignHCenter; color: Appearance.colors.colOnLayer1 }
        StyledToolTip { text: parent.tip }
    }
}
