import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls

ToolTip {
    id: root
    property bool extraVisibleCondition: true
    property bool alternativeVisibleCondition: false

    readonly property bool internalVisibleCondition: (extraVisibleCondition && (parent.hovered === undefined || parent?.hovered)) || alternativeVisibleCondition
    verticalPadding: 5
    horizontalPadding: 10
    background: null

    // Anchor BELOW the hovered widget (Qt centres it ON the parent, covering the
    // icon). Qt ToolTip resets a plain `y` binding to 0 on open, and even
    // onOpened/onVisibleChanged get overridden by a later reposition — so hold y
    // with a Binding that stays active while visible (Qt can't clear it).
    margins: 0
    Binding {
        target: root
        property: "y"
        value: (root.parent?.height ?? 0) + 4
        when: root.visible
        restoreMode: Binding.RestoreNone
    }
    font {
        family: Appearance.font.family.main
        variableAxes: Appearance.font.variableAxes.main
        pixelSize: Appearance?.font.pixelSize.smaller ?? 14
        hintingPreference: Font.PreferNoHinting
    }

    delay: 0
    visible: internalVisibleCondition

    contentItem: StyledToolTipContent {
        font: root.font
        text: root.text
        shown: root.internalVisibleCondition
        horizontalPadding: root.horizontalPadding
        verticalPadding: root.verticalPadding
    }
}
