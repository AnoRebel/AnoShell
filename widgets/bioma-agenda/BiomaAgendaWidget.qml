import QtQuick
import "../_bioma"

// Bioma's Organism agenda organism as a desktop widget (widgets/_bioma/OrganismFrame).
Item {
    id: root
    property var ctx
    property var settings: ({})
    OrganismFrame {
        ctx: root.ctx
        settings: root.settings
        body: Component { AgendaOrganism {} }
    }
}
