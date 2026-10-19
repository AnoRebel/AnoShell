import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.services

/**
 * The launcher's result providers (spec launcher-plugins). Each one is behind
 * search.plugins.<name>.enable (default off) and while off runs nothing:
 *
 *   calculator  an expression → qalc's answer; Enter copies it
 *   emoji       names matching the query (":" alone for emoji only); Enter copies
 *   packages    "pkg <name>" → yay/paru -Ss; Enter installs in your terminal
 *   actions     search.plugins.actions.items; dangerous ones need enableDangerous
 *   schemes     "scheme …" → colour themes and Material variants, applied live
 *   looks       "look …" → the looks, applied live
 *
 * A result is { provider, icon, text, title, subtitle, run() }; `text` is
 * a glyph shown instead of an icon (emoji).
 */
Item {
    id: root
    property string query: ""
    readonly property var p: Config.options?.search?.plugins ?? {}
    function on(name) { return root.p?.[name]?.enable ?? false }

    // Leading results go above the apps; `trailing` (emoji typed without ":")
    // below them, so Enter on a plain word still opens the app.
    readonly property var results: [].concat(calcResults, actionResults, schemeResults, lookResults, root.query.trim().startsWith(":") ? emojiResults : [], packageResults)
    readonly property var trailing: root.query.trim().startsWith(":") ? [] : emojiResults
    property string message: ""     // a one-line note (guarded action, missing helper)

    // ── Which helpers exist (once, only for enabled providers) ────────
    property var have: ({})
    Process {
        id: probe
        running: root.on("calculator") || root.on("packages")
        command: ["sh", "-c", 'for c in qalc yay paru; do command -v "$c" >/dev/null 2>&1 && echo "$c"; done']
        stdout: StdioCollector {
            onStreamFinished: {
                const h = {}
                for (const l of text.split("\n")) if (l) h[l] = true
                root.have = h
            }
        }
    }

    // ── Calculator ────────────────────────────────────────────────────
    readonly property bool isCalc: root.on("calculator") && /^[\d\s+\-*/().%^,e]+$|^[\d\s.]+\s*[a-zA-Z/^]+(\s+(to|in)\s+[a-zA-Z/^]+)?$/.test(root.query.trim())
        && /\d/.test(root.query) && root.query.trim().length > 1
    property string calcAnswer: ""
    readonly property var calcResults: root.isCalc && root.calcAnswer !== "" ? [{
        provider: "calculator", icon: "calculate", title: `= ${root.calcAnswer}`, subtitle: "Enter copies the result",
        run: () => { Quickshell.clipboardText = root.calcAnswer }
    }] : []
    onIsCalcChanged: if (!isCalc) calcAnswer = ""
    onQueryChanged: {
        if (root.isCalc && root.have.qalc) calcDebounce.restart()
        if (root.on("packages")) pkgDebounce.restart()
        root.message = ""
    }
    // A process still running ignores a new command: queue a rerun, and only
    // take an answer for the query it was asked (no "4" for "2+23").
    Timer { id: calcDebounce; interval: 120; onTriggered: root.runCalc() }
    function runCalc() {
        if (calc.running) { calc.again = true; return }
        calc.forQuery = root.query.trim()
        calc.command = ["qalc", "-t", "--", calc.forQuery]
        calc.running = true
    }
    Process {
        id: calc
        property string forQuery: ""
        property bool again: false
        stdout: StdioCollector { onStreamFinished: if (calc.forQuery === root.query.trim()) root.calcAnswer = text.trim() }
        onExited: if (again) { again = false; if (root.isCalc) root.runCalc() }
    }

    // ── Emoji ─────────────────────────────────────────────────────────
    property var emoji: []          // [glyph, name], loaded when enabled
    FileView {
        path: root.on("emoji") ? Quickshell.shellPath("assets/emoji.json") : ""
        onLoaded: { try { root.emoji = JSON.parse(text()) } catch (e) { root.emoji = [] } }
    }
    readonly property var emojiResults: {
        if (!root.on("emoji")) return []
        const raw = root.query.trim().toLowerCase()
        const q = raw.startsWith(":") ? raw.slice(1) : raw
        if (q.length < 2 && !raw.startsWith(":")) return []
        const scored = []
        for (const [g, name] of root.emoji) {
            if (q.length && !name.includes(q)) continue
            const words = name.split(" ")
            scored.push([name === q ? 0 : words.includes(q) ? 1 : words.some(w => w.startsWith(q)) ? 2 : 3, g, name])
        }
        scored.sort((a, b) => a[0] - b[0] || a[2].length - b[2].length)
        return scored.slice(0, raw.startsWith(":") ? 30 : 6).map(([s, g, name]) => ({
            provider: "emoji", text: g, title: name, subtitle: "Enter copies it",
            run: () => { Quickshell.clipboardText = g }
        }))
    }

    // ── Packages ("pkg <name>") ───────────────────────────────────────
    readonly property string helper: root.p?.packages?.helper || (root.have.paru ? "paru" : root.have.yay ? "yay" : "")
    readonly property string pkgQuery: root.query.startsWith("pkg ") ? root.query.slice(4).trim() : ""
    property var pkgList: []
    Timer {
        id: pkgDebounce
        interval: 450
        onTriggered: {
            root.pkgList = []
            if (root.pkgQuery.length < 2) return
            if (!root.helper) { root.message = "Package search needs yay or paru"; return }
            root.runPkg()
        }
    }
    function runPkg() {
        if (pkg.running) { pkg.again = true; return }
        pkg.forQuery = root.pkgQuery
        pkg.command = [root.helper, "-Ss", "--", pkg.forQuery]
        pkg.running = true
    }
    Process {
        id: pkg
        property string forQuery: ""
        property bool again: false
        onExited: if (again) { again = false; if (root.pkgQuery.length >= 2) root.runPkg() }
        stdout: StdioCollector {
            onStreamFinished: {
                if (pkg.forQuery !== root.pkgQuery) return
                // "repo/name version [tags]\n    description"
                const out = [], lines = text.split("\n")
                for (let i = 0; i < lines.length && out.length < 12; i++) {
                    const m = lines[i].match(/^(\S+)\/(\S+)\s+(\S+)(.*)$/)
                    if (!m) continue
                    out.push({ repo: m[1], name: m[2], version: m[3], installed: /\[installed/i.test(m[4]), desc: (lines[i + 1] ?? "").trim() })
                }
                const q = root.pkgQuery.toLowerCase() // the exact name first
                out.sort((a, b) => (b.name.toLowerCase() === q) - (a.name.toLowerCase() === q))
                root.pkgList = out
            }
        }
    }
    readonly property var packageResults: root.on("packages") && root.pkgQuery.length >= 2 ? root.pkgList.map(x => ({
        provider: "packages", icon: x.installed ? "check_circle" : "download",
        title: `${x.name} ${x.version}`, subtitle: `${x.repo}${x.installed ? " · installed" : ""} · ${x.desc}`,
        run: () => DefaultApps.run("terminal", ["-e", root.helper, "-S", "--", x.name])
    })) : []

    // ── Actions ───────────────────────────────────────────────────────
    readonly property var actionResults: {
        if (!root.on("actions") || root.query.trim().length < 2) return []
        const q = root.query.trim().toLowerCase()
        return (root.p?.actions?.items ?? []).filter(a => (a.name ?? "").toLowerCase().includes(q)).map(a => ({
            provider: "actions", icon: a.icon || (a.dangerous ? "warning" : "bolt"), title: a.name,
            subtitle: a.dangerous ? (root.p?.actions?.enableDangerous ? "Runs at once" : "Guarded: allow dangerous actions in Settings → Modules → App Launcher") : (a.command ?? []).join(" "),
            run: () => {
                if (a.dangerous && !(root.p?.actions?.enableDangerous ?? false)) {
                    root.message = `"${a.name}" is guarded: Settings → Modules → App Launcher → Allow dangerous actions`
                    return false // keep the launcher open to show why
                }
                if (Array.isArray(a.command) && a.command.length) Quickshell.execDetached(a.command)
            }
        }))
    }

    // ── Schemes and variants ("scheme …") ─────────────────────────────
    readonly property var variants: ["tonal-spot", "content", "expressive", "fidelity", "fruit-salad", "monochrome", "neutral", "rainbow"]
    readonly property var schemeResults: {
        if (!root.on("schemes") || !root.query.startsWith("scheme")) return []
        const q = root.query.slice(6).trim().toLowerCase()
        const out = []
        for (const v of root.variants) if (v.includes(q)) out.push({
            provider: "schemes", icon: "palette", title: `Variant: ${v}`, subtitle: "Material You colours from your wallpaper, this variant",
            run: () => {
                Config.setNestedValue("appearance.theme.source", "materialYou")
                Config.setNestedValue("appearance.colors.schemeType", v)
                Wallpapers.recolor(Config.options?.background?.wallpaperPath ?? "", Config.options?.appearance?.colors?.darkMode ?? true)
            }
        })
        for (let i = 0; i < ThemeRegistry.count; i++) {
            const t = ThemeRegistry.themes.get(i)
            const name = t?.name ?? ""
            if (name && (name + " " + (t.displayName ?? "")).toLowerCase().includes(q)) out.push({
                provider: "schemes", icon: "format_paint", title: `Theme: ${t.displayName || name}`, subtitle: t.description || "A fixed colour theme",
                run: () => { Config.setNestedValue("appearance.theme.source", "static"); Config.setNestedValue("appearance.theme.name", name) }
            })
        }
        return out.slice(0, 20)
    }

    // ── Looks ("look …") ──────────────────────────────────────────────
    readonly property var lookResults: {
        if (!root.on("looks") || !root.query.startsWith("look")) return []
        const q = root.query.slice(4).trim().toLowerCase()
        return Looks.list.filter(l => Looks.usable(l.id) && (l.id + " " + l.name).toLowerCase().includes(q)).map(l => ({
            provider: "looks", icon: "style", title: `Look: ${l.name}`, subtitle: l.description || "Applies now",
            run: () => Config.setNestedValue("appearance.look", l.id)
        }))
    }
}
