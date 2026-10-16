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

    // Moving the pill or the dock to an edge. In pill-bar style, moving one
    // onto the other's edge swaps them (iRiS rule). Called where you change an
    // edge (edge picker, Settings, config IPC) — never from change handlers,
    // which also fire while a config file loads and would rewrite it.
    //   which: "pill" | "dock";  edge: top/bottom/left/right (dock also "auto")
    Component.onCompleted: Config.edgeMover = root.moveEdge
    function moveEdge(which, edge) {
        const other = which === "pill" ? root.dockEdge : root.pillEdge
        const mine = which === "pill" ? root.pillEdge : root.dockEdge
        if (root.pillBar && edge === other && edge !== "auto") {
            if (which === "pill") Config.setNestedValue("dock.position", mine)
            else Config.setNestedValue("anoSpot.position", mine)
        }
        Config.setNestedValue(which === "pill" ? "anoSpot.position" : "dock.position", edge)
    }

    // The dock's edge: "auto" takes the edge opposite the pill-bar (bottom
    // otherwise).
    readonly property string dockEdge: {
        const p = Config.options?.dock?.position ?? "auto"
        if (p !== "auto") return p
        return pillBar ? opposite(pillEdge) : "bottom"
    }
}
