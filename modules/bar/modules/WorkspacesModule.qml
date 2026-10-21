import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * Workspaces bar module — dynamic, expandable indicators.
 *
 * By default only "interesting" workspaces are shown (occupied ones plus the
 * current one) for a clean look; a trailing ••• button expands to all
 * `workspacesShown` slots. Set bar.workspaces.alwaysShowAll to skip the
 * collapsing behaviour entirely. Works on Hyprland and Niri.
 */
Item {
    id: root
    property bool vertical: false

    readonly property int workspacesShown: Config.options?.bar?.workspaces?.shown ?? 10
    readonly property bool alwaysShowAll: Config.options?.bar?.workspaces?.alwaysShowAll ?? false
    property bool expanded: false

    readonly property string screenName: root.QsWindow.window?.screen?.name ?? ""
    readonly property int currentWorkspaceNumber: CompositorService.activeWorkspaceOn(root.screenName) || 1

    property list<bool> workspaceOccupied: []
    property int buttonSize: 26
    property real activeMargin: 2

    // The workspace numbers to actually render. Collapsed mode keeps occupied
    // workspaces and the current one (so you can always see where you are);
    // expanded / alwaysShowAll modes show every slot 1..workspacesShown.
    // Explicitly recomputed (not a reactive binding) to avoid a binding loop
    // between this list, the GridLayout that consumes it, and the geometry it
    // drives. recomputeVisible() is called from every input that affects it.
    property var visibleWorkspaces: [1]
    function recomputeVisible() {
        if (alwaysShowAll || expanded) {
            const all = []
            for (let i = 1; i <= workspacesShown; i++) all.push(i)
            visibleWorkspaces = all
            return
        }
        const set = {}
        for (let i = 0; i < workspaceOccupied.length; i++)
            if (workspaceOccupied[i]) set[i + 1] = true
        set[currentWorkspaceNumber] = true
        const out = Object.keys(set).map(n => parseInt(n)).filter(n => n >= 1 && n <= workspacesShown)
        out.sort((a, b) => a - b)
        visibleWorkspaces = out.length > 0 ? out : [currentWorkspaceNumber]
    }
    onExpandedChanged: recomputeVisible()
    onAlwaysShowAllChanged: recomputeVisible()

    // Whether there are hidden workspaces the ••• button could reveal.
    readonly property bool hasHidden: !alwaysShowAll && visibleWorkspaces.length < workspacesShown

    // Size from the data (count of visible cells + the expand button), NOT from
    // wsRow.implicitWidth — wsRow is centered in this Item, so deriving the
    // Item's size from a centered child forms a binding loop.
    readonly property bool _showToggle: hasHidden || expanded
    readonly property int _toggleSize: Math.round(buttonSize * 0.7)
    readonly property int _gap: 2
    // Cells + the toggle + the gaps between them: the grid's exact length, so
    // the group's padding is the same at both ends.
    readonly property int _length: visibleWorkspaces.length * buttonSize + (_showToggle ? _toggleSize : 0)
        + _gap * Math.max(0, visibleWorkspaces.length - (_showToggle ? 0 : 1))
    implicitWidth: vertical ? buttonSize : _length
    implicitHeight: vertical ? _length : Appearance.sizes.barHeight

    function updateOccupied() {
        const ws = CompositorService.workspacesFor(root.screenName)
        workspaceOccupied = Array.from({ length: workspacesShown }, (_, i) =>
            ws.some(w => w.number === i + 1 && w.occupied))
        recomputeVisible()
    }

    function switchTo(n) { CompositorService.focusWorkspace(n, root.screenName) }

    Component.onCompleted: updateOccupied()
    Connections {
        target: CompositorService
        function onWorkspacesChanged() { root.updateOccupied() }
    }
    onCurrentWorkspaceNumberChanged: { updateOccupied(); recomputeVisible() }

    // Scroll anywhere on the strip to switch; right-click toggles overview.
    MouseArea {
        z: 0
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onWheel: (event) => {
            const delta = event.angleDelta.y
            if (delta === 0) return
            const direction = delta > 0 ? -1 : 1
            CompositorService.focusWorkspaceRelative(direction, root.screenName)
        }
        onPressed: (event) => {
            if (event.button === Qt.RightButton) GlobalStates.overviewOpen = !GlobalStates.overviewOpen
        }
    }

    // Dynamic pills laid out in order. Each is its own clickable cell with the
    // dot indicator; the active one gets a filled pill behind it.
    GridLayout {
        id: wsRow
        z: 3
        anchors.centerIn: parent
        flow: vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        columnSpacing: root._gap
        rowSpacing: root._gap

        Repeater {
            model: root.visibleWorkspaces
            delegate: MouseArea {
                id: cell
                required property var modelData // the workspace number
                readonly property bool isActive: root.currentWorkspaceNumber === modelData
                readonly property bool isOccupied: root.workspaceOccupied[modelData - 1] ?? false
                implicitWidth: buttonSize
                implicitHeight: vertical ? buttonSize : Appearance.sizes.barHeight
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: root.switchTo(cell.modelData)

                // Active / occupied background pill
                Rectangle {
                    anchors.centerIn: parent
                    width: buttonSize - activeMargin * 2
                    height: width
                    radius: width / 2
                    color: cell.isActive
                        ? (Appearance?.colors.colPrimary ?? "#65558F")
                        : (Appearance?.m3colors.m3secondaryContainer ?? "#E8DEF8")
                    opacity: cell.isActive ? 1 : (cell.isOccupied ? 0.5 : 0)
                    Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(200); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }
                    Behavior on color { ColorAnimation { duration: AnimationConfig.scaledDuration(200) } }
                }

                // Dot / number
                Rectangle {
                    anchors.centerIn: parent
                    width: buttonSize * 0.18; height: width; radius: width / 2
                    visible: !cell.isActive
                    color: cell.isOccupied
                        ? (Appearance?.m3colors.m3onSecondaryContainer ?? "#1D1B20")
                        : (Appearance?.colors.colOnLayer1Inactive ?? "#A0A0A0")
                }
                StyledText {
                    anchors.centerIn: parent
                    visible: cell.isActive
                    text: `${cell.modelData}`
                    font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
                    font.weight: Font.DemiBold
                    color: Appearance?.m3colors.m3onPrimary ?? "white"
                }
            }
        }

        // Expand / collapse affordance — only when there are hidden workspaces.
        MouseArea {
            visible: root._showToggle
            Layout.alignment: Qt.AlignCenter
            implicitWidth: !visible ? 0 : vertical ? buttonSize : root._toggleSize
            implicitHeight: vertical ? root._toggleSize : Appearance.sizes.barHeight
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.PointingHandCursor
            onClicked: root.expanded = !root.expanded
            MaterialSymbol {
                anchors.centerIn: parent
                // Collapsing points back along the bar: up when it's vertical.
                text: root.expanded ? (root.vertical ? "expand_less" : "chevron_left") : (root.vertical ? "more_vert" : "more_horiz")
                iconSize: 16
                color: Appearance?.colors.colOnLayer1Inactive ?? "#A0A0A0"
            }
        }
    }
}
