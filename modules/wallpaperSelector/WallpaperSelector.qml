import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.services

/**
 * Wallpaper selector: a full-screen card deck (WallpaperDeck) over the
 * focused screen, with a live full-size preview of the card in front.
 * Card deck ported from wallpaperpicker (github: wallpaperpicker, GPL-3.0) and
 * split into WallpaperDeck, DeckCard, DeckPreview, DeckHeader,
 * SpectrumRibbon, WallhavenFilters and DeckSettings.
 *
 * Unlike the other standalone panels this one is modal while open: the
 * preview fills the screen, so the window takes the whole screen's input and
 * the keyboard (Exclusive) until it closes. The deck is created per opening
 * and destroyed once its close animation ends, so its pictures and players
 * don't stay in memory.
 *
 * IPC: qs -c ano ipc call wallpaperSelector open|close|toggle
 */
Scope {
    id: root

    IpcHandler {
        target: "wallpaperSelector"
        function toggle(): void { GlobalStates.wallpaperSelectorOpen = !GlobalStates.wallpaperSelectorOpen }
        function open(): void { GlobalStates.wallpaperSelectorOpen = true }
        function close(): void { GlobalStates.wallpaperSelectorOpen = false }
    }

    // Window and deck live from opening until the deck's close animation ends.
    property bool active: false
    property string screenName: "" // picked at opening, so focus moving doesn't move the deck
    Connections {
        target: GlobalStates
        function onWallpaperSelectorOpenChanged() {
            if (GlobalStates.wallpaperSelectorOpen) {
                if (root.active && deckLoader.item) deckLoader.item.open() // reopened while closing
                if (!root.active) root.screenName = GlobalStates.wallpaperSelectorTargetMonitor || CompositorService.focusedMonitorName
                root.active = true
            } else if (deckLoader.item && root.active) {
                deckLoader.item.close() // its `closed` then ends it
            } else {
                root.active = false
            }
        }
    }

    function finish() {
        root.active = false
        GlobalStates.wallpaperSelectorOpen = false
    }

    PanelWindow {
        id: window
        visible: root.active
        screen: Quickshell.screens.find(s => s.name === root.screenName) ?? Quickshell.screens[0] ?? null
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell:wallpaper"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        anchors { top: true; bottom: true; left: true; right: true }

        // Content attaches one turn after the surface exists (a deep tree
        // attached while a layer surface is created can crash; see
        // docs/architecture.md).
        Loader {
            id: deckLoader
            anchors.fill: parent
            asynchronous: true
            active: false
            sourceComponent: WallpaperDeck {
                onClosed: Qt.callLater(root.finish) // not from inside the deck's own signal
            }
        }
        Timer {
            interval: 0
            running: window.visible && !deckLoader.active
            onTriggered: deckLoader.active = true
        }
        onVisibleChanged: if (!visible) deckLoader.active = false
    }
}
