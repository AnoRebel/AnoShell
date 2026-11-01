import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * What a list shows when there's nothing in it (onboarding-ux "Responsive
 * feedback states"): an icon, what's missing, how to get some, and an
 * optional action.
 *
 *   EmptyState { icon: "content_paste"; title: "The clipboard is empty"; hint: "Copy something" }
 */
ColumnLayout {
    id: root
    property string icon: "inbox"
    property string title: ""
    property string hint: ""
    property string actionText: ""
    signal action()
    spacing: 4

    MaterialSymbol {
        Layout.alignment: Qt.AlignHCenter
        text: root.icon
        iconSize: 30
        color: Appearance.colors.colSubtext
        opacity: 0.7
    }
    StyledText {
        Layout.fillWidth: true
        Layout.preferredWidth: 0 // the caller sets the width; the text wraps to it
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: root.title
        color: Appearance.colors.colSubtext
    }
    StyledText {
        Layout.fillWidth: true
        Layout.preferredWidth: 0 // the caller sets the width; the text wraps to it
        visible: root.hint !== ""
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: root.hint
        color: Appearance.colors.colSubtext
        opacity: 0.75
        font.pixelSize: Appearance.font.pixelSize.smaller
    }
    RippleButton {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: 4
        visible: root.actionText !== ""
        implicitHeight: 30
        buttonText: root.actionText
        onClicked: root.action()
    }
}
