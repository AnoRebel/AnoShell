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

    // Drop BELOW the hovered widget instead of Qt's default (centred ON it),
    // so a bar-icon tooltip doesn't cover the icon you're pointing at. Centred
    // horizontally on the parent.
    y: (parent?.height ?? 0) + 4
    x: ((parent?.width ?? 0) - width) / 2
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
