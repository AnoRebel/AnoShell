import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * Shown next to a settings control whose value comes from the user's config
 * (or a legacy-key migration) rather than the bundled default. Clicking it
 * resets the key to the default.
 */
Rectangle {
    id: root
    property string configKey: ""

    readonly property string origin: configKey.length > 0 ? Config.originOf(configKey) : "default"
    visible: origin !== "default"

    implicitWidth: chipRow.implicitWidth + 12
    implicitHeight: 20
    radius: height / 2
    color: chipMouse.containsMouse
        ? (Appearance?.colors.colPrimaryContainer ?? "#E8DEF8")
        : (Appearance?.colors.colLayer2 ?? "#2B2930")
    Layout.alignment: Qt.AlignVCenter

    RowLayout {
        id: chipRow
        anchors.centerIn: parent
        spacing: 3
        MaterialSymbol {
            text: chipMouse.containsMouse ? "restart_alt" : "edit"
            iconSize: 12
            opacity: 0.8
        }
        StyledText {
            text: chipMouse.containsMouse ? "Reset" : (root.origin === "migrated" ? "Migrated" : "Changed")
            font.pixelSize: Appearance?.font.pixelSize.smallest ?? 10
            opacity: 0.8
        }
    }

    MouseArea {
        id: chipMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: Config.resetToDefault(root.configKey)
    }

    StyledToolTip {
        text: root.origin === "migrated"
            ? `${root.configKey} — moved here from an older key. Click to reset to the default.`
            : `${root.configKey} — set in your config. Click to reset to the default.`
        extraVisibleCondition: chipMouse.containsMouse
    }
}
