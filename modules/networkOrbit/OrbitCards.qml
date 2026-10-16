import QtQuick
import qs.modules.common
import qs.modules.common.widgets

/**
 * The cards orbiting the cores: networks / devices to connect to, or the
 * connection's details. With several Bluetooth cores each card follows its
 * own core on an arc. Actionable cards are press-and-hold: a fill sweeps
 * across, and the action runs when it is full.
 */
Item {
    id: cardsLayer
    required property var view
    required property Item orbitContainer
    required property var coreRepeater
    property alias repeater: orbitRepeater
    anchors.fill: parent
    opacity: view.currentPower ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { enabled: cardsLayer.view.shown; MotionNumber { curve: "standard"; baseDuration: 600 } }

    // A card's icon + label.
    component CardRow: Item {
        id: row
        property string icon: ""
        property string label: ""
        property color tint
        Row {
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 10; rightMargin: 10 }
            spacing: 6
            MaterialSymbol {
                id: glyph
                anchors.verticalCenter: parent.verticalCenter
                visible: text !== ""
                text: row.icon
                iconSize: 18
                color: row.tint
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                width: row.width - 20 - (glyph.visible ? glyph.implicitWidth + 6 : 0)
                text: row.label
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Bold
                color: row.tint
            }
        }
    }

    Repeater {
        id: orbitRepeater
        model: cardsLayer.view.orbitModel

        delegate: Item {
            id: card
            required property int index
            required property var model
            readonly property var view: cardsLayer.view
            readonly property Item orbitContainer: cardsLayer.orbitContainer

            width: 150; height: 52

            property bool isCardHovered: false
            property bool isLoaded: false
            opacity: isLoaded && view.currentPower ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { enabled: card.view.shown; MotionNumber { curve: "emphasizedDecel"; baseDuration: 400 } }

            property real entryAnim: isLoaded ? 1 : 0
            Behavior on entryAnim { enabled: card.view.shown; MotionSpring { token: "liquid"; epsilon: AnimationConfig.transitions ? 0.002 : 1000 } }

            Connections {
                target: card.view
                function onShownChanged() { if (!card.view.shown) card.isLoaded = false }
                function onCurrentPowerChanged() { if (!card.view.currentPower) card.isLoaded = false }
            }
            // Staggered entrance (Ethernet waits for its core to land).
            Timer {
                running: card.view.shown && card.view.currentPower && !card.isLoaded
                interval: card.view.activeMode === "eth" ? 400 + card.index * 60 : 40 + card.index * 30
                onTriggered: card.isLoaded = true
            }

            readonly property int myParentIdx: model.parentIndex ?? -1
            readonly property bool isInfo: model.isInfoNode ?? false
            readonly property var _siblings: {
                const m = view.orbitModel
                let count = 0, local = 0
                for (let i = 0; i < m.count; i++) {
                    if ((m.get(i).parentIndex ?? -1) !== myParentIdx) continue
                    if (i < index) local++
                    count++
                }
                return { count: Math.max(1, count), local: local }
            }
            readonly property real unifiedRatio: view.activeMode === "bt" ? view.multiTransitionState : 0
            readonly property real activeCount: (unifiedRatio > 0.5 && myParentIdx !== -1) ? _siblings.count : view.orbitModel.count
            readonly property real dynamicScale: activeCount > 10 ? Math.max(0.6, 12 / activeCount) : (unifiedRatio > 0.5 ? (view.activeCoreCount > 2 ? 0.7 : 0.8) : 1)

            readonly property var pItem: (myParentIdx >= 0 && myParentIdx < cardsLayer.coreRepeater.count) ? cardsLayer.coreRepeater.itemAt(myParentIdx) : null
            readonly property real parentBaseAngle: pItem ? pItem.animatedBaseAngle : 0
            readonly property real parentCoreAngle: view.globalOrbitAngle * 1.5 + parentBaseAngle
            readonly property real safeParentX: pItem ? orbitContainer.width / 2 + Math.cos(parentCoreAngle) * pItem.myOrbitRadiusX * unifiedRatio * pItem.activeTransition : orbitContainer.width / 2
            readonly property real safeParentY: pItem ? orbitContainer.height / 2 + Math.sin(parentCoreAngle) * pItem.myOrbitRadiusY * unifiedRatio * pItem.activeTransition : orbitContainer.height / 2

            property real singleBaseAngle: (index / Math.max(1, view.orbitModel.count)) * Math.PI * 2
            Behavior on singleBaseAngle { enabled: card.view.shown; MotionSpring { token: "liquid"; epsilon: AnimationConfig.transitions ? 0.002 : 1000 } }
            readonly property real singleLiveAngle: view.globalOrbitAngle * 1.5 + singleBaseAngle

            property real nodeOffset: _siblings.count > 1 ? (_siblings.local / (_siblings.count - 1) - 0.5) * Math.PI * 0.8 : 0
            Behavior on nodeOffset { enabled: card.view.shown; MotionSpring { token: "liquid"; epsilon: AnimationConfig.transitions ? 0.002 : 1000 } }
            readonly property real multiLiveAngle: myParentIdx === -1 ? singleLiveAngle : parentCoreAngle + nodeOffset

            // Two staggered rings for list cards, one for info cards.
            property real ringOffset: isInfo ? 0 : (index % 2) * 32
            Behavior on ringOffset { enabled: card.view.shown; MotionSpring { token: "liquid" } }

            readonly property real singleRadX: isInfo ? 253 : 260 + ringOffset
            readonly property real singleRadY: isInfo ? 154 : 160 + ringOffset
            readonly property real multiRadX: isInfo ? (myParentIdx === -1 ? 0 : (view.activeCoreCount > 2 ? 165 : 149)) : 270 + ringOffset
            readonly property real multiRadY: isInfo ? (myParentIdx === -1 ? 0 : (view.activeCoreCount > 2 ? 165 : 149)) : 190 + ringOffset
            readonly property real currentRadX: singleRadX * (1 - unifiedRatio) + multiRadX * unifiedRatio
            readonly property real currentRadY: singleRadY * (1 - unifiedRatio) + multiRadY * unifiedRatio
            readonly property real currentAngle: singleLiveAngle * (1 - unifiedRatio) + multiLiveAngle * unifiedRatio

            readonly property real animRadX: currentRadX * entryAnim
            readonly property real animRadY: currentRadY * entryAnim
            readonly property real cx: myParentIdx === -1 ? orbitContainer.width / 2 : safeParentX
            readonly property real cy: myParentIdx === -1 ? orbitContainer.height / 2 : safeParentY
            // Free-floating info cards bob gently.
            readonly property real liveBob: myParentIdx === -1 && isInfo ? Math.sin(view.globalOrbitAngle * 6) * 10 * (1 - unifiedRatio) : 0

            x: cx - width / 2 + Math.cos(currentAngle) * animRadX
            y: cy - height / 2 + Math.sin(currentAngle) * animRadY + liveBob

            readonly property string itemId: model.id ?? ""
            readonly property bool actionable: model.isActionable ?? false
            readonly property string target: model.arg ?? ""   // SSID / MAC / IP / URL
            readonly property bool isFailed: view.failedId !== "" && view.failedId === target
            readonly property bool isBusy: target !== "" && view.isBusy(target)
            readonly property bool isHighlighted: model.highlight ?? false
            readonly property bool hot: (cardMa.containsMouse || isHighlighted) && !triggered
            readonly property color tint: isFailed ? Appearance.colors.colError : (isHighlighted ? view.activeColor : Appearance.m3colors.m3onSurface)

            property real fillLevel: 0
            property bool triggered: false
            property real popScale: 1
            scale: (isLoaded ? (hot ? dynamicScale * 1.025 : dynamicScale) : 0) * popScale
            Behavior on scale { enabled: card.view.shown; MotionSpring { token: "snappy"; epsilon: AnimationConfig.transitions ? 0.002 : 1000 } }
            z: isCardHovered ? 10 : index

            HoverHandler {
                onHoveredChanged: {
                    if (card.isCardHovered === hovered) return
                    card.isCardHovered = hovered
                    card.view.hoveredCardCount = Math.max(0, card.view.hoveredCardCount + (hovered ? 1 : -1))
                }
            }
            Component.onDestruction: if (card.isCardHovered) card.view.hoveredCardCount = Math.max(0, card.view.hoveredCardCount - 1)

            Rectangle {
                id: face
                anchors.fill: parent
                radius: Appearance.rounding.normal
                color: cardMa.containsMouse ? Appearance.m3colors.m3surfaceContainerHigh : Appearance.m3colors.m3surfaceContainer
                border.width: 1
                border.color: card.isFailed ? Appearance.colors.colError
                    : (card.hot ? Qt.rgba(card.view.activeColor.r, card.view.activeColor.g, card.view.activeColor.b, 0.6) : Appearance.colors.colOutlineVariant)
                clip: true
                Behavior on color { enabled: card.view.shown; ColorAnimation { duration: AnimationConfig.scaledDuration(150) } }
                Behavior on border.color { enabled: card.view.shown; ColorAnimation { duration: AnimationConfig.scaledDuration(150) } }

                // Busy shimmer while a connect is in flight.
                Rectangle {
                    anchors { top: parent.top; bottom: parent.bottom }
                    width: parent.width * 0.35
                    visible: card.isBusy
                    opacity: 0.25
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: "transparent" }
                        GradientStop { position: 0.5; color: card.view.activeColor }
                        GradientStop { position: 1; color: "transparent" }
                    }
                    NumberAnimation on x {
                        running: card.isBusy && card.view.live && AnimationConfig.continuous
                        from: -face.width * 0.35; to: face.width; loops: Animation.Infinite
                        duration: AnimationConfig.scaledDuration(1100); easing.type: Easing.Linear
                    }
                }

                CardRow { anchors.fill: parent; icon: card.model.icon ?? ""; label: card.model.name ?? ""; tint: card.tint }

                // The hold fill, with the label redrawn on top in the accent's
                // "on" colour.
                Item {
                    id: fillClip
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                    width: parent.width * card.fillLevel
                    clip: true
                    visible: width > 0
                    Rectangle {
                        width: face.width; height: face.height
                        radius: face.radius
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: Qt.lighter(card.view.activeColor, 1.15) }
                            GradientStop { position: 1; color: card.view.activeColor }
                        }
                    }
                    CardRow { width: face.width; height: face.height; icon: card.model.icon ?? ""; label: card.model.name ?? ""; tint: card.view.onActiveColor }
                }

                Rectangle {
                    id: flash
                    anchors.fill: parent
                    radius: parent.radius
                    color: Appearance.m3colors.m3onBackground
                    opacity: 0
                }
            }

            MouseArea {
                id: cardMa
                anchors.fill: parent
                hoverEnabled: true
                enabled: card.actionable && !card.isBusy && !card.triggered
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onPressed: { drainAnim.stop(); fillAnim.start() }
                onReleased: if (!card.triggered) { fillAnim.stop(); drainAnim.start() }
                onCanceled: if (!card.triggered) { fillAnim.stop(); drainAnim.start() }
            }

            NumberAnimation {
                id: fillAnim
                target: card; property: "fillLevel"; to: 1
                duration: AnimationConfig.scaledDuration(600 * (1 - card.fillLevel))
                easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
                onFinished: {
                    card.triggered = true
                    popAnim.restart()
                    flashAnim.restart()
                    // Copy the node: a toggle can rebuild the model under us.
                    card.view.trigger({ id: card.itemId, cmd: card.model.cmd ?? "", arg: card.target })
                    resetTimer.restart()
                }
            }
            NumberAnimation {
                id: drainAnim
                target: card; property: "fillLevel"; to: 0
                duration: AnimationConfig.scaledDuration(1125 * card.fillLevel)
                easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.standardDecel
            }
            Timer { id: resetTimer; interval: 1200; onTriggered: { card.triggered = false; drainAnim.start() } }
            SequentialAnimation {
                id: popAnim
                NumberAnimation { target: card; property: "popScale"; to: 0.95; duration: AnimationConfig.scaledDuration(110); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.standardDecel }
                NumberAnimation { target: card; property: "popScale"; to: 1; duration: AnimationConfig.scaledDuration(400); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel }
            }
            NumberAnimation { id: flashAnim; target: flash; property: "opacity"; from: 0.4; to: 0; duration: AnimationConfig.scaledDuration(400); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel }
        }
    }
}
