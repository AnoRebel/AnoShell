pragma Singleton
pragma ComponentBehavior: Bound

import "root:modules/common"
import "root:modules/common/functions"
import "root:services"
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Niri keybind parser service. Reads the Niri KDL config file and extracts
 * keybindings into a structured format matching HyprlandKeybinds output
 * for the cheatsheet module. Only active on Niri.
 *
 * KDL keybind format:
 *   // ═══ SECTION NAME ═══
 *   // Description comment
 *   Mod+Key { action "arg"; }
 *   Mod+Key attr=value { action; }
 *
 * Output format (mirrors HyprlandKeybinds):
 *   {
 *     children: [
 *       {
 *         name: "Section Name",
 *         children: [
 *           { keys: "Mod+Key", action: "action arg", description: "Description" },
 *           ...
 *         ]
 *       },
 *       ...
 *     ]
 *   }
 */
Singleton {
    id: root

    property string niriConfigPath: `${Directories.config}/niri/ano.kdl`
    property var keybinds: ({ "children": [] })
    property bool ready: false

    Component.onCompleted: {
        if (CompositorService.compositor === "niri") reload()
    }

    function reload() {
        readProc.running = true
    }

    // Watch for config changes via NiriService events
    Connections {
        enabled: CompositorService.compositor === "niri"
        target: NiriService
        // Niri doesn't have a configreloaded event like Hyprland,
        // but we can re-read on demand via IPC or periodically
    }

    Process {
        id: readProc
        running: false
        command: ["cat", root.niriConfigPath]
        stdout: StdioCollector {
            id: configCollector
            onStreamFinished: {
                root.keybinds = root.parseKdlBinds(configCollector.text)
                root.ready = true
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                console.error("[NiriKeybinds] Failed to read config:", root.niriConfigPath)
            }
        }
    }

    /**
     * Parse a Niri KDL config string and extract the binds {} block
     * into a structured keybind tree.
     */
    function parseKdlBinds(configText) {
        const lines = configText.split("\n")
        const result = { children: [] }

        // Find the binds { } block
        let inBinds = false
        let braceDepth = 0
        let bindLines = []

        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim()

            if (!inBinds) {
                if (line.startsWith("binds {") || line === "binds{") {
                    inBinds = true
                    braceDepth = 1
                    continue
                }
                // Also match "binds {" at end of line
                if (/^binds\s*\{/.test(line)) {
                    inBinds = true
                    braceDepth = 1
                    continue
                }
            } else {
                // Track brace depth to find end of binds block
                for (const ch of line) {
                    if (ch === '{') braceDepth++
                    else if (ch === '}') braceDepth--
                }
                if (braceDepth <= 0) {
                    inBinds = false
                    break
                }
                bindLines.push(lines[i]) // Keep original indentation for comment detection
            }
        }

        // Now parse bindLines into sections
        let currentSection = null
        let lastComment = ""

        for (let i = 0; i < bindLines.length; i++) {
            const raw = bindLines[i]
            const trimmed = raw.trim()

            // Skip empty lines
            if (trimmed.length === 0) {
                // Reset pending comment on blank line only if it's not right before a keybind
                if (i + 1 < bindLines.length && !bindLines[i + 1].trim().startsWith("//")) {
                    // Keep the comment for the next keybind line
                } else {
                    lastComment = ""
                }
                continue
            }

            // Section header: // ═══...═══ or // ══...══
            if (/^\/\/\s*[═=]{3,}/.test(trimmed)) {
                // This is a section divider — next non-divider comment is the section name
                const nextLine = (i + 1 < bindLines.length) ? bindLines[i + 1].trim() : ""
                if (nextLine.startsWith("//") && !/^\/\/\s*[═=]{3,}/.test(nextLine)) {
                    const sectionName = nextLine.replace(/^\/\/\s*/, "").trim()
                    currentSection = {
                        name: sectionName,
                        children: []
                    }
                    result.children.push(currentSection)
                    i++ // Skip the section name line

                    // Skip closing divider if present
                    if (i + 1 < bindLines.length && /^\/\/\s*[═=]{3,}/.test(bindLines[i + 1].trim())) {
                        i++
                    }
                }
                lastComment = ""
                continue
            }

            // Regular comment: // Description
            if (trimmed.startsWith("//")) {
                lastComment = trimmed.replace(/^\/\/\s*/, "").trim()
                continue
            }

            // Keybind line: Mod+Key [attrs] { action [args]; }
            const bindMatch = trimmed.match(/^([\w+\-]+(?:\+[\w+\-]+)*)\s*(?:([^{]*?)\s*)?\{([^}]*)\}/)
            if (bindMatch) {
                const keys = bindMatch[1]
                // const attrs = (bindMatch[2] || "").trim() // e.g., "allow-when-locked=true cooldown-ms=150"
                const actionBlock = (bindMatch[3] || "").trim().replace(/;$/, "").trim()

                // Format the action nicely
                const action = formatAction(actionBlock)

                if (!currentSection) {
                    currentSection = {
                        name: "General",
                        children: []
                    }
                    result.children.push(currentSection)
                }

                currentSection.children.push({
                    keys: formatKeys(keys),
                    action: action,
                    description: lastComment || action
                })

                lastComment = ""
                continue
            }

            // Line didn't match anything — reset comment
            lastComment = ""
        }

        // Remove empty sections
        result.children = result.children.filter(section => section.children.length > 0)

        return result
    }

    /**
     * Format a Niri action block into a readable string.
     * e.g., 'spawn "kitty"' → 'Launch kitty'
     *       'focus-workspace 3' → 'Focus workspace 3'
     *       'spawn-sh "qs -c ano ipc call overviewWorkspacesToggle"' → 'QS: overviewWorkspacesToggle'
     */
    function formatAction(actionBlock) {
        if (!actionBlock) return ""

        // QS IPC calls: extract the IPC function name
        const qsIpcMatch = actionBlock.match(/spawn-sh\s+"qs\s+-c\s+ano\s+ipc\s+call\s+(\w+)/)
        if (qsIpcMatch) return `QS: ${qsIpcMatch[1]}`

        // spawn "cmd" "arg1" "arg2" → cmd arg1 arg2
        const spawnMatch = actionBlock.match(/^spawn\s+(.+)$/)
        if (spawnMatch) {
            const args = spawnMatch[1].replace(/"/g, "").trim()
            return args
        }

        // spawn-sh "..." → extract the core command
        const spawnShMatch = actionBlock.match(/^spawn-sh\s+"([^"]+)"/)
        if (spawnShMatch) {
            let cmd = spawnShMatch[1]
            // Simplify long shell commands
            if (cmd.length > 60) cmd = cmd.substring(0, 57) + "..."
            return cmd
        }

        // Built-in Niri actions: hyphenated → spaced
        return actionBlock.replace(/-/g, " ")
    }

    /**
     * Format key names for display.
     * Mod → Super, consistent with HyprlandKeybinds display.
     */
    function formatKeys(keys) {
        return keys
            .replace(/\bMod\b/g, "Super")
            .replace(/\bXF86Audio/g, "🔊 ")
            .replace(/\bXF86MonBrightness/g, "🔆 ")
            .replace(/\bXF86KbdBrightness/g, "⌨ ")
            .replace(/\bReturn\b/g, "Enter")
            .replace(/\bBracketLeft\b/g, "[")
            .replace(/\bBracketRight\b/g, "]")
            .replace(/\bSemicolon\b/g, ";")
            .replace(/\bPeriod\b/g, ".")
            .replace(/\bSlash\b/g, "/")
            .replace(/\bWheelScrollDown\b/g, "Scroll↓")
            .replace(/\bWheelScrollUp\b/g, "Scroll↑")
            .replace(/\bWheelScrollLeft\b/g, "Scroll←")
            .replace(/\bWheelScrollRight\b/g, "Scroll→")
    }

    // IPC: allow manual refresh
    IpcHandler {
        target: "niriKeybinds"
        function reload(): void { root.reload() }
    }
}
