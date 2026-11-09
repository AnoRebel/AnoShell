import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "."

// Startup applications (Settings → Services): autostart.entries, launched
// once per session by anod (anod/internal/autostart) on Hyprland and niri.
// The list is config (edited here with Config.setNestedValue); anod reports
// what it launched (autostart.list) and starts one now (autostart.run).
SettingsCard {
    id: card
    icon: "rocket_launch"
    title: "Startup applications"
    subtitle: "Started once when you log in, by anod (not again when the shell or anod restarts)"
    configKeys: ["autostart"]

    readonly property var entries: Array.from(Config.options?.autostart?.entries ?? [])
    property var status: []        // anod's rows, by index
    property var desktopFiles: []  // ~/.config/autostart, read-only
    property string autostartDir: ""
    property string filter: ""
    property string message: ""

    readonly property var matches: {
        const q = card.filter.trim().toLowerCase()
        if (q.length < 2) return []
        const out = []
        for (const e of DesktopEntries.applications.values) {
            if (e.noDisplay) continue
            if (String(e.name).toLowerCase().includes(q) || String(e.id).toLowerCase().includes(q)) out.push(e)
            if (out.length >= 8) break
        }
        return out
    }

    function save(list) {
        Config.setNestedValue("autostart.entries", list)
        refreshSoon.restart()
    }
    function _has(key, value) { return card.entries.some(x => (x[key] ?? "") === value) }
    function addDesktop(id) {
        id = String(id).replace(/\.desktop$/, "")
        if (!id || card._has("desktopId", id)) return
        card.save(card.entries.concat([{ desktopId: id, enabled: true, delayMs: 0 }]))
        card.filter = ""
    }
    function addCommand(cmd) {
        cmd = String(cmd).trim()
        if (!cmd || card._has("command", cmd)) return
        card.save(card.entries.concat([{ command: cmd, enabled: true, delayMs: 0 }]))
    }
    function setField(i, key, value) {
        const list = card.entries.map(x => Object.assign({}, x))
        list[i][key] = value
        card.save(list)
    }
    function remove(i) { const list = card.entries.slice(); list.splice(i, 1); card.save(list) }
    function nameOf(i) {
        const e = card.entries[i] ?? {}
        const s = card.status[i]
        if (e.desktopId) return s?.name || DesktopEntries.heuristicLookup(e.desktopId)?.name || e.desktopId
        return e.command ?? ""
    }

    function refresh() {
        if (!Anod.available) return
        Anod.call("autostart.list", {}, (r, e) => {
            if (e) { card.message = e.message; return }
            card.status = r.entries ?? []
            card.desktopFiles = r.desktopFiles ?? []
            card.autostartDir = r.autostartDir ?? ""
        })
    }
    // after the config is on disk: anod reads autostart.entries from there
    Timer { id: refreshSoon; interval: 800; onTriggered: card.refresh() }
    Component.onCompleted: refresh()
    Connections { target: Anod; function onAvailableChanged() { card.refresh() } }

    NoticeBox {
        visible: !Anod.available
        Layout.fillWidth: true
        iconName: "info"
        text: "anod isn't running, so nothing starts at login. The list is kept and used once it runs."
    }

    EmptyState {
        visible: card.entries.length === 0
        Layout.fillWidth: true
        icon: "rocket_launch"
        title: "No startup applications"
        hint: "Find an app below, or add a command"
    }

    Repeater {
        model: card.entries
        RowLayout {
            id: row
            required property var modelData
            required property int index
            readonly property var st: card.status[row.index] ?? null
            Layout.fillWidth: true
            spacing: 6

            StyledSwitch {
                checked: row.modelData.enabled !== false
                onToggled: card.setField(row.index, "enabled", checked)
                StyledToolTip { text: checked ? "Starts at login" : "Doesn't start at login" }
            }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 0
                StyledText { text: card.nameOf(row.index); elide: Text.ElideRight; Layout.fillWidth: true }
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: row.st?.error ? row.st.error
                        : (row.modelData.desktopId ? `${row.modelData.desktopId}.desktop` : "command")
                          + (row.st?.launchedAt ? ` · started ${new Date(row.st.launchedAt).toLocaleTimeString(Qt.locale(), "hh:mm")}` : "")
                    color: row.st?.error ? Appearance.colors.colError : Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smallest
                }
            }
            StyledTextInput {
                Layout.preferredWidth: 36
                horizontalAlignment: TextInput.AlignRight
                validator: IntValidator { bottom: 0; top: 600 }
                text: String(Math.round((row.modelData.delayMs ?? 0) / 1000))
                onEditingFinished: if (Number(text) * 1000 !== (row.modelData.delayMs ?? 0)) card.setField(row.index, "delayMs", Number(text) * 1000)
            }
            StyledText {
                text: "s"
                color: Appearance.colors.colSubtext
                StyledToolTip { text: "Seconds to wait after login" }
            }
            RippleButton {
                implicitWidth: 30; implicitHeight: 30; buttonRadius: 15
                enabled: Anod.available
                onClicked: Anod.call("autostart.run", { index: row.index }, (r, e) => { card.message = e ? e.message : ""; refreshSoon.restart() })
                contentItem: MaterialSymbol { text: "play_arrow"; iconSize: 18; horizontalAlignment: Text.AlignHCenter }
                StyledToolTip { text: "Start it now" }
            }
            RippleButton {
                implicitWidth: 30; implicitHeight: 30; buttonRadius: 15
                onClicked: card.remove(row.index)
                contentItem: MaterialSymbol { text: "close"; iconSize: 18; horizontalAlignment: Text.AlignHCenter }
                StyledToolTip { text: "Remove" }
            }
        }
    }

    ConfigTextInput {
        Layout.fillWidth: true
        placeholderText: "Add an app: type its name"
        text: card.filter
        onTextChanged: card.filter = text
    }
    Repeater {
        model: card.matches
        RippleButton {
            id: hit
            required property var modelData
            Layout.fillWidth: true
            implicitHeight: 34
            onClicked: card.addDesktop(hit.modelData.id)
            contentItem: RowLayout {
                spacing: 8
                MaterialSymbol { text: "add"; iconSize: 18; Layout.leftMargin: 8 }
                StyledText { text: hit.modelData.name; elide: Text.ElideRight; Layout.fillWidth: true }
                StyledText {
                    text: hit.modelData.id
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    Layout.rightMargin: 8
                }
            }
        }
    }
    ConfigTextInput {
        id: cmdInput
        Layout.fillWidth: true
        placeholderText: "Or a command, run with sh -c (e.g. syncthing serve --no-browser)"
        iconAction: "add"
        onIconClicked: { card.addCommand(text); text = "" }
    }

    StyledText {
        visible: card.message.length > 0
        Layout.fillWidth: true; wrapMode: Text.Wrap
        text: card.message
        color: Appearance.colors.colError
        font.pixelSize: Appearance.font.pixelSize.smaller
    }

    // ~/.config/autostart: shown, never run by anod (Hyprland and niri don't
    // run XDG autostart either); one click copies an entry into the list.
    ColumnLayout {
        visible: card.desktopFiles.length > 0
        Layout.fillWidth: true
        spacing: 2
        StyledText {
            Layout.fillWidth: true; wrapMode: Text.Wrap
            text: `In ${card.autostartDir} (other desktops start these; AnoShell doesn't unless you add them):`
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
        Repeater {
            model: card.desktopFiles
            RowLayout {
                id: xdg
                required property var modelData
                Layout.fillWidth: true
                spacing: 6
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: (xdg.modelData.name || xdg.modelData.id) + (xdg.modelData.hidden ? " (hidden)" : "")
                    opacity: xdg.modelData.hidden ? 0.5 : 1
                }
                RippleButton {
                    implicitWidth: 30; implicitHeight: 30; buttonRadius: 15
                    enabled: !card._has("desktopId", xdg.modelData.id)
                    onClicked: card.addDesktop(xdg.modelData.id)
                    contentItem: MaterialSymbol { text: "add"; iconSize: 18; horizontalAlignment: Text.AlignHCenter }
                    StyledToolTip { text: "Add to the list" }
                }
            }
        }
    }
}
