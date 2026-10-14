import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * A settings row with label on the left and a control on the right.
 */
RowLayout {
    id: root
    property string label: ""
    property string sublabel: ""
    // Dotted config key this control edits; shows a "Changed/Reset" chip when set by the user.
    property string configKey: ""

    spacing: 12
    Layout.fillWidth: true

    ColumnLayout {
        spacing: 2
        Layout.fillWidth: true
        RowLayout {
            spacing: 6
            Layout.fillWidth: true
            StyledText {
                text: root.label
                font.pixelSize: Appearance?.font.pixelSize.small ?? 15
                Layout.fillWidth: true
            }
            ConfigOriginChip { configKey: root.configKey }
        }
        StyledText {
            text: root.sublabel
            visible: root.sublabel.length > 0
            font.pixelSize: Appearance?.font.pixelSize.smaller ?? 13
            opacity: 0.6
            Layout.fillWidth: true
            wrapMode: Text.Wrap
        }
    }
}
