pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets

/**
 * System tray bar module — shows pinned + unpinned items with full DBus menu
 * and pin/unpin support. Right-click opens the app's context menu.
 */
Item {
    id: root
    property bool vertical: false
    // Every item in one row, no overflow (the control panel has the room).
    property bool showAll: false
    implicitWidth: trayRow.implicitWidth
    implicitHeight: vertical ? trayRow.implicitHeight + 8 : Appearance.sizes.barHeight

    property var activeMenu: null

    function setActiveMenu(menuWindow) {
        if (root.activeMenu && root.activeMenu !== menuWindow) {
            if (typeof root.activeMenu.close === "function")
                root.activeMenu.close();
        }
        root.activeMenu = menuWindow;
    }

    GridLayout {
        id: trayRow
        anchors.centerIn: parent
        flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rowSpacing: 2; columnSpacing: 2

        // Overflow button for unpinned items
        Loader {
            active: !root.showAll && TrayService.unpinnedItems.length > 0
            visible: active
            Layout.alignment: Qt.AlignCenter

            sourceComponent: Item {
                implicitWidth: 20; implicitHeight: 20

                property bool overflowOpen: false

                MaterialSymbol {
                    anchors.centerIn: parent
                    iconSize: 16
                    text: "expand_more"
                    color: Appearance.colors.colOnLayer1
                    // Points away from the bar; flips while open.
                    readonly property string _edge: PanelRegistry.windowEdge(root.QsWindow.window) || "top"
                    rotation: ({ "top": 0, "bottom": 180, "left": -90, "right": 90 })[_edge] + (parent.overflowOpen ? 180 : 0)
                    Behavior on rotation { NumberAnimation { duration: AnimationConfig.scaledDuration(200); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: parent.overflowOpen = !parent.overflowOpen
                }

                StyledPopup {
                    shown: parent.overflowOpen
                    popupWidth: overflowGrid.implicitWidth + 24
                    popupHeight: overflowGrid.implicitHeight + 24

                    GridLayout {
                        id: overflowGrid
                        anchors.centerIn: parent
                        columns: Math.ceil(Math.sqrt(TrayService.unpinnedItems.length))
                        columnSpacing: 8; rowSpacing: 8

                        Repeater {
                            model: TrayService.unpinnedItems
                            delegate: TrayIcon {
                                required property var modelData
                                item: modelData
                                onMenuOpened: (win) => root.setActiveMenu(win)
                            }
                        }
                    }
                }
            }
        }

        // Pinned items
        Repeater {
            model: ScriptModel { values: root.showAll ? TrayService.pinnedItems.concat(TrayService.unpinnedItems) : TrayService.pinnedItems }

            delegate: TrayIcon {
                required property SystemTrayItem modelData
                item: modelData
                Layout.alignment: Qt.AlignCenter
                onMenuOpened: (win) => root.setActiveMenu(win)
            }
        }
    }

    // ─── Inner component: single tray icon with menu ────────────────────
    component TrayIcon: MouseArea {
        id: trayIcon
        required property SystemTrayItem item
        signal menuOpened(qsWindow: var)

        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        implicitWidth: 24; implicitHeight: 24

        onPressed: (event) => {
            switch (event.button) {
            case Qt.LeftButton:
                item.activate();
                break;
            case Qt.RightButton:
                if (item.hasMenu) {
                    if (menuLoader.active && menuLoader.item && typeof menuLoader.item.close === "function")
                        menuLoader.item.close();
                    else
                        menuLoader.active = true;
                }
                break;
            }
            event.accepted = true;
        }

        // A themed icon name your theme doesn't have (and no picture sent)
        // would draw Qt's magenta "missing" square: a generic symbol instead.
        readonly property string _themeName: {
            const m = String(trayIcon.item.icon).match(/^image:\/\/icon\/([^?]+)$/)
            return m ? decodeURIComponent(m[1]) : ""
        }
        readonly property bool _missing: _themeName !== "" && !Quickshell.hasThemeIcon(_themeName)
        MaterialSymbol {
            anchors.centerIn: parent
            visible: trayIcon._missing
            text: "apps"; iconSize: 18
            color: Appearance.colors.colOnLayer1
        }
        IconImage {
            visible: !trayIcon._missing
            anchors.fill: parent
            source: trayIcon.item.icon
            implicitSize: 24
            asynchronous: true
            mipmap: true
        }

        StyledToolTip {
            text: TrayService.getTooltipForItem(trayIcon.item)
            // The parent is a MouseArea (has `containsMouse`, not `hovered`), so
            // StyledToolTip's default `parent.hovered` check is undefined and the
            // tooltip would show whenever its condition is true — i.e. always,
            // even with the menu open, covering the icons. Gate it explicitly on
            // real hover AND the menu being closed.
            extraVisibleCondition: trayIcon.containsMouse && !menuLoader.active
        }

        Loader {
            id: menuLoader
            active: false
            sourceComponent: SysTrayMenu {
                Component.onCompleted: this.open()
                trayItemMenuHandle: trayIcon.item.menu
                trayItemId: trayIcon.item.id
                trayItem: trayIcon.item
                fuse: !root.showAll // showAll: it sits in a panel, not on the bar edge
                anchor {
                    window: trayIcon.QsWindow.window
                    item: trayIcon
                    edges: barEdge === "bottom" ? Edges.Top : barEdge === "left" ? Edges.Right
                        : barEdge === "right" ? Edges.Left : Edges.Bottom
                    gravity: anchor.edges
                }
                onMenuOpened: (window) => trayIcon.menuOpened(window)
                onMenuClosed: menuLoader.active = false
            }
        }
    }
}
