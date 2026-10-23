import QtQuick

// Hosts a ported Bioma organism inside an AnoShell widget card: gives it the
// metrics at the normal step, its options (the widget's settings, under
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
    anchors.fill: parent

    readonly property var metrics: Metrics.step("normal")
    readonly property QtObject organism: QtObject {
        readonly property bool here: frame.ctx?.live ?? false
    }

    Loader {
        id: loader
        anchors.fill: parent
        anchors.margins: item?.bleeds === true ? -12 : 8 * frame.metrics.factor
        sourceComponent: frame.body
        onLoaded: {
            item.metrics = Qt.binding(() => frame.metrics)
            item.entry = Qt.binding(() => frame.settings ?? {})
            if (item.hasOwnProperty("organism")) item.organism = frame.organism
        }
    }
}
