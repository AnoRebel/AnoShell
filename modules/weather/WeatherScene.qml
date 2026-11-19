pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.services
import "scene.js" as S

/**
 * An animated picture of the current weather and time of day: a sky that follows the real sunrise and sunset, the sun
 * or the moon (in its real phase) on an arc, stars at night, clouds, hills and grass, and rain, snow, mist or a storm
 * with lightning, all drifting with the wind. A change of weather eases over ~2.5 s (clouds gather before rain;
 * rain stops before it clears). Inspired by Anserin's weather scene.
 *
 * Looks (bar.weather.scene.look): flat, pixel (low resolution, unsmoothed) or soft (blurred, muted); strength scales
 * the effects. Animates only while `live`, visible and continuous motion is allowed; otherwise a still frame.
 * Every input can be set from outside (a test harness steps time and weather through them).
 */
Item {
    id: root
    property bool live: visible
    ServiceLease { service: Weather; name: "weatherScene"; active: root.live }
    property real radius: 0
    property var code: Weather.data.wCode
    property real sunrise: Weather.data.sunriseMin ?? NaN
    property real sunset: Weather.data.sunsetMin ?? NaN
    property real windKmph: Weather.data.windKmph ?? 0
    property date date: new Date()
    property real minutes: root.date.getHours() * 60 + root.date.getMinutes()
    property string look: Config.options?.bar?.weather?.scene?.look ?? "flat"
    property real strength: Math.max(0.2, Math.min(1, Config.options?.bar?.weather?.scene?.strength ?? 1))
    property bool clock: true // follow the real time (a harness turns this off and sets `minutes`)

    readonly property string condition: S.condition(root.code)
    readonly property var target: S.look(root.condition)
    property var cur: S.look(root.condition)
    readonly property var sun: S.sun(root.minutes, root.sunrise, root.sunset)
    readonly property real night: root.sun.up ? 0 : 1 - root.sun.dawn * 0.6
    readonly property var skyCols: S.sky(root.sun)
    readonly property real phase: S.moonPhase(root.date)
    readonly property real wind: Math.max(0, Math.min(80, root.windKmph))
    readonly property bool moving: root.live && root.visible && AnimationConfig.continuous

    // Still frames jump straight to the weather. _settled: cur has reached target (no per-frame comparison after).
    property bool _settled: true
    onTargetChanged: { if (!root.moving) root.cur = root.target; else root._settled = S.same(root.cur, root.target) }
    onMovingChanged: if (!root.moving) { root.cur = root.target; root._settled = true }

    property real t: 0
    property real flashAt: -10
    property real nextFlash: 2
    FrameAnimation {
        running: root.moving
        onTriggered: {
            root.t += frameTime
            if (!root._settled) { root.cur = S.step(root.cur, root.target, frameTime); root._settled = S.same(root.cur, root.target) }
            if (root.cur.storm > 0.5 && root.t >= root.nextFlash) {
                root.flashAt = root.t
                root.nextFlash = root.t + 3 + Math.random() * 4
                bolt.seed = Math.random()
            }
        }
    }
    Timer {
        running: root.clock && root.live && root.visible
        interval: 30000; repeat: true; triggeredOnStart: true
        onTriggered: root.date = new Date()
    }
    readonly property real flash: Math.max(0, 1 - (root.t - root.flashAt) / 0.35) * root.cur.storm

    function mix(a, b, k) { return Qt.rgba(a.r + (b.r - a.r) * k, a.g + (b.g - a.g) * k, a.b + (b.b - a.b) * k, 1) }
    readonly property color grey: root.night > 0.5 ? "#1a1d24" : "#7d8590" // look-coverage: fixed (the scene's natural colours)

    layer.enabled: root.radius > 0
    layer.effect: OpacityMask { maskSource: Rectangle { width: root.width; height: root.height; radius: root.radius } }

    Item {
        id: content
        anchors.fill: parent
        layer.enabled: root.look === "pixel" || root.look === "soft"
        layer.smooth: root.look !== "pixel"
        layer.textureSize: root.look === "pixel" ? Qt.size(Math.max(1, root.width / 4), Math.max(1, root.height / 4)) : Qt.size(0, 0)
        layer.effect: root.look === "soft" ? softFx : null
        Component { id: softFx; MultiEffect { blurEnabled: true; blur: 0.35; blurMax: 24; saturation: -0.3 } }

        // Sky
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0; color: root.mix(Qt.color(root.skyCols[0]), root.grey, root.cur.dark * 0.8) }
                GradientStop { position: 1; color: root.mix(Qt.color(root.skyCols[1]), root.grey, root.cur.dark * 0.7) }
            }
        }

        // Stars
        Repeater {
            model: 36
            Rectangle {
                required property int index
                readonly property real sx: (index * 0.6180339 % 1)
                readonly property real sy: (index * 0.3819660 * 3.7 % 1) * 0.6
                x: sx * root.width; y: sy * root.height
                width: index % 5 === 0 ? 2.5 : 1.5; height: width; radius: width / 2
                color: "white"
                opacity: root.night * (1 - root.cur.clouds) * (0.55 + 0.45 * Math.sin(root.t * (1 + index % 3) + index))
            }
        }

        // Sun or moon on its arc
        Item {
            id: orb
            readonly property real d: Math.min(root.height * 0.28, 44)
            x: root.width * (0.08 + 0.84 * root.sun.t) - d / 2
            y: root.height * 0.72 - Math.sin(Math.PI * root.sun.t) * root.height * 0.55 - d / 2
            width: d; height: d
            // Overcast: only a glow.
            readonly property real disc: Math.max(0, 1 - Math.max(0, root.cur.clouds - 0.6) * 2.5)
            Rectangle {
                anchors.centerIn: parent
                width: parent.width * 2.4; height: width; radius: width / 2
                color: root.sun.up ? "#ffe9a8" : "#dfe6ff" // look-coverage: fixed (the scene's natural colours)
                opacity: (root.sun.up ? 0.35 : 0.15) * (0.5 + root.cur.clouds * 0.5)
            }
            Rectangle {
                visible: root.sun.up
                anchors.fill: parent; radius: width / 2
                color: root.sun.dawn > 0.3 ? "#ffb347" : "#ffd75e" // look-coverage: fixed (the scene's natural colours)
                opacity: orb.disc
            }
            // The moon: a dim disc and its lit part.
            Rectangle {
                visible: !root.sun.up
                anchors.fill: parent; radius: width / 2
                color: "#3a4060"; opacity: 0.5 * orb.disc // look-coverage: fixed (the scene's natural colours)
            }
            Shape {
                id: moon
                visible: !root.sun.up
                anchors.fill: parent
                opacity: orb.disc
                preferredRendererType: Shape.CurveRenderer
                readonly property real r: orb.d / 2
                readonly property bool waxing: root.phase < 0.5
                readonly property real tx: Math.cos(2 * Math.PI * root.phase) * r
                ShapePath {
                    strokeWidth: 0; strokeColor: "transparent"; fillColor: "#f1f3ff" // look-coverage: fixed (the scene's natural colours)
                    startX: orb.d / 2; startY: 0
                    PathArc {
                        x: orb.d / 2; y: orb.d
                        radiusX: orb.d / 2; radiusY: orb.d / 2
                        direction: moon.waxing ? PathArc.Clockwise : PathArc.Counterclockwise
                    }
                    PathArc {
                        x: orb.d / 2; y: 0
                        radiusX: Math.max(0.01, Math.abs(moon.tx)); radiusY: orb.d / 2
                        // Back up the terminator: a crescent bulges to the lit side, a gibbous moon away from it.
                        direction: (moon.waxing === (moon.tx > 0)) ? PathArc.Counterclockwise : PathArc.Clockwise
                    }
                }
            }
        }

        // Clouds
        Repeater {
            model: 7
            Item {
                id: cloud
                required property int index
                readonly property real w: root.width * (0.28 + (index % 3) * 0.08)
                readonly property real show: Math.max(0, Math.min(1, root.cur.clouds * 7 - index))
                readonly property real speed: (3 + index % 3) * (1 + root.wind * 0.08)
                width: w; height: w * 0.42
                x: ((index * 0.37 % 1) * (root.width + w) + root.t * speed) % (root.width + w) - w
                y: root.height * (0.04 + (index % 4) * 0.08) * (1 - root.cur.clouds * 0.3)
                opacity: cloud.show * (root.night > 0.5 ? 0.75 : 0.92)
                readonly property color tone: root.mix(root.night > 0.5 ? Qt.color("#5b6278") : Qt.color("#ffffff"), Qt.color("#4a4f5a"), root.cur.dark) // look-coverage: fixed (the scene's natural colours)
                Rectangle { x: 0; y: parent.height * 0.4; width: parent.width; height: parent.height * 0.6; radius: height / 2; color: cloud.tone }
                Rectangle { x: parent.width * 0.15; y: parent.height * 0.12; width: parent.width * 0.42; height: width * 0.8; radius: height / 2; color: cloud.tone }
                Rectangle { x: parent.width * 0.42; y: 0; width: parent.width * 0.45; height: width * 0.85; radius: height / 2; color: cloud.tone }
            }
        }

        // Lightning bolt
        Shape {
            id: bolt
            property real seed: 0.5
            anchors.fill: parent
            visible: root.flash > 0.05
            opacity: root.flash
            ShapePath {
                strokeColor: "#fffbe0"; strokeWidth: 2.5; fillColor: "transparent"; joinStyle: ShapePath.MiterJoin // look-coverage: fixed (the scene's natural colours)
                PathPolyline {
                    path: {
                        const pts = [], x0 = root.width * (0.2 + bolt.seed * 0.6)
                        for (let i = 0; i <= 6; i++)
                            pts.push(Qt.point(x0 + Math.sin(i * 7.3 + bolt.seed * 20) * 12 + i * 3, root.height * (0.18 + i * 0.09)))
                        return pts
                    }
                }
            }
        }

        // Hills, with snow lying on them
        Shape {
            id: hills
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            readonly property color far: root.mix(Qt.color("#5f8f5a"), Qt.color("#16231c"), root.night * 0.85) // look-coverage: fixed (the scene's natural colours)
            readonly property color near: root.mix(Qt.color("#47774a"), Qt.color("#101a14"), root.night * 0.85) // look-coverage: fixed (the scene's natural colours)
            ShapePath {
                strokeWidth: 0; strokeColor: "transparent"
                fillColor: root.mix(hills.far, Qt.color("#e8eef5"), root.cur.snow * 0.8 * root.strength) // look-coverage: fixed (the scene's natural colours)
                startX: 0; startY: root.height * 0.74
                PathQuad { x: root.width * 0.55; y: root.height * 0.7; controlX: root.width * 0.25; controlY: root.height * 0.52 }
                PathQuad { x: root.width; y: root.height * 0.68; controlX: root.width * 0.8; controlY: root.height * 0.58 }
                PathLine { x: root.width; y: root.height }
                PathLine { x: 0; y: root.height }
            }
            ShapePath {
                strokeWidth: 0; strokeColor: "transparent"
                fillColor: root.mix(hills.near, Qt.color("#f4f7fb"), root.cur.snow * 0.85 * root.strength) // look-coverage: fixed (the scene's natural colours)
                startX: 0; startY: root.height * 0.86
                PathQuad { x: root.width; y: root.height * 0.82; controlX: root.width * 0.6; controlY: root.height * 0.66 }
                PathLine { x: root.width; y: root.height }
                PathLine { x: 0; y: root.height }
            }
        }

        // Grass, leaning and swaying with the wind
        Repeater {
            model: 28
            Rectangle {
                required property int index
                width: 2; height: root.height * (0.06 + (index % 3) * 0.02); radius: 1
                x: (index + 0.5) / 28 * root.width
                y: root.height - height - 2
                transformOrigin: Item.Bottom
                rotation: Math.min(30, root.wind * 0.5) + Math.sin(root.t * (1.5 + root.wind * 0.05) + index * 0.7) * (3 + root.wind * 0.1)
                color: root.mix(Qt.color("#6fa86a"), Qt.color("#1a2a1e"), root.night * 0.85) // look-coverage: fixed (the scene's natural colours)
                opacity: 1 - root.cur.snow * 0.6
            }
        }

        // Mist
        Repeater {
            model: 3
            Rectangle {
                required property int index
                width: root.width * 1.6; height: root.height * 0.16
                x: -root.width * 0.3 + Math.sin(root.t * 0.1 + index * 2) * root.width * 0.15
                y: root.height * (0.48 + index * 0.13)
                radius: height / 2
                color: root.night > 0.5 ? "#8a93a8" : "#eef1f5" // look-coverage: fixed (the scene's natural colours)
                opacity: root.cur.mist * 0.45 * root.strength
            }
        }

        // Rain
        Repeater {
            model: 70
            Rectangle {
                required property int index
                readonly property real lean: Math.min(35, 6 + root.wind * 0.6)
                readonly property real fall: root.height * 1.8
                readonly property real py: ((index * 0.7548777 % 1) * (root.height + 20) + root.t * fall) % (root.height + 20) - 20
                visible: opacity > 0
                opacity: Math.max(0, Math.min(1, root.cur.rain * root.strength * 70 - index)) * 0.7
                width: 1.5; height: 11; radius: 1
                color: "#cfe3ff" // look-coverage: fixed (the scene's natural colours)
                rotation: lean
                x: ((index * 0.5698403 % 1) * (root.width + 60) - py * Math.tan(lean * Math.PI / 180)) % (root.width + 60)
                y: py
            }
        }

        // Snow
        Repeater {
            model: 50
            Rectangle {
                required property int index
                readonly property real py: ((index * 0.4142135 % 1) * (root.height + 10) + root.t * root.height * (0.18 + index % 4 * 0.04)) % (root.height + 10) - 10
                visible: opacity > 0
                opacity: Math.max(0, Math.min(1, root.cur.snow * root.strength * 50 - index)) * 0.9
                width: 2 + index % 3; height: width; radius: width / 2
                color: "white"
                x: ((index * 0.6823278 % 1) * root.width + Math.sin(root.t + index) * 6 + root.t * root.wind * 0.4) % root.width
                y: py
            }
        }

        // The flash
        Rectangle {
            anchors.fill: parent
            color: "white"
            opacity: root.flash * 0.45 * root.strength
            visible: opacity > 0.01
        }
    }
}
