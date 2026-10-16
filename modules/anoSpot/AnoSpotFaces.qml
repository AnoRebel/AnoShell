import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.widgets.spectrum
import qs.services
import qs.modules.bar.modules
import "."

/**
 * The pill's resting faces (status, media, spectrum, lyrics), switched by a
 * horizontal (trackpad) scroll or by dragging along the pill. (Shift-wheel
 * can't work here: Wayland only gives modifier state to the keyboard-focused
 * surface, which the pill never is.) `progress` is continuous (a face index
 * with a fraction); after the gesture stops it springs to the nearest face.
 * `preferredLength` blends the neighbouring faces' lengths by that fraction,
 * so the capsule morphs to fit as you swipe. Vertical wheel without shift is
 * left alone (volume on the media face).
 */
Item {
    id: root

    property bool vertical: false
    // Pill-bar style: the status face carries the bar's workspaces and tray.
    property bool barMode: false
    property real thickness: 36
    // Face ids in cycle order; the caller drops disabled/unavailable ones.
    property var faces: ["status"]
    property real progress: 0
    readonly property int count: faces.length
    readonly property int index: Math.max(0, Math.min(count - 1, Math.round(progress)))
    readonly property string currentFace: faces[index] ?? "status"

    // Natural length of each face, blended across the swipe.
    function _len(i) {
        const it = rep.itemAt(Math.max(0, Math.min(count - 1, i)))?.item
        if (!it) return thickness * 2
        return root.vertical ? it.implicitHeight : it.implicitWidth
    }
    readonly property real preferredLength: {
        void rep.count; void _lenRevision
        const lo = Math.floor(progress), f = progress - lo
        return _len(lo) * (1 - f) + _len(lo + 1) * f
    }
    property int _lenRevision: 0

    // Keep the index valid when faces come and go.
    onCountChanged: if (progress > count - 1) progress = Math.max(0, count - 1)

    // ── Gesture ──────────────────────────────────────────────────────────
    property real _start: 0
    property real _acc: 0
    property bool _swiping: false
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            const dx = event.pixelDelta.x !== 0 ? event.pixelDelta.x : event.angleDelta.x / 4
            const dy = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y / 4
            const shift = (event.modifiers & Qt.ShiftModifier) !== 0
            // Horizontal scroll (shift + vertical where the compositor gives us
            // modifiers). Plain vertical wheel passes through (volume).
            const d = Math.abs(dx) > Math.abs(dy) ? dx : (shift ? dy : 0)
            if (d === 0 || root.count < 2) { event.accepted = false; return }
            if (!root._swiping) { root._swiping = true; root._start = root.progress; root._acc = 0; settle.stop() }
            root._acc += d
            // ~240 px of travel per face; a little rubber band past the ends.
            const raw = root._start - root._acc / 240
            root.progress = raw < 0 ? raw * 0.25 : raw > root.count - 1 ? (root.count - 1) + (raw - root.count + 1) * 0.25 : raw
            idle.restart()
            event.accepted = true
        }
    }
    // Press and drag along the pill: the same swipe, by pointer.
    DragHandler {
        id: dragSwipe
        target: null
        enabled: root.count > 1
        xAxis.enabled: !root.vertical
        yAxis.enabled: root.vertical
        property real startProgress: 0
        onActiveChanged: {
            if (active) { settle.stop(); startProgress = root.progress }
            else root.settleTo(Math.round(root.progress))
        }
        onTranslationChanged: {
            if (!active) return
            const raw = startProgress - (root.vertical ? translation.y : translation.x) / 160
            root.progress = raw < 0 ? raw * 0.25 : raw > root.count - 1 ? (root.count - 1) + (raw - root.count + 1) * 0.25 : raw
        }
    }
    Timer {
        id: idle
        interval: 150
        onTriggered: { root._swiping = false; root.settleTo(Math.round(root.progress)) }
    }
    function settleTo(i) {
        settle.to = Math.max(0, Math.min(root.count - 1, i))
        settle.restart()
    }
    function showFace(id) { const i = root.faces.indexOf(id); if (i >= 0) settleTo(i) }
    MotionSpring { id: settle; target: root; property: "progress"; token: "settle" }

    // ── Faces ────────────────────────────────────────────────────────────
    Repeater {
        id: rep
        model: root.faces
        delegate: Loader {
            id: faceLoader
            required property string modelData
            required property int index
            // How far this face is from the one in view (0 = in view).
            readonly property real dist: index - root.progress
            readonly property bool near: Math.abs(dist) < 1
            anchors.centerIn: parent
            opacity: Math.max(0, 1 - Math.abs(dist) * 1.4)
            visible: opacity > 0.01
            // Slides along the capsule as it fades.
            transform: Translate {
                x: root.vertical ? 0 : faceLoader.dist * 36
                y: root.vertical ? faceLoader.dist * 36 : 0
            }
            sourceComponent: ({ status: statusFace, media: mediaFace, spectrum: spectrumFace, lyrics: lyricsFace })[modelData] ?? statusFace
            onLoaded: root._lenRevision++
            Connections {
                target: faceLoader.item
                ignoreUnknownSignals: true
                function onImplicitWidthChanged() { root._lenRevision++ }
                function onImplicitHeightChanged() { root._lenRevision++ }
            }
            // Spectrum and lyrics read this to stay idle while off-screen.
            property bool faceActive: near
        }
    }

    // Status: workspaces, recording, notification, clock and weather, battery
    // (and the media line, as before). Stacked on side edges.
    Component {
        id: statusFace
        Loader {
            sourceComponent: root.vertical ? statusV : statusH
        }
    }
    Component {
        id: statusH
        RowLayout {
            spacing: 10
            AnoSpotWorkspace  { visible: !root.barMode && (Config.options?.anoSpot?.showWorkspace ?? true) }
            WorkspacesModule  { visible: root.barMode }
            AnoSpotMpris      { Layout.minimumWidth: 60; visible: (Config.options?.anoSpot?.showMpris ?? true) && AnoSpotState.mpris !== null }
            AnoSpotRecording  { visible: (Config.options?.anoSpot?.showRecording ?? true) && AnoSpotState.recording.active }
            AnoSpotNotification { visible: (Config.options?.anoSpot?.showNotification ?? true) && AnoSpotState.latestNotification !== null }
            AnoSpotClockWeather { visible: Config.options?.anoSpot?.showClockWeather ?? true }
            AnoSpotBattery    { }
            TrayModule        { visible: root.barMode }
        }
    }
    Component {
        id: statusV
        ColumnLayout {
            spacing: 6
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                visible: Config.options?.anoSpot?.showWorkspace ?? true
                text: CompositorService.activeWorkspaceIndex
                font.pixelSize: Appearance.font.pixelSize.smaller; font.weight: Font.DemiBold
                color: Appearance.colors.colSecondary
            }
            // Stacked clock: hours over minutes.
            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter
                visible: Config.options?.anoSpot?.showClockWeather ?? true
                spacing: -2
                readonly property var _hm: (AnoSpotState.clockWeather.time ?? "").split(/[:.]/)
                StyledText { Layout.alignment: Qt.AlignHCenter; text: parent._hm[0] ?? ""; font.pixelSize: Appearance.font.pixelSize.small; font.weight: Font.Bold; font.family: Appearance.font.family.numbers }
                StyledText { Layout.alignment: Qt.AlignHCenter; text: (parent._hm[1] ?? "").slice(0, 2); font.pixelSize: Appearance.font.pixelSize.small; font.family: Appearance.font.family.numbers; opacity: 0.8 }
            }
            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                visible: AnoSpotState.mpris !== null && (Config.options?.anoSpot?.showMpris ?? true)
                text: AnoSpotState.mpris?.playing ? "music_note" : "pause"
                iconSize: 14; color: Appearance.colors.colPrimary
            }
            // Compact battery for the narrow capsule: icon over the number.
            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter
                visible: Battery.available && (Config.options?.anoSpot?.showBattery ?? true)
                spacing: 0
                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: Battery.isCharging ? "battery_charging_full" : "battery_full"
                    iconSize: 14
                    color: Battery.isLow && !Battery.isCharging ? Appearance.colors.colError : Appearance.colors.colOnLayer0
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Math.round(Battery.percentage * 100)
                    font.pixelSize: Appearance.font.pixelSize.smallest
                }
            }
        }
    }

    // Media: title and artist with transport.
    Component {
        id: mediaFace
        Loader { sourceComponent: root.vertical ? mediaV : mediaH }
    }
    Component {
        id: mediaH
        RowLayout {
            spacing: 8
            MaterialSymbol { text: "music_note"; iconSize: 16; color: Appearance.colors.colPrimary }
            StyledText {
                Layout.maximumWidth: 220
                elide: Text.ElideRight
                text: { const m = MprisController.activeTrack; return m ? (m.artist ? `${m.title} — ${m.artist}` : (m.title ?? "")) : "" }
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
            MediaButton { icon: "skip_previous"; onTap: MprisController.previous() }
            MediaButton { icon: MprisController.isPlaying ? "pause" : "play_arrow"; onTap: MprisController.togglePlaying() }
            MediaButton { icon: "skip_next"; onTap: MprisController.next() }
            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                acceptedModifiers: Qt.NoModifier
                onWheel: event => {
                    if (Math.abs(event.angleDelta.y) <= Math.abs(event.angleDelta.x) || (event.modifiers & Qt.ShiftModifier)) { event.accepted = false; return }
                    if (event.angleDelta.y > 0) Audio.incrementVolume(); else Audio.decrementVolume()
                }
            }
        }
    }
    Component {
        id: mediaV
        ColumnLayout {
            spacing: 4
            MediaButton { Layout.alignment: Qt.AlignHCenter; icon: "skip_previous"; onTap: MprisController.previous() }
            MediaButton { Layout.alignment: Qt.AlignHCenter; icon: MprisController.isPlaying ? "pause" : "play_arrow"; onTap: MprisController.togglePlaying() }
            MediaButton { Layout.alignment: Qt.AlignHCenter; icon: "skip_next"; onTap: MprisController.next() }
        }
    }
    component MediaButton: MaterialSymbol {
        id: mb
        property string icon
        signal tap()
        text: icon; iconSize: 18; fill: 1
        color: tapArea.containsMouse ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
        MouseArea { id: tapArea; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: mb.tap() }
    }

    // Spectrum: registered with cava only while this face is in view.
    Component {
        id: spectrumFace
        Item {
            id: spec
            readonly property bool live: parent?.faceActive ?? false
            implicitWidth: root.vertical ? root.thickness - 12 : 180
            implicitHeight: root.vertical ? 120 : root.thickness - 12
            onLiveChanged: live ? SpectrumService.registerComponent("anoSpotFace") : SpectrumService.unregisterComponent("anoSpotFace")
            Component.onCompleted: if (live) SpectrumService.registerComponent("anoSpotFace")
            Component.onDestruction: SpectrumService.unregisterComponent("anoSpotFace")
            LinearSpectrum {
                anchors.fill: parent
                vertical: root.vertical
                barPosition: root.vertical ? "left" : "bottom"
                fillColor: Appearance.colors.colPrimary
                cornerRadius: 2
            }
        }
    }

    // Lyrics: the current line, sliding in as it changes; a placeholder when
    // the track has none.
    Component {
        id: lyricsFace
        Item {
            id: lyr
            readonly property bool has: LyricsService.model.count > 0 && LyricsService.currentIndex >= 0
            readonly property string line: has ? (LyricsService.model.get(LyricsService.currentIndex)?.lyricLine ?? "") : ""
            implicitWidth: root.vertical ? root.thickness - 12 : Math.min(360, Math.max(140, shown.implicitWidth))
            implicitHeight: root.vertical ? 60 : root.thickness - 12
            clip: true
            MaterialSymbol {
                anchors.centerIn: parent
                visible: root.vertical
                text: "lyrics"; iconSize: 18; color: Appearance.colors.colPrimary
            }
            StyledText {
                id: shown
                visible: !root.vertical
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.italic: !lyr.has
                opacity: lyr.has ? 1 : 0.6
                text: lyr.has ? (lyr.line || "♪") : "No lyrics for this track"
                // New line: slide up from below and fade in.
                property real slide: 0
                transform: Translate { y: shown.slide }
                onTextChanged: lineAnim.restart()
                SequentialAnimation {
                    id: lineAnim
                    PropertyAction { target: shown; property: "slide"; value: 10 }
                    PropertyAction { target: shown; property: "opacity"; value: 0 }
                    ParallelAnimation {
                        NumberAnimation { target: shown; property: "slide"; to: 0; duration: AnimationConfig.scaledDuration(260); easing.type: Easing.OutCubic }
                        NumberAnimation { target: shown; property: "opacity"; to: lyr.has ? 1 : 0.6; duration: AnimationConfig.scaledDuration(260) }
                    }
                }
            }
        }
    }
}
