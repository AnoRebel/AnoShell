pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell

/**
 * PanelRegistry — reactive registry of visible shell-panel geometries for the
 * connected-corners frame.
 *
 * The connected-corners `AnoScreen` is a decorative full-screen window that must
 * NOT host panel content (doing so crashes QS 0.3.0 with the refWindow
 * recursion). To draw concave joins where a panel meets the rounded screen
 * frame, AnoScreen needs to know each visible panel's screen-space rectangle +
 * which edge it hugs — without owning the panel. Panels register/unregister
 * themselves here as they show/hide; AnoScreen reads `panels` reactively.
 *
 * Inert unless connected corners are enabled: `register()` is a no-op when the
 * feature is off, so floating mode pays nothing.
 *
 * A registered panel is a plain object:
 *   { key, kind, screenName, edge, x, y, w, h,
 *     priority, surfaceRadius, omitStartConnector, omitEndConnector }
 * where edge ∈ "top"|"bottom"|"left"|"right", and (x,y,w,h) is the panel's
 * screen-space content rect (NOT the host window, which may be full-screen).
 *
 * The frame shader has only FOUR chrome slots. `priority` (higher wins) decides
 * who gets one when more panels are visible than slots; bars register high so a
 * transient popout never evicts the bar from the silhouette.
 *
 * `omitStartConnector`/`omitEndConnector` mark an end that is flush against a
 * frame corner: it takes the panel's own convex rounding there instead of a
 * concave junction arc.
 */
Singleton {
    id: root

    readonly property bool enabled: Config.options?.appearance?.connectedCorners?.enable ?? false

    // key -> panel-geometry object. A plain map; `panels` is the reactive view.
    property var _byKey: ({})
    property var panels: []

    function _rebuild() {
        const out = []
        for (const k in root._byKey) out.push(root._byKey[k])
        root.panels = out
    }

    // Register or update a panel. `key` is a stable unique id (e.g. the panel's
    // namespace + screen). Passing a falsy rect (w<=0 or h<=0) unregisters it.
    function register(key, geom) {
        if (!root.enabled || !key) return
        if (!geom || (geom.w ?? 0) <= 0 || (geom.h ?? 0) <= 0) {
            root.unregister(key)
            return
        }
        root._byKey[key] = {
            "key": key,
            "kind": geom.kind ?? "panel",
            "screenName": geom.screenName ?? "",
            "edge": geom.edge ?? "top",
            "x": geom.x ?? 0,
            "y": geom.y ?? 0,
            "w": geom.w ?? 0,
            "h": geom.h ?? 0,
            "priority": geom.priority ?? 0,
            "surfaceRadius": geom.surfaceRadius,
            "omitStartConnector": geom.omitStartConnector ?? false,
            "omitEndConnector": geom.omitEndConnector ?? false
        }
        root._rebuild()
    }

    function unregister(key) {
        if (!key || root._byKey[key] === undefined) return
        delete root._byKey[key]
        root._rebuild()
    }

    // Panels registered on a given screen (by name).
    function panelsForScreen(screenName) {
        return root.panels.filter(p => p.screenName === screenName)
    }

    // The (at most `limit`) highest-priority panels on a screen, ready to be
    // packed into the frame shader's chrome slots. Ties break on `key` so the
    // order is stable across rebuilds (an unstable order makes slots flicker).
    function surfacesForScreen(screenName, limit) {
        const out = root.panelsForScreen(screenName).slice()
        out.sort((a, b) => (b.priority - a.priority) || (a.key < b.key ? -1 : a.key > b.key ? 1 : 0))
        return out.slice(0, limit ?? 4).map(p => ({
            "side": p.edge,
            "x": p.x, "y": p.y, "w": p.w, "h": p.h,
            "surfaceRadius": p.surfaceRadius,
            "omitStartConnector": p.omitStartConnector,
            "omitEndConnector": p.omitEndConnector
        }))
    }
}
