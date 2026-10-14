pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs
import qs.modules.common
import qs.services

// AnimationConfig — the motion gate. Tokens (curves, durations, springs) live
// in Appearance.animation (looks will supply them); this decides whether and
// how motion may run right now.
//
//   transitions:  open/close/morph animations. Off only when animations are
//                 disabled (state then changes instantly).
//   continuous:   looping/ambient motion (spectrum, pulses, gradients, animated
//                 shaders). Also stops for reduced motion, a locked screen, and
//                 on battery when battery-saver motion is on. Bind each such
//                 animation's `running` to `AnimationConfig.continuous && <visible>`.
Singleton {
    id: root

    readonly property bool enabled: Config.options?.animations?.enable ?? true
    readonly property bool reducedMotion: Config.options?.animations?.reducedMotion ?? false
    readonly property bool batterySaver: Config.options?.animations?.batterySaver ?? false
    readonly property bool onBattery: Battery.available && !Battery.isPluggedIn

    readonly property bool transitions: root.enabled
    readonly property bool continuous: root.enabled && !root.reducedMotion
        && !GlobalStates.screenLocked && !(root.batterySaver && root.onBattery)

    // Global speed factor (1 = normal, >1 slower, <1 faster).
    readonly property real speed: Math.max(0.1, Config.options?.animations?.speed ?? 1.0)
    function scaledDuration(baseDuration) {
        return root.enabled ? Math.max(1, Math.round(baseDuration * root.speed)) : 0
    }
}
