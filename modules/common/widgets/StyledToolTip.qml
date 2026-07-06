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

    // Anchor BELOW the hovered widget (Qt's default centres it ON the parent, so
    // a bar-icon tooltip covered the icon). ToolTip.y is measured from the parent
    // origin; push it past the parent's bottom edge.
    y: (parent?.height ?? 0) + 4
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
