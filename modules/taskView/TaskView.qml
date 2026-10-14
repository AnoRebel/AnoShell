import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.layouts
/**
 * Task View — separate from AnoView overview.
 * Shows only windows on the CURRENT workspace, using the configured
 * task view layout. Triggered by different keybind/IPC than overview.
 * Includes workspace strip at bottom for switching.
 */
Scope {
    id: root

    readonly property string layoutAlgorithm: Config.options?.taskView?.layout ?? "hero"

    IpcHandler {
        target: "taskView"
        function toggle(): void { GlobalStates.taskViewOpen = !GlobalStates.taskViewOpen }
        function open(): void { GlobalStates.taskViewOpen = true }
        function close(): void { GlobalStates.taskViewOpen = false }
    }

    Variants {
        model: Quickshell.screens

        LazyLoader {
            id: tvLoader
            required property var modelData
            active: GlobalStates.taskViewOpen

            component: PanelWindow {
                id: tvRoot
                screen: tvLoader.modelData
                visible: GlobalStates.taskViewOpen
                color: "transparent"
                anchors { top: true; bottom: true; left: true; right: true }
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.exclusiveZone: -1
                WlrLayershell.keyboardFocus: GlobalStates.taskViewOpen ? 1 : 0
                WlrLayershell.namespace: "quickshell:taskview"

                // Window tracking is leased while this window exists (created on open).
                Component.onCompleted: CompositorService.acquireWindows("taskView")
                Component.onDestruction: CompositorService.releaseWindows("taskView")

                property var lastPositions: ({})
                property bool animateWindows: false

                // Windows on this screen's visible workspace (model windows from
                // CompositorService; `win` carries the toplevel for previews).
                function getActiveAddress() {
                    return CompositorService.windows.find(w => w.focused)?.key ?? ""
                }

                function buildWindowList() {
                    return CompositorService.windowsOnOutput(tvRoot.screen?.name ?? "").map(w => ({
                        win: w, width: w.width || 800, height: w.height || 600, address: w.key
                    }))
                }

                function activateWindow(win) {
                    GlobalStates.taskViewOpen = false
                    CompositorService.focusWindow(win)
                }

                // Dim backdrop
                Rectangle {
                    anchors.fill: parent; color: "#88000000"
                    opacity: GlobalStates.taskViewOpen ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(200) } }
                }

                MouseArea { anchors.fill: parent; z: -1; onClicked: GlobalStates.taskViewOpen = false }
                Keys.onPressed: event => { if (event.key === Qt.Key_Escape) GlobalStates.taskViewOpen = false }

                Item {
                    anchors { fill: parent; margins: 48 }

                    // Window layout area
                    Item {
                        id: windowArea
                        anchors { top: parent.top; left: parent.left; right: parent.right }
                        height: parent.height - workspaceStrip.height - 16

                        ScriptModel {
                            id: taskLayoutModel
                            property int areaW: windowArea.width
                            property int areaH: windowArea.height
                            property var _dep: CompositorService.windows
                            values: {
                                if (areaW <= 0 || areaH <= 0) return []
                                return LayoutsManager.doLayout(root.layoutAlgorithm, tvRoot.buildWindowList(), areaW, areaH, tvRoot.getActiveAddress())
                            }
                        }

                        Repeater {
                            model: taskLayoutModel
                            delegate: Item {
                                x: modelData.x; y: modelData.y
                                width: modelData.width; height: modelData.height

                                Rectangle {
                                    anchors.fill: parent; anchors.margins: -4
                                    radius: 16; color: "#44000000"; z: -1
                                }

                                Loader {
                                    anchors.fill: parent
                                    active: !!modelData.win?.toplevel
                                    sourceComponent: ScreencopyView {
                                        anchors.fill: parent
                                        captureSource: modelData.win?.toplevel ?? null
                                        live: false; paintCursor: false
                                        layer.enabled: true
                                        layer.effect: OpacityMask { maskSource: Rectangle { width: parent.width; height: parent.height; radius: 12 } }
                                    }
                                }

                                Rectangle {
                                    anchors.fill: parent; radius: 12; color: "transparent"
                                    border.width: tvItemMA.containsMouse ? 3 : 1
                                    border.color: tvItemMA.containsMouse ? Appearance?.colors.colPrimary ?? "#65558F" : "#44444444"
                                }

                                // Title badge
                                Rectangle {
                                    anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 8 }
                                    width: Math.min(titleText.implicitWidth + 16, parent.width * 0.8)
                                    height: titleText.implicitHeight + 8; radius: 10
                                    color: "#CC000000"
                                    StyledText { id: titleText; anchors.centerIn: parent; text: modelData.win?.title ?? ""; color: "white"; font.pixelSize: 11; elide: Text.ElideRight; width: parent.width - 12 }
                                }

                                MouseArea {
                                    id: tvItemMA; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                    onClicked: event => {
                                        if (event.button === Qt.MiddleButton) {
                                            CompositorService.closeWindow(modelData.win)
                                        } else tvRoot.activateWindow(modelData.win)
                                    }
                                }
                            }
                        }
                    }

                    // Workspace strip at bottom
                    Rectangle {
                        id: workspaceStrip
                        anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
                        width: wsRow.implicitWidth + 24; height: 40; radius: 20
                        color: Appearance?.colors.colLayer0 ?? "#1C1B1F"
                        border.width: 1; border.color: Appearance?.colors.colLayer0Border ?? "#44444488"

                        RowLayout {
                            id: wsRow; anchors.centerIn: parent; spacing: 6
                            Repeater {
                                model: Config.options?.bar?.workspaces?.shown ?? 10
                                Rectangle {
                                    width: 24; height: 24; radius: 12
                                    color: tvRoot.getCurrentWorkspaceId() === index + 1
                                        ? Appearance?.colors.colPrimary ?? "#65558F"
                                        : wsMA.containsMouse ? Appearance?.colors.colLayer1 ?? "#E5E1EC" : "transparent"
                                    border.width: 1
                                    border.color: tvRoot.getCurrentWorkspaceId() === index + 1 ? "transparent" : "#33ffffff"
                                    StyledText { anchors.centerIn: parent; text: `${index + 1}`; font.pixelSize: 11; color: tvRoot.getCurrentWorkspaceId() === index + 1 ? "white" : "#aaa" }
                                    MouseArea {
                                        id: wsMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            CompositorService.focusWorkspace(index + 1, tvRoot.screen?.name)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
