pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell

/**
 * Theme studio (Settings → Appearance → Theme studio): a static theme made
 * from 1–3 seed colours. anod's matugen makes the Material 3 scheme
 * (theme.generate, a preview: nothing written), per-role overrides go on top,
 * theme.save writes cfg/anoshell/themes/<slug>.json (ThemeRegistry lists it
 * with the others), and applying it is picking it as the static theme —
 * StaticThemeLoader then sends the palette to the apps (theme.apply).
 */
Singleton {
    id: root

    property string name: ""
    property string primary: ""
    property string secondary: ""   // "": derived from the primary
    property string tertiary: ""
    property string mode: "dark"
    property string schemeType: "tonal-spot"
    property var overrides: ({})    // role → #rrggbb

    property var preview: ({})      // role → #rrggbb, the last generated scheme
    property bool busy: false
    property string error: ""
    // The roles offered for overrides: the ones a shell surface shows most.
    readonly property var overrideRoles: ["primary", "secondary", "tertiary", "surface", "surface_container",
        "on_surface", "outline", "error"]

    readonly property var studioThemes: {
        const c = ThemeRegistry.themeContents ?? {}
        return Object.keys(c).filter(n => c[n]?._meta?.studio === true).sort()
    }
    readonly property string slug: name.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 64)

    function validHex(s) { return /^#[0-9a-fA-F]{6}$/.test(s ?? "") }
    function hex(c) { return "#" + [c.r, c.g, c.b].map(v => Math.round(v * 255).toString(16).padStart(2, "0")).join("") }

    // The current palette as seeds: primary, secondary, tertiary and mode.
    function startFromCurrent() {
        const m = Appearance.m3colors
        primary = hex(m.m3primary)
        secondary = hex(m.m3secondary)
        tertiary = hex(m.m3tertiary)
        mode = m.darkmode ? "dark" : "light"
        overrides = ({})
        regenerate()
    }

    // A studio theme back into the editor.
    function load(themeName) {
        const t = ThemeRegistry.themeContents?.[themeName]
        const meta = t?._meta
        if (!meta?.studio) return
        name = meta.name ?? themeName
        primary = meta.seeds?.primary ?? t.primary
        secondary = meta.seeds?.secondary ?? ""
        tertiary = meta.seeds?.tertiary ?? ""
        mode = meta.darkmode === false ? "light" : "dark"
        schemeType = meta.schemeType ?? "tonal-spot"
        overrides = Object.assign({}, meta.overrides ?? {})
        regenerate()
    }

    function setOverride(role, value) {
        const o = Object.assign({}, overrides)
        if (validHex(value)) o[role] = value.toLowerCase()
        else delete o[role]
        overrides = o
        regenerate()
    }

    function _params() {
        const p = { primary: primary, mode: mode, schemeType: schemeType, overrides: overrides }
        if (validHex(secondary)) p.secondary = secondary
        if (validHex(tertiary)) p.tertiary = tertiary
        return p
    }

    // Debounced: typing a hex or dragging a slider asks once it settles.
    function regenerate() { if (validHex(primary)) generateSoon.restart() }
    Timer {
        id: generateSoon
        interval: 250
        onTriggered: {
            root.busy = true
            Anod.call("theme.generate", root._params(), (r, e) => {
                root.busy = false
                root.error = e ? e.message : ""
                if (!e) root.preview = r?.colors ?? ({})
            })
        }
    }
    onPrimaryChanged: regenerate()
    onSecondaryChanged: regenerate()
    onTertiaryChanged: regenerate()
    onModeChanged: regenerate()
    onSchemeTypeChanged: regenerate()

    // Save as a user theme; apply: make it the static theme too.
    function save(apply) {
        if (!validHex(primary) || slug.length === 0) return
        busy = true
        const p = _params()
        p.name = name.trim()
        Anod.call("theme.save", p, (r, e) => {
            root.busy = false
            root.error = e ? e.message : ""
            if (e) return
            ThemeRegistry.refresh()
            if (!apply) return
            const active = (Config.options?.appearance?.theme?.source ?? "") === "static"
                && (Config.options?.appearance?.theme?.name ?? "") === r.name
            Config.setNestedValue("appearance.theme.source", "static")
            Config.setNestedValue("appearance.theme.name", r.name)
            // Same name as the active theme: the file changed, the config didn't.
            if (active) StaticThemeLoader.applyApps(r.name)
        })
    }

    function remove(themeName) {
        Anod.call("theme.delete", { name: themeName }, (r, e) => {
            root.error = e ? e.message : ""
            if (e) return
            if ((Config.options?.appearance?.theme?.source ?? "") === "static"
                    && (Config.options?.appearance?.theme?.name ?? "") === themeName)
                Config.setNestedValue("appearance.theme.source", "materialYou")
            ThemeRegistry.refresh()
        })
    }
}
