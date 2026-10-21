import QtQuick
import qs.modules.common

/**
 * The shell's motion for shapes and surfaces (name kept from when it was a
 * spring). Usage:  Behavior on width { MotionSpring { token: "liquid" } }
 *
 * A time-bounded bezier tween, not a spring: springs overshot, oscillated by
 * sub-pixel amounts and then snapped to the target at their epsilon, which
 * read as jank at the start and the end of every morph. The reference shells
 * (caelestia, DMS, tide-island, prism) all tween geometry on M3 curves.
 *
 *   liquid  growing / opening   450 ms, expressive spatial (a slight overshoot)
 *   settle  retracting / closing 300 ms, emphasized accelerate
 *   snappy  small elements       300 ms, expressive fast spatial
 *
 * Scaled by the animation speed; 0 (a jump) with animations off.
 */
NumberAnimation {
    id: root
    property string token: "liquid"
    property real epsilon: 0 // accepted from the spring days, unused
    readonly property var _c: Appearance.animationCurves
    duration: AnimationConfig.scaledDuration(root.token === "liquid" ? 450 : 300)
    easing.type: Easing.BezierSpline
    easing.bezierCurve: root.token === "settle" ? root._c.emphasizedAccel
        : root.token === "snappy" ? root._c.expressiveFastSpatial : root._c.expressiveDefaultSpatial
}
