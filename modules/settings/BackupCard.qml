import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "."

// Backup & restore (Settings → About): the same archives as `ano backup`,
// through anod (backup.categories/list/create/restore). A restore is two
// steps: Preview lists the files it would write, Restore writes them and
// keeps the ones it replaces in a pre-restore archive.
SettingsCard {
    id: card
    icon: "settings_backup_restore"
    title: "Backup & restore"
    subtitle: "Your settings, themes, widgets and data in an archive; restore all of it or some"
    configKeys: []

    property var categories: []      // [{name, desc, default}]
    property var picked: ({})        // name → true, for a new backup
    property var backups: []         // [{path, created, files, categories}]
    property var chosen: null        // the backup being restored
    property var restorePick: ({})   // name → true, for the restore
    property var preview: null       // {files, snapshot, error} from a dry run
    property bool busy: false
    property string message: ""
    property bool messageIsError: false

    function _say(text, error) { card.message = text; card.messageIsError = !!error }
    function load() {
        if (!Anod.available) return
        Anod.call("backup.categories", {}, (r, e) => {
            if (!card) return
            if (!r) { card._say(`Couldn't list what can be backed up: ${e?.message ?? "no answer"}`, true); return }
            card.categories = r
            const p = {}
            for (const c of r) p[c.name] = c.default
            card.picked = p
        })
        card.refresh()
    }
    function refresh() {
        Anod.call("backup.list", {}, (r, e) => {
            if (!card) return
            if (r) card.backups = r
            else card._say(`Couldn't list the backups: ${e?.message ?? "no answer"}`, true)
        })
    }
    Component.onCompleted: load()
    Connections { target: Anod; function onAvailableChanged() { card.load() } }

    function names(map) { return Object.keys(map).filter(k => map[k]) }
    function create() {
        const only = card.names(card.picked)
        if (!only.length) { card._say("Pick at least one thing to back up.", true); return }
        card.busy = true; card._say("Backing up…")
        Anod.call("backup.create", { only: only }, (r, e) => {
            if (!card) return // Settings closed meanwhile
            card.busy = false
            if (e) { card._say(e.message, true); return }
            card._say(`Backed up ${r.files} file(s) to ${r.path}`)
            card.refresh()
        })
    }
    function choose(b) {
        card.chosen = b
        card.preview = null
        const p = {}
        for (const c of b.categories) p[c] = true
        card.restorePick = p
    }
    function restore(dryRun) {
        const only = card.names(card.restorePick)
        if (!card.chosen || !only.length) { card._say("Pick at least one thing to restore.", true); return }
        card.busy = true; card._say(dryRun ? "Checking…" : "Restoring…")
        Anod.call("backup.restore", { path: card.chosen.path, only: only, dryRun: dryRun }, (r, e) => {
            if (!card) return // Settings closed meanwhile
            card.busy = false
            if (e) { card._say(e.message, true); return }
            if (dryRun) {
                // A preview of an earlier pick doesn't count for this one.
                if (card.names(card.restorePick).join() === only.join()) card.preview = r
                card._say(""); return
            }
            if (r.error) { card._say(`Stopped: ${r.error}. Restored before that: ${r.files.length} file(s)` + (r.snapshot ? `; the previous versions are in ${r.snapshot}` : ""), true); return }
            card._say(`Restored ${r.files.length} file(s)` + (r.snapshot ? `; the files it replaced are in ${r.snapshot}` : "") + ". Settings apply as the shell reloads them; reload your compositor for its configs.")
            card.chosen = null; card.preview = null
            card.refresh()
        })
    }
    // A heading over its rows.
    component Section: ColumnLayout {
        id: sec
        property string title: ""
        Layout.fillWidth: true
        spacing: 6
        StyledText {
            text: sec.title
            visible: sec.title.length > 0
            font.weight: Font.DemiBold
            Layout.topMargin: 4
        }
    }
    function when(b) { return Qt.formatDateTime(new Date(b.created * 1000), "yyyy-MM-dd hh:mm") }

    StyledText {
        visible: !Anod.available
        Layout.fillWidth: true; wrapMode: Text.Wrap
        text: "Needs AnoShell's daemon (anod); `ano backup` does the same from a terminal."
        color: Appearance.colors.colSubtext
    }

    // ── New backup ───────────────────────────────────────────────────────
    Section {
        visible: Anod.available
        title: "Back up"
        Repeater {
            model: card.categories
            ConfigSwitch {
                id: cat
                required property var modelData
                Layout.fillWidth: true
                label: cat.modelData.name.charAt(0).toUpperCase() + cat.modelData.name.slice(1)
                sublabel: cat.modelData.name === "secrets" && cat.checked
                    ? "Your API keys go into the archive unencrypted: keep the file somewhere only you can read"
                    : cat.modelData.desc
                checked: !!card.picked[cat.modelData.name]
                onCheckedChanged: if (!!card.picked[cat.modelData.name] !== checked) {
                    const p = Object.assign({}, card.picked); p[cat.modelData.name] = checked; card.picked = p
                }
            }
        }
        RippleButton {
            toggled: true
            enabled: !card.busy
            buttonText: "Back up now"
            onClicked: card.create()
        }
    }

    // ── Backups and restoring ────────────────────────────────────────────
    Section {
        visible: Anod.available
        title: card.backups.length ? "Backups" : "No backups yet"
        Repeater {
            model: card.backups
            RowLayout {
                id: row
                required property var modelData
                Layout.fillWidth: true
                spacing: 8
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 0
                    StyledText { text: `${card.when(row.modelData)} · ${row.modelData.files} file(s)` + (row.modelData.preRestore ? " · replaced by a restore" : ""); Layout.fillWidth: true; elide: Text.ElideRight }
                    StyledText {
                        text: row.modelData.categories.join(", ")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        Layout.fillWidth: true; elide: Text.ElideRight
                    }
                }
                RippleButton {
                    enabled: !card.busy
                    toggled: card.chosen?.path === row.modelData.path
                    buttonText: card.chosen?.path === row.modelData.path ? "Chosen" : "Choose"
                    onClicked: card.chosen?.path === row.modelData.path ? (card.chosen = null) : card.choose(row.modelData)
                }
            }
        }
    }

    Section {
        visible: Anod.available && card.chosen !== null
        title: card.chosen ? `Restore from ${card.when(card.chosen)}` : ""
        Repeater {
            model: card.chosen ? card.chosen.categories : []
            ConfigSwitch {
                id: rcat
                required property var modelData
                Layout.fillWidth: true
                enabled: !card.busy
                label: rcat.modelData.charAt(0).toUpperCase() + rcat.modelData.slice(1)
                checked: !!card.restorePick[rcat.modelData]
                onCheckedChanged: if (!!card.restorePick[rcat.modelData] !== checked) {
                    const p = Object.assign({}, card.restorePick); p[rcat.modelData] = checked
                    card.restorePick = p; card.preview = null
                }
            }
        }
        StyledText {
            visible: card.preview !== null
            Layout.fillWidth: true; wrapMode: Text.Wrap
            text: !card.preview ? "" : card.preview.files.length === 0 ? "Nothing to restore for these."
                : `These ${card.preview.files.length} file(s) would be replaced:\n` + card.preview.files.slice(0, 12).map(f => "  ~/" + f).join("\n")
                    + (card.preview.files.length > 12 ? `\n  … and ${card.preview.files.length - 12} more` : "")
            font.family: Appearance.font.family.mono
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
        RowLayout {
            spacing: 8
            RippleButton { enabled: !card.busy; buttonText: "Preview"; onClicked: card.restore(true) }
            RippleButton {
                toggled: true
                enabled: !card.busy && card.preview !== null && card.preview.files.length > 0
                buttonText: "Restore"
                onClicked: card.restore(false)
            }
        }
    }

    StyledText {
        visible: card.message.length > 0
        Layout.fillWidth: true; wrapMode: Text.Wrap
        text: card.message
        color: card.messageIsError ? Appearance.colors.colError : Appearance.colors.colSubtext
        font.pixelSize: Appearance.font.pixelSize.smaller
    }
}
