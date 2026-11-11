import qs.modules.common
import QtQuick
import QtQuick.Layouts

TextInput {
    id: root
    renderType: Text.NativeRendering
    font {
        hintingPreference: Font.PreferDefaultHinting
        family: Appearance.font.family.main
        pixelSize: Appearance?.font.pixelSize.small ?? 15
        variableAxes: Appearance.font.variableAxes.main
    }
    color: Appearance?.m3colors.m3onBackground ?? "black"
    selectionColor: Appearance?.colors.colPrimary ?? "#65558F"
    selectedTextColor: Appearance?.m3colors.m3onPrimary ?? "white"
    selectByMouse: true
    clip: true // a value longer than the field scrolls inside it instead of drawing over its neighbours

    // boxed: draw the field (ConfigTextInput's look), for inputs that sit bare in a row
    // and would otherwise be invisible while empty.
    property bool boxed: false
    leftPadding: boxed ? 8 : 0
    rightPadding: boxed ? 8 : 0
    topPadding: boxed ? 5 : 0
    bottomPadding: boxed ? 5 : 0
    // An empty field has no width of its own; a field that sets one keeps it.
    Layout.preferredWidth: boxed ? 160 : -1
    Rectangle {
        z: -1 // under the text
        anchors.fill: parent
        visible: root.boxed
        radius: Appearance?.rounding.small ?? 8
        color: Appearance?.colors.colLayer2 ?? "#2B2930"
        border.width: 1
        border.color: root.activeFocus ? (Appearance?.colors.colPrimary ?? "#65558F")
                                       : (Appearance?.colors.colOutlineVariant ?? "#49454F")
    }
}
