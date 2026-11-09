import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "."

/**
 * Settings → Actions: macros (services/Actions.qml). Add, rename, reorder,
 * delete, run now; each step's fields come from its kind in Actions.kinds.
 * The first 8 are on the ring (Super+Ctrl+X).
 *
 * Repeaters count (model: n) rather than take the list itself: every edit
 * writes a new list, and a list model would rebuild the rows under the
 * control being used.
 */
ColumnLayout {
    id: root
    spacing: 16

    readonly property var macros: Actions.macros
    property int selected: -1
    readonly property var current: root.macros[root.selected] ?? null
    property string message: ""

    readonly property var icons: ["bolt", "work", "code", "sports_esports", "videocam", "music_note", "headphones",
        "bedtime", "self_improvement", "coffee", "brush", "call", "school", "home", "flight", "movie"]

    Component.onCompleted: Actions.loadPresets()

    function clone() { return JSON.parse(JSON.stringify(root.macros)) }
    function uniqueName(base) {
        let name = base, n = 2
        while (root.macros.some(m => m.name === name)) name = `${base} ${n++}`
        return name
    }
    function add() {
        const list = root.clone()
        list.push({ name: root.uniqueName("New action"), icon: "bolt", steps: [] })
        Actions.write(list)
        root.selected = list.length - 1
    }
    function remove(i) {
        const list = root.clone()
        list.splice(i, 1)
        Actions.write(list)
        root.selected = root.selected === i ? -1 : root.selected > i ? root.selected - 1 : root.selected
    }
    function move(i, d) {
        const list = root.clone(), j = i + d
        if (j < 0 || j >= list.length) return
        const t = list[i]; list[i] = list[j]; list[j] = t
        Actions.write(list)
        if (root.selected === i) root.selected = j
        else if (root.selected === j) root.selected = i
    }
    function setMacro(key, value) {
        const list = root.clone()
        if (!list[root.selected] || JSON.stringify(list[root.selected][key]) === JSON.stringify(value)) return
        list[root.selected][key] = value
        Actions.write(list)
    }
    function rename(text) {
        const name = text.trim()
        if (!name || name === root.current?.name) return
        if (root.macros.some(m => m.name === name)) { root.message = `There is already an action called "${name}".`; return }
        root.message = ""
        root.setMacro("name", name)
    }
    // steps: edit a copy of the selected macro's steps and write it back.
    function editSteps(fn) {
        const list = root.clone()
        const m = list[root.selected]
        if (!m) return
        m.steps = Array.from(m.steps ?? [])
        if (fn(m.steps) === false) return
        Actions.write(list)
    }
    function setField(si, key, value) {
        root.editSteps(steps => {
            if (!steps[si] || JSON.stringify(steps[si][key]) === JSON.stringify(value)) return false
            steps[si][key] = value
        })
    }
    function runNow(name) {
        const r = Actions.run(name)
        root.message = r === "queued" ? `"${name}" will run after "${Actions.running}".` : r ? `Running "${name}".` : ""
    }

    SettingsPageHeader {
        title: "Actions"
        subtitle: "Macros: a few steps run one after another, from the ring (Super+Ctrl+X), a key or IPC"
        configRoots: ["actions"]
    }

    SettingsCard {
        icon: "bolt"
        title: "Your actions"
        subtitle: root.macros.length > Actions.ringSize ? `The first ${Actions.ringSize} are on the ring; the rest run by name` : "In ring order"
        configKeys: ["actions", "actions.macros"]

        EmptyState {
            Layout.fillWidth: true
            Layout.topMargin: 8; Layout.bottomMargin: 8
            visible: root.macros.length === 0
            icon: "bolt"
            title: "No actions yet"
            hint: "An action is a list of steps: open apps, set the volume, change the wallpaper, wait, run a command…"
            actionText: "New action"
            onAction: root.add()
        }

        Repeater {
            model: root.macros.length
            RippleButton {
                id: row
                required property int index
                readonly property var macro: root.macros[index] ?? ({})
                Layout.fillWidth: true
                implicitHeight: 44
                toggled: root.selected === index
                colBackgroundToggled: Appearance.colors.colSecondaryContainer
                colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                onClicked: root.selected = root.selected === index ? -1 : index
                contentItem: RowLayout {
                    spacing: 6
                    StyledText {
                        Layout.leftMargin: 8
                        Layout.preferredWidth: 16
                        text: row.index < Actions.ringSize ? `${row.index + 1}` : ""
                        color: Appearance.colors.colSubtext
                    }
                    MaterialSymbol { text: row.macro.icon || "bolt"; iconSize: 20 }
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 0
                        StyledText { text: row.macro.name ?? ""; elide: Text.ElideRight; Layout.fillWidth: true }
                        StyledText {
                            readonly property int n: Array.from(row.macro.steps ?? []).length
                            text: Actions.running === row.macro.name ? "Running…" : n === 0 ? "No steps" : n === 1 ? "1 step" : `${n} steps`
                            color: Actions.running === row.macro.name ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.smallest
                        }
                    }
                    RowButton { icon: "play_arrow"; tip: "Run now"; onClicked: root.runNow(row.macro.name) }
                    RowButton { icon: "arrow_upward"; tip: "Move up"; enabled: row.index > 0; onClicked: root.move(row.index, -1) }
                    RowButton { icon: "arrow_downward"; tip: "Move down"; enabled: row.index < root.macros.length - 1; onClicked: root.move(row.index, 1) }
                    RowButton { icon: "delete"; tip: "Delete"; Layout.rightMargin: 4; onClicked: root.remove(row.index) }
                }
            }
        }

        RippleButtonWithIcon {
            visible: root.macros.length > 0
            iconName: "add"
            buttonText: "New action"
            onClicked: root.add()
        }

        StyledText {
            visible: root.message.length > 0
            Layout.fillWidth: true; wrapMode: Text.Wrap
            text: root.message
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
    }

    SettingsCard {
        visible: root.current !== null
        icon: root.current?.icon || "bolt"
        title: root.current ? `Edit "${root.current.name}"` : ""
        subtitle: "Steps run top to bottom; one that fails stops the rest and tells you which"
        configKeys: []

        ConfigRow {
            label: "Name"
            ConfigTextInput {
                Layout.preferredWidth: 260
                text: root.current?.name ?? ""
                validator: t => t.trim() !== root.current?.name && root.macros.some(m => m.name === t.trim()) ? "That name is taken" : ""
                onEditingFinished: root.rename(text)
            }
        }
        StyledText { text: "Icon"; font.pixelSize: Appearance.font.pixelSize.small }
        ChoiceRow {
            Layout.fillWidth: true
            compact: true
            model: root.icons.map(i => ({ value: i, label: i, icon: i }))
            current: root.current?.icon ?? "bolt"
            onChose: v => root.setMacro("icon", v)
        }

        StyledText {
            Layout.topMargin: 8
            text: "Steps"
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.DemiBold
        }
        StyledText {
            visible: Array.from(root.current?.steps ?? []).length === 0
            Layout.fillWidth: true; wrapMode: Text.Wrap
            text: "No steps yet: add one below."
            color: Appearance.colors.colSubtext
        }

        Repeater {
            model: Array.from(root.current?.steps ?? []).length
            Rectangle {
                id: stepBox
                required property int index
                readonly property var step: Array.from(root.current?.steps ?? [])[index] ?? ({})
                readonly property var kind: Actions.kindOf(step)
                Layout.fillWidth: true
                implicitHeight: stepCol.implicitHeight + 16
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2
                ColumnLayout {
                    id: stepCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                    spacing: 6
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        StyledText { text: `${stepBox.index + 1}`; color: Appearance.colors.colSubtext; Layout.preferredWidth: 16 }
                        MaterialSymbol { text: stepBox.kind?.icon ?? "help"; iconSize: 18 }
                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: `${stepBox.kind?.label ?? "Unknown step"} · ${Actions.describe(stepBox.step)}`
                        }
                        RowButton { icon: "arrow_upward"; tip: "Move up"; enabled: stepBox.index > 0
                            onClicked: root.editSteps(s => { const t = s[stepBox.index]; s[stepBox.index] = s[stepBox.index - 1]; s[stepBox.index - 1] = t }) }
                        RowButton { icon: "arrow_downward"; tip: "Move down"; enabled: stepBox.index < Array.from(root.current?.steps ?? []).length - 1
                            onClicked: root.editSteps(s => { const t = s[stepBox.index]; s[stepBox.index] = s[stepBox.index + 1]; s[stepBox.index + 1] = t }) }
                        RowButton { icon: "close"; tip: "Remove"; onClicked: root.editSteps(s => { s.splice(stepBox.index, 1) }) }
                    }
                    Repeater {
                        model: stepBox.kind?.fields?.length ?? 0
                        FieldEditor {
                            required property int index
                            Layout.fillWidth: true
                            stepIndex: stepBox.index
                            step: stepBox.step
                            field: stepBox.kind.fields[index]
                        }
                    }
                }
            }
        }

        StyledText { Layout.topMargin: 4; text: "Add a step"; font.pixelSize: Appearance.font.pixelSize.small }
        ChoiceRow {
            Layout.fillWidth: true
            model: Actions.order.map(t => ({ value: t, label: Actions.kinds[t].label, icon: Actions.kinds[t].icon }))
            onChose: t => root.editSteps(s => { s.push(Actions.kinds[t].fresh()) })
        }

        RippleButtonWithIcon {
            Layout.topMargin: 4
            iconName: "play_arrow"
            buttonText: "Run now"
            enabled: Array.from(root.current?.steps ?? []).length > 0
            onClicked: root.runNow(root.current.name)
        }
    }

    // A small round icon button for the rows.
    component RowButton: RippleButton {
        id: rb
        property string icon: ""
        property string tip: ""
        implicitWidth: 30; implicitHeight: 30; buttonRadius: 15
        contentItem: MaterialSymbol { text: rb.icon; iconSize: 18; horizontalAlignment: Text.AlignHCenter }
        StyledToolTip { text: rb.tip }
    }

    // One field of a step, drawn by its type (Actions.kinds[…].fields).
    component FieldEditor: ColumnLayout {
        id: fe
        property int stepIndex: 0
        property var step: ({})
        property var field: ({})
        readonly property var value: fe.step[fe.field.key]
        spacing: 4

        // text · app · seconds · snapshot: a line of text
        ConfigRow {
            visible: ["text", "app", "seconds", "snapshot"].includes(fe.field.type)
            label: fe.field.label ?? ""
            ConfigTextInput {
                id: textIn
                Layout.preferredWidth: 300
                placeholderText: fe.field.placeholder ?? ""
                text: fe.value === undefined || fe.value === null ? "" : String(fe.value)
                validator: fe.field.type === "seconds" ? (t => isNaN(Number(t)) || Number(t) < 0 ? "A number of seconds" : "")
                    : fe.field.type === "snapshot" ? (t => t.trim() && Actions.configValue(t.trim()) === undefined ? "No such setting" : "") : null
                onEditingFinished: {
                    if (fe.field.type === "seconds") { if (textIn.valid && text.trim()) root.setField(fe.stepIndex, fe.field.key, Number(text)) }
                    else if (fe.field.type === "snapshot") {
                        const k = text.trim()
                        if (k === fe.value) return
                        root.editSteps(s => { s[fe.stepIndex][fe.field.key] = k; s[fe.stepIndex].value = Actions.snapshot(k) })
                    } else root.setField(fe.stepIndex, fe.field.key, text.trim())
                }
            }
        }
        // app: matching applications while you type
        Repeater {
            model: fe.field.type === "app" && textIn.inputFocused ? fe.matches : []
            RippleButton {
                id: hit
                required property var modelData
                focusPolicy: Qt.NoFocus // the text keeps focus, so the list stays until the click lands
                Layout.fillWidth: true
                implicitHeight: 32
                onClicked: { root.setField(fe.stepIndex, fe.field.key, hit.modelData.id); textIn.text = hit.modelData.id }
                contentItem: RowLayout {
                    spacing: 8
                    MaterialSymbol { text: "apps"; iconSize: 16; Layout.leftMargin: 8 }
                    StyledText { text: hit.modelData.name; elide: Text.ElideRight; Layout.fillWidth: true }
                    StyledText { text: hit.modelData.id; color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.smaller; Layout.rightMargin: 8 }
                }
            }
        }
        readonly property var matches: {
            if (fe.field.type !== "app") return []
            const q = textIn.text.trim().toLowerCase()
            if (q.length < 2) return []
            return DesktopEntries.applications.values.filter(e => !e.noDisplay && (e.name.toLowerCase().includes(q) || e.id.toLowerCase().includes(q))).slice(0, 5)
        }
        // snapshot: the value the step will set
        RowLayout {
            visible: fe.field.type === "snapshot" && String(fe.value ?? "").length > 0
            Layout.fillWidth: true
            StyledText {
                Layout.fillWidth: true; elide: Text.ElideRight
                text: `Sets it to ${JSON.stringify(fe.step.value)}`
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
            RippleButtonWithIcon {
                iconName: "photo_camera"
                buttonText: "Take the current value"
                onClicked: root.setField(fe.stepIndex, "value", Actions.snapshot(fe.value))
            }
        }
        ConfigSlider {
            visible: fe.field.type === "percent"
            label: fe.field.label ?? ""
            from: 0; to: 100; stepSize: 1
            value: Number(fe.value ?? 50)
            valueText: `${Math.round(value)}%`
            onValueChanged: if (fe.field.type === "percent") root.setField(fe.stepIndex, fe.field.key, Math.round(value))
        }
        ConfigSwitch {
            visible: fe.field.type === "bool"
            label: fe.field.label ?? ""
            checked: fe.value === true
            onCheckedChanged: if (fe.field.type === "bool") root.setField(fe.stepIndex, fe.field.key, checked)
        }
        ConfigRow {
            visible: fe.field.type === "choice"
            label: fe.field.label ?? ""
            sublabel: fe.field.type === "choice" && fe.field.choices().length === 0 ? "Nothing to choose from yet" : ""
        }
        ChoiceRow {
            visible: fe.field.type === "choice"
            Layout.fillWidth: true
            model: fe.field.type === "choice" ? fe.field.choices() : []
            current: fe.value ?? null
            onChose: v => root.setField(fe.stepIndex, fe.field.key, v)
        }
    }
}
