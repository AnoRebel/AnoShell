pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.services

// Wallhaven's filters under the ribbon: sorting (and the toplist range),
// order, categories, purity and a colour. They write background.wallhaven.*; the
// Wallhaven service searches again when they change. NSFW shows only with an
// API key (Wallhaven ignores it without one).
Flow {
    id: filters
    required property Item deck
    readonly property var f: Config.options?.background?.wallhaven

    spacing: 8 * deck.u

    function set(key, value) { Config.setNestedValue(`background.wallhaven.${key}`, value) }
    // Flip one flag of a "101"-style mask, keeping at least one on.
    function flip(key, mask, i) {
        const c = (mask ?? "100").split("")
        c[i] = c[i] === "1" ? "0" : "1"
        if (c.includes("1")) filters.set(key, c.join(""))
    }

    component Chip: Rectangle {
        id: chip
        property string label
        property bool active
        property bool danger: false
        signal clicked
        width: chipText.implicitWidth + 22 * filters.deck.u
        height: 30 * filters.deck.u
        radius: height / 2
        color: active ? (danger ? Appearance.colors.colError : filters.deck.tint.accent)
            : Qt.rgba(filters.deck.tint.surface.r, filters.deck.tint.surface.g, filters.deck.tint.surface.b, chipMa.containsMouse ? 0.95 : 0.72)
        border.width: active ? 0 : 1
        border.color: Qt.rgba(filters.deck.tint.ink.r, filters.deck.tint.ink.g, filters.deck.tint.ink.b, 0.1)
        StyledText {
            id: chipText
            anchors.centerIn: parent
            text: chip.label
            font.pixelSize: (Appearance?.font.pixelSize.smaller ?? 12) * filters.deck.u
            font.weight: Font.Medium
            color: chip.active ? (chip.danger ? Appearance.colors.colOnError : filters.deck.tint.accentInk) : filters.deck.tint.ink
        }
        MouseArea { id: chipMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: chip.clicked() }
    }
    component Gap: Item { width: 8 * filters.deck.u; height: 30 * filters.deck.u }

    Repeater {
        model: [["Recent", "date_added"], ["Hot", "toplist"], ["Views", "views"], ["Favs", "favorites"], ["Random", "random"], ["Relevant", "relevance"]]
        Chip {
            required property var modelData
            label: modelData[0]
            active: (filters.f?.sorting ?? "date_added") === modelData[1]
            onClicked: filters.set("sorting", modelData[1])
        }
    }
    Repeater {
        model: (filters.f?.sorting ?? "") === "toplist" ? ["1d", "3d", "1w", "1M", "3M", "6M", "1y"] : []
        Chip {
            required property string modelData
            label: modelData
            active: (filters.f?.topRange ?? "1M") === modelData
            onClicked: filters.set("topRange", modelData)
        }
    }
    Chip {
        label: (filters.f?.order ?? "desc") === "desc" ? "↓" : "↑"
        onClicked: filters.set("order", (filters.f?.order ?? "desc") === "desc" ? "asc" : "desc")
    }
    Gap {}
    Repeater {
        model: [["General", 0], ["Anime", 1], ["People", 2]]
        Chip {
            required property var modelData
            label: modelData[0]
            active: (filters.f?.categories ?? "111")[modelData[1]] === "1"
            onClicked: filters.flip("categories", filters.f?.categories ?? "111", modelData[1])
        }
    }
    Gap {}
    Repeater {
        model: Wallhaven.hasKey ? [["SFW", 0], ["Sketchy", 1], ["NSFW", 2]] : [["SFW", 0], ["Sketchy", 1]]
        Chip {
            required property var modelData
            label: modelData[0]
            danger: modelData[1] === 2
            active: (filters.f?.purity ?? "100")[modelData[1]] === "1"
            onClicked: filters.flip("purity", filters.f?.purity ?? "100", modelData[1])
        }
    }
    Gap {}
    // Search by colour: Wallhaven's own palette (its API takes only these).
    Repeater {
        model: ["660000", "990000", "cc0000", "cc3333", "ea4c88", "993399", "663399", "333399", "0066cc", "0099cc",
            "66cccc", "77cc33", "669900", "336600", "666600", "999900", "cccc33", "ffff00", "ffcc33", "ff9900",
            "ff6600", "cc6633", "996633", "663300", "000000", "999999", "cccccc", "ffffff", "424153"]
        Rectangle {
            required property string modelData
            readonly property bool active: (filters.f?.colors ?? "") === modelData
            width: 22 * filters.deck.u; height: 30 * filters.deck.u
            color: "transparent"
            Rectangle {
                anchors.centerIn: parent
                width: (parent.active ? 20 : 16) * filters.deck.u; height: width; radius: width / 2
                color: "#" + parent.modelData
                border.width: parent.active ? 2 : 1
                border.color: parent.active ? filters.deck.tint.accent : Qt.rgba(filters.deck.tint.ink.r, filters.deck.tint.ink.g, filters.deck.tint.ink.b, 0.25)
                Behavior on width { NumberAnimation { duration: AnimationConfig.scaledDuration(120) } }
            }
            MouseArea {
                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                // Again on the chosen one: any colour.
                onClicked: filters.set("colors", parent.active ? "" : parent.modelData)
            }
        }
    }
}
