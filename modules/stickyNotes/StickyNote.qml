import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services

/**
 * A sticky note on the desktop (stickyNotes.enable), kept in
 * ~/.local/share/anoshell/sticky.md (edit it anywhere; it reloads).
 * Click-through (stickyNotes.clickThrough): clicks go to the windows below,
 * except on the pin button that turns it back off.
 *
 *   qs -c ano ipc call stickyNote clickThrough
 */
Scope {
    id: root
    readonly property var cfg: Config.options?.stickyNotes ?? {}
    readonly property bool through: cfg.clickThrough ?? false
    readonly property string path: `${Directories.anoData}/sticky.md`

    IpcHandler {
        target: "stickyNote"
        function clickThrough(): void { Config.setNestedValue("stickyNotes.clickThrough", !root.through) }
    }

    Process { id: mkdir; command: ["mkdir", "-p", "--", Directories.anoData] }
    FileView {
        id: file
        path: root.path
        watchChanges: true
        onFileChanged: reload()
        printErrors: false // missing until the first save
        onLoadFailed: mkdir.running = true
    }
    Timer {
        id: saveTimer
        interval: 500
        onTriggered: {
            file.setText(area.text)
            // The save replaces the file (atomic rename), which drops the watch: re-arm it.
            file.watchChanges = false
            rewatch.restart()
        }
    }
    Timer { id: rewatch; interval: 200; onTriggered: file.watchChanges = true }

    PanelWindow {
        screen: Quickshell.screens.find(s => s.name === CompositorService.focusedMonitorName) ?? Quickshell.screens[0]
        anchors { top: true; left: true }
        margins { top: root.cfg.y ?? 80; left: root.cfg.x ?? 40 }
        implicitWidth: root.cfg.width ?? 280
        implicitHeight: root.cfg.height ?? 220
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.namespace: "quickshell:stickyNote"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: root.through ? WlrKeyboardFocus.None : WlrKeyboardFocus.OnDemand
        // Click-through: only the pin takes input.
        mask: Region { item: root.through ? pin : note }

        SurfaceMaterial {
            id: note
            anchors.fill: parent
            surface: "stickyNote"
            radius: Appearance.rounding.normal
            color: ColorUtils.transparentize(Appearance.m3colors.m3tertiaryContainer, root.through ? 0.85 : 0.95)
            textColor: Appearance.m3colors.m3onTertiaryContainer

            StyledTextArea {
                id: area
                anchors { fill: parent; margins: 8; topMargin: 30 }
                readOnly: root.through
                color: Appearance.m3colors.m3onTertiaryContainer
                background: null
                placeholderText: "A note…"
                text: file.loaded ? file.text() : ""
                onTextChanged: if (activeFocus) saveTimer.restart()
            }
            MaterialSymbol {
                id: pin
                anchors { right: parent.right; top: parent.top; margins: 6 }
                text: root.through ? "push_pin" : "edit"
                iconSize: 18
                color: Appearance.m3colors.m3onTertiaryContainer
                MouseArea {
                    anchors.fill: parent; anchors.margins: -4
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Config.setNestedValue("stickyNotes.clickThrough", !root.through)
                }
            }
        }
    }
}
