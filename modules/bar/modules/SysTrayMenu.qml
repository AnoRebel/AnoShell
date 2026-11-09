pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

/**
 * System tray context menu with DBus menu rendering and pin/unpin support.
 * Uses StackView for submenu navigation. Right-click or Back to go back.
 * Adapted from end-4/ii for Ano Shell.
 */
PopupWindow {
    id: root
    required property QsMenuHandle trayItemMenuHandle
    property string trayItemId: ""
    property var trayItem: null
    // Fuse into the bar edge in connected mode (not from inside a panel).
    property bool fuse: true

    signal menuClosed
    signal menuOpened(qsWindow: var)

    color: "transparent"
    property real padding: 8

    // The icon's window. Inside the tray overflow popout it is a popup, whose
    // item coordinates are not screen space, so the menu can't be placed in
    // the frame there: it keeps its own background instead of fusing.
    readonly property var _iconWindow: root.anchor.item?.QsWindow?.window ?? null
    // The bar edge the menu hangs from (via the overflow popup's parent window).
    readonly property string barEdge: PanelRegistry.windowEdge(root._iconWindow)
        || PanelRegistry.windowEdge(root._iconWindow?.anchor?.window) || "top"
    readonly property bool _vertical: root.barEdge === "left" || root.barEdge === "right"
    readonly property bool _fused: root.fuse && PanelRegistry.enabled && root._iconWindow !== null && root._iconWindow.anchor === undefined

    // Constrain the input region to the visible menu card. Without a mask the
    // PopupWindow's input handling is unreliable here and the entries don't
    // respond to clicks (the menu renders but items aren't actionable).
    mask: Region { item: popupBackground }

    implicitHeight: {
        let result = 0;
        for (let child of stackView.children) {
            result = Math.max(child.implicitHeight, result);
        }
        return result + popupBackground.padding * 2 + root.padding * 2;
    }
    implicitWidth: {
        let result = 0;
        for (let child of stackView.children) {
            result = Math.max(child.implicitWidth, result);
        }
        return result + popupBackground.padding * 2 + root.padding * 2;
    }

    function open() {
        root.visible = true;
        root.menuOpened(root);
    }

    function close() {
        root.visible = false;
        while (stackView.depth > 1)
            stackView.pop();
        root.menuClosed();
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.BackButton | Qt.RightButton
        onPressed: event => {
            if ((event.button === Qt.BackButton || event.button === Qt.RightButton) && stackView.depth > 1)
                stackView.pop();
        }

        SurfaceMaterial {
            id: popupBackground
            surface: "trayMenu"
            readonly property real padding: 4
            // Grows out of the tray icon away from the bar, pinned to the bar
            // edge; the menu entries are uncovered, not relaid out.
            anchors {
                top: root.barEdge !== "bottom" ? parent.top : undefined
                bottom: root.barEdge !== "top" ? parent.bottom : undefined
                left: root.barEdge !== "right" ? parent.left : undefined
                right: root.barEdge !== "left" ? parent.right : undefined
                margins: root.padding
            }
            property real reveal: 0
            Behavior on reveal { MotionSpring { token: "liquid" } }
            Component.onCompleted: reveal = 1
            readonly property real _grow: Math.max(0, Math.min(reveal, 1.04))
            height: root._vertical ? undefined : (parent.height - root.padding * 2) * _grow
            width: root._vertical ? (parent.width - root.padding * 2) * _grow : undefined

            // Connected mode: the frame paints the menu fused into the bar.
            readonly property bool connected: root._fused
            // In a panel it covers the panel's own rows: opaque there.
            color: connected ? "transparent" : !root.fuse ? Appearance.m3colors.m3surfaceContainerHigh : (Appearance?.colors.colLayer0 ?? "#1C1B1F")
            radius: Appearance?.rounding.normal ?? 12
            border.width: connected ? 0 : Appearance.borders.width
            border.color: Appearance.borders.color
            clip: true

            ConnectedSurfaceLease {
                key: "trayMenu:" + root.trayItemId
                kind: "trayMenu"; edge: root.barEdge; priority: 10
                active: root.visible && root._fused
                progress: popupBackground.reveal
                surfaceRadius: popupBackground.radius
                // Screen rect from the anchor icon (the popup's own origin is
                // not screen space); centred on the icon along the bar, clamped
                // on-screen, pinned to the icon's side facing away from the bar.
                readonly property Item _icon: root.anchor.item
                readonly property var _win: root._iconWindow
                screenName: _win?.screen?.name ?? ""
                readonly property point _a: {
                    void root.visible
                    if (!_icon) return Qt.point(0, 0)
                    const o = PanelRegistry.windowOrigin(_win), p = _icon.mapToItem(null, 0, 0)
                    return Qt.point(o.x + p.x, o.y + p.y)
                }
                readonly property real _sw: _win?.screen?.width ?? 0
                readonly property real _sh: _win?.screen?.height ?? 0
                readonly property real _iw: _icon?.width ?? 0
                readonly property real _ih: _icon?.height ?? 0
                x: root.barEdge === "left" ? _a.x + _iw + root.padding
                    : root.barEdge === "right" ? _a.x - root.padding - w
                    : Math.max(0, Math.min(_a.x + _iw / 2 - root.implicitWidth / 2, _sw - root.implicitWidth)) + root.padding
                y: root.barEdge === "top" ? _a.y + _ih + root.padding
                    : root.barEdge === "bottom" ? _a.y - root.padding - h
                    : Math.max(0, Math.min(_a.y + _ih / 2 - root.implicitHeight / 2, _sh - root.implicitHeight)) + root.padding
                w: popupBackground.width
                h: popupBackground.height
            }

            implicitWidth: stackView.implicitWidth + popupBackground.padding * 2
            implicitHeight: stackView.implicitHeight + popupBackground.padding * 2

            Behavior on implicitHeight { NumberAnimation { duration: AnimationConfig.scaledDuration(200); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }
            Behavior on implicitWidth { NumberAnimation { duration: AnimationConfig.scaledDuration(200); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }

            StackView {
                id: stackView
                anchors { fill: parent; margins: popupBackground.padding }
                // A submenu slides in from the side it opens towards (and back on
                // pop) while SubMenu fades itself; reduced motion keeps the fade only.
                readonly property real slide: AnimationConfig.reducedMotion ? 0 : 28
                readonly property int slideMs: AnimationConfig.scaledDuration(220)
                pushEnter: Transition { NumberAnimation { property: "x"; from: stackView.slide; to: 0; duration: stackView.slideMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }
                pushExit: Transition { NumberAnimation { property: "x"; from: 0; to: -stackView.slide; duration: stackView.slideMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }
                popEnter: Transition { NumberAnimation { property: "x"; from: -stackView.slide; to: 0; duration: stackView.slideMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }
                popExit: Transition { NumberAnimation { property: "x"; from: 0; to: stackView.slide; duration: stackView.slideMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }

                implicitWidth: currentItem.implicitWidth
                implicitHeight: currentItem.implicitHeight

                initialItem: SubMenu { handle: root.trayItemMenuHandle }
            }
        }
    }

    component SubMenu: ColumnLayout {
        id: submenu
        required property QsMenuHandle handle
        property bool isSubMenu: false
        property bool shown: false
        opacity: shown ? 1 : 0

        Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(150); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }

        Component.onCompleted: shown = true
        StackView.onActivating: shown = true
        StackView.onDeactivating: shown = false
        StackView.onRemoved: destroy()

        QsMenuOpener {
            id: menuOpener
            menu: submenu.handle
        }

        spacing: 0

        // Back button (visible in submenus)
        Loader {
            Layout.fillWidth: true
            visible: submenu.isSubMenu
            active: visible
            sourceComponent: RippleButton {
                id: backButton
                buttonRadius: popupBackground.radius - popupBackground.padding
                horizontalPadding: 12
                implicitWidth: contentItem.implicitWidth + horizontalPadding * 2
                implicitHeight: 36
                downAction: () => stackView.pop()
                contentItem: RowLayout {
                    anchors { verticalCenter: parent.verticalCenter; left: parent.left; right: parent.right; leftMargin: backButton.horizontalPadding; rightMargin: backButton.horizontalPadding }
                    spacing: 8
                    MaterialSymbol { iconSize: 20; text: "chevron_left" }
                    StyledText { Layout.fillWidth: true; text: "Back" }
                }
            }
        }

        // Pin/Unpin button (only at root menu level)
        RippleButton {
            id: pinEntry
            buttonRadius: popupBackground.radius - popupBackground.padding
            horizontalPadding: 12
            implicitWidth: contentItem.implicitWidth + horizontalPadding * 2
            implicitHeight: 36
            Layout.fillWidth: true
            visible: root.trayItem !== null && stackView.depth === 1
            releaseAction: () => { if (root.trayItem) TrayService.togglePin(root.trayItem) }
            contentItem: RowLayout {
                anchors { verticalCenter: parent.verticalCenter; left: parent.left; right: parent.right; leftMargin: pinEntry.horizontalPadding; rightMargin: pinEntry.horizontalPadding }
                spacing: 8
                MaterialSymbol { iconSize: 18; text: "push_pin" }
                StyledText { Layout.fillWidth: true; text: root.trayItem && TrayService.isPinned(root.trayItem) ? "Unpin" : "Pin" }
            }
        }

        // Separator after pin button
        Rectangle {
            Layout.fillWidth: true; implicitHeight: 1
            color: Appearance?.m3colors.m3outlineVariant ?? "#44444488"
            Layout.topMargin: 4; Layout.bottomMargin: 4
            visible: pinEntry.visible
        }

        // Menu entries
        Repeater {
            id: menuEntriesRepeater
            property bool iconColumnNeeded: {
                for (let i = 0; i < menuOpener.children.values.length; i++) {
                    if (menuOpener.children.values[i].icon.length > 0) return true;
                }
                return false;
            }
            property bool specialInteractionColumnNeeded: {
                for (let i = 0; i < menuOpener.children.values.length; i++) {
                    if (menuOpener.children.values[i].buttonType !== QsMenuButtonType.None) return true;
                }
                return false;
            }
            model: menuOpener.children
            delegate: SysTrayMenuEntry {
                required property QsMenuEntry modelData
                required property int index
                // Leading, trailing and doubled separators are noise (apps
                // send them around hidden items); show only ones that divide.
                visible: {
                    if (!modelData.isSeparator) return true
                    const all = menuOpener.children.values
                    return index > 0 && !all[index - 1].isSeparator && all.slice(index + 1).some(e => !e.isSeparator)
                }
                forceIconColumn: menuEntriesRepeater.iconColumnNeeded
                forceSpecialInteractionColumn: menuEntriesRepeater.specialInteractionColumnNeeded
                menuEntry: modelData
                buttonRadius: popupBackground.radius - popupBackground.padding
                onDismiss: root.close()
                onOpenSubmenu: handle => {
                    stackView.push(subMenuComponent.createObject(null, { handle: handle, isSubMenu: true }));
                }
            }
        }
    }

    Component {
        id: subMenuComponent
        SubMenu {}
    }
}
