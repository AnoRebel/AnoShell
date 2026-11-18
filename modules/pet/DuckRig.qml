import QtQuick

// The duck, side view facing right, in a 100 × 100 space with its feet at the bottom middle. `p` is a pet.js pose,
// `c` a duck preset. Original art for AnoShell.
Item {
    id: root
    property var p
    property var c
    width: 100; height: 100
    readonly property real fold: Math.max(root.p.lie, root.p.sit) // sitting or lying: legs tucked under

    // Legs: pivot under the body; a webbed foot pointing forward.
    Repeater {
        model: [{ x: 45, i: 2, shade: 1.12 }, { x: 53, i: 0, shade: 1 }]
        Item {
            id: leg
            required property var modelData
            width: 100; height: 100
            opacity: root.fold > 0.4 ? 0 : 1 - root.fold
            transform: Rotation { origin.x: leg.modelData.x; origin.y: 82; angle: -root.p.legs[leg.modelData.i] }
            Rectangle { x: leg.modelData.x - 1.4; y: 80; width: 2.8; height: 18; radius: 1.4; color: Qt.darker(root.c.legs, leg.modelData.shade) }
            PetShape {
                fill: Qt.darker(root.c.legs, leg.modelData.shade)
                d: `M ${leg.modelData.x - 2.5} 97 C ${leg.modelData.x + 2} 95.5 ${leg.modelData.x + 7} 96 ${leg.modelData.x + 9} 98.5 C ${leg.modelData.x + 6} 100.3 ${leg.modelData.x} 100.3 ${leg.modelData.x - 2.5} 99.6 Z`
            }
        }
    }

    // Body, wing, neck and head move together.
    Item {
        width: 100; height: 100
        transform: [
            Rotation { origin.x: 50; origin.y: 84; angle: root.p.rot },
            Translate { x: root.p.bx; y: root.p.by + root.fold * 10 }
        ]

        // Tail: a perky point at the back.
        PetShape {
            fill: root.c.body
            d: "M 30 64 C 22 60 15 54 12 47 C 20 50 28 52 36 56 Z"
            transform: Rotation { origin.x: 32; origin.y: 62; angle: -root.p.tail * 0.35 }
        }
        PetShape {
            fill: root.c.body
            d: "M 22 66 C 22 52 38 49 55 52 C 71 55 82 61 80 72 C 78 83 62 88 46 87 C 31 86 22 78 22 66 Z"
        }
        // Breast shading under the neck.
        PetShape { fill: Qt.darker(root.c.body, 1.06); d: "M 60 82 C 70 80 78 76 79 70 C 80 76 74 84 62 86 Z" }

        // Neck and head: pivot at the neck's base.
        Item {
            width: 100; height: 100
            transform: [
                Rotation { origin.x: 64; origin.y: 60; angle: root.p.hr },
                Translate { x: root.p.hx; y: root.p.hy }
            ]
            PetShape { fill: root.c.head; d: "M 57 62 C 59 50 61 42 64 34 L 77 35 C 75 44 73 53 71 62 Z" }
            // A mallard's white collar.
            PetShape {
                visible: !!root.c.ring
                stroke: root.c.ring || "transparent"; strokeW: 2.2
                d: "M 59.5 53 C 63 54.5 68 54.5 72.5 53"
            }
            Rectangle { x: 59; y: 17; width: 26; height: 26; radius: 13; color: root.c.head }
            // Bill: the lower half opens with the call.
            PetShape {
                fill: Qt.darker(root.c.bill, 1.1)
                d: "M 81 32 C 87 33 92 33 94 34 C 91 37.5 85 38 81 36.5 Z"
                transform: Rotation { origin.x: 81; origin.y: 33; angle: root.p.mouth * 20 }
            }
            PetShape { fill: root.c.bill; d: "M 80 26.5 C 87 26 95 28.5 95 32 C 95 34 90 34.5 81 33.5 Z" }
            // Eye, or a happy ^ when petted.
            Item {
                x: 73.4; y: 25.4; width: 4; height: 4
                visible: root.p.eye >= 0
                Rectangle {
                    anchors.centerIn: parent
                    width: 3.8; height: 3.8 * Math.max(0.12, Math.min(1, root.p.eye)); radius: width / 2
                    color: Qt.rgba(0.07, 0.07, 0.08, 1)
                    Rectangle { visible: root.p.eye > 0.5; x: 2.2; y: 0.6; width: 1.1; height: 1.1; radius: 0.55; color: "white" }
                }
            }
            PetShape {
                visible: root.p.eye < 0
                stroke: Qt.rgba(0.07, 0.07, 0.08, 1); strokeW: 1.2
                d: "M 73.3 28.6 Q 75.4 25 77.5 28.6"
            }
        }

        // Wing on top: lifts for a stretch, flaps while falling, tucks for preening.
        Item {
            width: 100; height: 100
            transform: Rotation { origin.x: 38; origin.y: 63; angle: root.p.wing }
            PetShape { fill: root.c.wing; d: "M 33 63 C 40 54 58 55 66 64 C 62 74 47 77 37 73 C 31 70 30 66 33 63 Z" }
            PetShape { visible: !!root.c.patch; fill: root.c.patch || "transparent"; d: "M 50 66 C 54 64 59 65 61 67 C 58 70 53 70 50 68.5 Z" }
            PetShape { stroke: Qt.darker(root.c.wing, 1.12); strokeW: 0.9; d: "M 38 68 C 44 69 50 68.5 56 67" }
        }
    }
}
