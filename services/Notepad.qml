pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * Notepad tabs (notepad.enable): [{ title, text }] in
 * ~/.local/share/anoshell/notepad.json, saved half a second after the last
 * edit (atomic). Nothing is read or written while the notepad is off.
 */
Singleton {
    id: root
    readonly property bool enabled: Config.options?.notepad?.enable ?? false
    property var tabs: [{ title: "Note", text: "" }]
    property int current: 0
    property bool loaded: false

    function setText(i, text) {
        if (!root.tabs[i] || root.tabs[i].text === text) return
        const t = root.tabs.slice(); t[i] = Object.assign({}, t[i], { text: text })
        // A tab's title follows its first line.
        const first = text.split("\n")[0].trim()
        if (first) t[i].title = first.slice(0, 24)
        root.tabs = t
        saveTimer.restart()
    }
    function addTab() {
        root.tabs = root.tabs.concat([{ title: "Note", text: "" }])
        root.current = root.tabs.length - 1
        saveTimer.restart()
    }
    function closeTab(i) {
        const t = root.tabs.slice(); t.splice(i, 1)
        root.tabs = t.length ? t : [{ title: "Note", text: "" }]
        root.current = Math.min(root.current, root.tabs.length - 1)
        saveTimer.restart()
    }

    Process { id: mkdir; command: ["mkdir", "-p", "--", Directories.anoData] }
    FileView {
        id: file
        path: root.enabled ? `${Directories.anoData}/notepad.json` : ""
        onLoaded: {
            try {
                const d = JSON.parse(text())
                if (Array.isArray(d.tabs) && d.tabs.length) { root.tabs = d.tabs; root.current = Math.min(d.current ?? 0, d.tabs.length - 1) }
                root.loaded = true
            } catch (e) {
                // Unreadable (a hand edit, a truncated write): keep a copy before anything saves over it.
                console.warn(`[Notepad] ${e}; keeping a copy as notepad.json.bad`)
                backup.running = true
            }
        }
        printErrors: false // missing until the first save
        onLoadFailed: error => {
            if (error !== FileViewError.FileNotFound) { console.warn("[Notepad] can't read notepad.json; not saving"); return }
            root.loaded = true
            mkdir.running = true
        }
    }
    Process {
        id: backup
        command: ["cp", "-f", "--", `${Directories.anoData}/notepad.json`, `${Directories.anoData}/notepad.json.bad`]
        onExited: code => { if (code === 0) root.loaded = true }
    }
    Timer {
        id: saveTimer
        interval: 500
        onTriggered: if (root.enabled && root.loaded) file.setText(JSON.stringify({ tabs: root.tabs, current: root.current }, null, 1))
    }
}
