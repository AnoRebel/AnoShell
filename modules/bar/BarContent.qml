import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import qs.modules.bar.modules
import "."
import "BarLayout.js" as BarLayout
import "BarEdit.js" as BarEdit

/**
 * BarContent — Fully configurable bar content renderer.
 *
 * Content is a list of groups (bars[].groups, or the legacy
 * modules.{left,center,right} migrated into start/center/end groups). Each
 * group is attached to the bar body or detached into its own island, and the
 * bar's form (full | fit | islands | notch) decides where groups sit and what
 * the body is (BarLayout.js). Positions and separation spring-animate, and
 * `bodyRects` (the body segments plus islands, in this item's coordinates)
 * drives the window's painting, input mask and connected-frame slots.
 *
 * Every aspect is driven by config:
 *   - Which modules appear in each group
 *   - Spacing between modules (per-section overridable)
 *   - Edge padding (distance from bar edges to first/last module)
 *   - Center group padding and corner radius
 *   - Click actions per section (what happens on left/right click)
 *   - Scroll actions per section (brightness/volume/workspace)
 *   - Separator visibility between sections
 *   - Module alignment within sections
 */
Item {
    id: root
    required property var barConfig
    required property bool isVertical
    required property string edge
    property int barIndex: 0

    // ═══════════════════════════════════════════════════════════════════
    // Module lists (configurable per-bar or global fallback)
    // ═══════════════════════════════════════════════════════════════════
    readonly property var moduleConfig: barConfig?.modules ?? {
        "left": ["sidebarButton", "activeWindow"],
        "center": ["workspaces"],
        "right": ["clock", "battery", "network", "bluetooth", "tray", "sidebarButton"]
    }

    // ═══════════════════════════════════════════════════════════════════
    // Spacing & Padding (configurable at bar level → global fallback)
    // ═══════════════════════════════════════════════════════════════════
    readonly property real leftSpacing: barConfig?.leftSpacing ?? Config.options?.bar?.layout?.leftSpacing ?? 8
    readonly property real centerSpacing: barConfig?.centerSpacing ?? Config.options?.bar?.layout?.centerSpacing ?? 4
    readonly property real rightSpacing: barConfig?.rightSpacing ?? Config.options?.bar?.layout?.rightSpacing ?? 8
    readonly property real edgePadding: barConfig?.edgePadding ?? Config.options?.bar?.layout?.edgePadding ?? 8
    readonly property real centerGroupPadding: barConfig?.centerGroupPadding ?? Config.options?.bar?.layout?.centerGroupPadding ?? 5
    readonly property real centerGroupRadius: barConfig?.centerGroupRadius ?? Config.options?.bar?.layout?.centerGroupRadius ?? 8
    readonly property bool showCenterBackground: barConfig?.showCenterBackground ?? Config.options?.bar?.layout?.showCenterBackground ?? true
    readonly property bool showSeparators: barConfig?.showSeparators ?? Config.options?.bar?.layout?.showSeparators ?? false

    // ═══════════════════════════════════════════════════════════════════
    // Click Actions (configurable per section)
    // ═══════════════════════════════════════════════════════════════════
    // Empty-space left-click defaults to "none": clicking bar background should
    // do nothing, and icons handle their own left-click. (Previously these
    // defaulted to sidebarLeft/Right, so any click that fell through an icon —
    // most icons don't consume clicks — opened a sidebar unexpectedly.) Still
    // user-configurable via bar.actions.leftClick / .rightClick.
    readonly property string leftClickAction: barConfig?.leftClickAction ?? Config.options?.bar?.actions?.leftClick ?? "none"
    readonly property string rightClickAction: barConfig?.rightClickAction ?? Config.options?.bar?.actions?.rightClick ?? "none"
    readonly property string centerClickAction: barConfig?.centerClickAction ?? Config.options?.bar?.actions?.centerClick ?? "overview"
    readonly property string scrollLeftAction: barConfig?.scrollLeftAction ?? Config.options?.bar?.actions?.scrollLeft ?? "brightness"
    readonly property string scrollRightAction: barConfig?.scrollRightAction ?? Config.options?.bar?.actions?.scrollRight ?? "volume"
    readonly property string scrollCenterAction: barConfig?.scrollCenterAction ?? Config.options?.bar?.actions?.scrollCenter ?? "workspace"

    function performClickAction(action) {
        switch (action) {
            case "sidebarLeft":  GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen; break
            case "sidebarRight": GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen; break
            case "overview":     GlobalStates.overviewOpen = !GlobalStates.overviewOpen; break
            case "settings":     GlobalStates.settingsOpen = !GlobalStates.settingsOpen; break
            case "hud":          GlobalStates.hudVisible = !GlobalStates.hudVisible; break
            case "session":      GlobalStates.sessionOpen = !GlobalStates.sessionOpen; break
            case "clipboard":    GlobalStates.clipboardOpen = !GlobalStates.clipboardOpen; break
            case "wallpaper":    GlobalStates.wallpaperSelectorOpen = !GlobalStates.wallpaperSelectorOpen; break
            case "cheatsheet":   GlobalStates.cheatsheetOpen = !GlobalStates.cheatsheetOpen; break
            case "none": break
            default: break
        }
    }

    function performScrollAction(action, isUp) {
        switch (action) {
            case "brightness":
                const monitor = Brightness.getMonitorForScreen(root.QsWindow.window?.screen)
                if (monitor) monitor.setBrightness(monitor.brightness + (isUp ? 0.05 : -0.05))
                break
            case "volume":
                if (isUp) Audio.incrementVolume(); else Audio.decrementVolume()
                break
            case "workspace":
                CompositorService.focusWorkspaceRelative(isUp ? -1 : 1)
                break
            case "none": break
        }
    }

    // Tell a loaded module where it lives: its section (position-aware modules
    // like sidebarButton) and the bar's orientation.
    function _place(item, section) {
        if (!item) return
        if (item.hasOwnProperty("barSection")) item.barSection = section
        if (item.hasOwnProperty("vertical")) item.vertical = Qt.binding(() => root.isVertical)
    }

    // ═══════════════════════════════════════════════════════════════════
    // Forms and groups
    // ═══════════════════════════════════════════════════════════════════
    // Edits to a bar replace the bars array (Config copy-on-write), so
    // barConfig changes by itself. Groups are memoised by content: a new array
    // would make the Repeater rebuild every module on any unrelated change.
    readonly property string form: BarLayout.formOf(barConfig?.form ?? Config.options?.bar?.form ?? "full")
    readonly property var _groupsMemo: ({ key: "", value: [] })
    readonly property var groups: {
        const g = (barConfig?.groups?.length ?? 0) > 0 ? barConfig.groups : BarLayout.groupsFromModules(moduleConfig)
        const key = JSON.stringify(g)
        if (key !== root._groupsMemo.key) { root._groupsMemo.key = key; root._groupsMemo.value = g }
        return root._groupsMemo.value
    }

    function _setGroups(groups) { Config.setNestedValue(`bars.${root.barIndex}.groups`, groups) }
    function toggleAttached(id) {
        const g = BarEdit.editable(root.barConfig)
        const cur = g.find(x => x.id === id)
        if (cur) root._setGroups(BarEdit.patch(g, id, { attached: cur.attached === false }))
    }
    function openCustomize() { GlobalStates.customizeSurface = "bar" } // CustomizeSheet

    BarGroupMenu { id: groupMenu; barEdge: root.edge }
    // Gap a detached group opens on each side; inset of floating forms.
    readonly property real groupGap: barConfig?.groupGap ?? Config.options?.bar?.layout?.groupGap ?? 10
    readonly property real groupSpacing: barConfig?.groupSpacing ?? Config.options?.bar?.layout?.groupSpacing ?? 8
    readonly property real edgeMargin: (form === "fit" || form === "islands") ? (barConfig?.formMargin ?? Config.options?.bar?.layout?.formMargin ?? 6) : 0
    readonly property real islandPad: 6
    // A full or fit body spreads from the groups' extent to its span on the
    // groups' own motion (BarLayout.bodies opts.open), so switching from
    // notch or islands grows it instead of snapping it edge to edge.
    property real spanOpen: (root.form === "full" || root.form === "fit") ? 1 : 0
    Behavior on spanOpen { enabled: root._ready; MotionNumber { curve: "emphasizedDecel"; baseDuration: 350 } }
    onSpanOpenChanged: _relayout()
    readonly property real along: isVertical ? height : width
    readonly property real thickness: isVertical ? width : height

    // The pill's span along this bar when it sits inside it ([from, to] in
    // this item's coordinates, or null): centre groups make way (BarLayout).
    property var pillHole: null
    onPillHoleChanged: _relayout()

    // Body segments + islands in this item's coordinates: [{x, y, w, h, island, id}]
    property var bodyRects: []
    property var _targets: ({})
    // No springs until the layout has settled (modules load asynchronously and
    // change length for a few turns), so groups appear in place instead of
    // flying in from 0.
    property bool _ready: false
    // Hidden until then (see BarWindow.laidOut), then a short fade in.
    opacity: _ready ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(160) } }
    Timer { id: settle; interval: 250; onTriggered: root._ready = root.along > 0 }

    function _zoneSpacing(zone) { return zone === "start" ? root.leftSpacing : zone === "end" ? root.rightSpacing : root.centerSpacing }

    // Coalesced: lengths → target positions; live positions/separation → bodies.
    function _relayout() { Qt.callLater(root._doRelayout) }
    function _doRelayout() {
        const items = []
        for (let i = 0; i < groupRep.count; i++) {
            const it = groupRep.itemAt(i)
            if (it) items.push(it)
        }
        // Natural lengths (before any squeeze) and what each group can give.
        root._targets = BarLayout.place({ length: root.along, padding: root.edgePadding, spacing: root.groupSpacing,
            form: root.form, margin: root.edgeMargin, hole: root.pillHole },
            items.map(it => ({ id: it.gid, zone: it.zone, len: it.contentLen + Math.min(it.squeeze, it.flex), flex: it.flex })))
        const bodies = BarLayout.bodies({ length: root.along, padding: root.edgePadding, form: root.form,
            gap: root.groupGap, islandPad: root.islandPad, margin: root.edgeMargin, open: root.spanOpen },
            items.map(it => ({ id: it.gid, pos: it.pos, len: it.len, sep: Math.max(0, Math.min(1, it.sep)) })))
        root.bodyRects = bodies.map(b => root.isVertical
            ? { x: 0, y: b.pos, w: root.thickness, h: b.len, island: b.island, id: b.id ?? "", sep: b.sep ?? 0 }
            : { x: b.pos, y: 0, w: b.len, h: root.thickness, island: b.island, id: b.id ?? "", sep: b.sep ?? 0 })
        // Only a laid-out bar counts: before its window maps the length is 0,
        // and settling then would spring every group in from 0 once it maps.
        if (!root._ready && root.along > 0 && root.visible) settle.restart()
    }
    // ── Settings' bar preview (BarPreview) ───────────────────────────────
    // The module under (px, py), in this item's coordinates: { gid, id }.
    function previewHit(px, py) {
        for (let i = 0; i < groupRep.count; i++) {
            const g = groupRep.itemAt(i)
            if (!g || !g.visible || px < g.x || py < g.y || px > g.x + g.width || py > g.y + g.height) continue
            for (const m of g.moduleItems()) {
                const o = m.mapToItem(root, 0, 0)
                if (px >= o.x && py >= o.y && px <= o.x + m.width && py <= o.y + m.height) return { gid: g.gid, id: m.modelData }
            }
            return { gid: g.gid, id: "" }
        }
        return null
    }
    // A shown module's rect in this item's coordinates ({x, y, w, h}) or null.
    function previewModuleRect(gid, id) {
        for (let i = 0; i < groupRep.count; i++) {
            const g = groupRep.itemAt(i)
            if (!g || g.gid !== gid) continue
            for (const m of g.moduleItems()) if (m.modelData === id) {
                const o = m.mapToItem(root, 0, 0)
                return { x: o.x, y: o.y, w: m.width, h: m.height }
            }
        }
        return null
    }
    // Where a module dropped at (px, py) lands: { gid, before } with `before`
    // an index into that group's modules list (end zones run edge-inwards, so
    // their list is reversed on screen), or null off every group.
    function previewSlot(px, py) {
        const at = root.isVertical ? py : px
        let best = null, bestD = Infinity
        for (let i = 0; i < groupRep.count; i++) {
            const g = groupRep.itemAt(i)
            if (!g || !g.visible) continue
            const a = root.isVertical ? g.y : g.x, len = root.isVertical ? g.height : g.width
            const d = at < a ? a - at : at > a + len ? at - a - len : 0
            if (d < bestD) { bestD = d; best = g }
        }
        if (!best) return null
        // The first shown module past the pointer, by id (hidden modules —
        // weather without data — keep their place in the list).
        let next = ""
        for (const m of best.moduleItems()) {
            const o = m.mapToItem(root, 0, 0)
            if (at < (root.isVertical ? o.y + m.height / 2 : o.x + m.width / 2)) { next = m.modelData; break }
        }
        const list = best.mods
        if (best.zone === "end") // reversed on screen: left of `next` is after it in the list
            return { gid: best.gid, before: next ? list.indexOf(next) + 1 : 0 }
        return { gid: best.gid, before: next ? list.indexOf(next) : list.length }
    }

    onAlongChanged: _relayout()
    // Vertical bars get their width after their length: bodies laid out
    // before it were 0 wide (no background, groups centred on the edge).
    onThicknessChanged: _relayout()
    onFormChanged: _relayout()
    onGroupsChanged: _relayout()
    onEdgeMarginChanged: _relayout()

    Repeater {
        id: groupRep
        model: root.groups

        delegate: Item {
            id: grp
            required property var modelData
            required property int index
            readonly property string gid: modelData.id ?? `group${index}`
            readonly property string zone: ["start", "center", "end"].includes(modelData.zone) ? modelData.zone : "start"
            readonly property var mods: modelData.modules ?? []
            readonly property real contentLen: mods.length === 0 ? 0 : (root.isVertical ? content.implicitHeight : content.implicitWidth)
            readonly property real len: hiddenCenter ? 0 : contentLen
            // No room beside a pill in the bar: the centre steps aside (BarLayout $hideCenter).
            readonly property bool hiddenCenter: zone === "center" && !!root._targets.$hideCenter
            // Width the group is asked to give up, and how much its modules can
            // (modules with barFlex/barSqueeze: the window title).
            readonly property real squeeze: root._targets.$squeeze?.[gid] ?? 0
            property int _modRev: 0
            readonly property real flex: {
                void _modRev
                let f = 0
                for (let i = 0; i < modRep.count; i++) f += modRep.itemAt(i)?.item?.barFlex ?? 0
                return f
            }
            onFlexChanged: root._relayout()
            // The module loaders in on-screen order (BarPreview hit tests).
            function moduleItems() {
                const out = []
                for (let i = 0; i < modRep.count; i++) { const m = modRep.itemAt(i); if (m && m.visible && m.width > 0) out.push(m) }
                return out
            }

            // Along-axis position and separation (0 attached … 1 island).
            property real pos: root._targets[gid] ?? 0
            // No overshoot: a group at an end would slide past the bar's end.
            Behavior on pos { enabled: root._ready; MotionNumber { curve: "emphasizedDecel"; baseDuration: 350 } }
            property real sep: BarLayout.sepTarget(root.form, modelData)
            Behavior on sep { enabled: root._ready; MotionSpring { token: grp.sep < 0.5 ? "liquid" : "settle" } }
            onPosChanged: root._relayout()
            onSepChanged: root._relayout()
            onLenChanged: root._relayout()
            onContentLenChanged: root._relayout()
            Component.onCompleted: root._relayout()

            visible: len > 0
            x: root.isVertical ? 0 : pos
            y: root.isVertical ? pos : 0
            width: root.isVertical ? root.thickness : len
            height: root.isVertical ? len : root.thickness

            // Zone click/scroll catcher behind the modules. The centre takes
            // only the right button, so workspace buttons keep left clicks.
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                // The centre takes only the right button so workspace buttons keep left clicks.
                acceptedButtons: grp.zone === "center" ? Qt.RightButton : (Qt.LeftButton | Qt.RightButton)
                onWheel: event => {
                    const d = event.angleDelta.y
                    if (d !== 0) root.performScrollAction(grp.zone === "start" ? root.scrollLeftAction
                        : grp.zone === "end" ? root.scrollRightAction : root.scrollCenterAction, d > 0)
                }
                onClicked: event => {
                    if (event.button === Qt.RightButton) {
                        // Group menu; the centre's old right-click action stays first.
                        const e = []
                        if (grp.zone === "center" && root.centerClickAction !== "none")
                            e.push({ icon: "apps", text: root.centerClickAction === "overview" ? "Overview" : root.centerClickAction,
                                     run: () => root.performClickAction(root.centerClickAction) })
                        e.push({ icon: grp.modelData.attached === false ? "link" : "link_off",
                                 text: grp.modelData.attached === false ? "Attach group" : "Detach group",
                                 run: () => root.toggleAttached(grp.gid) })
                        e.push({ icon: "tune", text: "Customize bar…", run: () => root.openCustomize() })
                        groupMenu.entries = e
                        groupMenu.openAt(grp)
                    } else if (grp.zone !== "center") {
                        root.performClickAction(grp.zone === "start" ? root.leftClickAction : root.rightClickAction)
                    }
                }
            }

            BarGroup {
                id: content
                anchors.centerIn: parent
                vertical: root.isVertical
                padding: grp.zone === "center" ? root.centerGroupPadding : 0
                spacing: root._zoneSpacing(grp.zone)
                showBackground: grp.zone === "center" && root.showCenterBackground
                backgroundColor: Appearance?.colors.colLayer1 ?? "#E5E1EC"
                backgroundRadius: root.centerGroupRadius

                Repeater {
                    id: modRep
                    // End zones read from the bar's edge inwards, as before.
                    model: grp.zone === "end" ? grp.mods.slice().reverse() : grp.mods
                    Loader {
                        id: modLoader
                        required property string modelData
                        Layout.fillHeight: !root.isVertical
                        Layout.fillWidth: root.isVertical
                        Layout.alignment: root.isVertical ? Qt.AlignHCenter : Qt.AlignVCenter
                        sourceComponent: BarModuleLoader.getModule(modelData)
                        onLoaded: { root._place(item, grp.zone === "start" ? "left" : grp.zone === "end" ? "right" : "center"); grp._modRev++ }
                        // ponytail: every flexible module in the group gets the whole squeeze; fine while the title is the only one.
                        Binding { when: !!modLoader.item && modLoader.item.hasOwnProperty("barSqueeze"); target: modLoader.item; property: "barSqueeze"; value: grp.squeeze }
                    }
                }
            }

            // Optional hairline between this group and the next one.
            Rectangle {
                visible: root.showSeparators && grp.zone !== "end" && grp.sep < 0.02
                color: Appearance?.colors.colOutlineVariant ?? "#C4C7C5"
                opacity: 0.3
                width: root.isVertical ? parent.width * 0.4 : 1
                height: root.isVertical ? 1 : parent.height * 0.4
                x: root.isVertical ? (parent.width - width) / 2 : parent.width + 4
                y: root.isVertical ? parent.height + 4 : (parent.height - height) / 2
            }
        }
    }
}
