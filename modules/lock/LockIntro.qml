import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.widgets

/**
 * The intro played over a screen's lock as the session locks (lock.intro), at most 0.9 s, then gone:
 *   waves   — coloured waves sweep down over a still of the desktop and open onto the lock (diagonally from
 *             `from`, a corner, when the corner revolver's bullet locked);
 *   padlock — a padlock spins and grows over the still while the lock shows through;
 *   portal  — a spinning ring grows from the centre, the lock inside it.
 * `still` is the screen as it was just before locking (LockScreen captures it); without one the wallpaper
 * stands in. Takes no input: the lock's field keeps the keys.
 */
Item {
    id: root
    property string kind: "none"
    property url still: ""
    property url fallback: ""
    property string from: ""
    property real p: 0
    property bool done: false
    readonly property bool playing: ["waves", "padlock", "portal"].includes(root.kind) && !root.done
    visible: root.playing

    Image {
        id: stillImg
        anchors.fill: parent
        source: root.playing ? (root.still.toString() !== "" ? root.still : root.fallback) : ""
        fillMode: Image.PreserveAspectCrop
        visible: root.kind === "padlock"
        opacity: root.kind === "padlock" ? 1 - Math.max(0, Math.min(1, (root.p - 0.3) / 0.5)) : 1
        cache: false
    }

    ShaderEffect {
        anchors.fill: parent
        visible: root.kind === "waves" || root.kind === "portal"
        readonly property var corner: root.from
        property var still: stillImg
        property real progress: root.p
        property real mode: root.kind === "portal" ? 1 : 0
        property real widthPx: width
        property real heightPx: height
        property point origin: !corner ? Qt.point(width / 2, 0)
            : Qt.point(corner.endsWith("Left") ? 0 : width, corner.startsWith("top") ? 0 : height)
        property point dir: {
            if (!corner) return Qt.point(0, 1)
            const dx = (corner.endsWith("Left") ? 1 : -1) * width, dy = (corner.startsWith("top") ? 1 : -1) * height
            const l = Math.hypot(dx, dy) || 1
            return Qt.point(dx / l, dy / l)
        }
        property real hasStill: stillImg.status === Image.Ready ? 1 : 0
        property color c1: Appearance.m3colors.m3primary
        property color c2: Appearance.m3colors.m3secondary
        property color c3: Appearance.m3colors.m3tertiary
        fragmentShader: Qt.resolvedUrl(Quickshell.shellPath("shaders/qsb/lock_intro.frag.qsb"))
    }

    // Padlock: spins a full turn and grows past the screen, fading out in its second half.
    Rectangle {
        visible: root.kind === "padlock"
        anchors.centerIn: parent
        width: 120; height: 120; radius: 60
        color: Appearance.colors.colPrimaryContainer
        scale: 0.4 + root.p * root.p * 9
        rotation: root.p * 360
        opacity: 1 - Math.max(0, (root.p - 0.45) / 0.55)
        MaterialSymbol {
            anchors.centerIn: parent
            text: "lock"
            fill: 1
            iconSize: 64
            color: Appearance.colors.colOnPrimaryContainer
        }
    }

    // The clock starts with the first frame the lock surface actually shows.
    property bool started: false
    Connections {
        target: root.Window.window
        enabled: !root.started && root.kind !== "none"
        function onFrameSwapped() { root.started = true }
    }
    NumberAnimation on p {
        running: root.started && ["waves", "padlock", "portal"].includes(root.kind)
        from: 0; to: 1
        duration: Math.min(1000, AnimationConfig.scaledDuration(900)) // at most 1 s
        easing.type: Easing.Linear // the waves, ring and padlock ease themselves
        onFinished: root.done = true
    }
}
