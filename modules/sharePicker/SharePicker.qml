import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * The screen-share picker (Hyprland). xdg-desktop-portal-hyprland runs
 * scripts/share-picker → `ano share-pick`, which calls `sharePicker pick
 * <json>` here with what the portal offers ({ id, reply, allowToken,
 * windows: [{ id, class, title, address }], outputs: [{ name, x, y, w, h }] })
 * and waits for {"choice", "restore"} in the `reply` file ("" = cancelled).
 * `ano share-pick` checks the choice against the offer and prints the line
 * the portal reads. Until a request comes this is just the IPC target.
 *
 * Keys: ←↑→↓ choose, Enter shares, Tab / Shift+Tab switch tabs, Esc cancels.
 */
Scope {
    id: root

    property var request: null
    property string answered: ""  // the last answered id (its reply may still be on its way)
    property string tab: "screens" // screens | windows | region
    property bool restore: false
    property string region: ""     // a region choice, "region:<output>@x,y,w,h"
    property bool slurping: false
    property string screenName: ""

    readonly property var tabs: ["screens", "windows", "region"]

    // Screens: the portal's list (names it knows), else every screen.
    readonly property var screens: {
        const offered = root.request?.outputs ?? []
        const names = offered.length ? offered.map(o => o.name) : Quickshell.screens.map(s => s.name)
        return names.map(n => {
            const s = Quickshell.screens.find(x => x.name === n) ?? null
            return { choice: `screen:${n}`, title: n, subtitle: s ? `${s.width}×${s.height}` : "", source: s }
        })
    }
    // Windows, matched to their toplevel by Hyprland address for a live view.
    readonly property var windows: {
        if (!root.request) return []
        const byAddress = {}
        for (const t of Array.from(ToplevelManager.toplevels?.values ?? [])) {
            const a = t?.HyprlandToplevel?.address
            if (a) byAddress[String(a).replace(/^0x/, "").toLowerCase()] = t
        }
        return (root.request.windows ?? []).map(w => ({
            choice: `window:${w.id}`, title: w.title || w.class || "(window)", subtitle: w.class,
            source: byAddress[String(w.address ?? "").replace(/^0x/, "").toLowerCase()] ?? null
        }))
    }

    function finish(choice: string): void {
        const r = root.request
        if (!r) return
        root.answered = r.id
        root.request = null
        // Arguments, never a command line: nothing from the request reaches a shell.
        Quickshell.execDetached(["sh", "-c", 'printf %s "$1" > "$2.tmp" && mv -f "$2.tmp" "$2"', "sh",
            JSON.stringify({ choice: choice, restore: root.restore }), r.reply])
    }

    IpcHandler {
        target: "sharePicker"
        function pick(request: string): string {
            if (root.request) return "busy"
            let r
            try { r = JSON.parse(request) } catch (e) { return "bad request" }
            const runtime = Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
            if (typeof r?.id !== "string" || typeof r.reply !== "string"
                || !r.reply.startsWith(`${runtime}/ano-share-`) || r.reply.includes("..")) return "bad request"
            root.screenName = GlobalStates.focusedScreenName
            root.restore = !!r.allowToken
            root.region = ""
            root.tab = "screens"
            root.request = r
            return "ok"
        }
        function pending(id: string): string { return (root.request?.id === id || root.answered === id) ? "yes" : "no" }
        function cancel(id: string): void { if (root.request?.id === id) root.request = null }
    }

    Process {
        id: slurp
        // slurp reads predefined boxes from a non-terminal stdin: give it none.
        // %X %Y: relative to the output %o, as the portal wants them.
        command: ["sh", "-c", 'exec slurp -f "%o %X %Y %W %H" < /dev/null']
        stdout: StdioCollector {
            onStreamFinished: {
                const f = text.trim().split(" ")
                if (f.length === 5 && f.slice(1).every(v => /^\d+$/.test(v)) && +f[3] > 0 && +f[4] > 0)
                    root.region = `region:${f[0]}@${f[1]},${f[2]},${f[3]},${f[4]}`
            }
        }
        onExited: root.slurping = false
    }
    function pickRegion(): void {
        if (slurp.running) return
        root.slurping = true
        slurp.running = true
    }

    LazyLoader {
        active: root.request !== null

        PanelWindow {
            id: win
            screen: Quickshell.screens.find(s => s.name === root.screenName) ?? Quickshell.screens[0]
            visible: !root.slurping
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.namespace: "quickshell:sharePicker"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            property bool _shown: false
            // Focus the grid once the window is up (and again after slurp):
            // set earlier, inside the loader, it never reached the window, so
            // no key worked until a click.
            function _focusGrid() { Qt.callLater(() => { if (root.tab === "region") card.forceActiveFocus(); else grid.forceActiveFocus() }) }
            onVisibleChanged: if (visible) _focusGrid()
            Component.onCompleted: { Qt.callLater(() => win._shown = true); _focusGrid() }

            readonly property var items: root.tab === "screens" ? root.screens : root.tab === "windows" ? root.windows : []
            readonly property string choice: root.tab === "region" ? root.region : (items[grid.currentIndex]?.choice ?? "")

            Rectangle {
                anchors.fill: parent
                color: "black"
                opacity: win._shown ? 0.35 : 0
                Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(220) } }
                TapHandler { onTapped: root.finish("") }
            }

            SurfaceMaterial {
                id: card
                surface: "sharePicker"
                anchors.centerIn: parent
                width: Math.min(880, parent.width - 48)
                height: Math.min(640, parent.height - 48)
                radius: Appearance.rounding.large
                color: Appearance.m3colors.m3surfaceContainer
                opacity: win._shown ? 1 : 0
                scale: win._shown ? 1 : 0.94
                Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(180) } }
                Behavior on scale { MotionSpring { token: "liquid" } }
                TapHandler {} // a click on the card is not a click on the dim

                // Keys for the whole card: the grid keeps focus and hands them here.
                Keys.onPressed: event => card.handleKey(event)
                function handleKey(event) {
                    const i = root.tabs.indexOf(root.tab)
                    if (event.key === Qt.Key_Escape) root.finish("")
                    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        if (root.tab === "region" && !root.region) root.pickRegion()
                        else if (win.choice) root.finish(win.choice)
                    } else if (event.key === Qt.Key_Tab) root.tab = root.tabs[(i + 1) % 3]
                    else if (event.key === Qt.Key_Backtab) root.tab = root.tabs[(i + 2) % 3]
                    else return
                    event.accepted = true
                }

                ColumnLayout {
                    anchors { fill: parent; margins: 20 }
                    spacing: 14

                    RowLayout {
                        spacing: 12
                        Rectangle {
                            implicitWidth: 44; implicitHeight: 44; radius: 22
                            color: Appearance.colors.colPrimaryContainer
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "screen_share"; iconSize: 22
                                color: Appearance.colors.colOnPrimaryContainer
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            StyledText {
                                text: "Share your screen"
                                font.pixelSize: Appearance.font.pixelSize.large; font.weight: Font.DemiBold
                            }
                            StyledText {
                                text: "An app asked to see a screen, a window or a part of a screen"
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }

                    ChoiceRow {
                        model: [
                            { value: "screens", label: "Screens", icon: "desktop_windows" },
                            { value: "windows", label: "Windows", icon: "select_window" },
                            { value: "region", label: "Region", icon: "crop_free" }
                        ]
                        current: root.tab
                        onChose: value => { root.tab = value; grid.forceActiveFocus() }
                    }

                    GridView {
                        id: grid
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: root.tab !== "region"
                        clip: true
                        focus: true
                        model: win.items
                        cellWidth: Math.floor(width / Math.max(1, Math.floor(width / 260)))
                        cellHeight: 180
                        keyNavigationWraps: true
                        onModelChanged: currentIndex = 0
                        Keys.onPressed: event => card.handleKey(event)

                        delegate: Item {
                            id: tile
                            required property var modelData
                            required property int index
                            readonly property bool current: GridView.isCurrentItem
                            width: grid.cellWidth
                            height: grid.cellHeight

                            Rectangle {
                                id: frame
                                anchors { fill: parent; margins: 6; bottomMargin: 42 }
                                radius: 10
                                color: Appearance.colors.colLayer1
                                border.width: tile.current ? 2 : 1
                                border.color: tile.current ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                                Behavior on border.color { ColorAnimation { duration: AnimationConfig.scaledDuration(120) } }

                                Loader {
                                    anchors { fill: parent; margins: 3 }
                                    active: win.visible && !!tile.modelData.source
                                    sourceComponent: ScreencopyView {
                                        id: view
                                        captureSource: tile.modelData.source
                                        live: true
                                        paintCursor: false
                                        layer.enabled: true
                                        layer.effect: OpacityMask {
                                            maskSource: Rectangle { width: view.width; height: view.height; radius: 8 }
                                        }
                                    }
                                }
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    visible: !tile.modelData.source
                                    text: "preview_off"; iconSize: 28; opacity: 0.4
                                }
                            }
                            ColumnLayout {
                                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 6 }
                                spacing: 0
                                StyledText {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: tile.modelData.title
                                    font.weight: tile.current ? Font.DemiBold : Font.Normal
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: tile.modelData.subtitle
                                    color: Appearance.colors.colSubtext
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                }
                            }
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            TapHandler {
                                onTapped: { grid.currentIndex = tile.index; grid.forceActiveFocus() }
                                onDoubleTapped: root.finish(tile.modelData.choice)
                            }
                        }

                        StyledText {
                            anchors.centerIn: parent
                            visible: grid.count === 0
                            text: root.tab === "windows" ? "No windows to share" : "No screens to share"
                            color: Appearance.colors.colSubtext
                        }
                    }

                    // Region: slurp picks it, the picker hides meanwhile.
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: root.tab === "region"
                        spacing: 12
                        Item { Layout.fillHeight: true }
                        MaterialSymbol {
                            Layout.alignment: Qt.AlignHCenter
                            text: "crop_free"; iconSize: 48; opacity: 0.6
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: {
                                const m = root.region.match(/^region:(.+)@(\d+),(\d+),(\d+),(\d+)$/)
                                return m ? `${m[4]}×${m[5]} at ${m[2]},${m[3]} on ${m[1]}` : "Drag over the part of a screen to share"
                            }
                            color: Appearance.colors.colSubtext
                        }
                        RippleButton {
                            Layout.alignment: Qt.AlignHCenter
                            buttonText: root.region ? "Choose another region" : "Choose region"
                            onClicked: root.pickRegion()
                        }
                        Item { Layout.fillHeight: true }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        StyledSwitch {
                            id: restoreSwitch
                            checked: root.restore
                            onToggled: root.restore = checked
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: "Allow restore: the app may share the same thing again later without asking"
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.small
                            wrapMode: Text.Wrap
                            TapHandler { onTapped: root.restore = !root.restore }
                        }
                        RippleButton { buttonText: "Cancel"; onClicked: root.finish("") }
                        RippleButton {
                            buttonText: "Share"
                            toggled: true // the primary action
                            enabled: win.choice !== ""
                            onClicked: root.finish(win.choice)
                        }
                    }
                }
            }
        }
    }
}
