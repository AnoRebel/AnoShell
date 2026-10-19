//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000
//@ pragma Env QT_SCALE_FACTOR=1

import "modules/common"
import "services"
// Loader-only modules (PanelGate sources) whose subfolders hold qs.* modules:
// Quickshell's scanner follows import lines only, so they are imported here.
import "modules/reader"
import "modules/search"
import "modules/onboarding"

import QtQuick
import Quickshell
import Quickshell.Io

// ═══════════════════════════════════════════════════════════════════════════
// Ano Shell — Entry Point
// 175 QML components. Compositor-agnostic: Hyprland + Niri.
//
// Modules and the panel families that host them are defined in
// modules/common/PanelGate.qml (Config.options.panelFamily picks the family).
// ═══════════════════════════════════════════════════════════════════════════
ShellRoot {
    id: root

    function _log(msg: string): void {
        if (Quickshell.env("QS_DEBUG") === "1") console.log("[Ano] " + msg);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Singleton Force-Init
    // ═══════════════════════════════════════════════════════════════════════
    Component.onCompleted: {
        root._log(`Initializing Ano shell on ${CompositorService.compositor}`);
        root._log(`Shell root: ${Directories.shellRoot}`);
        // Touch autonomous singletons so they instantiate even when no UI
        // currently reads them. Each runs purely on side-effects:
        //   PowerProfilePersistence — restores profile on Config.ready
        //   AntiFlashbang           — IPC-controlled shader on Hyprland
        //   MinimizedWindows        — Niri minimize-emulation registry
        //   DefaultApps             — `apps` IPC target used by keybinds
        //   Anod                    — daemon socket + shell events for hooks
        void PowerProfilePersistence;
        void AntiFlashbang;
        void MinimizedWindows;
        void DefaultApps;
        void Anod;
        void AppColorScheme;
        void StaticThemeLoader; // singletons only exist once referenced; static/fixed themes need it
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Config Ready Hook
    // ═══════════════════════════════════════════════════════════════════════
    // Startup settle: give layout one beat after the config is ready (bars
    // measure their groups, the pill its content, the frame its reserves).
    Timer { id: settleTimer; interval: 800; onTriggered: GlobalStates.shellSettled = true }

    Connections {
        target: Config
        function onReadyChanged() {
            if (!Config.ready) return;
            root._log("Config ready, initializing services");
            StaticThemeLoader.reapplyTheme(); // static/fixed theme, else Material You
            settleTimer.start();
            Wallpapers.load();
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Panel Families — see PanelGate.familyModules
    // ═══════════════════════════════════════════════════════════════════════
    property list<string> families: ["ano", "minimal", "hefty", "clean"]

    // Every shell module, each behind PanelGate.enabled(id). A family is just
    // the set of ids it hosts (PanelGate.familyModules), so a family switch
    // loads/unloads only the modules that differ.
    Instantiator {
        model: PanelGate.modules
        // component: Loader{source} (not LazyLoader.source) so a disabled
        // module's file is never even compiled.
        delegate: LazyLoader {
            required property var modelData
            active: PanelGate.enabled(modelData.id)
            component: Loader { source: Qt.resolvedUrl(modelData.source) }
        }
    }

    // Family-switch transition. Hosted here, outside the families, so it
    // survives the very family swap it is animating (inside a family it was
    // destroyed mid-transition and the switch never finished).
    FamilyTransitionOverlay {
        onExitComplete: root.applyPendingFamily()
        onEnterComplete: root.finishFamilyTransition()
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Family Transition
    // ═══════════════════════════════════════════════════════════════════════
    property string _pendingFamily: ""
    property bool _transitionInProgress: false

    function cyclePanelFamily() {
        const currentFamily = Config.options?.panelFamily ?? "ano";
        const currentIndex = families.indexOf(currentFamily);
        const nextIndex = (currentIndex + 1) % families.length;
        const nextFamily = families[nextIndex];
        root.startFamilyTransition(nextFamily);
    }

    function setPanelFamily(family: string) {
        const currentFamily = Config.options?.panelFamily ?? "ano";
        if (families.includes(family) && family !== currentFamily) {
            root.startFamilyTransition(family);
        }
    }

    function startFamilyTransition(targetFamily: string) {
        if (_transitionInProgress) return;
        if (!(Config.options?.familyTransitionAnimation ?? true)) {
            // Instant switch — no animation
            root._applyFamily(targetFamily);
            return;
        }
        _transitionInProgress = true;
        _pendingFamily = targetFamily;
        GlobalStates.familyTransitionActive = true;
    }

    function applyPendingFamily() {
        if (_pendingFamily && families.includes(_pendingFamily)) {
            root._applyFamily(_pendingFamily);
        }
        _pendingFamily = "";
    }

    function _applyFamily(family: string) {
        // Family-specific behaviour (which modules exist, morphing panels) is
        // computed by PanelGate — nothing else is written to the user config.
        Config.setNestedValue("panelFamily", family);
        root._log(`Applied family: ${family}`);
    }

    function finishFamilyTransition() {
        _transitionInProgress = false;
        GlobalStates.familyTransitionActive = false;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // IPC Handlers
    // ═══════════════════════════════════════════════════════════════════════
    IpcHandler {
        target: "panelFamily"
        function cycle(): void { root.cyclePanelFamily() }
        function set(family: string): void { root.setPanelFamily(family) }
    }

    IpcHandler {
        target: "shell"
        function reload(): void { Quickshell.reload(true) }
        function quit(): void { Quickshell.quit() }
    }

    // Launch standalone settings window
    IpcHandler {
        target: "settingsStandalone"
        function open(): void {
            Quickshell.execDetached(["/usr/bin/qs", "-n", "-p", Quickshell.shellPath("settings.qml")])
        }
    }
}
