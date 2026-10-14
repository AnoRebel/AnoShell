import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Wayland
import Quickshell.Hyprland
import Qt5Compat.GraphicalEffects
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.layouts
import qs.modules.overview
import "."
/**
 * AnoView — Compositor-agnostic window overview with 10 selectable layouts.
 * Compositor-agnostic: windows come from CompositorService.windows (leased while open).
 * Supports text filtering, keyboard navigation, random layout mode.
 */
Scope {
    id: anoView

    Variants {
        model: Quickshell.screens

        LazyLoader {
            id: viewLoader
            required property var modelData
            active: GlobalStates.overviewOpen

            component: PanelWindow {
                id: root
                screen: viewLoader.modelData

                // Layout config
                property string layoutAlgorithm: Config.options?.overview?.layout ?? "smartgrid"
                property string lastLayoutAlgorithm: ""
                property bool animateWindows: false
                property var lastPositions: ({})

                anchors { top: true; bottom: true; left: true; right: true }
                color: "transparent"
                visible: GlobalStates.overviewOpen

                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.exclusiveZone: -1
                WlrLayershell.keyboardFocus: GlobalStates.overviewOpen ? 1 : 0
                WlrLayershell.namespace: "quickshell:anoview"

                // Dim background
                Rectangle {
                    anchors.fill: parent
                    color: "#88000000"
                    opacity: GlobalStates.overviewOpen ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(200) } }
                }

                // Focused window key for Hero/Spiral/Satellite layouts
                function getActiveAddress() {
                    return CompositorService.windows.find(w => w.focused)?.key ?? ""
                }

                function toggleView() {
                    if (GlobalStates.overviewOpen) {
                        // Closing
                        GlobalStates.overviewOpen = false
                        root.animateWindows = false
                        root.lastPositions = {}
                    } else {
                        // Opening
                        if (root.layoutAlgorithm === 'random') {
                            var layouts = LayoutsManager.layoutNames.filter(l => l !== root.lastLayoutAlgorithm)
                            root.lastLayoutAlgorithm = layouts[Math.floor(Math.random() * layouts.length)]
                        } else {
                            root.lastLayoutAlgorithm = root.layoutAlgorithm
                        }
                        exposeArea.currentIndex = -1
                        searchBox.reset()
                        GlobalStates.overviewOpen = true
                        refreshThumbs()
                    }
                }

                function refreshThumbs() {
                    if (!GlobalStates.overviewOpen) return
                    for (var i = 0; i < winRepeater.count; ++i) {
                        var it = winRepeater.itemAt(i)
                        if (it?.visible && it.refreshThumb) it.refreshThumb()
                    }
                }

                // Periodically refresh thumbnails
                Timer {
                    interval: 125; repeat: true
                    running: GlobalStates.overviewOpen
                    onTriggered: root.refreshThumbs()
                }

                // Window tracking is leased while this overview window exists
                // (it is created on open and destroyed on close).
                Component.onCompleted: CompositorService.acquireWindows("overview")
                Component.onDestruction: CompositorService.releaseWindows("overview")

                function activateWindow(win) {
                    GlobalStates.overviewOpen = false
                    root.animateWindows = false
                    root.lastPositions = {}
                    CompositorService.focusWindow(win)
                }

                function closeWindow(win) { CompositorService.closeWindow(win) }

                // Every window matching the search, grouped by workspace.
                function buildWindowList(query) {
                    const q = (query || "").toLowerCase()
                    return CompositorService.windows
                        .filter(w => q.length === 0 || w.title.toLowerCase().includes(q) || w.appId.toLowerCase().includes(q))
                        .map(w => ({ win: w, width: w.width || 800, height: w.height || 600, address: w.key, workspaceId: w.workspace }))
                        .sort((a, b) => a.workspaceId - b.workspaceId)
                }

                // Main UI
                FocusScope {
                    anchors.fill: parent; focus: true

                    Keys.onPressed: event => {
                        if (!GlobalStates.overviewOpen) return
                        if (event.key === Qt.Key_Escape) { root.toggleView(); event.accepted = true; return }
                        const total = winRepeater.count; if (total <= 0) return

                        function moveH(delta) {
                            for (var s = 1; s <= total; ++s) {
                                var c = (exposeArea.currentIndex + delta * s + total) % total
                                var it = winRepeater.itemAt(c); if (it?.visible) { exposeArea.currentIndex = c; return }
                            }
                        }
                        function moveV(dir) {
                            var cur = winRepeater.itemAt(exposeArea.currentIndex)
                            if (!cur?.visible) { moveH(dir > 0 ? 1 : -1); return }
                            var cx = cur.x + cur.width / 2, cy = cur.y + cur.height / 2
                            var bestIdx = -1, bestDy = 99999999, bestDx = 99999999
                            for (var i = 0; i < total; ++i) {
                                var it = winRepeater.itemAt(i)
                                if (!it?.visible || i === exposeArea.currentIndex) continue
                                var dy = (it.y + it.height / 2) - cy
                                if (dir > 0 && dy <= 0) continue; if (dir < 0 && dy >= 0) continue
                                var absDy = Math.abs(dy), absDx = Math.abs((it.x + it.width / 2) - cx)
                                if (absDy < bestDy || (absDy === bestDy && absDx < bestDx)) { bestDy = absDy; bestDx = absDx; bestIdx = i }
                            }
                            if (bestIdx >= 0) exposeArea.currentIndex = bestIdx
                        }

                        if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab) { moveH(1); event.accepted = true }
                        else if (event.key === Qt.Key_Left || event.key === Qt.Key_Backtab) { moveH(-1); event.accepted = true }
                        else if (event.key === Qt.Key_Down) { moveV(1); event.accepted = true }
                        else if (event.key === Qt.Key_Up) { moveV(-1); event.accepted = true }
                        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            var item = winRepeater.itemAt(exposeArea.currentIndex)
                            if (item) { root.activateWindow(item.hWin, item.clientInfo); event.accepted = true }
                        }
                    }

                    MouseArea { anchors.fill: parent; hoverEnabled: false; z: -1; onClicked: root.toggleView() }

                    Item {
                        anchors.fill: parent; anchors.margins: 32

                        Column {
                            id: layoutRoot
                            anchors.fill: parent; anchors.margins: 48; spacing: 20

                            Item {
                                id: exposeArea
                                width: layoutRoot.width
                                height: layoutRoot.height - searchBox.implicitHeight - layoutRoot.spacing
                                property int currentIndex: 0
                                property string searchText: ""
                                onSearchTextChanged: currentIndex = (windowLayoutModel.count > 0) ? 0 : -1

                                ScriptModel {
                                    id: windowLayoutModel
                                    property int areaW: exposeArea.width
                                    property int areaH: exposeArea.height
                                    property string query: exposeArea.searchText
                                    property string algo: root.lastLayoutAlgorithm
                                    // Depend on toplevel changes
                                    property var _dep: CompositorService.windows

                                    values: {
                                        if (areaW <= 0 || areaH <= 0) return []
                                        var wl = root.buildWindowList(query)
                                        return LayoutsManager.doLayout(algo, wl, areaW, areaH, root.getActiveAddress())
                                    }
                                }

                                Repeater {
                                    id: winRepeater
                                    model: windowLayoutModel

                                    delegate: WindowThumbnail {
                                        hWin: modelData.win
                                        wHandle: hWin?.toplevel ?? null
                                        winKey: String(modelData.address ?? modelData.win?.address ?? index)
                                        thumbW: modelData.width
                                        thumbH: modelData.height
                                        clientInfo: ({})
                                        targetX: modelData.x
                                        targetY: modelData.y
                                        targetZ: (visible && exposeArea.currentIndex === index) ? 1000 : (modelData.zIndex || 0)
                                        targetRotation: modelData.rotation || 0
                                        hovered: visible && (exposeArea.currentIndex === index)
                                        animateWindows: root.animateWindows
                                        lastPositions: root.lastPositions

                                        onActivated: root.activateWindow(hWin)
                                        onClosed: root.closeWindow(hWin)
                                    }
                                }
                            }

                            SearchBox {
                                id: searchBox
                                onTextChanged: text => { root.animateWindows = true; exposeArea.searchText = text }
                            }
                        }
                    }
                }
            }
        }
    }

    // IPC
    IpcHandler {
        target: "anoview"
        function toggle(layout: string): void {
            if (layout) Config.setNestedValue("overview.layout", layout)
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen
        }
        function open(layout: string): void {
            if (layout) Config.setNestedValue("overview.layout", layout)
            GlobalStates.overviewOpen = true
        }
        function close(): void { GlobalStates.overviewOpen = false }
    }

    // Also respond to the generic overviewWorkspacesToggle IPC from companion configs
    IpcHandler {
        target: "overviewWorkspacesToggle"
        function invoke(): void { GlobalStates.overviewOpen = !GlobalStates.overviewOpen }
    }

    // GlobalShortcuts (Hyprland only)
    Loader {
        active: CompositorService.compositor === "hyprland"
        sourceComponent: Item {
            GlobalShortcut { name: "overviewToggle"; description: "Toggle AnoView"; onPressed: GlobalStates.overviewOpen = !GlobalStates.overviewOpen }
        }
    }
}
