pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * PanelRegistry — the connected frame's geometry registry (DMS ConnectedModeState
 * semantics, trimmed).
 *
 * The AnoScreen frame is a decorative full-screen window that must NOT host
 * panel content (QS 0.3 refWindow crash), so every surface that fuses into the
 * frame publishes its screen-space body rect here instead, through a
 * ConnectedSurfaceLease (modules/common). AnoScreen reads `panels` reactively.
 *
 * Ownership: a lease claims a key and gets an owner token; only the current
 * owner may write or release the key, and each write carries a revision that
 * must increase. A stale writer (a window being torn down after its
 * replacement claimed the key, or an out-of-order write) is rejected and
 * counted in `rejected`. Entries on screens that no longer exist are pruned.
 *
 * A descriptor:
 *   { key, kind, screenName, edge, x, y, w, h, progress,
 *     priority, surfaceRadius, omitStartConnector, omitEndConnector, owner, rev }
 * edge ∈ top|bottom|left|right; (x,y,w,h) is the CURRENT (animated) body rect;
 * progress ∈ 0..1 is how far the surface has grown out of its edge.
 *
 * `priority` (higher wins) decides who gets one of the shader's 8 slots when
 * more surfaces are visible than slots. Inert when connected mode is off.
 */
Singleton {
    id: root

    readonly property bool enabled: Config.options?.appearance?.connectedCorners?.enable ?? false

    property var _byKey: ({})
    property var _owner: ({})       // key -> current owner token
    property int _serial: 0
    property var panels: []
    property int revision: 0        // bumps on every accepted change
    property int rejected: 0        // stale/foreign writes refused

    onEnabledChanged: if (!enabled) { _byKey = {}; _owner = {}; _schedule() }

    function _rebuild() {
        const out = []
        for (const k in root._byKey) out.push(root._byKey[k])
        root.panels = out
        root.revision++
    }
    function _schedule() { Qt.callLater(root._rebuild) }

    function _reject(key, why) {
        root.rejected++
        console.warn(`PanelRegistry: rejected ${why} write to "${key}"`)
        return false
    }

    /// Take ownership of `key`; earlier owners' writes are refused from now on.
    function claim(key) {
        root._serial++
        const token = `${key}#${root._serial}`
        root._owner[key] = token
        return token
    }

    /// Write the current geometry. False when not the owner or `rev` is stale.
    function publish(key, owner, rev, geom) {
        if (!root.enabled || !key) return false
        if (root._owner[key] !== owner) return root._reject(key, "foreign")
        const prev = root._byKey[key]
        if (prev && prev.owner === owner && rev <= prev.rev) return root._reject(key, "stale-revision")
        if (!geom || (geom.w ?? 0) <= 0 || (geom.h ?? 0) <= 0) {
            if (prev) { delete root._byKey[key]; root._schedule() }
            return true
        }
        root._byKey[key] = {
            "key": key, "owner": owner, "rev": rev,
            "kind": geom.kind ?? "panel",
            "screenName": geom.screenName ?? "",
            "edge": geom.edge ?? "top",
            "x": geom.x ?? 0, "y": geom.y ?? 0, "w": geom.w, "h": geom.h,
            "progress": geom.progress ?? 1,
            "priority": geom.priority ?? 0,
            "surfaceRadius": geom.surfaceRadius,
            "omitStartConnector": geom.omitStartConnector ?? false,
            "omitEndConnector": geom.omitEndConnector ?? false
        }
        root._schedule()
        return true
    }

    /// Drop `key` if `owner` still owns it.
    function release(key, owner) {
        if (root._owner[key] !== owner) return false
        delete root._owner[key]
        if (root._byKey[key] !== undefined) { delete root._byKey[key]; root._schedule() }
        return true
    }

    // Surfaces on monitors that went away never release cleanly; drop them.
    Connections {
        target: Quickshell
        function onScreensChanged() {
            const live = Quickshell.screens.map(s => s.name)
            let changed = false
            for (const k in root._byKey) {
                if (!live.includes(root._byKey[k].screenName)) { delete root._byKey[k]; delete root._owner[k]; changed = true }
            }
            if (changed) root._schedule()
        }
    }

    function panelsForScreen(screenName) {
        return root.panels.filter(p => p.screenName === screenName)
    }

    // The (at most `limit`) highest-priority panels on a screen, ready for the
    // frame's slots. Ties break on `key` so the order is stable across rebuilds.
    function surfacesForScreen(screenName, limit) {
        const out = root.panelsForScreen(screenName).slice()
        out.sort((a, b) => (b.priority - a.priority) || (a.key < b.key ? -1 : a.key > b.key ? 1 : 0))
        return out.slice(0, limit ?? 8).map(p => ({
            "side": p.edge,
            "x": p.x, "y": p.y, "w": p.w, "h": p.h,
            "progress": p.progress,
            "surfaceRadius": p.surfaceRadius,
            "omitStartConnector": p.omitStartConnector,
            "omitEndConnector": p.omitEndConnector
        }))
    }

    IpcHandler {
        target: "frame"
        /// Registered surfaces as JSON (used by `ano status --frame`).
        function dump(): string {
            return JSON.stringify({ "enabled": root.enabled, "revision": root.revision,
                "rejected": root.rejected, "surfaces": root.panels.map(p => ({
                    "key": p.key, "kind": p.kind, "screen": p.screenName, "edge": p.edge,
                    "rect": [Math.round(p.x), Math.round(p.y), Math.round(p.w), Math.round(p.h)],
                    "progress": Math.round(p.progress * 100) / 100, "priority": p.priority, "rev": p.rev })) })
        }
        /// Ownership/revision self-test on a scratch key; returns PASS/FAIL lines.
        function selftest(): string {
            if (!root.enabled) return "SKIP connected mode is off"
            const key = "selftest", screen = Quickshell.screens[0]?.name ?? ""
            const g = { "screenName": screen, "x": 0, "y": 0, "w": 10, "h": 10 }
            const before = root.rejected
            const a = root.claim(key)
            const r = []
            const t = (name, ok) => r.push((ok ? "PASS " : "FAIL ") + name)
            t("owner writes rev 1", root.publish(key, a, 1, g))
            t("stale rev 1 rejected", !root.publish(key, a, 1, g))
            t("older rev 0 rejected", !root.publish(key, a, 0, g))
            const b = root.claim(key)
            t("new owner writes", root.publish(key, b, 1, g))
            t("old owner write rejected", !root.publish(key, a, 2, g))
            t("old owner release refused", !root.release(key, a))
            t("rejections counted", root.rejected - before === 3)
            t("owner releases", root.release(key, b) && root._byKey[key] === undefined)
            return r.join("\n")
        }
    }
}
