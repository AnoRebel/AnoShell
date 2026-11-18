import QtQuick

// The dog, side view facing right with its face turned three-quarters to us, in a 100 × 100 space with its feet at the
// bottom middle. `p` is a pet.js pose, `c` a dog preset (tuxedo: white chest, muzzle and paws). Original art for AnoShell.
Item {
    id: root
    property var p
    property var c
    width: 100; height: 100
    readonly property color far: Qt.darker(root.c.base, 1.2)
    readonly property real tilt: -root.p.sit * 32
    readonly property color ink: Qt.rgba(0.08, 0.07, 0.07, 1)
    readonly property bool tux: root.c.pattern === "tux"

    component Leg: Item {
        id: leg
        property real px
        property int i
        property bool front
        property color col
        width: 100; height: 100
        readonly property real fold: leg.front ? root.p.lie : Math.max(root.p.lie, root.p.sit)
        transform: Rotation { origin.x: leg.px; origin.y: 72; angle: -root.p.legs[leg.i] - (leg.front ? root.tilt : 45 * root.p.sit) }
        Rectangle {
            id: bone
            x: leg.px - 4.2; y: 68; width: 8.4; radius: 4.2
            height: 30 * (1 - 0.55 * leg.fold)
            color: leg.col
            // Tuxedo: white paws.
            Rectangle { visible: root.tux; anchors.bottom: parent.bottom; width: parent.width; height: Math.min(parent.height, 7); radius: 4.2; color: root.c.mark || "transparent" }
        }
    }

    Item {
        width: 100; height: 100
        transform: [
            Rotation { origin.x: 66; origin.y: 74; angle: root.p.rot + root.tilt },
            Translate { x: root.p.bx; y: root.p.by + root.p.lie * 14 }
        ]

        // Tail: short and upright, wagging from its root.
        Item {
            x: 27; y: 58; width: 1; height: 1
            rotation: -root.p.tail * 0.9 + 8
            transformOrigin: Item.TopLeft
            PetShape {
                anchors.fill: undefined; width: 1; height: 1
                stroke: root.c.base; strokeW: 6
                d: "M 0 0 C -6 -3 -9 -10 -8 -19"
            }
        }

        Leg { px: 61; i: 1; front: true; col: root.far }
        Leg { px: 33; i: 3; front: false; col: root.far }
        PetShape {
            fill: root.c.base
            d: "M 25 62 C 25 51 34 47 46 47 L 63 47 C 75 47 80 54 80 62 C 80 72 74 77 64 77 L 39 77 C 30 77 25 71 25 62 Z"
        }
        PetShape { fill: root.c.belly; d: "M 40 76 C 48 69 64 68 73 74 C 68 77.5 46 77.5 40 76 Z" }
        // Tuxedo chest.
        PetShape { visible: root.tux; fill: root.c.mark || "transparent"; d: "M 68 50 C 76 52 80 58 79 66 C 77 72 72 75 66 75 C 70 67 70 57 68 50 Z" }
        Leg { px: 65; i: 0; front: true; col: root.c.base }
        Leg { px: 37; i: 2; front: false; col: root.c.base }

        // Head: pivot at the neck.
        Item {
            width: 100; height: 100
            transform: [
                Rotation { origin.x: 70; origin.y: 54; angle: root.p.hr - root.tilt * 0.8 },
                Translate { x: root.p.hx; y: root.p.hy }
            ]
            // Far ear, behind the head.
            Item {
                width: 100; height: 100
                transform: Rotation { origin.x: 90; origin.y: 29; angle: -root.p.ear - 6 }
                PetShape { fill: Qt.darker(root.c.ear, 1.15); d: "M 87 28 C 93 26 98 30 97 40 C 96 46 92 47 90 43 C 88 38 86 32 87 28 Z" }
            }
            Rectangle { x: 64; y: 25; width: 32; height: 30; radius: 15; color: root.c.base }
            // Snout.
            PetShape { fill: root.tux ? (root.c.mark || root.c.belly) : root.c.belly; d: "M 74 46 C 76 40 92 39 96 44 C 99 49 95 55 86 55 C 78 55 73 51 74 46 Z" }
            // Eyes: round and dark, closing to a line; ^ ^ when petted.
            Repeater {
                model: [76.5, 88]
                Item {
                    id: eye
                    required property var modelData
                    x: eye.modelData - 2.5; y: 34; width: 5; height: 5
                    visible: root.p.eye >= 0
                    Rectangle {
                        anchors.centerIn: parent
                        width: 5; height: 5 * Math.max(0.1, Math.min(1, root.p.eye)); radius: 2.5
                        color: root.ink
                        Rectangle { visible: root.p.eye > 0.5; x: 2.8; y: 0.8; width: 1.4; height: 1.4; radius: 0.7; color: "white" }
                    }
                }
            }
            PetShape {
                visible: root.p.eye < 0
                stroke: root.ink; strokeW: 1.4
                d: "M 74 38 Q 76.5 34 79 38 M 85.5 38 Q 88 34 90.5 38"
            }
            // Nose, mouth and tongue (out when happy or barking).
            PetShape { fill: root.c.nose; d: "M 86.5 42 C 89 41 93 41 94 43 C 93.5 45.5 90 46.5 88.5 46.2 C 86.5 45.5 85.8 43.5 86.5 42 Z" }
            PetShape { stroke: root.ink; strokeW: 0.9; d: "M 90 46.2 L 90 48.5 M 85 49 Q 87.5 51 90 48.5 Q 92.5 51 95 49" }
            Rectangle {
                visible: root.p.mouth > 0.3
                x: 87.5; y: 49.5; width: 5; height: 7 * root.p.mouth; radius: 2.5
                color: Qt.rgba(0.91, 0.45, 0.5, 1)
            }
            // Near ear: floppy, swinging with p.ear.
            Item {
                width: 100; height: 100
                transform: Rotation { origin.x: 69; origin.y: 28; angle: root.p.ear + 4 }
                PetShape { fill: root.c.ear; d: "M 66 26 C 72 24 75 29 74 38 C 73 46 69 49 65 46 C 62 42 62 30 66 26 Z" }
            }
        }
    }
}
