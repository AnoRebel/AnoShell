import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.layouts
import qs.services
import "."

/**
 * AnoView overview settings — elaborate layout selection with visual previews
 * showing abstract representations of each layout algorithm.
 */
ColumnLayout {
    id: root
    spacing: 16

    SettingsPageHeader {
        title: "Overview"
        subtitle: "AnoView layout algorithm, scrolling workspaces and the infinite desktop"
        configRoots: ["overview", "scrolling"]
    }

    readonly property string thumbMode: Config.options?.overview?.liveThumbnails ?? "off"
    readonly property string currentLayout: Config.options?.overview?.layout ?? "smartgrid"

    // Hoisted so the selected-indicator can resolve display names without
    // duplicating the list. Each entry: id (config value) + name (UI label).
    readonly property var layoutsModel: [
        { id: "smartgrid", name: "Smart Grid", desc: "Optimal grid with aspect-fit", icon: "grid_view" },
        { id: "justified", name: "Justified", desc: "Text-wrap style rows", icon: "view_week" },
        { id: "bands", name: "Bands", desc: "Grouped by workspace", icon: "view_stream" },
        { id: "masonry", name: "Masonry", desc: "Pinterest-style columns", icon: "dashboard" },
        { id: "hero", name: "Hero", desc: "Active window large + stack", icon: "picture_in_picture" },
        { id: "spiral", name: "Spiral", desc: "Fibonacci space partitions", icon: "rotate_right" },
        { id: "satellite", name: "Satellite", desc: "Active center + orbital ring", icon: "blur_circular" },
        { id: "staggered", name: "Staggered", desc: "Brick-wall offset grid", icon: "view_comfy" },
        { id: "columnar", name: "Columnar", desc: "One window per column", icon: "view_column" },
        { id: "vortex", name: "Vortex", desc: "Golden spiral with rotation", icon: "cyclone" },
        { id: "random", name: "Random", desc: "Different layout each time", icon: "shuffle" },
    ]

    // ═══ Layout Selection ═══
    SettingsCard {
        icon: "overview"
        title: "AnoView Layout"
        subtitle: "Choose how windows are arranged in the overview"
        configKeys: ["overview.layout"]
        collapsible: false

        // Visual layout grid with mini-previews
        GridLayout {
            Layout.fillWidth: true
            columns: 3
            columnSpacing: 10; rowSpacing: 10

            Repeater {
                model: root.layoutsModel

                Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 80
                    radius: Appearance?.rounding.small ?? 8
                    color: root.currentLayout === modelData.id
                        ? Qt.rgba((Appearance?.colors.colPrimary ?? "#65558F").r, (Appearance?.colors.colPrimary ?? "#65558F").g, (Appearance?.colors.colPrimary ?? "#65558F").b, 0.2)
                        : Appearance?.colors.colLayer2 ?? "#2B2930"
                    border.width: root.currentLayout === modelData.id ? 2 : 1
                    border.color: root.currentLayout === modelData.id
                        ? Appearance?.colors.colPrimary ?? "#65558F"
                        : Appearance?.colors.colOutlineVariant ?? "#44444488"

                    Behavior on color { ColorAnimation { duration: AnimationConfig.scaledDuration(200) } }
                    Behavior on border.color { ColorAnimation { duration: AnimationConfig.scaledDuration(200) } }

                    scale: layoutMA.pressed ? 0.95 : (layoutMA.containsMouse ? 1.02 : 1)
                    Behavior on scale { NumberAnimation { duration: AnimationConfig.scaledDuration(150); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 4

                        MaterialSymbol {
                            text: modelData.icon
                            iconSize: 24
                            fill: root.currentLayout === modelData.id ? 1 : 0
                            color: root.currentLayout === modelData.id
                                ? Appearance?.colors.colPrimary ?? "#65558F"
                                : Appearance?.colors.colOnLayer1 ?? "#E6E1E5"
                            Layout.alignment: Qt.AlignHCenter
                        }
                        StyledText {
                            text: modelData.name
                            font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
                            font.weight: Font.DemiBold
                            color: root.currentLayout === modelData.id
                                ? Appearance?.colors.colPrimary ?? "#65558F"
                                : Appearance?.colors.colOnLayer1 ?? "#E6E1E5"
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }

                    MouseArea {
                        id: layoutMA
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Config.setNestedValue("overview.layout", modelData.id)
                    }

                    StyledToolTip {
                        text: modelData.desc
                        visible: layoutMA.containsMouse
                    }
                }
            }
        }

        // Current selection indicator
        RowLayout {
            Layout.fillWidth: true; spacing: 8
            MaterialSymbol { text: "check_circle"; iconSize: 18; color: Appearance?.colors.colPrimary ?? "#65558F"; fill: 1 }
            StyledText {
                // Show the layout's display name (e.g. "Smart Grid"), not
                // the kebab-case id with first letter capitalised.
                text: {
                    const m = root.layoutsModel ?? []
                    for (const l of m) if (l.id === root.currentLayout) return `Selected: ${l.name}`
                    return `Selected: ${root.currentLayout}`
                }
                font.pixelSize: Appearance?.font.pixelSize.small ?? 14
                font.weight: Font.DemiBold
                color: Appearance?.colors.colPrimary ?? "#65558F"
            }
        }
    }

    // ═══ Thumbnails ═══
    SettingsCard {
        icon: "live_tv"
        title: "Live Thumbnails"
        subtitle: "Overview, task view and the Alt+Tab list"
        configKeys: ["overview.liveThumbnails"]

        ConfigRow {
            label: "Live thumbnails"
            configKey: "overview.liveThumbnails"
            sublabel: "Off shows one still frame per window. Streaming costs GPU time while the view is open."
            ButtonGroup {
                buttons: [
                    GroupButton { label: "Off"; toggled: root.thumbMode === "off"; onClicked: Config.setNestedValue("overview.liveThumbnails", "off") },
                    GroupButton { label: "Hovered"; toggled: root.thumbMode === "hovered"; onClicked: Config.setNestedValue("overview.liveThumbnails", "hovered") },
                    GroupButton { label: "All (up to 12)"; toggled: root.thumbMode === "all"; onClicked: Config.setNestedValue("overview.liveThumbnails", "all") }
                ]
            }
        }
    }

    // ═══ Workspace layouts ═══
    SettingsCard {
        id: wsCard
        icon: "view_column"
        title: "Scrolling workspaces"
        subtitle: "Windows in columns on a strip wider than the screen"
        configKeys: ["scrolling.workspaces", "scrolling.columnWidth", "scrolling.apps"]
        readonly property string backend: CompositorService.backendName
        readonly property bool can: CompositorService.supports.scrollingLayout ?? false
        readonly property var sc: Config.options?.scrolling ?? ({})
        readonly property var wsList: Array.from(wsCard.sc.workspaces ?? [])
        readonly property var wsIds: wsCard.wsList.map(w => w.id)
        readonly property string dir: wsCard.wsList[0]?.direction ?? "right"
        function setWorkspaces(ids, dir) {
            Config.setNestedValue("scrolling.workspaces", ids.slice().sort((a, b) => a - b).map(id => ({ id, direction: dir })))
        }

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Appearance?.colors.colSubtext ?? "#CAC4D0"
            font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
            text: !wsCard.can ? `${wsCard.backend} has no scrolling layout`
                : wsCard.backend === "niri" ? "Every niri workspace scrolls. The widths below go into anod's managed file (include ano-managed.kdl in your config)."
                : wsCard.backend === "hyprland" ? "Uses Hyprland's own scrolling layout, applied straight away and kept in anod's managed file (ano-managed.lua, dofile'd from your hyprland.lua)."
                : "Uses mango's scroller layout through ~/.config/mango/ano-managed.conf (the bundled config sources it); mango reloads its config."
        }
        ConfigRow {
            label: wsCard.backend === "mango" ? "Scrolling tags" : "Scrolling workspaces"
            sublabel: "The others keep their usual layout"
            configKey: "scrolling.workspaces"
            visible: wsCard.can && wsCard.backend !== "niri"
        }
        ChoiceRow {
            Layout.fillWidth: true
            visible: wsCard.can && wsCard.backend !== "niri"
            model: Array.from({ length: 10 }, (_, i) => ({ value: i + 1, label: String(i + 1), icon: "" }))
            current: wsCard.wsIds
            onChose: value => {
                const ids = wsCard.wsIds.includes(value) ? wsCard.wsIds.filter(i => i !== value) : wsCard.wsIds.concat([value])
                wsCard.setWorkspaces(ids, wsCard.dir)
            }
        }
        ConfigRow {
            label: "Direction"
            sublabel: "Where new columns open and the strip scrolls"
            configKey: "scrolling.workspaces"
            visible: wsCard.can && wsCard.backend !== "niri" && wsCard.wsIds.length > 0
        }
        ChoiceRow {
            Layout.fillWidth: true
            visible: wsCard.can && wsCard.backend !== "niri" && wsCard.wsIds.length > 0
            model: wsCard.backend === "mango"
                ? [{ value: "right", label: "Sideways", icon: "arrow_forward" }, { value: "down", label: "Down", icon: "arrow_downward" }]
                : [{ value: "right", label: "Right", icon: "arrow_forward" }, { value: "left", label: "Left", icon: "arrow_back" },
                   { value: "down", label: "Down", icon: "arrow_downward" }, { value: "up", label: "Up", icon: "arrow_upward" }]
            current: wsCard.dir
            onChose: value => wsCard.setWorkspaces(wsCard.wsIds, value)
        }
        ConfigSlider {
            label: "Column width"
            sublabel: "New columns, as a share of the screen; leftmost = the compositor's own default"
            configKey: "scrolling.columnWidth"
            visible: wsCard.can
            from: 0; to: 1; stepSize: 0.05
            value: wsCard.sc.columnWidth ?? 0
            valueText: value < 0.1 ? "Default" : `${Math.round(value * 100)}%`
            onValueChanged: {
                const v = value < 0.1 ? 0 : Math.round(value * 100) / 100
                if (v !== (wsCard.sc.columnWidth ?? 0)) Config.setNestedValue("scrolling.columnWidth", v)
            }
        }
        ConfigRow {
            label: "Per-app widths"
            sublabel: "App id and share of the screen, e.g. firefox 0.8, kitty 0.5"
            configKey: "scrolling.apps"
            visible: wsCard.can
            StyledTextInput {
                boxed: true
                Layout.preferredWidth: 200
                text: Array.from(wsCard.sc.apps ?? []).map(a => `${a.app} ${a.width}`).join(", ")
                onEditingFinished: {
                    const apps = []
                    for (const part of text.split(",")) {
                        const m = part.trim().match(/^([A-Za-z0-9._-]+)\s+(0?\.\d+|1(\.0+)?)$/)
                        if (m && !apps.some(a => a.app === m[1])) apps.push({ app: m[1], width: Math.max(0.1, Math.min(1, Number(m[2]))) })
                    }
                    Config.setNestedValue("scrolling.apps", apps)
                }
            }
        }
    }

    SettingsCard {
        id: infCard
        icon: "pan_tool"
        title: "Infinite desktop"
        subtitle: "A workspace of floating windows on a canvas you pan around (idea from Anserin)"
        configKeys: []
        readonly property string backend: CompositorService.backendName

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Appearance?.colors.colSubtext ?? "#CAC4D0"
            font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
            text: !InfiniteDesktop.available ? `Unavailable: ${InfiniteDesktop.unavailableReason}`
                : (infCard.backend === "hyprland"
                    ? "Tap Super+Ctrl (or Super+Ctrl+I) to turn the focused workspace into one and back. Pan: drag the empty desktop, or hold Super+Alt and drag anywhere; drag a window against a screen edge."
                    : "Super+Ctrl+I turns the focused workspace into one and back. Pan: drag the empty desktop, or Super+Alt+G and move the pointer (click or Esc ends).")
                  + " Super+arrows focus the nearest window and bring it into view; new windows open in the middle."
                  + (infCard.backend === "niri" ? " niri keeps a sliver of each window that's off screen at the edge." : "")
        }
        RowLayout {
            spacing: 8
            visible: InfiniteDesktop.available
            StyledText {
                Layout.fillWidth: true
                text: InfiniteDesktop.active ? "This workspace is an infinite desktop" : "This workspace tiles"
                color: Appearance?.colors.colOnLayer1 ?? "#E6E0E9"
            }
            RippleButton {
                buttonText: InfiniteDesktop.active ? "Tile again" : "Make it infinite"
                onClicked: InfiniteDesktop.toggle()
            }
            RippleButton {
                buttonText: "Arrange"
                visible: InfiniteDesktop.active
                onClicked: InfiniteDesktop.arrange()
            }
        }
    }
}
