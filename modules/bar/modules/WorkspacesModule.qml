import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
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

    readonly property int currentWorkspaceNumber: {
        if (CompositorService.compositor === "niri")
            return NiriService.getCurrentWorkspaceNumber()
        const monitor = Hyprland.monitorFor(root.QsWindow.window?.screen)
        return monitor?.activeWorkspace?.id ?? 1
    }

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
    readonly property int _cellCount: visibleWorkspaces.length + ((hasHidden || expanded) ? 1 : 0)
    implicitWidth: vertical ? buttonSize : (_cellCount * buttonSize)
    implicitHeight: vertical ? (_cellCount * buttonSize) : Appearance.sizes.barHeight

    function updateOccupied() {
        if (CompositorService.compositor === "niri") {
            const wsList = NiriService.currentOutputWorkspaces || []
            const windows = NiriService.windows || []
            const occupiedIds = new Set(windows.map(w => w.workspace_id))
            workspaceOccupied = Array.from({ length: workspacesShown }, (_, i) => {
                const ws = wsList.find(w => w.idx === i + 1)
                return ws ? occupiedIds.has(ws.id) : false
            })
        } else {
            workspaceOccupied = Array.from({ length: workspacesShown }, (_, i) =>
                Hyprland.workspaces.values.some(ws => ws.id === i + 1)
            )
        }
        recomputeVisible()
    }

    function switchTo(n) {
        if (CompositorService.compositor === "niri") NiriService.switchToWorkspace(n)
        // Lua Hyprland config: dispatchers must be hl.dsp.* expressions.
        else Quickshell.execDetached(["hyprctl", "dispatch", `hl.dsp.focus({ workspace = "${n}" })`])
    }

    Component.onCompleted: updateOccupied()
    Connections {
        target: CompositorService.compositor === "hyprland" ? Hyprland.workspaces : null
        function onValuesChanged() { updateOccupied() }
    }
    Connections {
        target: CompositorService.compositor === "niri" ? NiriService : null
        function onAllWorkspacesChanged() { updateOccupied() }
        function onWindowsChanged() { updateOccupied() }
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
            if (CompositorService.compositor === "niri") {
                if (direction > 0) NiriService.focusWorkspaceDown()
                else NiriService.focusWorkspaceUp()
            } else {
                Quickshell.execDetached(["hyprctl", "dispatch", direction > 0 ? `hl.dsp.focus({ workspace = "r+1" })` : `hl.dsp.focus({ workspace = "r-1" })`])
            }
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
        columnSpacing: 2
        rowSpacing: 2

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
                    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 200 } }
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
            visible: root.hasHidden || root.expanded
            implicitWidth: visible ? Math.round(buttonSize * 0.7) : 0
            implicitHeight: vertical ? Math.round(buttonSize * 0.7) : Appearance.sizes.barHeight
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.PointingHandCursor
            onClicked: root.expanded = !root.expanded
            MaterialSymbol {
                anchors.centerIn: parent
                text: root.expanded ? "chevron_left" : "more_horiz"
                iconSize: 16
                color: Appearance?.colors.colOnLayer1Inactive ?? "#A0A0A0"
            }
        }
    }
}
