import QtQuick
import "../_bioma"

// Bioma's Osmosis organism as a piece (pieces/_bioma/OrganismFrame).
Item {
    id: root
    property var ctx
    property var settings: ({})
    OrganismFrame {
        ctx: root.ctx
        settings: root.settings
        design: Qt.size(2, 4)
        body: Component { OsmosisOrganism {} }
    }
}
