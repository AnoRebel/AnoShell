import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import qs.modules.settings

/**
 * Welcome — the first-run wizard (spec onboarding-ux). Shown once on a fresh
 * config (no user changes, onboarding.seen false); `ano welcome` or Settings
 * → About runs it again. Every choice previews live on the real shell through
 * Config.preview (nothing written); Finish keeps them, Skip writes only
 * onboarding.seen. Display and cursor use the Settings controls themselves.
 */
Scope {
    id: root

    property bool open: false
    property int step: 0
    property var choices: ({})        // dotted key → value, previewed live
    readonly property var steps: ["Welcome", "Panels", "Bar", "Look", "Wallpapers", "Display & cursor", "Keybinds"]

    // First start: the user config is still empty.
    Connections {
        target: Config
        function onReadyChanged() { root.maybeStart() }
    }
    Component.onCompleted: maybeStart()
    function maybeStart() {
        if (Config.ready && !(Config.options.onboarding?.seen ?? false) && !Config.hasUserOverrides) root.start()
    }

    function start() {
        root.choices = {}
        root.step = 0
        root.open = true
    }
    function choose(key, value) {
        const c = Object.assign({}, root.choices)
        c[key] = value
        root.choices = c
        Config.preview(c)
    }
    function value(key, fallback) {
        if (key in root.choices) return root.choices[key]
        const keys = key.split(".")
        let v = Config.options
        for (const k of keys) v = v?.[k]
        return v ?? fallback
    }
    function finish() {
        Config.commitPreview()
        Config.setNestedValue("onboarding.seen", true)
        root.open = false
    }
    function skip() {
        Config.cancelPreview()
        Config.setNestedValue("onboarding.seen", true)
        root.open = false
    }

    IpcHandler {
        target: "welcome"
        function open(): void { root.start() }
        function close(): void { root.skip() }
    }

    LazyLoader {
        active: root.open
        component: PanelWindow {
            id: win
            screen: Quickshell.screens.find(s => s.name === CompositorService.focusedMonitorName) ?? Quickshell.screens[0]
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.namespace: "quickshell:welcome"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            // Only the card takes input: the shell behind stays live to look at.
            mask: Region { item: card }

            SurfaceMaterial {
                id: card
                surface: "welcome"
                anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 32 }
                width: Math.min(520, parent.width - 64)
                height: Math.min(parent.height - 64, body.implicitHeight + 40)
                radius: Appearance.rounding.large
                color: Appearance.m3colors.m3surfaceContainer
                focus: true
                Keys.onEscapePressed: root.skip()
                Keys.onReturnPressed: root.step === root.steps.length - 1 ? root.finish() : root.step++

                ColumnLayout {
                    id: body
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
                    spacing: 14

                    // Step dots
                    RowLayout {
                        spacing: 6
                        Repeater {
                            model: root.steps.length
                            delegate: Rectangle {
                                required property int index
                                width: index === root.step ? 22 : 8; height: 8; radius: 4
                                color: index <= root.step ? Appearance.colors.colPrimary : Appearance.colors.colLayer3
                                Behavior on width { NumberAnimation { duration: AnimationConfig.scaledDuration(180) } }
                            }
                        }
                        Item { Layout.fillWidth: true }
                        StyledText { text: `${root.step + 1} / ${root.steps.length}`; color: Appearance.colors.colSubtext }
                    }
                    StyledText {
                        text: root.steps[root.step]
                        font.pixelSize: Appearance.font.pixelSize.huge
                        font.weight: Font.DemiBold
                    }

                    // ── Steps ──────────────────────────────────────
                    StyledText {
                        visible: root.step === 0
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: "A few choices to set AnoShell up. Each one shows on your shell as you pick it; nothing is saved until Finish. Skip keeps the defaults, and Settings → About runs this again."
                    }
                    ChoiceRow {
                        visible: root.step === 1
                        compact: false
                        model: [
                            { value: "ano", label: "Ano (full)", icon: "auto_awesome" },
                            { value: "hefty", label: "Hefty", icon: "view_quilt" },
                            { value: "clean", label: "Clean", icon: "crop_square" },
                            { value: "minimal", label: "Minimal", icon: "remove" }
                        ]
                        current: root.value("panelFamily", "ano")
                        onChose: v => root.choose("panelFamily", v)
                    }
                    ColumnLayout {
                        visible: root.step === 2
                        spacing: 10
                        ChoiceRow {
                            compact: false
                            model: [{ value: "pill", label: "The pill", icon: "view_compact_alt" }, { value: "classic", label: "Full bar", icon: "dock_to_bottom" }]
                            current: root.value("bar.style", "pill")
                            onChose: v => root.choose("bar.style", v)
                        }
                        ChoiceRow {
                            compact: false
                            readonly property string key: root.value("bar.style", "pill") === "pill" ? "anoSpot.position" : "bars.0.edge"
                            model: ["top", "bottom", "left", "right"].map(e => ({ value: e, label: e[0].toUpperCase() + e.slice(1) }))
                            current: root.value(key, key === "anoSpot.position" ? "bottom" : "top")
                            onChose: v => root.choose(key, v)
                        }
                    }
                    ColumnLayout {
                        visible: root.step === 3
                        spacing: 10
                        ChoiceRow {
                            compact: false
                            model: [
                                { value: "liquid", label: "Liquid", icon: "water_drop" }, { value: "ink", label: "Ink", icon: "ink_pen" },
                                { value: "neotech", label: "Neo-tech", icon: "memory" }, { value: "clay", label: "Clay", icon: "category" }
                            ]
                            current: root.value("appearance.look", "")
                            onChose: v => root.choose("appearance.look", v)
                        }
                        ChoiceRow {
                            compact: false
                            model: [{ value: true, label: "Dark", icon: "dark_mode" }, { value: false, label: "Light", icon: "light_mode" }]
                            current: root.value("appearance.colors.darkMode", true)
                            onChose: v => root.choose("appearance.colors.darkMode", v)
                        }
                    }
                    ColumnLayout {
                        visible: root.step === 4
                        spacing: 8
                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            text: "The folder the wallpaper picker deals from (and Wallhaven saves to). Empty: Wallpapers in your Pictures folder."
                        }
                        ConfigTextInput {
                            Layout.fillWidth: true
                            placeholderText: FileUtils.trimFileProtocol(Directories.wallpaperDir)
                            text: root.value("background.wallpaperDir", "")
                            onEditingFinished: root.choose("background.wallpaperDir", text.trim())
                        }
                    }
                    ColumnLayout {
                        visible: root.step === 5
                        spacing: 8
                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            text: "Monitors: arrangement, scale and profiles are in Settings → Displays (a change there asks to keep it, and goes back by itself if you don't). The cursor applies right away:"
                        }
                        RippleButton { buttonText: "Open Settings → Displays"; onClicked: { GlobalStates.settingsPage = SettingsRegistry.pages.findIndex(p => p.name === "Displays"); GlobalStates.settingsOpen = true } }
                        CursorCard { Layout.fillWidth: true }
                    }
                    ColumnLayout {
                        visible: root.step === 6
                        spacing: 8
                        property var info: null
                        onVisibleChanged: if (visible && Anod.available)
                            Anod.call("keybinds.active", { compositor: CompositorService.compositor }, r => { info = r })
                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            text: !Anod.available ? "Keybinds are checked through anod, which isn't running."
                                : !parent.info ? "Checking your binds…"
                                : `${CompositorService.compositor}: ${parent.info.binds.length} binds. ` + (parent.info.unbound.length
                                    ? `${parent.info.unbound.length} AnoShell actions have no key yet (the cheatsheet lists them; Settings → Keybinds can bind them).`
                                    : "Every AnoShell action has a key.")
                        }
                        RippleButton { buttonText: "Open Settings → Keybinds"; onClicked: { GlobalStates.settingsPage = SettingsRegistry.pages.findIndex(p => p.name === "Keybinds"); GlobalStates.settingsOpen = true } }
                    }

                    // ── Navigation ─────────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        RippleButton { buttonText: "Skip"; onClicked: root.skip() }
                        Item { Layout.fillWidth: true }
                        RippleButton { visible: root.step > 0; buttonText: "Back"; onClicked: root.step-- }
                        RippleButton {
                            toggled: true
                            buttonText: root.step === root.steps.length - 1 ? "Finish" : "Next"
                            onClicked: root.step === root.steps.length - 1 ? root.finish() : root.step++
                        }
                    }
                }
            }
        }
    }
}
