pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services

/**
 * Keyboard layout service: the active layout's name (from the compositor
 * backend) and its short XKB code (looked up in base.lst) for indicators.
 */
Singleton {
    id: root
    // Layout name and list come from the compositor backend (Hyprland:
    // activelayout events + j/devices; niri: keyboard layout events).
    readonly property var layoutCodes: CompositorService.keyboardLayouts
    property var cachedLayoutCodes: ({})
    readonly property string currentLayoutName: CompositorService.keyboardLayout
    property string currentLayoutCode: ""
    property string baseLayoutFilePath: "/usr/share/X11/xkb/rules/base.lst"

    onCurrentLayoutNameChanged: root.updateLayoutCode()

    function updateLayoutCode() {
        if (cachedLayoutCodes.hasOwnProperty(currentLayoutName)) {
            root.currentLayoutCode = cachedLayoutCodes[currentLayoutName]
        } else {
            getLayoutProc.running = true
        }
    }

    Process {
        id: getLayoutProc
        command: ["cat", root.baseLayoutFilePath]
        stdout: StdioCollector {
            id: layoutCollector
            onStreamFinished: {
                const lines = layoutCollector.text.split("\n")
                const targetDescription = root.currentLayoutName
                lines.find(line => {
                    if (!line.trim() || line.trim().startsWith('!')) return false

                    const matchLayout = line.match(/^\s*(\S+)\s+(.+)$/)
                    if (matchLayout && matchLayout[2] === targetDescription) {
                        root.cachedLayoutCodes[matchLayout[2]] = matchLayout[1]
                        root.currentLayoutCode = matchLayout[1]
                        return true
                    }

                    const matchVariant = line.match(/^\s*(\S+)\s+(\S+)\s+(.+)$/)
                    if (matchVariant && matchVariant[3] === targetDescription) {
                        const complexLayout = matchVariant[2] + matchVariant[1]
                        root.cachedLayoutCodes[matchVariant[3]] = complexLayout
                        root.currentLayoutCode = complexLayout
                        return true
                    }
                    return false
                })
            }
        }
    }

}
