pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services

/**
 * Palette cursors and icons (ported from Bioma's services/Looks.qml): cursor
 * and icon themes drawn in the current palette by scripts/themes/cursors and
 * scripts/themes/icon-theme, into $XDG_DATA_HOME/icons. Nothing is built until
 * one is chosen (cursor.theme / icons.theme in Settings → Displays); then each
 * palette change rebuilds it.
 *
 * Toolkits and compositors keep a theme loaded by its name, so every palette
 * theme has two slots, <id>.a and <id>.b (empty themes inheriting from <id>),
 * and after a rebuild the desktop is moved to the other slot: the new name is
 * what makes the new colours show. The cursor goes through anod (cursor.apply:
 * Hyprland, niri, GTK); the icon theme through scripts/themes/looks (GTK and
 * qt5ct/qt6ct).
 */
Singleton {
    id: root

    readonly property var cursorIds: ["anoshell-cursor", "anoshell-cursor-cell"]
    readonly property var iconIds: ["anoshell-icons", "anoshell-icons-primary"]

    readonly property string cursorTheme: Config.options?.cursor?.theme ?? ""
    readonly property int cursorSize: Config.options?.cursor?.size ?? 24
    readonly property string iconTheme: Config.options?.icons?.theme ?? ""
    readonly property string iconBase: Config.options?.icons?.base ?? "Papirus-Dark"
    readonly property bool cursorWanted: root.cursorIds.includes(root.cursorTheme)
    readonly property bool iconsWanted: root.iconIds.includes(root.iconTheme)

    // What the desktop is set to now (a slot while a palette theme is on).
    property string cursorLive: ""
    property string iconsLive: ""
    // Installed icon themes, from scripts/themes/looks list: [{id, name, slotted}]
    property var iconThemes: []
    signal cursorBuilt()

    // The slot `id` is not on now, so the toolkits load it afresh.
    function nextSlot(id: string, live: string): string {
        return live === `${id}.a` ? `${id}.b` : `${id}.a`
    }

    readonly property var colours: {
        const m = Appearance.m3colors
        const hex = c => Qt.rgba(c.r, c.g, c.b, 1).toString()
        const p = m.m3primary
        const hsl = (s, l) => Qt.hsla(Math.max(0, p.hslHue), Math.max(0, Math.min(1, p.hslSaturation + s)),
                                      Math.max(0, Math.min(1, p.hslLightness + l)), 1)
        return {
            "background": hex(m.m3background),
            "text": hex(m.m3onBackground),
            "primary": hex(p),
            "cell": hex(m.m3surfaceContainerHigh),
            "raised": hex(m.m3surfaceContainerHighest),
            "rim": hex(m.m3outline),
            "line": hex(m.m3outlineVariant),
            // the folder face lit from above; its back the same hue in shade
            "grad_top": hex(hsl(0.14, 0.16)),
            "grad_bottom": hex(hsl(-0.15, -0.15)),
            "back_top": hex(hsl(-0.1, -0.18)),
            "back_bottom": hex(hsl(-0.2, -0.3))
        }
    }
    readonly property bool _anim: Config.options?.animations?.enable ?? true
    readonly property string cursorRequest: root.cursorWanted ? JSON.stringify({
        "colours": root.colours,
        // the wait/progress loader: 600 ms out, 600 ms back (none with animations off)
        "loader": { "ms": root._anim ? 1200 : 0, "ease": [0.45, 0, 0.55, 1] }
    }) : ""
    readonly property string iconRequest: root.iconsWanted ? JSON.stringify({
        "colours": root.colours,
        "base": root.iconBase
    }) : ""

    // The palette eases between colours: build once it has rested.
    onCursorRequestChanged: if (root.cursorRequest) cursorDebounce.restart()
    onIconRequestChanged: if (root.iconRequest) iconDebounce.restart()
    Timer { id: cursorDebounce; interval: 1500; onTriggered: if (root.cursorRequest) cursorBuilder.build(root.cursorRequest) }
    Timer { id: iconDebounce; interval: 1500; onTriggered: if (root.iconRequest) iconBuilder.build(root.iconRequest) }

    function applyCursor(): void {
        if (!root.cursorTheme || !Anod.available) return
        const name = root.cursorWanted ? root.nextSlot(root.cursorTheme, root.cursorLive) : root.cursorTheme
        Anod.call("cursor.apply", { theme: name, size: root.cursorSize }, (r, e) => { if (!e) root.cursorLive = name })
    }
    function applyIcons(): void {
        if (!root.iconTheme) return
        const name = root.iconsWanted ? root.nextSlot(root.iconTheme, root.iconsLive) : root.iconTheme
        root.iconsLive = name
        Quickshell.execDetached([Quickshell.shellPath("scripts/themes/looks"), "icons", name])
    }
    // Settings → Displays. A theme of someone else's also becomes what the
    // palette icons inherit from.
    function setIconTheme(id: string): void {
        if (!root.iconIds.includes(id) && id) Config.setNestedValue("icons.base", id)
        Config.setNestedValue("icons.theme", id)
        if (!root.iconsWanted) root.applyIcons() // a palette theme applies once built
    }

    function refresh(): void { if (!lister.running) lister.running = true }
    Process {
        id: lister
        command: [Quickshell.shellPath("scripts/themes/looks"), "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text)
                    root.iconThemes = d.icons ?? []
                    if (!root.cursorLive) root.cursorLive = d.current?.live ?? ""
                    if (!root.iconsLive) root.iconsLive = d.current?.iconsLive ?? ""
                } catch (e) {}
            }
        }
    }
    Component.onCompleted: refresh()

    Builder {
        id: cursorBuilder
        script: "scripts/themes/cursors"
        // rebuilt, or chosen while the desktop is on something else
        onFinished: built => {
            if (built) root.cursorBuilt()
            if (built || !root.cursorLive.startsWith(root.cursorTheme)) root.applyCursor()
        }
    }
    Builder {
        id: iconBuilder
        script: "scripts/themes/icon-theme"
        onFinished: built => {
            if (built) root.refresh()
            if (built || !root.iconsLive.startsWith(root.iconTheme)) root.applyIcons()
        }
    }

    // Runs a builder with a request on stdin; one that arrives while it runs
    // is built after it, the latest only.
    component Builder: Process {
        id: builder
        property string script: ""
        property string request: ""
        property string next: ""
        signal finished(bool built)

        function build(req: string): void {
            if (builder.running) { builder.next = req; return }
            builder.request = req
            builder.running = true
        }
        command: [Quickshell.shellPath(builder.script), "build"]
        stdinEnabled: true
        onStarted: { builder.write(builder.request); builder.stdinEnabled = false }
        stdout: StdioCollector {
            onStreamFinished: {
                let built = false
                try { built = JSON.parse(text).built === true } catch (e) { return }
                builder.finished(built)
            }
        }
        stderr: StdioCollector {
            onStreamFinished: if (text.trim()) console.warn(`[PaletteThemes] ${builder.script}: ${text.trim()}`)
        }
        onExited: {
            builder.stdinEnabled = true
            if (builder.next) { const r = builder.next; builder.next = ""; builder.build(r) }
        }
    }
}
