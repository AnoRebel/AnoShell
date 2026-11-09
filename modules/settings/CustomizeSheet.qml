import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "."

/**
 * In-place Customize: right-click the bar (or the pill with Ctrl) → a sheet
 * grows out of that surface's edge with its own Settings page. Changes apply
 * live; Undo steps back through them one at a time (Config.undo).
 *
 *   qs -c ano ipc call customize open bar|pill|dock
 */
Scope {
    id: root

    readonly property string surface: GlobalStates.customizeSurface
    readonly property bool open: surface !== ""
    // Where the surface sits: the sheet grows from that edge.
    readonly property string edge: surface === "pill" ? (Config.options.anoSpot?.position ?? "bottom")
        : surface === "dock" ? (Config.options.dock?.position === "auto" ? "bottom" : (Config.options.dock?.position ?? "bottom"))
        : (Config.options.bars?.[0]?.edge ?? "top")
    readonly property var titles: ({ bar: "Customize the bar", pill: "Customize the pill", dock: "Customize the dock" })

    onOpenChanged: {
        Config.undoStack = []
        Config.holdUndo(open)
    }

    IpcHandler {
        target: "customize"
        function open(surface: string): void { if (["bar", "pill", "dock"].includes(surface)) GlobalStates.customizeSurface = surface }
        function close(): void { GlobalStates.customizeSurface = "" }
        function undo(): void { Config.undo() }
    }

    LazyLoader {
        active: root.open
        component: PanelWindow {
            screen: Quickshell.screens.find(s => s.name === CompositorService.focusedMonitorName) ?? Quickshell.screens[0]
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Normal // beside the bar, not over it
            color: "transparent"
            WlrLayershell.namespace: "quickshell:customize"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            mask: Region { item: sheet }

            SurfaceMaterial {
                id: sheet
                surface: "customize"
                width: Math.min(600, parent.width - 32)
                height: Math.min(parent.height - 32, 640)
                radius: Appearance.rounding.large
                color: Appearance.m3colors.m3surfaceContainer
                x: root.edge === "left" ? 16 : root.edge === "right" ? parent.width - width - 16 : (parent.width - width) / 2
                y: root.edge === "top" ? 16 : root.edge === "bottom" ? parent.height - height - 16 : (parent.height - height) / 2
                // Grows out of the surface's edge.
                transformOrigin: root.edge === "top" ? Item.Top : root.edge === "bottom" ? Item.Bottom : root.edge === "left" ? Item.Left : Item.Right
                scale: shown ? 1 : 0.6
                opacity: shown ? 1 : 0
                property bool shown: false
                Component.onCompleted: shown = true
                Behavior on scale { MotionSpring { token: "liquid" } }
                Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(160) } }
                focus: true
                Keys.onEscapePressed: GlobalStates.customizeSurface = ""
                Keys.onPressed: e => { if (e.key === Qt.Key_Z && (e.modifiers & Qt.ControlModifier)) { Config.undo(); e.accepted = true } }

                ColumnLayout {
                    anchors { fill: parent; margins: 16 }
                    spacing: 10
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        StyledText {
                            Layout.fillWidth: true
                            text: root.titles[root.surface] ?? "Customize"
                            font.pixelSize: Appearance.font.pixelSize.large
                            font.weight: Font.DemiBold
                        }
                        RippleButton {
                            enabled: Config.undoStack.length > 0
                            buttonText: Config.undoStack.length > 0 ? `Undo (${Config.undoStack.length})` : "Undo"
                            onClicked: Config.undo()
                        }
                        RippleButton {
                            toggled: true
                            buttonText: "Done"
                            onClicked: GlobalStates.customizeSurface = ""
                        }
                    }
                    StyledFlickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        contentHeight: page.implicitHeight
                        Loader {
                            id: page
                            width: parent.width
                            sourceComponent: root.surface === "pill" ? pillPage : root.surface === "dock" ? dockPage : barPage
                        }
                    }
                }
            }
            Component { id: barPage; BarConfig {} }
            Component { id: pillPage; AnoSpotConfig {} }
            Component { id: dockPage; DockConfig {} }
        }
    }
}
