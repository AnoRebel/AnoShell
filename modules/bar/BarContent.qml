import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import qs.modules.bar.modules
import "."

/**
 * BarContent — Fully configurable bar content renderer.
 *
 * Every aspect is driven by config:
 *   - Which modules appear in left/center/right sections
 *   - Spacing between modules (per-section overridable)
 *   - Edge padding (distance from bar edges to first/last module)
 *   - Center group padding and corner radius
 *   - Click actions per section (what happens on left/right click)
 *   - Scroll actions per section (brightness/volume/workspace)
 *   - Separator visibility between sections
 *   - Module alignment within sections
 */
Item {
    id: root
    required property var barConfig
    required property bool isVertical
    required property string edge

    // ═══════════════════════════════════════════════════════════════════
    // Module lists (configurable per-bar or global fallback)
    // ═══════════════════════════════════════════════════════════════════
    readonly property var moduleConfig: barConfig?.modules ?? {
        "left": ["sidebarButton", "activeWindow"],
        "center": ["workspaces"],
        "right": ["clock", "battery", "network", "bluetooth", "tray", "sidebarButton"]
    }
    readonly property var leftModules: moduleConfig.left ?? []
    readonly property var centerModules: moduleConfig.center ?? []
    readonly property var rightModules: moduleConfig.right ?? []

    // ═══════════════════════════════════════════════════════════════════
    // Spacing & Padding (configurable at bar level → global fallback)
    // ═══════════════════════════════════════════════════════════════════
    readonly property real leftSpacing: barConfig?.leftSpacing ?? Config.options?.bar?.layout?.leftSpacing ?? 8
    readonly property real centerSpacing: barConfig?.centerSpacing ?? Config.options?.bar?.layout?.centerSpacing ?? 4
    readonly property real rightSpacing: barConfig?.rightSpacing ?? Config.options?.bar?.layout?.rightSpacing ?? 8
    readonly property real edgePadding: barConfig?.edgePadding ?? Config.options?.bar?.layout?.edgePadding ?? 8
    readonly property real centerGroupPadding: barConfig?.centerGroupPadding ?? Config.options?.bar?.layout?.centerGroupPadding ?? 5
    readonly property real centerGroupRadius: barConfig?.centerGroupRadius ?? Config.options?.bar?.layout?.centerGroupRadius ?? 8
    readonly property bool showCenterBackground: barConfig?.showCenterBackground ?? Config.options?.bar?.layout?.showCenterBackground ?? true
    readonly property bool showSeparators: barConfig?.showSeparators ?? Config.options?.bar?.layout?.showSeparators ?? false

    // ═══════════════════════════════════════════════════════════════════
    // Click Actions (configurable per section)
    // ═══════════════════════════════════════════════════════════════════
    // Empty-space left-click defaults to "none": clicking bar background should
    // do nothing, and icons handle their own left-click. (Previously these
    // defaulted to sidebarLeft/Right, so any click that fell through an icon —
    // most icons don't consume clicks — opened a sidebar unexpectedly.) Still
    // user-configurable via bar.actions.leftClick / .rightClick.
    readonly property string leftClickAction: barConfig?.leftClickAction ?? Config.options?.bar?.actions?.leftClick ?? "none"
    readonly property string rightClickAction: barConfig?.rightClickAction ?? Config.options?.bar?.actions?.rightClick ?? "none"
    readonly property string centerClickAction: barConfig?.centerClickAction ?? Config.options?.bar?.actions?.centerClick ?? "overview"
    readonly property string scrollLeftAction: barConfig?.scrollLeftAction ?? Config.options?.bar?.actions?.scrollLeft ?? "brightness"
    readonly property string scrollRightAction: barConfig?.scrollRightAction ?? Config.options?.bar?.actions?.scrollRight ?? "volume"
    readonly property string scrollCenterAction: barConfig?.scrollCenterAction ?? Config.options?.bar?.actions?.scrollCenter ?? "workspace"

    function performClickAction(action) {
        switch (action) {
            case "sidebarLeft":  GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen; break
            case "sidebarRight": GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen; break
            case "overview":     GlobalStates.overviewOpen = !GlobalStates.overviewOpen; break
            case "settings":     GlobalStates.settingsOpen = !GlobalStates.settingsOpen; break
            case "hud":          GlobalStates.hudVisible = !GlobalStates.hudVisible; break
            case "session":      GlobalStates.sessionOpen = !GlobalStates.sessionOpen; break
            case "clipboard":    GlobalStates.clipboardOpen = !GlobalStates.clipboardOpen; break
            case "wallpaper":    GlobalStates.wallpaperSelectorOpen = !GlobalStates.wallpaperSelectorOpen; break
            case "cheatsheet":   GlobalStates.cheatsheetOpen = !GlobalStates.cheatsheetOpen; break
            case "none": break
            default: break
        }
    }

    function performScrollAction(action, isUp) {
        switch (action) {
            case "brightness":
                const monitor = Brightness.getMonitorForScreen(root.QsWindow.window?.screen)
                if (monitor) monitor.setBrightness(monitor.brightness + (isUp ? 0.05 : -0.05))
                break
            case "volume":
                if (isUp) Audio.incrementVolume(); else Audio.decrementVolume()
                break
            case "workspace":
                CompositorService.focusWorkspaceRelative(isUp ? -1 : 1)
                break
            case "none": break
        }
    }

    // Tell a loaded module where it lives: its section (position-aware modules
    // like sidebarButton) and the bar's orientation.
    function _place(item, section) {
        if (!item) return
        if (item.hasOwnProperty("barSection")) item.barSection = section
        if (item.hasOwnProperty("vertical")) item.vertical = Qt.binding(() => root.isVertical)
    }

    // ═══════════════════════════════════════════════════════════════════
    // Separator component
    // ═══════════════════════════════════════════════════════════════════
    // Anchor-positioned (never a Layout child) — Layout.* attached props here
    // crash Quickshell 0.3.0 via recursive refWindow() during window attach.
    component BarSeparator: Rectangle {
        visible: root.showSeparators
        width: 1
        height: 1
        color: Appearance?.colors.colOutlineVariant ?? "#C4C7C5"
        opacity: 0.3
        anchors.topMargin: isVertical ? 0 : Appearance.sizes.baseBarHeight / 3
        anchors.bottomMargin: isVertical ? 0 : Appearance.sizes.baseBarHeight / 3
        anchors.leftMargin: isVertical ? Appearance.sizes.baseBarHeight / 3 : 0
        anchors.rightMargin: isVertical ? Appearance.sizes.baseBarHeight / 3 : 0
    }

    // ═══════════════════════════════════════════════════════════════════
    // LEFT SECTION
    // ═══════════════════════════════════════════════════════════════════
    Item {
        id: leftSection
        anchors {
            top: parent.top
            left: parent.left
            bottom: isVertical ? undefined : parent.bottom
            right: isVertical ? parent.right : middleSection.left
        }
        height: isVertical ? leftGrid.implicitHeight + root.edgePadding : undefined

        // Section click/scroll catcher — sits BEHIND the modules (declared
        // first → lowest in stacking). Module-level MouseAreas (tray icons,
        // sidebar buttons, etc.) are later siblings and grab their own clicks;
        // only clicks on empty section space fall through to this.
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onWheel: event => {
                const delta = event.angleDelta.y
                if (delta !== 0) performScrollAction(scrollLeftAction, delta > 0)
            }
            onClicked: event => {
                if (event.button === Qt.LeftButton) performClickAction(leftClickAction)
            }
        }

        GridLayout {
            id: leftGrid
            anchors.fill: parent
            anchors.leftMargin: isVertical ? 0 : root.edgePadding
            anchors.rightMargin: isVertical ? 0 : 4
            anchors.topMargin: isVertical ? root.edgePadding : 0
            flow: isVertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
            rowSpacing: root.leftSpacing; columnSpacing: root.leftSpacing

            Repeater {
                model: root.leftModules
                Loader {
                    required property string modelData
                    Layout.fillHeight: !isVertical
                    Layout.fillWidth: isVertical
                    Layout.alignment: isVertical ? Qt.AlignHCenter : Qt.AlignVCenter
                    sourceComponent: BarModuleLoader.getModule(modelData)
                    // Tell position-aware modules (sidebarButton) which section
                    // they live in — reliable, unlike guessing from pixel X.
                    onLoaded: root._place(item, "left")
                }
            }
            Item { Layout.fillWidth: !isVertical; Layout.fillHeight: isVertical }
        }
    }

    // Optional separator
    BarSeparator {
        anchors {
            right: middleSection.left; rightMargin: 4
            top: parent.top; bottom: parent.bottom
        }
        visible: root.showSeparators && !isVertical && leftModules.length > 0 && centerModules.length > 0
    }

    // ═══════════════════════════════════════════════════════════════════
    // CENTER SECTION
    // ═══════════════════════════════════════════════════════════════════
    Item {
        id: middleSection
        // top+bottom already pin the vertical extent; adding verticalCenter
        // on top of them is an over-specified anchor conflict.
        anchors {
            top: isVertical ? leftSection.bottom : parent.top
            bottom: isVertical ? rightSection.top : parent.bottom
            horizontalCenter: parent.horizontalCenter
        }
        implicitWidth: isVertical ? parent.width : centerRow.implicitWidth
        implicitHeight: isVertical ? centerRow.implicitHeight : parent.height

        MouseArea {
            anchors.fill: parent
            // Only the right button is handled here (centerClickAction). Accepting
            // the left button too would swallow it before the workspace buttons
            // layered above could receive the click, making them non-clickable.
            acceptedButtons: Qt.RightButton
            onWheel: event => {
                const delta = event.angleDelta.y
                if (delta !== 0) performScrollAction(scrollCenterAction, delta > 0)
            }
            onClicked: event => {
                if (event.button === Qt.RightButton) performClickAction(centerClickAction)
            }
        }

        RowLayout {
            id: centerRow
            anchors.centerIn: parent
            spacing: root.centerSpacing

            // Center group container
            BarGroup {
                id: centerGroup
                padding: root.centerGroupPadding
                visible: centerModules.length > 0
                vertical: root.isVertical

                showBackground: root.showCenterBackground
                backgroundColor: Appearance?.colors.colLayer1 ?? "#E5E1EC"
                backgroundRadius: root.centerGroupRadius

                Repeater {
                    model: root.centerModules
                    Loader {
                        required property string modelData
                        Layout.fillHeight: !isVertical
                        Layout.fillWidth: isVertical
                        Layout.alignment: isVertical ? Qt.AlignHCenter : Qt.AlignVCenter
                        sourceComponent: BarModuleLoader.getModule(modelData)
                        onLoaded: root._place(item, "center")
                    }
                }
            }
        }
    }

    // Optional separator
    BarSeparator {
        anchors {
            left: middleSection.right; leftMargin: 4
            top: parent.top; bottom: parent.bottom
        }
        visible: root.showSeparators && !isVertical && centerModules.length > 0 && rightModules.length > 0
    }

    // ═══════════════════════════════════════════════════════════════════
    // RIGHT SECTION
    // ═══════════════════════════════════════════════════════════════════
    Item {
        id: rightSection
        anchors {
            top: isVertical ? undefined : parent.top
            bottom: parent.bottom
            left: isVertical ? parent.left : middleSection.right
            right: parent.right
        }
        height: isVertical ? rightGrid.implicitHeight + root.edgePadding : undefined

        // Section click/scroll catcher behind the modules (see leftSection).
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onWheel: event => {
                const delta = event.angleDelta.y
                if (delta !== 0) performScrollAction(scrollRightAction, delta > 0)
            }
            onClicked: event => {
                if (event.button === Qt.LeftButton) performClickAction(rightClickAction)
            }
        }

        // Laid out from the far end: right to left, or bottom up when vertical.
        GridLayout {
            id: rightGrid
            anchors.fill: parent
            anchors.leftMargin: isVertical ? 0 : 4
            anchors.rightMargin: isVertical ? 0 : root.edgePadding
            anchors.bottomMargin: isVertical ? root.edgePadding : 0
            flow: isVertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
            layoutDirection: isVertical ? Qt.LeftToRight : Qt.RightToLeft
            rowSpacing: root.rightSpacing; columnSpacing: root.rightSpacing

            Repeater {
                model: isVertical ? root.rightModules.slice().reverse() : root.rightModules
                Loader {
                    required property string modelData
                    Layout.fillHeight: !isVertical
                    Layout.fillWidth: isVertical
                    Layout.alignment: isVertical ? Qt.AlignHCenter : Qt.AlignVCenter
                    sourceComponent: BarModuleLoader.getModule(modelData)
                    onLoaded: root._place(item, "right")
                }
            }
            Item { Layout.fillWidth: !isVertical }
        }
    }
}
