import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * RippleButton with a leading MaterialSymbol icon and text label.
 */
RippleButton {
    id: root
    property string iconName: ""
    property real iconSize: Appearance?.font.pixelSize.normal ?? 18
    property real iconFill: 0
    // On the primary fill (toggled, default colours) icon and label take its
    // on-colour, as RippleButton's label does.
    readonly property color _fg: root.toggled && root.enabled && Qt.colorEqual(root.colBackgroundToggled, Appearance?.colors.colPrimary ?? "#65558F")
        ? (Appearance?.colors.colOnPrimary ?? "white") : (Appearance?.m3colors.m3onBackground ?? "black")

    contentItem: RowLayout {
        spacing: 6
        MaterialSymbol {
            text: root.iconName
            iconSize: root.iconSize
            fill: root.iconFill
            visible: root.iconName.length > 0
            color: root._fg
            Layout.alignment: Qt.AlignVCenter
        }
        StyledText {
            text: root.buttonText
            visible: root.buttonText.length > 0
            color: root._fg
            Layout.alignment: Qt.AlignVCenter
        }
    }
}
