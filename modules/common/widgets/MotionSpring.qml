import QtQuick
import qs.modules.common

/**
 * A SpringAnimation bound to a spring token (Appearance.springs.<token>).
 * Usage:  Behavior on width { MotionSpring { token: "liquid" } }
 * Retargets from its current velocity when the target changes mid-flight.
 * With animations disabled it jumps straight to the target.
 */
SpringAnimation {
    id: root
    property string token: "liquid"
    readonly property QtObject _t: Appearance.springs[root.token] ?? Appearance.springs.liquid

    spring: AnimationConfig.transitions ? root._t.spring : 1000
    damping: AnimationConfig.transitions ? root._t.damping : 1
    mass: root._t.mass
    epsilon: AnimationConfig.transitions ? root._t.epsilon : 1000
}
