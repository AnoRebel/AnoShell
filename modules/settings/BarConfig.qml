import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.bar.modules
import qs.services
import "."
import "../bar/BarLayout.js" as BarLayout
import "../bar/BarEdit.js" as BarEdit

/**
 * Bar configuration — elaborate settings with visual bar preview,
 * edge selector with diagram, module reorder, scroll actions, weather, tray.
 */
ColumnLayout {
    id: root
    spacing: 16

    // Bars whose own (non-null) value for `key` overrides the global setting.
    function overridingBars(key) {
        return (Config.options?.bars ?? []).filter(b => b?.[key] !== null && b?.[key] !== undefined).map(b => b.id ?? "?")
    }
    function overrideNote(key, fallback) {
        const ids = root.overridingBars(key)
        return ids.length > 0 ? `Overridden on bar ${ids.join(", ")} — those bars ignore this switch` : fallback
    }

    // configRoots: this page owns `bar` (including bar.morphingPanels even
    // though ModulesConfig has a dotted entry for it — both pages can
    // reset the key, the user can pick whichever page they think of first).
    SettingsPageHeader {
        title: "Bar"
        subtitle: "Edge, layout, modules, click actions, weather, tray"
        configRoots: ["bar", "bars", "tray"]
    }

    readonly property string currentEdge: Config.options?.bars?.[0]?.edge ?? "top"

    // ═══ Bar Position & Style ═══
    SettingsCard {
        icon: "dock_to_bottom"
        title: "Position & Style"
        subtitle: "Bar style, edge, auto-hide, background, and margin"
        configKeys: ["bar.style", "bar.cornerStyle", "bar.autoHide", "bar.showBackground", "bars"]

        ConfigRow {
            label: "Bar style"
            configKey: "bar.style"
            sublabel: BarStyle.family !== "ano"
                ? `Not applicable: the ${BarStyle.family} layout always uses the classic bar`
                : (BarStyle.pillBar ? "The pill is the bar: workspaces, clock, status and tray, resting at the bottom" : "The full classic bar")
            ChoiceRow {
                enabled: BarStyle.family === "ano"
                opacity: enabled ? 1 : 0.5
                model: [{ value: "pill", label: "Pill", icon: "capsule" }, { value: "classic", label: "Classic", icon: "toolbar" }]
                current: Config.options?.bar?.style ?? "pill"
                onChose: value => Config.setNestedValue("bar.style", value)
            }
        }

        // Visual edge selector
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 160

            Rectangle {
                id: screenPreview
                anchors.centerIn: parent
                width: 200; height: 130
                radius: 8
                color: Appearance?.colors.colLayer2 ?? "#2B2930"
                border.width: 1; border.color: Appearance?.colors.colOutlineVariant ?? "#C4C7C5"

                // Desktop label
                StyledText {
                    anchors.centerIn: parent
                    text: "Desktop"
                    font.pixelSize: Appearance.font.pixelSize.smaller; opacity: 0.3
                }

                // Bar indicator for each edge
                Repeater {
                    model: [
                        { edge: "top", x: 20, y: 2, w: 160, h: 8 },
                        { edge: "bottom", x: 20, y: 120, w: 160, h: 8 },
                        { edge: "left", x: 2, y: 20, w: 8, h: 90 },
                        { edge: "right", x: 190, y: 20, w: 8, h: 90 }
                    ]

                    Rectangle {
                        required property var modelData
                        x: modelData.x; y: modelData.y
                        width: modelData.w; height: modelData.h
                        radius: 4
                        color: root.currentEdge === modelData.edge
                            ? Appearance?.colors.colPrimary ?? "#65558F"
                            : "transparent"
                        border.width: 1
                        border.color: root.currentEdge === modelData.edge
                            ? Appearance?.colors.colPrimary ?? "#65558F"
                            : Appearance?.colors.colOutlineVariant ?? "#44444488"
                        opacity: root.currentEdge === modelData.edge ? 1 : 0.3

                        Behavior on color { ColorAnimation { duration: AnimationConfig.scaledDuration(200) } }
                        Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(200) } }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Config.setNestedValue("bars.0.edge", modelData.edge)
                        }
                    }
                }
            }

            // Edge label
            StyledText {
                anchors { bottom: screenPreview.top; horizontalCenter: screenPreview.horizontalCenter; bottomMargin: 4 }
                text: `Current: ${root.currentEdge}`
                font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
                font.weight: Font.DemiBold
                color: Appearance?.colors.colPrimary ?? "#65558F"
            }
        }

        // Quick edge buttons
        RowLayout {
            Layout.fillWidth: true; spacing: 6
            Repeater {
                model: ["top", "bottom", "left", "right"]
                GroupButton {
                    required property string modelData
                    label: modelData.charAt(0).toUpperCase() + modelData.slice(1)
                    iconName: modelData === "top" ? "vertical_align_top" : modelData === "bottom" ? "vertical_align_bottom" : modelData === "left" ? "align_horizontal_left" : "align_horizontal_right"
                    toggled: root.currentEdge === modelData
                    onClicked: Config.setNestedValue("bars.0.edge", modelData)
                    Layout.fillWidth: true
                }
            }
        }

        // Divider
        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Appearance?.colors.colOutlineVariant ?? "#C4C7C5"; opacity: 0.2 }

        ConfigSwitch {
            label: "Auto hide"
            configKey: "bar.autoHide.enable"
            sublabel: root.overrideNote("autoHide", "Bar slides away when not hovered, revealing more screen")
            checked: Config.options?.bar?.autoHide?.enable ?? false
            onCheckedChanged: Config.setNestedValue("bar.autoHide.enable", checked)
        }

        ConfigSlider {
            label: "Auto-hide delay"
            configKey: "bar.autoHide.delay"
            sublabel: "How long the bar stays after the pointer leaves"
            enabled: Config.options?.bar?.autoHide?.enable ?? false
            from: 0; to: 3000; stepSize: 100
            value: Config.options?.bar?.autoHide?.delay ?? 1000
            onValueChanged: Config.setNestedValue("bar.autoHide.delay", Math.round(value))
            valueText: Format.formatDuration(value)
        }

        ConfigSwitch {
            label: "Show background"
            configKey: "bar.showBackground"
            sublabel: root.overrideNote("showBackground", "Transparent bar when disabled — modules float directly")
            checked: Config.options?.bar?.showBackground ?? true
            onCheckedChanged: Config.setNestedValue("bar.showBackground", checked)
        }

        ConfigRow {
            label: "Corner style"
            configKey: "bar.cornerStyle"
            sublabel: "0 = floating (default), 1 = edge-to-edge with bezel padding"
            ButtonGroup {
                buttons: [
                    GroupButton { label: "Floating"; toggled: (Config.options?.bar?.cornerStyle ?? 0) === 0; onClicked: Config.setNestedValue("bar.cornerStyle", 0) },
                    GroupButton { label: "Edge-to-edge"; toggled: (Config.options?.bar?.cornerStyle ?? 0) === 1; onClicked: Config.setNestedValue("bar.cornerStyle", 1) }
                ]
            }
        }
    }

    // ═══ Bar layout: form + groups ═══
    // The bar is a list of groups; each is attached to the bar body or its own
    // island, and the form shapes the whole bar. Edits apply live.
    readonly property var barConfig0: Config.options?.bars?.[0] ?? null
    readonly property var groups: BarEdit.editable(root.barConfig0)
    readonly property string currentForm: BarLayout.formOf(root.barConfig0?.form ?? Config.options?.bar?.form ?? "full")
    function setGroups(arr) { Config.setNestedValue("bars.0.groups", arr) }
    function setGroupModules(id, arr) { root.setGroups(BarEdit.patch(root.groups, id, { modules: arr })) }
    function moveModule(moduleId, fromId, toId) { if (fromId !== toId) root.setGroups(BarEdit.moveModule(root.groups, moduleId, fromId, toId)) }
    // Drop before the chip at `before` in group toId (written once, on drop).
    function moveModuleBefore(moduleId, fromId, toId, before) {
        const from = root.groups.find(g => g.id === fromId)?.modules ?? []
        const i = from.indexOf(moduleId)
        if (i < 0) return
        const at = fromId === toId && i < before ? before - 1 : before
        if (fromId === toId && at === i) return
        root.setGroups(BarEdit.moveModule(root.groups, moduleId, fromId, toId, at))
    }

    SettingsCard {
        icon: "view_module"
        title: "Bar layout"
        subtitle: "Form, groups and modules. Detach a group to make it its own island; drag modules between groups."
        configKeys: ["bars", "bar.form"]

        ConfigRow {
            label: "Form"
            configKey: "bars"
            sublabel: "Edge to edge, inset, a pill per group, or hugging the content"
            ButtonGroup {
                buttons: [
                    GroupButton { label: "Full"; toggled: root.currentForm === "full"; onClicked: Config.setNestedValue("bars.0.form", "full") },
                    GroupButton { label: "Fit"; toggled: root.currentForm === "fit"; onClicked: Config.setNestedValue("bars.0.form", "fit") },
                    GroupButton { label: "Islands"; toggled: root.currentForm === "islands"; onClicked: Config.setNestedValue("bars.0.form", "islands") },
                    GroupButton { label: "Notch"; toggled: root.currentForm === "notch"; onClicked: Config.setNestedValue("bars.0.form", "notch") }
                ]
            }
        }

        Repeater {
            model: root.groups
            delegate: Rectangle {
                id: groupBox
                required property var modelData
                required property int index
                readonly property string gid: modelData.id
                Layout.fillWidth: true
                implicitHeight: groupCol.implicitHeight + 16
                radius: Appearance?.rounding.normal ?? 12
                color: drop.containsDrag ? (Appearance?.colors.colLayer2Hover ?? "#3C3947") : (Appearance?.colors.colLayer2 ?? "#2B2930")
                border.width: drop.containsDrag ? 2 : 0
                border.color: Appearance?.colors.colPrimary ?? "#65558F"
                Behavior on color { ColorAnimation { duration: AnimationConfig.scaledDuration(120) } }

                // Drop target for chips dragged from another group.
                DropArea {
                    id: drop
                    anchors.fill: parent
                    keys: ["barmodule"]
                    // Deferred: the write rebuilds the chips, and the dragged chip's
                    // handler must finish (clearing the ghost) before it is destroyed.
                    onDropped: Qt.callLater(root.moveModule, dragGhost.moduleId, dragGhost.groupId, groupBox.gid)
                }

                ColumnLayout {
                    id: groupCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                    spacing: 6
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        MaterialSymbol { text: groupBox.modelData.attached === false ? "bubble_chart" : "view_week"; iconSize: 18 }
                        StyledText {
                            text: groupBox.gid
                            font.weight: Font.DemiBold
                            font.pixelSize: Appearance?.font.pixelSize.small ?? 14
                        }
                        Item { Layout.fillWidth: true }
                        ButtonGroup {
                            buttons: [
                                GroupButton { label: "Start"; toggled: groupBox.modelData.zone === "start"; onClicked: root.setGroups(BarEdit.patch(root.groups, groupBox.gid, { zone: "start" })) },
                                GroupButton { label: "Centre"; toggled: groupBox.modelData.zone === "center"; onClicked: root.setGroups(BarEdit.patch(root.groups, groupBox.gid, { zone: "center" })) },
                                GroupButton { label: "End"; toggled: groupBox.modelData.zone === "end"; onClicked: root.setGroups(BarEdit.patch(root.groups, groupBox.gid, { zone: "end" })) }
                            ]
                        }
                        ButtonGroup {
                            buttons: [
                                GroupButton { label: "Attached"; toggled: groupBox.modelData.attached !== false; onClicked: root.setGroups(BarEdit.patch(root.groups, groupBox.gid, { attached: true })) },
                                GroupButton { label: "Island"; toggled: groupBox.modelData.attached === false; onClicked: root.setGroups(BarEdit.patch(root.groups, groupBox.gid, { attached: false })) }
                            ]
                        }
                        ToolbarButton {
                            iconName: "delete"; iconSize: 16
                            visible: root.groups.length > 1
                            toolTipText: "Remove group (its modules move to another group)"
                            onClicked: root.setGroups(BarEdit.removeGroup(root.groups, groupBox.gid))
                        }
                    }
                    BarModuleSection {
                        Layout.fillWidth: true
                        groupId: groupBox.gid
                        modules: groupBox.modelData.modules ?? []
                    }
                }
            }
        }

        RowLayout {
            spacing: 8
            RippleButton {
                implicitHeight: 32
                buttonRadius: Appearance?.rounding.small ?? 8
                onClicked: root.setGroups(BarEdit.addGroup(root.groups, "end"))
                contentItem: RowLayout {
                    spacing: 4
                    MaterialSymbol { text: "add"; iconSize: 16; Layout.leftMargin: 10 }
                    StyledText { text: "Add group"; font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12; Layout.rightMargin: 10 }
                }
            }
            StyledText {
                text: "Tip: right-click a group on the bar to detach it or open these settings."
                font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
                opacity: 0.6
            }
        }
    }

    // The chip being dragged, drawn above the page so it can leave its Flow.
    Rectangle {
        id: dragGhost
        property string moduleId: ""
        property string groupId: ""
        property bool dragging: false
        // Out of the page's layout: lives on the window's content item.
        parent: root.Window.contentItem ?? root
        z: 1000
        visible: dragging
        width: ghostLabel.implicitWidth + 20; height: 30
        radius: Appearance?.rounding.small ?? 8
        color: Appearance?.colors.colPrimary ?? "#65558F"
        opacity: 0.92
        Drag.active: dragging
        Drag.keys: ["barmodule"]
        Drag.hotSpot.x: width / 2
        Drag.hotSpot.y: height / 2
        StyledText {
            id: ghostLabel
            anchors.centerIn: parent
            text: BarModuleLoader.labelFor(dragGhost.moduleId)
            color: Appearance?.m3colors.m3onPrimary ?? "#FFFFFF"
            font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
        }
    }

    // Inline component for one bar section's chip editor. Shows active
    // chips with reorder/remove affordances, and an "Add" button revealing
    // the available-modules palette.
    component BarModuleSection: ColumnLayout {
        id: section
        property string groupId: ""
        property var modules: []              // current active list
        property bool _addingMode: false      // true while the available palette is shown
        // While a chip is dragged over this group's chips: the chip it would
        // land before (-1: none). The chips slide aside to show the gap; the
        // order is written only on drop, so a cancelled drag changes nothing.
        property int _hoverIndex: -1
        readonly property int _fromIndex: dragGhost.dragging && dragGhost.groupId === section.groupId ? section.modules.indexOf(dragGhost.moduleId) : -1
        function _shift(k) {
            const h = section._hoverIndex, f = section._fromIndex
            if (h < 0 || !dragGhost.dragging) return 0
            const w = dragGhost.width + 6
            if (f < 0) return k >= h ? w : 0                 // from another group: make room
            if (f < h) return k > f && k < h ? -w : 0        // moving later: close up behind
            return k >= h && k < f ? w : 0                   // moving earlier: open up ahead
        }

        readonly property var _allIds: BarModuleLoader.availableModuleIds ?? []
        // Available = catalogue minus what's already active
        readonly property var _availableIds: {
            const active = section.modules ?? []
            return section._allIds.filter(id => !active.includes(id))
        }

        function _writeModules(arr) {
            root.setGroupModules(section.groupId, arr)
        }

        function _moveBy(idx, delta) {
            const arr = [...section.modules]
            const next = idx + delta
            if (next < 0 || next >= arr.length) return
            const tmp = arr[next]; arr[next] = arr[idx]; arr[idx] = tmp
            section._writeModules(arr)
        }

        function _remove(idx) {
            const arr = [...section.modules]
            arr.splice(idx, 1)
            section._writeModules(arr)
        }

        function _add(id) {
            const arr = [...section.modules, id]
            section._writeModules(arr)
            section._addingMode = false
        }

        spacing: 6

        // Active chip row + add button
        Flow {
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: section.modules

                delegate: Rectangle {
                    id: chip
                    required property var modelData
                    required property int index

                    readonly property string moduleId: chip.modelData
                    readonly property bool isKnown: BarModuleLoader.isKnownModule(chip.moduleId)
                    readonly property string displayLabel:
                        chip.isKnown
                            ? `${chip.index + 1}. ${BarModuleLoader.labelFor(chip.moduleId)}`
                            : `Unknown: ${chip.moduleId}`

                    implicitWidth: chipRow.implicitWidth + 14
                    implicitHeight: 30
                    opacity: dragGhost.dragging && dragGhost.moduleId === chip.moduleId ? 0.35 : 1
                    transform: Translate {
                        x: section._shift(chip.index)
                        Behavior on x { MotionNumber { curve: "expressiveFastSpatial"; baseDuration: 160 } }
                    }

                    // Drop here: the dragged chip lands before this one.
                    DropArea {
                        anchors.fill: parent
                        keys: ["barmodule"]
                        onEntered: section._hoverIndex = chip.index
                        onExited: if (section._hoverIndex === chip.index) section._hoverIndex = -1
                        onDropped: {
                            section._hoverIndex = -1
                            Qt.callLater(root.moveModuleBefore, dragGhost.moduleId, dragGhost.groupId, section.groupId, chip.index)
                        }
                    }

                    // Drag the chip onto another group to move the module there.
                    DragHandler {
                        id: chipDrag
                        target: null
                        cursorShape: Qt.ClosedHandCursor
                        onActiveChanged: {
                            if (active) {
                                dragGhost.moduleId = chip.moduleId
                                dragGhost.groupId = section.groupId
                                dragGhost.dragging = true
                            } else {
                                dragGhost.Drag.drop()
                                dragGhost.dragging = false
                                dragGhost.moduleId = ""
                            }
                        }
                        onCentroidChanged: if (active) {
                            const p = dragGhost.parent.mapFromItem(null, centroid.scenePosition.x, centroid.scenePosition.y)
                            dragGhost.x = p.x - dragGhost.width / 2
                            dragGhost.y = p.y - dragGhost.height / 2
                        }
                    }
                    radius: Appearance?.rounding.small ?? 8
                    color: chip.isKnown
                        ? (Appearance?.colors.colSecondaryContainer ?? "#E8DEF8")
                        : (Appearance?.m3colors.m3errorContainer ?? "#5C1A1A")
                    border.width: chip.isKnown ? 0 : 1
                    border.color: Appearance?.m3colors.m3error ?? "#F2B8B5"

                    RowLayout {
                        id: chipRow
                        anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 8 }
                        spacing: 4

                        StyledText {
                            text: chip.displayLabel
                            font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
                            color: chip.isKnown
                                ? (Appearance?.m3colors.m3onSecondaryContainer ?? "#1D192B")
                                : (Appearance?.m3colors.m3onErrorContainer ?? "#F9DEDC")
                        }

                        // ◂ move-left / ▴ move-up
                        ToolbarButton {
                            iconName: "chevron_left"
                            iconSize: 16
                            visible: chip.index > 0
                            toolTipText: "Move earlier"
                            onClicked: section._moveBy(chip.index, -1)
                        }
                        // ▸ move-right / ▾ move-down
                        ToolbarButton {
                            iconName: "chevron_right"
                            iconSize: 16
                            visible: chip.index < (section.modules.length - 1)
                            toolTipText: "Move later"
                            onClicked: section._moveBy(chip.index, 1)
                        }
                        // ✕ remove
                        ToolbarButton {
                            iconName: "close"
                            iconSize: 16
                            toolTipText: "Remove"
                            onClicked: section._remove(chip.index)
                        }
                    }
                }
            }

            // Empty-state hint when the section has no modules
            Loader {
                active: (section.modules ?? []).length === 0
                visible: active
                sourceComponent: StyledText {
                    text: "No modules yet — click + to add"
                    font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
                    color: Appearance?.colors.colSubtext ?? "#CAC4D0"
                    opacity: 0.7
                }
            }

            // + Add module button
            RippleButton {
                implicitHeight: 30
                buttonRadius: Appearance?.rounding.small ?? 8
                visible: section._availableIds.length > 0
                contentItem: RowLayout {
                    spacing: 4
                    anchors.leftMargin: 10; anchors.rightMargin: 10
                    MaterialSymbol {
                        text: section._addingMode ? "expand_less" : "add"
                        iconSize: 14
                    }
                    StyledText {
                        text: section._addingMode ? "Hide" : "Add"
                        font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
                    }
                }
                onClicked: section._addingMode = !section._addingMode
            }
        }

        // Available palette — only visible while adding
        Loader {
            Layout.fillWidth: true
            active: section._addingMode && section._availableIds.length > 0
            visible: active
            sourceComponent: Rectangle {
                implicitHeight: paletteFlow.implicitHeight + 12
                radius: Appearance?.rounding.small ?? 8
                color: Appearance?.colors.colLayer2 ?? "#2B2930"
                border.width: 1
                border.color: Appearance?.colors.colOutlineVariant ?? "#49454F"

                Flow {
                    id: paletteFlow
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
                    spacing: 6

                    Repeater {
                        model: section._availableIds
                        delegate: Rectangle {
                            id: paletteChip
                            required property var modelData

                            implicitWidth: paletteLabel.implicitWidth + 22
                            implicitHeight: 28
                            radius: Appearance?.rounding.small ?? 8
                            color: paletteMA.containsMouse
                                ? (Appearance?.colors.colLayer1Hover ?? "#3C3947")
                                : (Appearance?.colors.colLayer1 ?? "#2B2930")
                            border.width: 1
                            border.color: Appearance?.colors.colOutlineVariant ?? "#49454F"

                            Behavior on color { ColorAnimation { duration: AnimationConfig.scaledDuration(100) } }

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 4
                                MaterialSymbol {
                                    text: "add"
                                    iconSize: 12
                                    color: Appearance?.colors.colSubtext ?? "#CAC4D0"
                                }
                                StyledText {
                                    id: paletteLabel
                                    text: BarModuleLoader.labelFor(paletteChip.modelData)
                                    font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
                                    color: Appearance?.colors.colOnLayer1 ?? "#E6E1E5"
                                }
                            }

                            MouseArea {
                                id: paletteMA
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: section._add(paletteChip.modelData)
                            }
                        }
                    }
                }
            }
        }
    }

    // ═══ Layout & Sizing ═══
    SettingsCard {
        icon: "straighten"
        title: "Layout & Sizing"
        advanced: true // hidden unless Settings shows advanced options (search still finds it)
        subtitle: "Bar height, corner radius, module spacing, padding, and decorations"
        configKeys: ["bar.layout"]

        // Live preview bar mockup
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 80

            Rectangle {
                anchors.centerIn: parent
                width: parent.width * 0.85; height: Config.options?.bar?.layout?.height ?? 42
                radius: Config.options?.bar?.layout?.radius ?? 12
                color: Appearance?.colors.colLayer0 ?? "#1C1B1F"
                border.width: 1; border.color: Appearance?.colors.colLayer0Border ?? "#44444488"

                RowLayout {
                    anchors { fill: parent; leftMargin: Config.options?.bar?.layout?.edgePadding ?? 8; rightMargin: Config.options?.bar?.layout?.edgePadding ?? 8 }

                    // Left mock modules
                    RowLayout {
                        spacing: Config.options?.bar?.layout?.leftSpacing ?? 8
                        Repeater { model: 2; Rectangle { width: 40; height: 14; radius: 7; color: Appearance?.colors.colOnLayer1 ?? "#E6E1E5"; opacity: 0.15 } }
                    }

                    Item { Layout.fillWidth: true }

                    // Center mock group
                    Rectangle {
                        implicitWidth: centerMockRow.implicitWidth + (Config.options?.bar?.layout?.centerGroupPadding ?? 5) * 2
                        implicitHeight: parent.height - 8
                        radius: Config.options?.bar?.layout?.centerGroupRadius ?? 8
                        color: (Config.options?.bar?.layout?.showCenterBackground ?? true) ? (Appearance?.colors.colLayer1 ?? "#E5E1EC") : "transparent"
                        RowLayout {
                            id: centerMockRow; anchors.centerIn: parent; spacing: Config.options?.bar?.layout?.centerSpacing ?? 4
                            Repeater { model: 6; Rectangle { width: 8; height: 8; radius: 4; color: Appearance?.colors.colPrimary ?? "#65558F"; opacity: index === 2 ? 1 : 0.3 } }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Right mock modules
                    RowLayout {
                        spacing: Config.options?.bar?.layout?.rightSpacing ?? 8
                        Repeater { model: 4; Rectangle { width: 30; height: 14; radius: 7; color: Appearance?.colors.colOnLayer1 ?? "#E6E1E5"; opacity: 0.15 } }
                    }

                    // Separators if enabled
                    Repeater {
                        model: (Config.options?.bar?.layout?.showSeparators ?? false) ? 2 : 0
                        Rectangle { width: 1; height: parent.height * 0.5; color: Appearance?.colors.colOutlineVariant ?? "#C4C7C5"; opacity: 0.3 }
                    }
                }
            }

            StyledText {
                anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
                text: `${Config.options?.bar?.layout?.height ?? 42}px tall • ${Config.options?.bar?.layout?.radius ?? 12}px radius`
                font.pixelSize: Appearance.font.pixelSize.smallest; opacity: 0.4
            }
        }

        ConfigSlider {
            label: "Bar height"
            configKey: "bar.layout.height"
            sublabel: "Total thickness of the bar in pixels"
            from: 28; to: 64; stepSize: 2
            value: Config.options?.bar?.layout?.height ?? 42
            onValueChanged: Config.setNestedValue("bar.layout.height", Math.round(value))
            valueText: `${Math.round(value)}px`
        }
        ConfigSlider {
            label: "Corner radius"
            configKey: "bar.layout.radius"
            sublabel: "Rounding of the bar background corners"
            from: 0; to: 28; stepSize: 1
            value: Config.options?.bar?.layout?.radius ?? 12
            onValueChanged: Config.setNestedValue("bar.layout.radius", Math.round(value))
            valueText: `${Math.round(value)}px`
        }

        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Appearance?.colors.colOutlineVariant ?? "#C4C7C5"; opacity: 0.15 }

        ConfigSlider {
            label: "Left section spacing"
            configKey: "bar.layout.leftSpacing"
            sublabel: "Gap between modules in the left section"
            from: 0; to: 24; stepSize: 1
            value: Config.options?.bar?.layout?.leftSpacing ?? 8
            onValueChanged: Config.setNestedValue("bar.layout.leftSpacing", Math.round(value))
            valueText: `${Math.round(value)}px`
        }
        ConfigSlider {
            label: "Center section spacing"
            configKey: "bar.layout.centerSpacing"
            sublabel: "Gap between modules in the center group"
            from: 0; to: 16; stepSize: 1
            value: Config.options?.bar?.layout?.centerSpacing ?? 4
            onValueChanged: Config.setNestedValue("bar.layout.centerSpacing", Math.round(value))
            valueText: `${Math.round(value)}px`
        }
        ConfigSlider {
            label: "Right section spacing"
            configKey: "bar.layout.rightSpacing"
            sublabel: "Gap between modules in the right section"
            from: 0; to: 24; stepSize: 1
            value: Config.options?.bar?.layout?.rightSpacing ?? 8
            onValueChanged: Config.setNestedValue("bar.layout.rightSpacing", Math.round(value))
            valueText: `${Math.round(value)}px`
        }
        ConfigSlider {
            label: "Edge padding"
            configKey: "bar.layout.edgePadding"
            sublabel: "Distance from screen edge to first/last module"
            from: 0; to: 32; stepSize: 1
            value: Config.options?.bar?.layout?.edgePadding ?? 8
            onValueChanged: Config.setNestedValue("bar.layout.edgePadding", Math.round(value))
            valueText: `${Math.round(value)}px`
        }

        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Appearance?.colors.colOutlineVariant ?? "#C4C7C5"; opacity: 0.15 }

        ConfigSlider {
            label: "Center group padding"
            configKey: "bar.layout.centerGroupPadding"
            sublabel: "Inner padding of the center pill container"
            from: 0; to: 16; stepSize: 1
            value: Config.options?.bar?.layout?.centerGroupPadding ?? 5
            onValueChanged: Config.setNestedValue("bar.layout.centerGroupPadding", Math.round(value))
            valueText: `${Math.round(value)}px`
        }
        ConfigSlider {
            label: "Center group radius"
            configKey: "bar.layout.centerGroupRadius"
            sublabel: "Corner rounding of the center pill container"
            from: 0; to: 24; stepSize: 1
            value: Config.options?.bar?.layout?.centerGroupRadius ?? 8
            onValueChanged: Config.setNestedValue("bar.layout.centerGroupRadius", Math.round(value))
            valueText: `${Math.round(value)}px`
        }
        ConfigSwitch {
            label: "Show center group background"
            configKey: "bar.layout.showCenterBackground"
            sublabel: "Visible pill background behind center modules (workspaces)"
            checked: Config.options?.bar?.layout?.showCenterBackground ?? true
            onCheckedChanged: Config.setNestedValue("bar.layout.showCenterBackground", checked)
        }
        ConfigSwitch {
            label: "Show section separators"
            configKey: "bar.layout.showSeparators"
            sublabel: "Thin vertical lines between left, center, and right sections"
            checked: Config.options?.bar?.layout?.showSeparators ?? false
            onCheckedChanged: Config.setNestedValue("bar.layout.showSeparators", checked)
        }
    }

    // ═══ Click & Scroll Actions ═══
    SettingsCard {
        id: actionsCard
        icon: "touch_app"
        title: "Click & Scroll Actions"
        subtitle: "What happens when you click or scroll on each bar section"
        configKeys: ["bar.actions"]

        readonly property var actionChoices: [
            { value: "sidebarLeft", label: "Left Sidebar", icon: "view_sidebar" },
            { value: "sidebarRight", label: "Right Sidebar", icon: "view_sidebar" },
            { value: "overview", label: "Overview", icon: "overview" },
            { value: "settings", label: "Settings", icon: "settings" },
            { value: "hud", label: "HUD", icon: "dashboard" },
            { value: "session", label: "Session", icon: "power_settings_new" },
            { value: "clipboard", label: "Clipboard", icon: "content_paste" },
            { value: "wallpaper", label: "Wallpaper", icon: "image" },
            { value: "cheatsheet", label: "Cheatsheet", icon: "keyboard" },
            { value: "none", label: "None", icon: "block" },
        ]
        readonly property var scrollChoices: [
            { value: "brightness", label: "Brightness", icon: "brightness_6" },
            { value: "volume", label: "Volume", icon: "volume_up" },
            { value: "workspace", label: "Workspace", icon: "grid_view" },
            { value: "none", label: "None", icon: "block" },
        ]

        // Helper to look up an action's display label for the header rows
        function _labelFor(actions, value) {
            for (const a of actions) if (a.value === value) return a.label
            return "(unknown)"
        }

        // Click actions
        StyledText { text: "Click actions"; font.weight: Font.DemiBold; font.pixelSize: Appearance?.font.pixelSize.small ?? 14; Layout.fillWidth: true }

        Repeater {
            model: [
                { section: "Left", key: "leftClick", default_: "sidebarLeft", desc: "Left section click" },
                { section: "Right", key: "rightClick", default_: "sidebarRight", desc: "Right section click" },
                { section: "Center", key: "centerClick", default_: "overview", desc: "Center section right-click" },
            ]

            ColumnLayout {
                id: clickRow
                required property var modelData
                Layout.fillWidth: true
                spacing: 4

                // Header row — section name + currently-selected action label.
                // Replaces the previous icon-only buttons with no visible label.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    StyledText {
                        text: clickRow.modelData.desc
                        font.pixelSize: Appearance?.font.pixelSize.small ?? 13
                        font.weight: Font.DemiBold
                        Layout.fillWidth: true
                    }
                    StyledText {
                        text: "→ " + actionsCard._labelFor(actionsCard.actionChoices,
                            Config.options?.bar?.actions?.[clickRow.modelData.key] ?? clickRow.modelData.default_)
                        font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
                        opacity: 0.7
                    }
                }

                ChoiceRow {
                    Layout.fillWidth: true
                    compact: true
                    itemSpacing: 4
                    model: actionsCard.actionChoices
                    current: Config.options?.bar?.actions?.[clickRow.modelData.key] ?? clickRow.modelData.default_
                    onChose: value => Config.setNestedValue(`bar.actions.${clickRow.modelData.key}`, value)
                }
            }
        }

        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Appearance?.colors.colOutlineVariant ?? "#C4C7C5"; opacity: 0.15 }

        // Scroll actions
        StyledText { text: "Scroll actions"; font.weight: Font.DemiBold; font.pixelSize: Appearance?.font.pixelSize.small ?? 14; Layout.fillWidth: true }

        ConfigRow {
            label: "Left section scroll"
            configKey: "bar.actions.scrollLeft"
            ChoiceRow {
                model: actionsCard.scrollChoices
                current: Config.options?.bar?.actions?.scrollLeft ?? "brightness"
                onChose: value => Config.setNestedValue("bar.actions.scrollLeft", value)
            }
        }
        ConfigRow {
            label: "Right section scroll"
            configKey: "bar.actions.scrollRight"
            ChoiceRow {
                model: actionsCard.scrollChoices
                current: Config.options?.bar?.actions?.scrollRight ?? "volume"
                onChose: value => Config.setNestedValue("bar.actions.scrollRight", value)
            }
        }
        ConfigRow {
            label: "Center section scroll"
            configKey: "bar.actions.scrollCenter"
            ChoiceRow {
                model: actionsCard.scrollChoices
                current: Config.options?.bar?.actions?.scrollCenter ?? "workspace"
                onChose: value => Config.setNestedValue("bar.actions.scrollCenter", value)
            }
        }
    }

    // ═══ Workspaces ═══
    SettingsCard {
        icon: "grid_view"
        title: "Workspaces"
        subtitle: "Workspace indicator count and style"
        configKeys: ["bar.workspaces"]

        ConfigSlider {
            label: "Number of workspaces shown"
            configKey: "bar.workspaces.shown"
            sublabel: "How many workspace dots appear in the bar"
            from: 2; to: 20; stepSize: 1
            value: Config.options?.bar?.workspaces?.shown ?? 10
            onValueChanged: Config.setNestedValue("bar.workspaces.shown", Math.round(value))
            valueText: `${Math.round(value)}`
        }
        ConfigSwitch {
            label: "Show windows on hover"
            configKey: "bar.workspaces.hoverWindows"
            sublabel: "Hovering a workspace button shows its windows as live thumbnails; click one to go to it"
            checked: Config.options?.bar?.workspaces?.hoverWindows ?? false
            onCheckedChanged: Config.setNestedValue("bar.workspaces.hoverWindows", checked)
        }
    }

    // ═══ Weather ═══
    SettingsCard {
        icon: "thermostat"
        title: "Weather"
        subtitle: "Weather data in bar and sidebar"
        configKeys: ["bar.weather"]

        ConfigSwitch {
            label: "Show weather module in bar"
            configKey: "bar.weather.enable"
            checked: Config.options?.bar?.weather?.enable ?? false
            onCheckedChanged: Config.setNestedValue("bar.weather.enable", checked)
        }

        ConfigRow {
            label: "City name"
            configKey: "bar.weather.city"
            sublabel: Location.valid
                ? `Using your location (${Location.city || Location.source}) from Settings → Services → Location; this city is used when location is off`
                : "Used when location (Settings → Services → Location) is off or unknown; empty: guessed from your IP address"
            StyledTextInput {
                text: Config.options?.bar?.weather?.city ?? ""
                onEditingFinished: Config.setNestedValue("bar.weather.city", text)
                Layout.preferredWidth: 180
            }
        }

        ConfigSwitch {
            label: "Use Fahrenheit (USCS)"
            configKey: "bar.weather.useUSCS"
            sublabel: "Imperial units (°F, mph, inches)"
            checked: Config.options?.bar?.weather?.useUSCS ?? false
            onCheckedChanged: Config.setNestedValue("bar.weather.useUSCS", checked)
        }

        ConfigSlider {
            label: "Fetch interval"
            configKey: "bar.weather.fetchInterval"
            sublabel: "How often weather data refreshes"
            from: 1; to: 60; stepSize: 1
            value: Config.options?.bar?.weather?.fetchInterval ?? 15
            onValueChanged: Config.setNestedValue("bar.weather.fetchInterval", Math.round(value))
            valueText: `${Math.round(value)} min`
        }
    }

    // ═══ System Tray ═══
    SettingsCard {
        icon: "more_horiz"
        title: "System Tray"
        subtitle: "Tray icon filtering and pin management"
        configKeys: ["tray"]

        ConfigSwitch {
            label: "Filter passive items"
            configKey: "tray.filterPassive"
            sublabel: "Hide tray items with 'passive' status (reduces clutter)"
            checked: Config.options?.tray?.filterPassive ?? false
            onCheckedChanged: Config.setNestedValue("tray.filterPassive", checked)
        }

        ConfigSwitch {
            label: "Invert pinned items"
            configKey: "tray.invertPinnedItems"
            sublabel: "Swap which items are shown as pinned vs overflow"
            checked: Config.options?.tray?.invertPinnedItems ?? false
            onCheckedChanged: Config.setNestedValue("tray.invertPinnedItems", checked)
        }

        ConfigSwitch {
            label: "Show item ID in tooltip"
            configKey: "tray.showItemId"
            sublabel: "Useful for identifying which items to pin"
            checked: Config.options?.tray?.showItemId ?? false
            onCheckedChanged: Config.setNestedValue("tray.showItemId", checked)
        }
    }
}
