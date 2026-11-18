import QtQuick
import qs
import qs.modules.common
import qs.modules.lock
import qs.services

/**
 * Settings' lock screen preview (settings-wiring "Interactive previews in Settings"): the chosen lock screen
 * in miniature, nothing typed is checked (its field takes no input). One that supports layouts (the built-in
 * one, Simple) is arranged in place: drag an element anywhere or its round corner handle to resize it,
 * written once on release as lock.layouts.<id> (LockLayoutStage). More (turning, opacity, adding and
 * removing, grid, undo) in the full-screen layout editor. Other packages are shown as they are.
 */
PreviewScreen {
    id: root
    maxHeight: 300
    readonly property string lockId: LockScreens.selected !== "default" && LockScreens.current ? LockScreens.selected : "default"
    readonly property bool arrangeable: LockScreens.supportsLayout(root.lockId)

    LockContext {
        id: previewCtx
        preview: true
        screen: root.targetScreen
        layoutOverride: root.arrangeable ? stage.shown : null
        layout: root.arrangeable ? stage.shown : []
    }

    // The built-in one, arranged (unarranged, its column sits where its own arrangement puts the elements).
    Loader {
        anchors.fill: parent
        active: root.lockId === "default"
        sourceComponent: DefaultLockSurface { ctx: previewCtx; miniature: true; forceArranged: true }
    }
    // A package, one per selection (the host picks its package once, when created).
    Repeater {
        model: root.lockId !== "default" ? [root.lockId] : []
        LockSurfaceHost {
            required property string modelData
            width: root.worldW; height: root.worldH
            packageId: modelData; ctx: previewCtx; focus: false
        }
    }

    LockLayoutStage {
        id: stage
        width: root.worldW; height: root.worldH
        visible: root.arrangeable
        enabled: root.arrangeable
        ctx: previewCtx
        ui: 1 / Math.max(0.05, root.s)
        // The built-in one draws its own elements (arranged) or its column: the stage only outlines them.
        drawElements: false
        elements: LockScreens.layoutOf(root.lockId)
        onEdited: list => LockScreens.saveLayout(root.lockId, list)
    }
}
