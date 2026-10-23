import QtQuick
import qs.modules.common as Ano

// Drop-in for FrameAnimation in the ported organisms: the same running,
// frameTime and triggered, at widgets.fps (10 by default) instead of every
// frame. The widget layer is a full-screen surface, so each tick redraws it;
// at the display's rate a few moving organisms cost ~20% of a core.
Timer {
    readonly property int fps: Math.max(1, Math.min(60, Ano.Config.options?.widgets?.fps ?? 10))
    readonly property real frameTime: interval / 1000
    interval: Math.round(1000 / fps)
    repeat: true
}
