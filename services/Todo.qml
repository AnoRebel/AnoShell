pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * To-do (todo.enable), kept in a todo.txt you can edit anywhere: one task a
 * line, "x <date> " in front when done (todo.txt format: "(A) " priority,
 * due:YYYY-MM-DD, +project, @context). The file is watched, so an edit
 * elsewhere shows here at once, and a change here rewrites the file.
 */
Singleton {
    id: root
    // todo.enable, or a desktop to-do widget holding it (hold(true/false)).
    property int _holds: 0
    function hold(on: bool): void { root._holds = Math.max(0, root._holds + (on ? 1 : -1)) }
    readonly property bool enabled: (Config.options?.todo?.enable ?? false) || root._holds > 0
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
        return t.split("\n").map(l => l.replace(/\s+$/, "")).filter(l => l.trim() !== "").map(l => {
            if (!l.startsWith("x ")) return { done: false, text: l, completed: "" }
            const m = l.slice(2).match(/^(\d{4}-\d{2}-\d{2}) (.*)$/)
            return m ? { done: true, text: m[2], completed: m[1] } : { done: true, text: l.slice(2), completed: "" }
        })
    }
    function serialize(list) {
        // due:today etc. written by another app become dates when we save.
        return list.map(i => (i.done ? "x " + (i.completed ? i.completed + " " : "") : "") + root.expandDue(i.text.replace(/\n/g, " "))).join("\n") + "\n"
    }
    function today(offset) { const d = new Date(); d.setDate(d.getDate() + (offset ?? 0)); return Qt.formatDate(d, "yyyy-MM-dd") }
    // due:today / due:tomorrow / due:mon…sun → a date (the next such day).
    function expandDue(text) {
        const days = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
        return text.replace(/\bdue:(today|tomorrow|sun|mon|tue|wed|thu|fri|sat)\b/i, (_, w) => {
            w = w.toLowerCase()
            if (w === "today") return "due:" + root.today(0)
            if (w === "tomorrow") return "due:" + root.today(1)
            const ahead = (days.indexOf(w) - new Date().getDay() + 7) % 7 || 7
            return "due:" + root.today(ahead)
        })
    }
    function save(list) {
        if (!root.writable) { console.warn(`[Todo] ${root.path} didn't load; not saving`); return }
        root.lastRemoved = null
        root.items = list
        file.setText(root.serialize(list))
        // The save replaces the file (atomic rename), which drops the watch: re-arm it.
        file.watchChanges = false
        rewatch.restart()
    }
    // Re-arm, then re-read: an edit made elsewhere during the 200 ms isn't lost.
    Timer { id: rewatch; interval: 200; onTriggered: { file.watchChanges = true; file.reload() } }

    function add(text) { if (text.trim()) root.save(root.items.concat([{ done: false, text: root.expandDue(text.trim()), completed: "" }])) }
    function toggle(i) {
        const l = root.items.slice()
        l[i] = { done: !l[i].done, text: l[i].text, completed: l[i].done ? "" : root.today(0) }
        root.save(l)
    }
    function setText(i, text) {
        if (!text.trim()) return root.remove(i)
        const l = root.items.slice()
        l[i] = Object.assign({}, l[i], { text: root.expandDue(text.trim()) })
        root.save(l)
    }
    // The last removed task, for Undo (cleared by the next change).
    property var lastRemoved: null
    function remove(i) {
        const l = root.items.slice()
        const [gone] = l.splice(i, 1)
        root.save(l)
        root.lastRemoved = { item: gone, index: i }
    }
    function undoRemove() {
        const r = root.lastRemoved
        if (!r) return
        const l = root.items.slice()
        l.splice(Math.min(r.index, l.length), 0, r.item)
        root.save(l)
    }
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
