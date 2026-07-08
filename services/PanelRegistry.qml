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
 *   { key, kind, screenName, edge, x, y, w, h }
 * where edge ∈ "top"|"bottom"|"left"|"right", and (x,y,w,h) is the panel's
 * screen-space content rect (NOT the host window, which may be full-screen).
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
            "h": geom.h ?? 0
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
}
