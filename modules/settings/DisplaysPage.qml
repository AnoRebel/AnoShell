import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "."

/**
 * Displays — arrangement (drag), mode, scale, rotation, VRR and on/off per
 * monitor, profiles, and the cursor; through anod (`display.*`, `cursor.*`)
 * on Hyprland and niri. Risky changes ask "Keep these display settings?"
 * and go back on their own after 15 s (DisplayConfirm).
 */
ColumnLayout {
    id: root
    spacing: 16

    property var outputs: []      // as anod reports them
    property var edited: []       // the working copy
    property var profiles: []
    property int selected: 0
    property string message: ""
    property string profileName: ""
    property bool included: true   // the compositor config includes anod's managed file
    readonly property var sel: root.edited[root.selected] ?? null
    readonly property bool dirty: JSON.stringify(root.edited) !== JSON.stringify(root.outputs)

    function reload() {
        if (!Anod.available) return
        Anod.call("display.get", {}, (r, e) => {
            if (e) { root.message = e.message; return }
            root.outputs = r.outputs ?? []
            root.edited = JSON.parse(JSON.stringify(root.outputs))
            root.profiles = r.profiles ?? []
            root.included = r.included ?? true
            root.selected = Math.min(root.selected, Math.max(0, root.edited.length - 1))
        })
    }
    Component.onCompleted: reload()
    Connections {
        target: Anod
        function onAvailableChanged() { root.reload() }
        function onEvent(name, data) { if (name.startsWith("display_")) root.reload() }
    }

    function set(field, value) {
        const e = JSON.parse(JSON.stringify(root.edited))
        e[root.selected][field] = value
        root.edited = e
    }
    function setMode(m) {
        const r = m.match(/^(\d+)x(\d+)@([\d.]+)/)
        if (!r) return
        const e = JSON.parse(JSON.stringify(root.edited))
        Object.assign(e[root.selected], { width: +r[1], height: +r[2], refresh: +r[3] })
        root.edited = e
    }
    function logicalW(o) { return Math.round((o.transform % 2 ? o.height : o.width) / (o.scale || 1)) }
    function logicalH(o) { return Math.round((o.transform % 2 ? o.width : o.height) / (o.scale || 1)) }

    function apply(outs) {
        // Positions start at 0,0 (dragging can leave them anywhere).
        const on = outs.filter(o => o.enabled)
        const minX = Math.min(...on.map(o => o.x)), minY = Math.min(...on.map(o => o.y))
        const norm = outs.map(o => Object.assign({}, o, { x: o.x - (isFinite(minX) ? minX : 0), y: o.y - (isFinite(minY) ? minY : 0) }))
        Anod.call("display.apply", { outputs: norm }, (r, e) => {
            root.message = e ? e.message : ""
            root.reload()
        })
    }

    SettingsPageHeader {
        title: "Displays"
        subtitle: "Arrangement, mode, scale, rotation, VRR, profiles and the cursor"
        configRoots: ["cursor"]
    }
    NoticeBox {
        Layout.fillWidth: true
        visible: !Anod.available
        level: "warning"
        text: "Displays are set through anod, which isn't running. Run `ano doctor`."
    }
    NoticeBox {
        Layout.fillWidth: true
        visible: Anod.available && !root.included
        text: "Changes apply now, but your compositor config doesn't load AnoShell's managed file yet, so they reset when the compositor restarts. `ano keybinds migrate` adds the include line (with a backup; --revert undoes it)."
    }
    NoticeBox {
        Layout.fillWidth: true
        visible: root.message !== ""
        level: "error"
        text: root.message
    }

    SettingsCard {
        icon: "desktop_windows"
        title: "Arrangement"
        subtitle: "Drag a monitor to move it; click one to change it"
        visible: root.edited.length > 0
        collapsible: false

        // The monitors to scale; snapped to the others' edges on release.
        Item {
            id: canvas
            Layout.fillWidth: true
            Layout.preferredHeight: 220
            readonly property var on: root.edited.map((o, i) => ({ o: o, i: i })).filter(x => x.o.enabled)
            readonly property real minX: Math.min(0, ...on.map(x => x.o.x))
            readonly property real minY: Math.min(0, ...on.map(x => x.o.y))
            readonly property real spanW: Math.max(1, ...on.map(x => x.o.x + root.logicalW(x.o))) - minX
            readonly property real spanH: Math.max(1, ...on.map(x => x.o.y + root.logicalH(x.o))) - minY
            readonly property real k: Math.min((width - 40) / (spanW * 1.6), (height - 20) / (spanH * 1.3))

            Repeater {
                model: canvas.on
                delegate: Rectangle {
                    id: mon
                    required property var modelData
                    readonly property var o: modelData.o
                    x: 20 + (o.x - canvas.minX) * canvas.k
                    y: 10 + (o.y - canvas.minY) * canvas.k
                    width: root.logicalW(o) * canvas.k
                    height: root.logicalH(o) * canvas.k
                    radius: Appearance.rounding.small
                    color: root.selected === modelData.i ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2
                    border.width: 2
                    border.color: root.selected === modelData.i ? Appearance.colors.colPrimary : Appearance.colors.colLayer0Border
                    StyledText {
                        anchors.centerIn: parent
                        text: mon.o.name
                        font.weight: Font.DemiBold
                        color: root.selected === mon.modelData.i ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                    }
                    MouseArea {
                        anchors.fill: parent
                        drag.target: canvas.on.length > 1 ? mon : null
                        cursorShape: Qt.PointingHandCursor
                        onPressed: root.selected = mon.modelData.i
                        onReleased: {
                            if (canvas.on.length < 2) return
                            let nx = Math.round((mon.x - 20) / canvas.k + canvas.minX)
                            let ny = Math.round((mon.y - 10) / canvas.k + canvas.minY)
                            // Snap to the nearest edge of another monitor (within 15% of it).
                            const w = root.logicalW(mon.o), h = root.logicalH(mon.o)
                            for (const x of canvas.on) {
                                if (x.i === mon.modelData.i) continue
                                const ow = root.logicalW(x.o), oh = root.logicalH(x.o), t = Math.max(ow, oh) * 0.15
                                for (const c of [x.o.x - w, x.o.x + ow, x.o.x]) if (Math.abs(nx - c) < t) nx = c
                                for (const c of [x.o.y - h, x.o.y + oh, x.o.y]) if (Math.abs(ny - c) < t) ny = c
                            }
                            const e = JSON.parse(JSON.stringify(root.edited))
                            e[mon.modelData.i].x = nx
                            e[mon.modelData.i].y = ny
                            root.edited = e
                        }
                    }
                }
            }
        }

        // ── The selected monitor ──────────────────────────────────
        StyledText {
            visible: root.sel !== null
            text: root.sel ? `${root.sel.name} · ${root.sel.make} ${root.sel.model}`.trim() : ""
            font.weight: Font.DemiBold
        }
        ConfigSwitch {
            visible: root.sel !== null && root.edited.length > 1
            label: "On"
            checked: root.sel?.enabled ?? true
            onCheckedChanged: if (root.sel && checked !== root.sel.enabled) root.set("enabled", checked)
        }
        ConfigRow {
            visible: root.sel !== null && (root.sel?.modes ?? []).length > 0
            label: "Mode"
            sublabel: root.sel ? `${root.sel.width}×${root.sel.height} @ ${(+root.sel.refresh).toFixed(2)} Hz` : ""
            Flow {
                Layout.fillWidth: true
                spacing: 4
                Repeater {
                    model: (root.sel?.modes ?? []).slice(0, 16)
                    delegate: RippleButton {
                        required property string modelData
                        toggled: root.sel && modelData.startsWith(`${root.sel.width}x${root.sel.height}@`) && Math.abs(parseFloat(modelData.split("@")[1]) - root.sel.refresh) < 0.5
                        buttonText: modelData.replace(/@([\d.]+)$/, (_, r) => ` @ ${Math.round(+r)}`)
                        onClicked: root.setMode(modelData)
                    }
                }
            }
        }
        ConfigRow {
            visible: root.sel !== null
            label: "Scale"
            ChoiceRow {
                compact: false
                model: [1, 1.25, 1.5, 1.75, 2].map(v => ({ value: v, label: `${v}×` }))
                current: root.sel?.scale ?? 1
                onChose: value => root.set("scale", value)
            }
        }
        ConfigRow {
            visible: root.sel !== null
            label: "Rotation"
            ChoiceRow {
                compact: false
                model: [{ value: 0, label: "None" }, { value: 1, label: "90°" }, { value: 2, label: "180°" }, { value: 3, label: "270°" }]
                current: (root.sel?.transform ?? 0) % 4
                onChose: value => root.set("transform", value)
            }
        }
        ConfigSwitch {
            visible: root.sel !== null
            label: "Variable refresh rate"
            sublabel: "Adaptive sync, where the monitor supports it"
            checked: root.sel?.vrr ?? false
            onCheckedChanged: if (root.sel && checked !== root.sel.vrr) root.set("vrr", checked)
        }
        RowLayout {
            spacing: 8
            RippleButton {
                enabled: root.dirty
                toggled: root.dirty
                buttonText: "Apply"
                onClicked: root.apply(root.edited)
            }
            RippleButton {
                enabled: root.dirty
                buttonText: "Undo changes"
                onClicked: root.edited = JSON.parse(JSON.stringify(root.outputs))
            }
        }
    }

    SettingsCard {
        icon: "bookmarks"
        title: "Profiles"
        subtitle: "Saved arrangements; the one saved for the monitors you plug in applies by itself"
        visible: Anod.available

        Repeater {
            model: root.profiles
            delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: 8
                StyledText { text: modelData.name; font.weight: Font.DemiBold }
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    color: Appearance.colors.colSubtext
                    text: (modelData.outputs ?? []).map(o => o.enabled ? `${o.name} ${o.width}×${o.height} ${o.scale}×` : `${o.name} off`).join(" · ")
                }
                RippleButton { buttonText: "Apply"; onClicked: root.apply(modelData.outputs) }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            ConfigTextInput {
                Layout.fillWidth: true
                placeholderText: "Name for the current arrangement (e.g. Desk)"
                text: root.profileName
                onTextChanged: root.profileName = text
            }
            RippleButton {
                enabled: root.profileName.trim() !== ""
                buttonText: "Save"
                onClicked: Anod.call("display.saveProfile", { name: root.profileName.trim() }, (r, e) => {
                    root.message = e ? e.message : ""
                    root.profileName = ""
                    root.reload()
                })
            }
        }
    }

    CursorCard {}
}
