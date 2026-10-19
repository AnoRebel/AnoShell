pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * To-do (todo.enable), kept in a todo.txt you can edit anywhere: one task a
 * line, "x " in front when done (todo.txt format). The file is watched, so an
 * edit elsewhere shows here at once, and a change here rewrites the file.
 */
Singleton {
    id: root
    readonly property bool enabled: Config.options?.todo?.enable ?? false
    readonly property string path: {
        let p = (Config.options?.todo?.file ?? "").trim()
        if (p.startsWith("~/")) p = Quickshell.env("HOME") + p.slice(1)
        return p || `${Directories.anoData}/todo.txt`
    }
    property var items: []          // { done, text }
    // Writes only once the file loaded (or is confirmed missing), so a file
    // that fails to load (permissions) is never replaced.
    property bool writable: false

    function parse(t) {
        return t.split("\n").map(l => l.replace(/\s+$/, "")).filter(l => l.trim() !== "").map(l =>
            l.startsWith("x ") ? { done: true, text: l.slice(2) } : { done: false, text: l })
    }
    function serialize(list) { return list.map(i => (i.done ? "x " : "") + i.text.replace(/\n/g, " ")).join("\n") + "\n" }
    function save(list) {
        if (!root.writable) { console.warn(`[Todo] ${root.path} didn't load; not saving`); return }
        root.items = list
        file.setText(root.serialize(list))
        // The save replaces the file (atomic rename), which drops the watch: re-arm it.
        file.watchChanges = false
        rewatch.restart()
    }
    Timer { id: rewatch; interval: 200; onTriggered: file.watchChanges = true }

    function add(text) { if (text.trim()) root.save(root.items.concat([{ done: false, text: text.trim() }])) }
    function toggle(i) { const l = root.items.slice(); l[i] = { done: !l[i].done, text: l[i].text }; root.save(l) }
    function remove(i) { const l = root.items.slice(); l.splice(i, 1); root.save(l) }
    function clearDone() { root.save(root.items.filter(i => !i.done)) }

    Process { id: mkdir; command: ["mkdir", "-p", "--", root.path.slice(0, root.path.lastIndexOf("/"))] }
    FileView {
        id: file
        path: root.enabled ? root.path : ""
        watchChanges: true
        onFileChanged: reload()
        onPathChanged: root.writable = false
        onLoaded: { root.items = root.parse(text()); root.writable = true }
        printErrors: false // missing until the first save
        onLoadFailed: error => {
            root.items = []
            root.writable = error === FileViewError.FileNotFound
            if (root.writable) mkdir.running = true
            else console.warn(`[Todo] can't read ${root.path}`)
        }
    }
}
