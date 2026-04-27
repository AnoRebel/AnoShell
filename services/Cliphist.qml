pragma Singleton
pragma ComponentBehavior: Bound

import "root:modules/common"
import "root:modules/common/functions"
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

    function entryIsImage(entry) {
        return !!(/^\d+\t\[\[.*binary data.*\d+x\d+.*\]\]$/.test(entry))
    }

    function refresh() {
        readProc.buffer = []
        readProc.running = true
    }

    function copy(entry) {
        const entryNumber = entry.split("\t")[0]
        Quickshell.execDetached(["bash", "-c", `printf '%s' ${entryNumber} | ${root.cliphistBinary} decode | wl-copy`])
    }

    function paste(entry) {
        const entryNumber = entry.split("\t")[0]
        Quickshell.execDetached(["bash", "-c", `printf '%s' ${entryNumber} | ${root.cliphistBinary} decode | wl-copy; ${root.pressPasteCommand}`])
    }

    function superpaste(count, isImage = false) {
        const targetEntries = entries.filter(entry => !isImage || entryIsImage(entry)).slice(0, count)
        const pasteCommands = [...targetEntries].reverse().map(entry => {
            const entryNumber = entry.split("\t")[0]
            return `printf '%s' ${entryNumber} | ${root.cliphistBinary} decode | wl-copy && sleep ${root.pasteDelay} && ${root.pressPasteCommand}`
        })
        Quickshell.execDetached(["bash", "-c", pasteCommands.join(` && sleep ${root.pasteDelay} && `)])
    }

    Process {
        id: deleteProc
        property string entry: ""
        command: ["bash", "-c", `printf '%s' ${deleteProc.entry.split("\t")[0]} | ${root.cliphistBinary} delete`]
        function deleteEntry(e) { deleteProc.entry = e; deleteProc.running = true; deleteProc.entry = "" }
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
        function onClipboardTextChanged() { delayedUpdateTimer.restart() }
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
