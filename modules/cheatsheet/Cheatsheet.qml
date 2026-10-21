import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * Keybind cheatsheet overlay. Reads keybinds from HyprlandKeybinds (Hyprland)
 * or NiriKeybinds (Niri) and displays them in a searchable, categorized grid.
 * Each category is a collapsible section with key combinations styled as keyboard keys.
 */
Scope {
    id: root
    property bool cheatsheetOpen: false
    property string searchQuery: ""

    function toggle() { cheatsheetOpen = !cheatsheetOpen }
    function open() { cheatsheetOpen = true }
    function close() { cheatsheetOpen = false; searchQuery = "" }

    // What the running compositor binds, from anod (keybinds.active: ano's set
    // once migrated, else the compositor's own config), plus the ano actions
    // nothing binds. Without anod: the old per-compositor parsers.
    property var anodData: null
    property var catalogue: ({})
    readonly property var keybindData: {
        if (root.anodData) return root.anodData
        if (CompositorService.compositor === "hyprland") return HyprlandKeybinds.keybinds
        if (CompositorService.compositor === "niri") return NiriKeybinds.keybinds
        return { children: [] }
    }
    onCheatsheetOpenChanged: if (cheatsheetOpen) root.fetch()

    function fetch() {
        if (!Anod.available) return
        Anod.call("keybinds.catalogue", {}, (r) => { if (r) root.catalogue = r })
        Anod.call("keybinds.active", { compositor: CompositorService.compositor }, (r, e) => {
            if (e || !r) { console.warn(`[Cheatsheet] keybinds.active: ${e?.message}`); return }
            root.anodData = root.sections(r.binds ?? [], r.unbound ?? [])
        })
    }

    function describe(b) {
        const a = b.args ?? []
        if (b.action === "shell") return a.join(" ")
        if (b.action === "exec") return a[0] ?? ""
        if (b.action === "hyprland" || b.action === "niri") return a[0]?.startsWith("hl.bind(") ? "(Lua function)" : (a[0] ?? "")
        const label = root.catalogue[b.action]?.label ?? b.action
        return a.length ? `${label} ${a.join(" ")}` : label
    }
    function sectionOf(b) {
        if (b.chord.startsWith("XF86")) return "Media & hardware"
        if (b.action === "shell") return "Shell"
        if (b.action === "exec") return "Apps & commands"
        if (b.action.startsWith("focus.")) return "Focus"
        if (b.action.startsWith("workspace.") || b.action.startsWith("window.toWorkspace")) return "Workspaces"
        if (b.action.startsWith("window.")) return "Windows"
        if (b.action === "hyprland") return "Hyprland"
        if (b.action === "niri") return "niri"
        return "Other"
    }
    function sections(binds, unbound) {
        const order = ["Shell", "Apps & commands", "Windows", "Focus", "Workspaces", "Media & hardware", "Hyprland", "niri", "Other"]
        const by = {}
        for (const b of binds) {
            if (b.submap) continue
            const name = root.sectionOf(b)
            ;(by[name] = by[name] ?? []).push({ keys: b.chord, action: root.describe(b), description: "" })
        }
        const children = order.filter(n => by[n]).map(n => ({ name: n, children: by[n] }))
        if (unbound.length > 0)
            children.push({ name: "AnoShell actions with no key", children: unbound.map(b => ({ keys: "", action: root.describe(b), description: "" })) })
        return { children: children }
    }

    IpcHandler {
        target: "cheatsheet"
        function toggle(): void { root.toggle() }
        function open(): void { root.open() }
        function close(): void { root.close() }
    }

    PanelWindow {
        id: csWindow
        visible: root.cheatsheetOpen

        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell:cheatsheet"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.cheatsheetOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        // Non-modal: no scrim, input only on the card (clicks elsewhere reach
        // your windows), keyboard focus when you interact with it.
        mask: Region { x: csCard.x; y: csCard.y; width: csCard.width; height: csCard.height }  // geometry: an item region keeps the scale-in size
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }

        // Keys can't attach to a window (only to Items); a Shortcut works there.

        Shortcut { sequence: "Escape"; autoRepeat: false; onActivated: root.close() }

        // Card
        PanelDragHandle { panelCard: csCard; key: "cheatsheet" }

        SurfaceMaterial {
            id: csCard
            surface: "cheatsheet"
            anchors.centerIn: parent
            width: Math.min(900, parent.width * 0.85)
            height: Math.min(700, parent.height * 0.85)
            radius: Appearance?.rounding.windowRounding ?? 20
            color: Appearance?.m3colors.m3background ?? "#1C1B1F"
            border.width: 1; border.color: Appearance?.colors.colLayer0Border ?? "#44444488"
            clip: true

            opacity: root.cheatsheetOpen ? 1 : 0
            scale: root.cheatsheetOpen ? 1 : 0.92
            Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(250); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }
            Behavior on scale { NumberAnimation { duration: AnimationConfig.scaledDuration(250); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }

            ColumnLayout {
                anchors { fill: parent; margins: 20 }
                spacing: 12

                // Header
                RowLayout {
                    Layout.fillWidth: true; spacing: 12
                    MaterialSymbol { text: "keyboard"; iconSize: 28; color: Appearance?.colors.colPrimary ?? "#65558F" }
                    StyledText { text: "Keyboard Shortcuts"; font.pixelSize: Appearance?.font.pixelSize.huger ?? 22; font.weight: Font.Bold; Layout.fillWidth: true }
                    StyledText { text: CompositorService.compositor; font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12; opacity: 0.4 }
                    ToolbarButton { iconName: "close"; iconSize: 22; onClicked: root.close() }
                }

                // Search bar
                Rectangle {
                    Layout.fillWidth: true; implicitHeight: 40; radius: 20
                    color: Appearance?.colors.colLayer1 ?? "#E5E1EC"

                    RowLayout {
                        anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                        spacing: 8
                        MaterialSymbol { text: "search"; iconSize: 20; opacity: 0.5 }
                        StyledTextInput {
                            id: csSearch
                            Layout.fillWidth: true
                            verticalAlignment: TextInput.AlignVCenter
                            font.pixelSize: Appearance.font.pixelSize.small
                            focus: root.cheatsheetOpen
                            text: root.searchQuery
                            onTextChanged: root.searchQuery = text

                            StyledText {
                                anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                                text: "Search keybinds..."; opacity: 0.4; font.pixelSize: Appearance.font.pixelSize.small
                                visible: !csSearch.text || csSearch.text.length === 0
                            }
                        }
                        ToolbarButton {
                            iconName: "close"; iconSize: 16
                            visible: root.searchQuery.length > 0
                            onClicked: { root.searchQuery = ""; csSearch.text = "" }
                        }
                    }
                }

                // Keybind sections
                StyledFlickable {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    contentHeight: sectionColumn.implicitHeight; clip: true

                    ColumnLayout {
                        id: sectionColumn
                        width: parent.width; spacing: 16

                        // Empty state
                        ColumnLayout {
                            visible: keybindData.children.length === 0
                            Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 60; spacing: 8
                            MaterialSymbol { text: "info"; iconSize: 48; opacity: 0.3; Layout.alignment: Qt.AlignHCenter }
                            StyledText { text: "No keybinds loaded"; font.pixelSize: Appearance.font.pixelSize.normal; opacity: 0.5; Layout.alignment: Qt.AlignHCenter }
                            StyledText { text: "Keybinds are loaded from your compositor config"; font.pixelSize: Appearance.font.pixelSize.smallie; opacity: 0.3; Layout.alignment: Qt.AlignHCenter }
                        }

                        Repeater {
                            model: keybindData.children ?? []

                            ColumnLayout {
                                id: sectionDelegate
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true; spacing: 6

                                property string sectionName: modelData.name ?? `Section ${index + 1}`
                                property var binds: modelData.children ?? []
                                property var filteredBinds: root.searchQuery.length === 0
                                    ? binds
                                    : binds.filter(b => {
                                        const q = root.searchQuery.toLowerCase()
                                        return (b.keys ?? "").toLowerCase().includes(q)
                                            || (b.action ?? "").toLowerCase().includes(q)
                                            || (b.description ?? "").toLowerCase().includes(q)
                                    })

                                visible: filteredBinds.length > 0

                                property bool expanded: true

                                // Section header
                                MouseArea {
                                    Layout.fillWidth: true
                                    implicitHeight: sectionHeaderRow.implicitHeight + 8
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: sectionDelegate.expanded = !sectionDelegate.expanded

                                    RowLayout {
                                        id: sectionHeaderRow
                                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                                        spacing: 8
                                        Rectangle { width: 4; height: 18; radius: 2; color: Appearance?.colors.colPrimary ?? "#65558F" }
                                        StyledText {
                                            text: sectionDelegate.sectionName
                                            font.pixelSize: Appearance?.font.pixelSize.normal ?? 16
                                            font.weight: Font.DemiBold
                                            color: Appearance?.colors.colPrimary ?? "#65558F"
                                            Layout.fillWidth: true
                                        }
                                        StyledText {
                                            text: `${sectionDelegate.filteredBinds.length}`
                                            font.pixelSize: Appearance.font.pixelSize.smaller; opacity: 0.4
                                        }
                                        MaterialSymbol {
                                            text: sectionDelegate.expanded ? "expand_less" : "expand_more"
                                            iconSize: 20; opacity: 0.5
                                        }
                                    }
                                }

                                // Keybind rows
                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: 3
                                    visible: sectionDelegate.expanded
                                    Layout.leftMargin: 12

                                    Repeater {
                                        model: sectionDelegate.filteredBinds

                                        Rectangle {
                                            required property var modelData
                                            required property int index
                                            Layout.fillWidth: true
                                            implicitHeight: bindRow.implicitHeight + 8
                                            radius: Appearance?.rounding.verysmall ?? 4
                                            color: index % 2 === 0 ? Qt.rgba(1, 1, 1, 0.02) : "transparent"

                                            RowLayout {
                                                id: bindRow
                                                anchors { fill: parent; leftMargin: 8; rightMargin: 8; topMargin: 4; bottomMargin: 4 }
                                                spacing: 12

                                                // Key combination pills
                                                RowLayout {
                                                    spacing: 4
                                                    Layout.preferredWidth: 200
                                                    Layout.alignment: Qt.AlignVCenter

                                                    StyledText { visible: !modelData.keys; text: "not bound"; opacity: 0.45 }
                                                    Repeater {
                                                        model: modelData.keys ? modelData.keys.split("+") : []

                                                        KeyboardKey {
                                                            required property string modelData
                                                            keyText: modelData
                                                        }
                                                    }
                                                }

                                                // Description / action
                                                StyledText {
                                                    text: modelData.description || modelData.action || ""
                                                    font.pixelSize: Appearance?.font.pixelSize.small ?? 13
                                                    elide: Text.ElideRight
                                                    Layout.fillWidth: true
                                                    opacity: 0.8
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
