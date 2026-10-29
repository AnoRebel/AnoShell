import QtQuick
import "../_bioma"

// Bioma's Nucleus organism as a piece (pieces/_bioma/OrganismFrame).
Item {
    id: root
    property var ctx
    property var settings: ({})
    OrganismFrame {
        ctx: root.ctx
        settings: root.settings
        design: Qt.size(4, 2)
        body: Component { NucleusOrganism {} }
    }
}
