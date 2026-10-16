pragma Singleton

import QtQuick
import Quickshell
import qs.modules.common

/**
 * Bar style (bar.style: pill | classic, Ano family only; design D12).
 * In pill style the pill (AnoSpot) is the bar: it hosts workspaces, clock,
 * status and tray, reserves its edge, and rests at the bottom centre unless
 * you moved it. The dock (dock.position: auto) takes the opposite edge.
 * Other families always use the classic bar.
 */
Singleton {
    id: root

    readonly property string family: Config.options?.panelFamily ?? "ano"
    readonly property string style: Config.options?.bar?.style ?? "pill"
    readonly property bool pillBar: family === "ano" && style === "pill"

    // The pill's edge (anoSpot.position; bottom by default, design D12).
    readonly property string pillEdge: Config.options?.anoSpot?.position ?? "bottom"

    function opposite(e) { return ({ top: "bottom", bottom: "top", left: "right", right: "left" })[e] ?? "bottom" }

    // Same-edge swap (iRiS rule): moving the dock onto the pill-bar's edge
    // moves the pill to the dock's old edge, and the other way round.
    // Plain values (not bindings): a binding would already hold the new edge
    // when the change handler reads it.
    property string _lastDock: ""
    property string _lastPill: ""
    Component.onCompleted: { _lastDock = dockEdge; _lastPill = pillEdge }
    onDockEdgeChanged: {
        // Deferred a turn: during a config reload a write here is overwritten.
        if (pillBar && dockEdge === pillEdge && (Config.options?.dock?.position ?? "auto") !== "auto") {
            const to = _lastDock
            Qt.callLater(() => Config.setNestedValue("anoSpot.position", to))
        }
        _lastDock = dockEdge
    }
    onPillEdgeChanged: {
        if (pillBar && pillEdge === dockEdge && (Config.options?.dock?.position ?? "auto") !== "auto") {
            const to = _lastPill
            Qt.callLater(() => Config.setNestedValue("dock.position", to))
        }
        _lastPill = pillEdge
    }

    // The dock's edge: "auto" takes the edge opposite the pill-bar (bottom
    // otherwise).
    readonly property string dockEdge: {
        const p = Config.options?.dock?.position ?? "auto"
        if (p !== "auto") return p
        return pillBar ? opposite(pillEdge) : "bottom"
    }
}
