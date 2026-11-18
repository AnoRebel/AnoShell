import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import "pet.js" as Pet

// A pet drawn at `size` px, feet at the bottom middle: the kind's rig scaled from its 100 × 100 space (curve-rendered,
// so sharp), turned by `facing` (1 right, -1 left), squashed by p.sq, with its speech bubble, sleep z's and hearts.
Item {
    id: root
    property string kind: "duck"
    property string preset: ""
    property var p: Pet.pose("duck", "idle", 0)
    property real size: 128
    property real facing: 1
    property real t: 0            // seconds, for the z's and hearts
    property string say: ""       // speech bubble text, "" for none
    property bool hearts: false
    width: size; height: size

    Item {
        id: art
        width: 100; height: 100
        transformOrigin: Item.TopLeft
        scale: root.size / 100
        transform: Scale { origin.x: 50; origin.y: 100; xScale: root.facing * (1 + (1 - root.p.sq) * 0.6); yScale: root.p.sq }
        Loader {
            sourceComponent: root.kind === "cat" ? cat : root.kind === "dog" ? dog : duck
        }
        Component { id: duck; DuckRig { p: root.p; c: Pet.presetOf("duck", root.preset) } }
        Component { id: cat; CatRig { p: root.p; c: Pet.presetOf("cat", root.preset) } }
        Component { id: dog; DogRig { p: root.p; c: Pet.presetOf("dog", root.preset) } }
    }

    // Where the head is (for the bubble and the z's), in px.
    readonly property real headX: root.width / 2 + root.facing * root.size * 0.3
    readonly property real headY: root.size * 0.25

    Rectangle {
        visible: root.say !== ""
        x: Math.round(root.headX - width / 2 + root.facing * root.size * 0.1)
        y: Math.round(root.headY - height - root.size * 0.12)
        width: bubbleText.implicitWidth + 16; height: bubbleText.implicitHeight + 8
        radius: height / 2
        color: Appearance.colors.colLayer1
        border.width: 1; border.color: Appearance.colors.colOutlineVariant
        StyledText {
            id: bubbleText
            anchors.centerIn: parent
            text: root.say
            font.pixelSize: Math.max(Appearance.font.pixelSize.smaller, root.size * 0.11)
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnLayer1
        }
    }

    // Sleep: z's drifting up from the head.
    Repeater {
        model: root.p.lie > 0.9 && root.p.eye === 0 ? 3 : 0
        StyledText {
            required property int index
            readonly property real k: ((root.t * 0.45 + index / 3) % 1)
            x: root.headX + root.facing * (k * root.size * 0.22) - width / 2
            y: root.headY + root.size * 0.1 - k * root.size * 0.5
            opacity: Math.sin(Math.PI * k)
            text: "z"
            font.pixelSize: root.size * (0.1 + k * 0.08)
            font.weight: Font.Bold
            color: Appearance.colors.colOnLayer0
        }
    }

    // Petted: hearts rising.
    Repeater {
        model: root.hearts ? 3 : 0
        MaterialSymbol {
            required property int index
            readonly property real k: ((root.t * 0.8 + index / 3) % 1)
            x: root.headX + (index - 1) * root.size * 0.14 - width / 2
            y: root.headY - k * root.size * 0.45
            opacity: Math.sin(Math.PI * k)
            text: "favorite"
            fill: 1
            iconSize: root.size * 0.13
            color: Appearance.colors.colError
        }
    }
}
