import QtQuick
import "../_bioma"

// Bioma's Lava lamp organism as a desktop widget (widgets/_bioma/OrganismFrame).
Item {
    id: root
    property var ctx
    property var settings: ({})
    OrganismFrame {
        ctx: root.ctx
        settings: root.settings
        design: Qt.size(2, 4)
        body: Component { LavaOrganism {} }
    }
}
