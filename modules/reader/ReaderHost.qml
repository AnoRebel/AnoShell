import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.reader.anime
import qs.modules.reader.manga
import qs.modules.reader.novel

/**
 * ReaderHost — the novel, manga and anime panels (reader.enable).
 *
 * One layer window on the focused screen holds a slot per reader. A slot
 * grows out of its edge (reader.<kind>.edge) and retracts into it. Only one
 * reader shows per edge: opening another on the same edge minimises the one
 * there (it stays loaded, so it comes back as it was left). Closing a reader
 * unloads it and tells anod (Reader.close); a minimised one stays open, so
 * anod's backend keeps its images valid.
 *
 *   qs -c ano ipc call reader toggle manga    (or: ano reader manga)
 */
Scope {
    id: root

    readonly property var kinds: ["anime", "manga", "novel"]
    property var shown: ({ anime: false, manga: false, novel: false })
    property var minimized: ({ anime: false, manga: false, novel: false })
    property var loaded: ({ anime: false, manga: false, novel: false })
    // Each panel's width once loaded (reported by its slot), for the overlap check.
    property var widths: ({ anime: 540, manga: 600, novel: 600 })
    property var screenName: ""

    readonly property bool anyShown: kinds.some(k => root.shown[k])
    readonly property bool anyLoaded: kinds.some(k => root.loaded[k])

    function enabled(kind) { return Config.options.reader[kind]?.enable ?? true }
    function edge(kind) { return Config.options.reader[kind]?.edge === "right" ? "right" : "left" }
    function _with(obj, k, v) { const o = Object.assign({}, obj); o[k] = v; return o }

    function show(kind) {
        if (!root.kinds.includes(kind) || !root.enabled(kind)) return
        if (!root.anyShown)
            root.screenName = CompositorService.focusedMonitorName
        // One reader per edge: the one already there steps aside, keeping its
        // state. One on the other edge does too when both don't fit side by side.
        const scr = Quickshell.screens.find(s => s.name === root.screenName) ?? Quickshell.screens[0]
        for (const k of root.kinds) {
            if (k === kind || !root.shown[k]) continue
            if (root.edge(k) === root.edge(kind) || root.widths[k] + root.widths[kind] > (scr?.width ?? 0))
                root.minimize(k)
        }
        root.minimized = root._with(root.minimized, kind, false)
        root.shown = root._with(root.shown, kind, true)
        root.loaded = root._with(root.loaded, kind, true)
        if (Reader.state(kind) !== "ready") Reader.open(kind)
    }
    function minimize(kind) {
        root.shown = root._with(root.shown, kind, false)
        root.minimized = root._with(root.minimized, kind, true)
    }
    function close(kind) {
        const wasShown = root.shown[kind]
        root.shown = root._with(root.shown, kind, false)
        root.minimized = root._with(root.minimized, kind, false)
        // A showing slot unloads once it has retracted (ReaderSlot.onRevealChanged);
        // a minimised one is already retracted, so it unloads now.
        if (!wasShown && root.loaded[kind]) {
            root.loaded = root._with(root.loaded, kind, false)
            Reader.close(kind)
        }
    }
    function toggle(kind) {
        if (root.shown[kind]) root.close(kind)
        else root.show(kind)
    }

    Component.onCompleted: Reader.sweep()
    // reader.enable turned off (PanelGate unloads this): nothing stays open in anod.
    Component.onDestruction: root.kinds.forEach(k => Reader.close(k))

    IpcHandler {
        target: "reader"
        function toggle(kind: string): void { root.toggle(kind) }
        function open(kind: string): void { root.show(kind) }
        function close(kind: string): void { root.close(kind) }
        function minimize(kind: string): void { root.minimize(kind) }
    }

    component ReaderSlot: Item {
        id: slot
        required property string kind
        readonly property bool isShown: root.shown[kind] ?? false
        readonly property bool onRight: root.edge(kind) === "right"
        // (an unmapped window is 0 wide, so its width only caps once mapped)
        readonly property real fullWidth: loader.item ? Math.min(loader.item.implicitWidth, parent.width > 0 ? parent.width : Infinity) : 0

        // 0 → 1 as the panel grows out of its edge (pinned there, never slid off-screen).
        property real reveal: 0
        Binding on reveal { value: slot.isShown && loader.status === Loader.Ready ? 1 : 0 }
        Behavior on reveal { id: revealMotion; MotionSpring { token: revealMotion.targetValue > 0.5 ? "liquid" : "settle" } }
        onFullWidthChanged: if (fullWidth > 0) root.widths = root._with(root.widths, kind, fullWidth)
        onRevealChanged: {
            if (reveal > 0.001 || slot.isShown) return
            if (!(root.minimized[kind] ?? false) && (root.loaded[kind] ?? false)) {
                root.loaded = root._with(root.loaded, kind, false)
                Reader.close(kind)
            }
        }

        // Past the bar's zone but, like the sidebars, not the pill's when the
        // pill at its widest stays clear of this panel (then it reaches the edge).
        // (parent: the window's `area`, which knows its screen and zone mode)
        readonly property real _from: parent.x + (onRight ? parent.width - fullWidth : 0)
        function _inset(e) {
            return parent.ignoreZones ? PanelRegistry.insetBeside(parent.scr, e, _from, _from + fullWidth)
                + PanelRegistry.foreignInset(parent.scr, e) : 0
        }
        anchors { top: parent.top; bottom: parent.bottom; topMargin: _inset("top"); bottomMargin: _inset("bottom") }
        x: onRight ? parent.width - width : 0
        width: fullWidth * reveal
        visible: reveal > 0.001
        clip: true

        Loader {
            id: loader
            active: root.loaded[slot.kind] ?? false
            width: slot.fullWidth
            height: slot.height
            // Pinned to the screen edge; the slot's growing clip reveals it.
            x: slot.onRight ? slot.width - width : 0
            sourceComponent: slot.kind === "anime" ? animeComp : slot.kind === "manga" ? mangaComp : novelComp
            Component { id: animeComp; AnimePanel { onMinimizeRequested: root.minimize("anime") } }
            Component { id: mangaComp; MangaReader { onMinimizeRequested: root.minimize("manga") } }
            Component { id: novelComp; NovelReader { onMinimizeRequested: root.minimize("novel") } }
        }

        // Backend starting / failed: the panel says so and offers a retry.
        Rectangle {
            anchors.fill: parent
            visible: Reader.state(slot.kind) === "starting" || Reader.state(slot.kind) === "error"
            color: Appearance.m3colors.m3background
            Column {
                anchors.centerIn: parent
                width: Math.min(parent.width - 48, 360)
                spacing: 12
                MaterialSymbol {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Reader.state(slot.kind) === "error" ? "cloud_off" : "hourglass_top"
                    iconSize: 40
                    color: Reader.state(slot.kind) === "error" ? Appearance.m3colors.m3error : Appearance.m3colors.m3primary
                }
                StyledText {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: Reader.state(slot.kind) === "error" ? Reader.error : "Starting the reader…"
                    color: Appearance.m3colors.m3onSurfaceVariant
                }
                RippleButton {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: Reader.state(slot.kind) === "error"
                    buttonText: "Retry"
                    onClicked: Reader.open(slot.kind)
                }
            }
        }
    }

    LazyLoader {
        active: root.anyLoaded || root.anyShown
        component: PanelWindow {
            id: win
            screen: Quickshell.screens.find(s => s.name === root.screenName) ?? Quickshell.screens[0]
            visible: root.anyShown || animeSlot.visible || mangaSlot.visible || novelSlot.visible
            color: "transparent"
            anchors { top: true; bottom: true; left: true; right: true }
            // Beside the bar, not under it. With the connected frame the
            // registry knows every zone, so the window covers the screen and
            // each panel places itself (see ReaderSlot._inset).
            readonly property bool ignoreZones: PanelRegistry.enabled
            exclusionMode: ignoreZones ? ExclusionMode.Ignore : ExclusionMode.Normal
            WlrLayershell.namespace: "quickshell:reader"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: root.anyShown ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            // Input only on the panels; the rest of the screen stays usable.
            mask: Region {
                Region { item: animeSlot }
                Region { item: mangaSlot }
                Region { item: novelSlot }
            }

            Item {
                id: area
                readonly property bool ignoreZones: win.ignoreZones
                readonly property string scr: win.screen?.name ?? ""
                anchors.fill: parent
                anchors.leftMargin: ignoreZones ? PanelRegistry.inset(scr, "left") + PanelRegistry.foreignInset(scr, "left") : 0
                anchors.rightMargin: ignoreZones ? PanelRegistry.inset(scr, "right") + PanelRegistry.foreignInset(scr, "right") : 0
                ReaderSlot { id: animeSlot; kind: "anime" }
                ReaderSlot { id: mangaSlot; kind: "manga" }
                ReaderSlot { id: novelSlot; kind: "novel" }
            }
        }
    }
}
