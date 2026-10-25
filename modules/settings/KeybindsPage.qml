import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "."

/**
 * Keybinds — ano's one keybind set (anod `keybinds.*`, docs/keybinds.md):
 * search, add, change (press the new chord), remove, reset. A chord already
 * in use asks Replace or Cancel. Changes apply live once the binds are
 * migrated (ano keybinds migrate); before that they are saved but unused.
 */
ColumnLayout {
    id: root
    spacing: 16

    property var binds: []
    property var overrides: ({ binds: [], remove: [] })
    property var catalogue: ({})
    property bool migrated: false
    property bool loaded: false
    property string query: ""
    property string message: ""
    // The bind being edited: { origChord, chord, action, argText, native, args, submap } or null.
    property var editing: null
    property string conflict: ""
    property bool confirmReset: false

    readonly property string comp: CompositorService.compositor === "niri" ? "niri" : "hyprland"
    readonly property var actionIds: Object.keys(root.catalogue).sort((a, b) => root.catalogue[a].label.localeCompare(root.catalogue[b].label))
    readonly property var changed: {
        const s = {}
        for (const b of root.overrides?.binds ?? []) s[b.chord] = true
        for (const c of root.overrides?.remove ?? []) s[c] = true
        return s
    }
    readonly property var shown: {
        const q = root.query.trim().toLowerCase()
        return root.binds.filter(b => !b.submap && (q === "" || b.chord.toLowerCase().includes(q) || b.label.toLowerCase().includes(q)
            || (root.catalogue[b.action]?.label ?? "").toLowerCase().includes(q)))
    }

    function reload() {
        if (!Anod.available) return
        Anod.call("keybinds.catalogue", {}, (r, e) => { if (r) root.catalogue = r })
        Anod.call("keybinds.list", {}, (r, e) => {
            if (e) { root.message = e.message; return }
            root.binds = r.binds ?? []
            root.overrides = r.overrides ?? { binds: [], remove: [] }
            root.migrated = r.migrated ?? false
            root.loaded = true
        })
    }
    Component.onCompleted: reload()
    Connections {
        target: Anod
        function onAvailableChanged() { root.reload() }
    }

    function edit(b) {
        root.conflict = ""
        const native = b ? (b.action === "hyprland" || b.action === "niri") : false
        root.editing = {
            origChord: b?.chord ?? "", chord: b?.chord ?? "", action: b?.action ?? "exec",
            argText: b && !native ? (b.action === "exec" ? (b.args?.[0] ?? "") : (b.args ?? []).join(" ")) : "",
            native: native, args: b?.args ?? [], only: b?.only ?? "", raw: b?.raw ?? false,
            // Kept as they are: Hyprland options (mouse, repeating…), niri properties, lock-screen use.
            hyprland: b?.hyprland ?? null, niri: b?.niri ?? null, locked: b?.locked ?? false
        }
    }

    function save(replace) {
        const e = root.editing
        if (!e || e.chord === "") return
        // A Lua-function bind carries its chord in its own text: it can't move.
        if (e.raw && e.origChord !== "" && e.chord !== e.origChord) { root.conflict = ""; root.message = "A Lua-function bind can't change its chord here; edit it in keybinds.json"; return }
        let bind
        if (e.native) {
            bind = { action: e.action, args: e.args, only: e.only, raw: e.raw }
        } else {
            const spec = root.catalogue[e.action]?.arg ?? ""
            const args = spec === "" ? [] : e.action === "exec" ? [e.argText.trim()] : e.argText.trim().split(/\s+/).filter(x => x)
            bind = { action: e.action, args: args }
        }
        if (e.hyprland) bind.hyprland = e.hyprland
        if (e.niri) bind.niri = e.niri
        if (e.locked) bind.locked = true
        const moving = e.origChord !== "" && e.origChord !== e.chord
        Anod.call("keybinds.set", { chord: e.chord, bind: bind, replace: replace || (e.origChord === e.chord) }, (r, err) => {
            if (err?.code === "conflict") { root.conflict = err.message; return }
            if (err) { root.message = err.message; return }
            const done = () => { root.editing = null; root.conflict = ""; root.reload() }
            if (moving) Anod.call("keybinds.set", { chord: e.origChord, bind: null }, done)
            else done()
        })
    }

    function remove(chord) { Anod.call("keybinds.set", { chord: chord, bind: null }, () => root.reload()) }
    function reset(chord) { Anod.call("keybinds.reset", { chord: chord }, () => root.reload()) }

    // A key press → "Super+Shift+Left" (niri/xkb key names, as anod stores them).
    function chordFrom(event) {
        const k = event.key
        if ([Qt.Key_Shift, Qt.Key_Control, Qt.Key_Alt, Qt.Key_Meta, Qt.Key_Super_L, Qt.Key_Super_R, Qt.Key_AltGr].includes(k)) return ""
        const named = {
            [Qt.Key_Return]: "Return", [Qt.Key_Enter]: "Return", [Qt.Key_Tab]: "Tab", [Qt.Key_Backtab]: "Tab",
            [Qt.Key_Space]: "Space", [Qt.Key_Left]: "Left", [Qt.Key_Right]: "Right", [Qt.Key_Up]: "Up", [Qt.Key_Down]: "Down",
            [Qt.Key_Comma]: "Comma", [Qt.Key_Period]: "Period", [Qt.Key_Slash]: "Slash", [Qt.Key_Minus]: "Minus",
            [Qt.Key_Equal]: "Equal", [Qt.Key_Semicolon]: "Semicolon", [Qt.Key_Apostrophe]: "Apostrophe",
            [Qt.Key_BracketLeft]: "BracketLeft", [Qt.Key_BracketRight]: "BracketRight", [Qt.Key_Backslash]: "Backslash",
            [Qt.Key_QuoteLeft]: "Grave", [Qt.Key_Delete]: "Delete", [Qt.Key_Backspace]: "BackSpace", [Qt.Key_Home]: "Home",
            [Qt.Key_End]: "End", [Qt.Key_PageUp]: "Page_Up", [Qt.Key_PageDown]: "Page_Down", [Qt.Key_Print]: "Print",
            [Qt.Key_Escape]: "Escape", [Qt.Key_Insert]: "Insert"
        }
        let key = named[k] ?? ""
        if (!key && k >= Qt.Key_A && k <= Qt.Key_Z) key = String.fromCharCode(k)
        if (!key && k >= Qt.Key_0 && k <= Qt.Key_9) key = String.fromCharCode(k)
        if (!key && k >= Qt.Key_F1 && k <= Qt.Key_F24) key = "F" + (k - Qt.Key_F1 + 1)
        if (!key) return ""
        const m = event.modifiers
        const mods = []
        if (m & Qt.MetaModifier) mods.push("Super")
        if (m & Qt.ControlModifier) mods.push("Ctrl")
        if (m & Qt.AltModifier) mods.push("Alt")
        if (m & Qt.ShiftModifier) mods.push("Shift")
        return mods.concat([key]).join("+")
    }

    SettingsPageHeader {
        title: "Keybinds"
        subtitle: "Keyboard layouts, and one set of keybinds for Hyprland and niri · search, add, change, remove, reset"
        configRoots: ["keyboard"]
    }

    KeyboardLayoutsCard {}

    NoticeBox {
        Layout.fillWidth: true
        visible: !Anod.available
        level: "warning"
        text: "Keybinds are kept by anod, which isn't running. Run `ano doctor`."
    }
    NoticeBox {
        Layout.fillWidth: true
        visible: Anod.available && root.loaded && !root.migrated
        text: "Your compositor configs still have their own binds, so changes here are saved but not used yet. Run `ano keybinds migrate` (backs up first; `--revert` undoes it). See docs/keybinds.md."
    }
    NoticeBox {
        Layout.fillWidth: true
        visible: root.message !== ""
        level: "error"
        text: root.message
    }
    NoticeBox {
        Layout.fillWidth: true
        visible: Anod.available && !root.loaded && root.message === ""
        iconName: "progress_activity"
        text: "Reading your keybinds…"
    }

    SettingsCard {
        icon: "keyboard"
        title: "Keybinds"
        subtitle: `${root.binds.length} binds · ${Object.keys(root.changed).length} changed by you`
        collapsible: false

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            ConfigTextInput {
                Layout.fillWidth: true
                placeholderText: "Search by chord or action…"
                text: root.query
                onTextChanged: root.query = text
                iconAction: text.length > 0 ? "close" : "search"
                onIconClicked: { if (text.length > 0) text = "" }
            }
            RippleButton {
                buttonText: "Add"
                onClicked: root.edit(null)
            }
        }

        // ── Editor ──────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            visible: root.editing !== null
            implicitHeight: editorCol.implicitHeight + 24
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer2
            ColumnLayout {
                id: editorCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                spacing: 8

                StyledText {
                    text: root.editing?.origChord ? `Change ${root.editing.origChord}` : "New bind"
                    font.weight: Font.DemiBold
                }
                // Press the chord here (or type it, e.g. Super+Shift+D).
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Rectangle {
                        id: capture
                        Layout.preferredWidth: 220
                        implicitHeight: 36
                        radius: Appearance.rounding.small
                        color: capture.activeFocus ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer3
                        focus: false
                        activeFocusOnTab: true
                        StyledText {
                            anchors.centerIn: parent
                            text: capture.activeFocus ? "Press the keys…" : (root.editing?.chord || "Click, then press the keys")
                            color: capture.activeFocus ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer3
                        }
                        MouseArea { anchors.fill: parent; onClicked: capture.forceActiveFocus() }
                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Escape && event.modifiers === Qt.NoModifier) { capture.focus = false; event.accepted = true; return }
                            const c = root.chordFrom(event)
                            if (c !== "") {
                                root.editing = Object.assign({}, root.editing, { chord: c })
                                root.conflict = ""
                                capture.focus = false
                            }
                            event.accepted = true
                        }
                    }
                    ConfigTextInput {
                        Layout.fillWidth: true
                        placeholderText: "or type: Super+Shift+D"
                        text: root.editing?.chord ?? ""
                        onEditingFinished: if (root.editing) root.editing = Object.assign({}, root.editing, { chord: text.trim() })
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: root.editing?.native ?? false
                    wrapMode: Text.Wrap
                    color: Appearance.colors.colSubtext
                    text: `${root.editing?.action === "niri" ? "niri" : "Hyprland"}-only action (kept as is): ${(root.editing?.args ?? [])[0] ?? ""}`
                }
                Flow {
                    Layout.fillWidth: true
                    visible: !(root.editing?.native ?? false)
                    spacing: 6
                    Repeater {
                        model: root.actionIds
                        delegate: RippleButton {
                            required property string modelData
                            toggled: root.editing?.action === modelData
                            buttonText: root.catalogue[modelData]?.label ?? modelData
                            onClicked: root.editing = Object.assign({}, root.editing, { action: modelData })
                        }
                    }
                }
                ConfigTextInput {
                    Layout.fillWidth: true
                    visible: !(root.editing?.native ?? false) && (root.catalogue[root.editing?.action]?.arg ?? "") !== ""
                    placeholderText: root.catalogue[root.editing?.action]?.arg ?? ""
                    text: root.editing?.argText ?? ""
                    onTextChanged: if (root.editing && root.editing.argText !== text) root.editing = Object.assign({}, root.editing, { argText: text })
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: root.conflict !== ""
                    wrapMode: Text.Wrap
                    color: Appearance.m3colors.m3error
                    text: `${root.editing?.chord} is ${root.conflict}`
                }
                RowLayout {
                    spacing: 8
                    RippleButton {
                        visible: root.conflict === ""
                        enabled: (root.editing?.chord ?? "") !== ""
                        buttonText: "Save"
                        onClicked: root.save(false)
                    }
                    RippleButton {
                        visible: root.conflict !== ""
                        buttonText: "Replace"
                        onClicked: root.save(true)
                    }
                    RippleButton {
                        buttonText: "Cancel"
                        onClicked: { root.editing = null; root.conflict = "" }
                    }
                }
            }
        }

        // ── The list ───────────────────────────────────────────────
        Repeater {
            model: root.shown
            delegate: RowLayout {
                id: row
                required property var modelData
                readonly property bool here: root.comp === "niri" ? modelData.onNiri : modelData.onHyprland
                Layout.fillWidth: true
                spacing: 10
                opacity: here ? 1 : 0.55

                Row {
                    Layout.preferredWidth: 230
                    spacing: 3
                    Repeater {
                        model: row.modelData.chord.split("+")
                        delegate: KeyboardKey { required property string modelData; keyText: modelData }
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: (root.catalogue[row.modelData.action]?.label ?? "") + (row.modelData.args?.length && !row.modelData.raw
                        ? (root.catalogue[row.modelData.action] ? ": " : "") + row.modelData.args.join(" ") : (row.modelData.raw ? "Lua function" : ""))
                }
                StyledText {
                    visible: !row.here || row.modelData.onHyprland !== row.modelData.onNiri
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    text: !row.here ? `not available on ${root.comp}` : (row.modelData.onHyprland ? "Hyprland only" : "niri only")
                }
                StyledText {
                    visible: root.changed[row.modelData.chord] ?? false
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colPrimary
                    text: "changed"
                }
                RippleButton {
                    implicitWidth: 32; implicitHeight: 32
                    contentItem: MaterialSymbol { text: "edit"; iconSize: 18; horizontalAlignment: Text.AlignHCenter }
                    onClicked: root.edit(row.modelData)
                }
                RippleButton {
                    implicitWidth: 32; implicitHeight: 32
                    contentItem: MaterialSymbol { text: "delete"; iconSize: 18; horizontalAlignment: Text.AlignHCenter }
                    onClicked: root.remove(row.modelData.chord)
                }
                RippleButton {
                    implicitWidth: 32; implicitHeight: 32
                    visible: root.changed[row.modelData.chord] ?? false
                    contentItem: MaterialSymbol { text: "restart_alt"; iconSize: 18; horizontalAlignment: Text.AlignHCenter }
                    onClicked: root.reset(row.modelData.chord)
                }
            }
        }
        StyledText {
            visible: root.loaded && root.shown.length === 0
            color: Appearance.colors.colSubtext
            text: "No bind matches."
        }

        // Removed defaults can come back one by one.
        Flow {
            Layout.fillWidth: true
            visible: (root.overrides?.remove ?? []).length > 0
            spacing: 6
            StyledText { text: "Removed:"; color: Appearance.colors.colSubtext; height: 32; verticalAlignment: Text.AlignVCenter }
            Repeater {
                model: root.overrides?.remove ?? []
                delegate: RippleButton {
                    required property string modelData
                    buttonText: "↺ " + modelData
                    onClicked: root.reset(modelData)
                }
            }
        }
    }

    SettingsCard {
        icon: "restart_alt"
        title: "Reset"
        subtitle: "Back to the shipped keybinds"
        RowLayout {
            spacing: 8
            RippleButton {
                visible: !root.confirmReset
                enabled: Object.keys(root.changed).length > 0
                buttonText: "Reset all to defaults"
                onClicked: root.confirmReset = true
            }
            RippleButton {
                visible: root.confirmReset
                buttonText: `Reset ${Object.keys(root.changed).length} change(s)`
                onClicked: { root.confirmReset = false; root.reset("") }
            }
            RippleButton {
                visible: root.confirmReset
                buttonText: "Cancel"
                onClicked: root.confirmReset = false
            }
        }
    }
}
