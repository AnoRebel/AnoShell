pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Clipboard history service using cliphist. Supports fuzzy search,
 * paste, superpaste, and image detection.
 */
Singleton {
    id: root
    property string cliphistBinary: "cliphist"
    property real pasteDelay: 0.05
    property string pressPasteCommand: "ydotool key -d 1 29:1 47:1 47:0 29:0"
    property list<string> entries: []

    /**
     * Pause the auto-refresh that's triggered when the wl-clipboard
     * contents change. Set this true around an operation that briefly
     * hijacks the clipboard (e.g. a screenshot script that copies a PNG
     * into the clipboard, then restores the previous payload). When
     * cleared, callers should also invoke refresh() to bring the entry
     * list back in sync with whatever cliphist saw during the suppression
     * window.
     *
     * Compositor-agnostic — the underlying wl-clipboard protocol is the
     * same on Hyprland and Niri.
     */
    property bool suppressRefresh: false

    function entryIsImage(entry) {
        return !!(/^\d+\t\[\[.*binary data.*\d+x\d+.*\]\]$/.test(entry))
    }

    function refresh() {
        if (root.suppressRefresh) return
        readProc.buffer = []
        readProc.running = true
    }

    // cliphist ids are numbers; anything else is rejected rather than run.
    function _id(entry) {
        const id = String(entry ?? "").split("\t")[0].trim()
        return /^[0-9]+$/.test(id) ? id : ""
    }

    function copy(entry) {
        const id = root._id(entry); if (!id) return
        Quickshell.execDetached({ command: ["bash", "-c", `printf '%s' "$ID" | ${root.cliphistBinary} decode | wl-copy`], environment: ({ ID: id }) })
    }

    function paste(entry) {
        const id = root._id(entry); if (!id) return
        Quickshell.execDetached({ command: ["bash", "-c", `printf '%s' "$ID" | ${root.cliphistBinary} decode | wl-copy; ${root.pressPasteCommand}`], environment: ({ ID: id }) })
    }

    function superpaste(count, isImage = false) {
        const targetEntries = entries.filter(entry => !isImage || entryIsImage(entry)).slice(0, count)
        const pasteCommands = [...targetEntries].reverse().map(entry => {
            const id = root._id(entry) || "0" // ids are validated digits
            return `printf '%s' ${id} | ${root.cliphistBinary} decode | wl-copy && sleep ${root.pasteDelay} && ${root.pressPasteCommand}`
        })
        Quickshell.execDetached(["bash", "-c", pasteCommands.join(` && sleep ${root.pasteDelay} && `)])
    }

    Process {
        id: deleteProc
        function deleteEntry(e) {
            const id = root._id(e); if (!id) return
            deleteProc.exec({ command: ["bash", "-c", `printf '%s' "$ID" | ${root.cliphistBinary} delete`], environment: ({ ID: id }) })
        }
        onExited: root.refresh()
    }

    function deleteEntry(entry) { deleteProc.deleteEntry(entry) }

    Process {
        id: wipeProc
        command: [root.cliphistBinary, "wipe"]
        onExited: root.refresh()
    }

    function wipe() { wipeProc.running = true }

    Connections {
        target: Quickshell
        function onClipboardTextChanged() {
            if (root.suppressRefresh) return
            delayedUpdateTimer.restart()
        }
    }

    Timer {
        id: delayedUpdateTimer
        interval: Config.options.hacks.arbitraryRaceConditionDelay
        repeat: false
        onTriggered: root.refresh()
    }

    Process {
        id: readProc
        property list<string> buffer: []
        command: [root.cliphistBinary, "list"]
        stdout: SplitParser {
            onRead: line => { readProc.buffer.push(line) }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) root.entries = readProc.buffer
            else console.error("[Cliphist] Failed to refresh with code", exitCode)
        }
    }

    IpcHandler {
        target: "cliphistService"
        function update(): void { root.refresh() }
    }
}
