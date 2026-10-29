import QtQuick

// Hosts a ported Bioma organism inside an AnoShell piece card: gives it the
// metrics at the normal step, its options (the piece's settings, under
// Bioma's keys) as `entry`, and `organism.here` from ctx.live, so it runs
// only while the desktop can be seen. Bioma pads an organism by 20 px; the
// card already insets 12. An organism that `bleeds` gets the whole card.
//
//   OrganismFrame { ctx: root.ctx; settings: root.settings; body: Component { LavaOrganism {} } }
Item {
    id: frame
    property var ctx
    property var settings: ({})
    property Component body
    // The piece's default size in cells (its manifest `size`): the card is
    // scaled from it, so a resized organism grows or shrinks its type and
    // spacing with the card (0.75–1.6×) instead of overflowing or floating.
    property size design: Qt.size(4, 2)
    anchors.fill: parent

    readonly property real cellStep: (frame.ctx?.cell ?? 96) + 12
    readonly property real fit: Math.max(0.75, Math.min(1.6, Math.min(
        (frame.width + 24) / Math.max(1, frame.design.width * frame.cellStep - 12),
        (frame.height + 24) / Math.max(1, frame.design.height * frame.cellStep - 12))))
    // Bioma's metrics at the normal step, times the scale (hairlines stay).
    readonly property var metrics: {
        const m = Object.assign({}, Metrics.step("normal"))
        const keep = ["name", "thread", "nodeSize", "rimWidth"]
        for (const k in m) if (typeof m[k] === "number" && !keep.includes(k))
            m[k] = k.startsWith("font") ? Math.round(m[k] * frame.fit) : m[k] * frame.fit
        return m
    }
    readonly property QtObject organism: QtObject {
        readonly property bool here: frame.ctx?.live ?? false
    }

    // Built once the card has its size, and again (debounced) when a resize
    // changes the scale: Bioma's lit text draws through layers that don't
    // follow a font that grows after they were made.
    property real builtFit: 0
    onFitChanged: if (frame.builtFit > 0 && Math.abs(frame.fit - frame.builtFit) > 0.04) rebuild.restart()
    Timer { id: rebuild; interval: 250; onTriggered: { loader.active = false; loader.active = true } }

    Loader {
        id: loader
        anchors.fill: parent
        active: frame.width > 0 && frame.height > 0
        anchors.margins: item?.bleeds === true ? -12 : 8 * frame.metrics.factor
        sourceComponent: frame.body
        onLoaded: {
            frame.builtFit = frame.fit
            item.metrics = Qt.binding(() => frame.metrics)
            item.entry = Qt.binding(() => frame.settings ?? {})
            if (item.hasOwnProperty("organism")) item.organism = frame.organism
        }
    }
}
