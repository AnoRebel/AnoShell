import QtQuick
import qs.modules.common

/**
 * A NumberAnimation bound to a curve token from Appearance.animationCurves
 * (e.g. "expressiveDefaultSpatial", "emphasizedDecel") and a base duration,
 * scaled by the global speed; 0 ms when animations are disabled.
 * Usage:  Behavior on opacity { MotionNumber { curve: "expressiveEffects"; baseDuration: 200 } }
 */
NumberAnimation {
    id: root
    property string curve: "expressiveDefaultSpatial"
    property int baseDuration: Appearance.animationCurves.expressiveDefaultSpatialDuration

    duration: AnimationConfig.scaledDuration(root.baseDuration)
    easing.type: Easing.BezierSpline
    easing.bezierCurve: Appearance.animationCurves[root.curve] ?? Appearance.animationCurves.expressiveDefaultSpatial
}
