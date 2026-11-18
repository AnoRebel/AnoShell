import QtQuick

// The cat, side view facing right with its face turned three-quarters to us, in a 100 × 100 space with its feet at the
// bottom middle. `p` is a pet.js pose, `c` a cat preset (tabby stripes, calico patches). Original art for AnoShell.
Item {
    id: root
    property var p
    property var c
    width: 100; height: 100
    readonly property color far: Qt.darker(root.c.base, 1.18)
    readonly property real tilt: -root.p.sit * 32 // sitting: the back end drops, pivoting on the shoulders
    readonly property color ink: Qt.rgba(0.09, 0.08, 0.08, 1)

    component Leg: Item {
        id: leg
        property real px
        property int i
        property bool front
        property color col
        width: 100; height: 100
        // Front legs stay upright when the body tilts; back legs fold when sitting or lying.
        readonly property real fold: leg.front ? root.p.lie : Math.max(root.p.lie, root.p.sit)
        transform: Rotation { origin.x: leg.px; origin.y: 74; angle: -root.p.legs[leg.i] - (leg.front ? root.tilt : 45 * root.p.sit) }
        Rectangle {
            x: leg.px - 3.6; y: 70; width: 7.2; radius: 3.6
            height: 28 * (1 - 0.55 * leg.fold)
            color: leg.col
        }
    }

    Item {
        width: 100; height: 100
        transform: [
            Rotation { origin.x: 66; origin.y: 76; angle: root.p.rot + root.tilt },
            Translate { x: root.p.bx; y: root.p.by + root.p.lie * 13 }
        ]

        // Tail: a thick curve from the rump, swishing.
        Item {
            x: 30; y: 62; width: 1; height: 1
            rotation: -root.p.tail * 0.7
            transformOrigin: Item.TopLeft
            PetShape {
                anchors.fill: undefined; width: 1; height: 1
                stroke: root.c.base; strokeW: 6.5
                d: "M 0 0 C -12 -2 -17 -14 -13 -28 C -12 -32 -9 -35 -6 -35"
            }
        }

        Leg { px: 62; i: 1; front: true; col: root.far }
        Leg { px: 34; i: 3; front: false; col: root.far }
        PetShape {
            fill: root.c.base
            d: "M 27 64 C 27 54 35 50 46 50 L 64 50 C 74 50 79 56 79 64 C 79 73 73 78 64 78 L 40 78 C 32 78 27 72 27 64 Z"
        }
        PetShape { fill: root.c.belly; d: "M 40 77 C 46 71 62 70 71 76 C 66 78.5 46 78.5 40 77 Z" }
        // Tabby stripes.
        Repeater {
            model: root.c.pattern === "stripes" ? [36, 44, 52, 60] : []
            PetShape {
                required property var modelData
                stroke: root.c.mark; strokeW: 2.4
                d: `M ${modelData} 51 Q ${modelData + 2.5} 56 ${modelData + 0.5} 61`
            }
        }
        // Calico patches.
        PetShape { visible: root.c.pattern === "patches"; fill: root.c.mark || "transparent"; d: "M 33 56 C 35 51 44 51 47 55 C 49 60 42 64 36 63 C 32 62 32 59 33 56 Z" }
        PetShape { visible: root.c.pattern === "patches"; fill: root.c.mark2 || "transparent"; d: "M 52 51 C 58 50 66 51 67 55 C 66 59 58 60 53 58 C 50 56 50 52 52 51 Z" }
        Leg { px: 66; i: 0; front: true; col: root.c.base }
        Leg { px: 38; i: 2; front: false; col: root.c.base }

        // Head: three-quarter face, pivot at the neck.
        Item {
            width: 100; height: 100
            transform: [
                Rotation { origin.x: 70; origin.y: 56; angle: root.p.hr - root.tilt * 0.8 },
                Translate { x: root.p.hx; y: root.p.hy }
            ]
            // Ears (inner ear in the nose colour), tipping back with p.ear.
            Repeater {
                model: [{ d: "M 68 40 L 70 23 L 79 33 Z", i: "M 70.5 37 L 71.5 27 L 76.5 33 Z", ox: 72 },
                        { d: "M 84 33 L 92 23 L 94 40 Z", i: "M 86.5 33 L 91.5 27 L 92.5 37 Z", ox: 89 }]
                Item {
                    id: ear
                    required property var modelData
                    width: 100; height: 100
                    transform: Rotation { origin.x: ear.modelData.ox; origin.y: 36; angle: root.p.ear * (ear.modelData.ox < 80 ? 1 : -1) }
                    PetShape { fill: root.c.base; d: ear.modelData.d }
                    PetShape { fill: root.c.nose; opacity: 0.7; d: ear.modelData.i }
                }
            }
            Rectangle { x: 66; y: 30; width: 30; height: 27; radius: 13.5; color: root.c.base }
            PetShape { visible: root.c.pattern === "stripes"; stroke: root.c.mark || "transparent"; strokeW: 1.8; d: "M 78 31 L 79 36 M 82 30.5 L 82 35.5 M 86 31 L 85 36" }
            PetShape { visible: root.c.pattern === "patches"; fill: root.c.mark2 || "transparent"; d: "M 66.5 42 C 66 35 71 30.5 77 31 C 76 36 72 40 66.5 42 Z" }
            // Muzzle.
            PetShape { fill: root.c.belly; d: "M 76 50 C 78 46 88 46 90 50 C 89 54.5 77 54.5 76 50 Z" }
            // Eyes: iris and slit pupil, closing to a line; ^ ^ when petted.
            Repeater {
                model: [76.5, 87]
                Item {
                    id: eye
                    required property var modelData
                    x: eye.modelData - 2.6; y: 39; width: 5.2; height: 6
                    visible: root.p.eye >= 0
                    Rectangle {
                        anchors.centerIn: parent
                        width: 5.2; height: 6 * Math.max(0.1, Math.min(1, root.p.eye)); radius: 2.6
                        color: root.p.eye > 0.3 ? root.c.eye : root.ink
                        Rectangle { anchors.centerIn: parent; visible: root.p.eye > 0.3; width: 1.5; height: parent.height * 0.85; radius: 0.75; color: root.ink }
                        Rectangle { visible: root.p.eye > 0.5; x: 3.1; y: 0.8; width: 1.2; height: 1.2; radius: 0.6; color: "white" }
                    }
                }
            }
            PetShape {
                visible: root.p.eye < 0
                stroke: root.ink; strokeW: 1.3
                d: "M 74 43 Q 76.5 39 79 43 M 84.5 43 Q 87 39 89.5 43"
            }
            // Nose and mouth; open for the call.
            PetShape { fill: root.c.nose; d: "M 81 47.5 L 85 47.5 L 83 50 Z" }
            PetShape { stroke: root.ink; strokeW: 0.8; d: "M 83 50 L 83 51.2 M 80.5 52 Q 81.8 53.2 83 51.2 Q 84.2 53.2 85.5 52" }
            Rectangle {
                visible: root.p.mouth > 0.05
                x: 81; y: 51.5; width: 4; height: 4.5 * root.p.mouth; radius: 2
                color: Qt.darker(root.c.nose, 1.6)
            }
            // Whiskers.
            PetShape {
                stroke: Qt.rgba(1, 1, 1, 0.55); strokeW: 0.5
                d: "M 77 50.5 L 66 49 M 77 52 L 66.5 53.5 M 89 50.5 L 99 49 M 89 52 L 98.5 53.5"
            }
        }
    }
}
