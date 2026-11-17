pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs
import qs.modules.common
import qs.services

/**
 * The persistent notification history (anod's notifhistory store; notifications.history.*), for the history panel.
 * It queries anod only while `active` (the panel open). Recording is Notifications.record().
 *
 * Filters: text (summary, body, app), app, urgency ("" | "low" | "normal" | "critical") and range ("today" | "7d" |
 * "30d" | "all"). entries are newest first, a page of 50 at a time (loadMore()).
 */
Singleton {
    id: root

    property bool active: false
    property string text: ""
    property string app: ""
    property string urgency: ""
    property string range: "all"

    property var entries: []
    property int total: 0
    property string next: ""
    property bool loading: false
    property var apps: []
    property var stats: ({})
    property string error: ""
    readonly property bool available: Anod.available
    readonly property bool enabled: Config.options?.notifications?.history?.enable ?? true
    readonly property bool filtered: root.text.trim() !== "" || root.app !== "" || root.urgency !== "" || root.range !== "all"

    function _query(cursor) {
        let since = 0
        const now = new Date()
        if (root.range === "today") since = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
        else if (root.range === "7d") since = now.getTime() - 7 * 86400000
        else if (root.range === "30d") since = now.getTime() - 30 * 86400000
        return { text: root.text.trim(), app: root.app, urgency: root.urgency ? [root.urgency] : [], since: since, cursor: cursor ?? "", limit: 50 }
    }

    // Each refresh gets a number; a reply to an older one is dropped (typing fires several).
    property int _gen: 0
    function refresh() {
        if (!root.active) return
        if (!Anod.available) { root.error = "anod is not running: start the shell with \"ano start\" to see the history"; return }
        const gen = ++root._gen
        root.loading = true
        Anod.call("notifhistory.query", root._query(""), (res, err) => {
            if (gen !== root._gen) return
            root.loading = false
            root.error = err ? (err.message ?? err.code) : ""
            root.entries = res?.entries ?? []
            root.total = res?.total ?? 0
            root.next = res?.next ?? ""
        })
        Anod.call("notifhistory.apps", null, res => root.apps = res ?? [])
        Anod.call("notifhistory.stats", null, res => root.stats = res ?? {})
    }
    function loadMore() {
        if (!root.next || root.loading || !Anod.available) return
        const gen = root._gen
        root.loading = true
        Anod.call("notifhistory.query", root._query(root.next), (res, err) => {
            if (gen !== root._gen) return
            root.loading = false
            if (err) { root.error = err.message ?? err.code; return }
            root.entries = root.entries.concat(res?.entries ?? [])
            root.next = res?.next ?? ""
        })
    }
    // What a delete removes: one entry (ids), one app, the current matches, or everything.
    function deleteIds(ids) { root._delete({ ids: ids }) }
    function deleteApp(app) { root._delete({ app: app }) }
    function deleteMatching() {
        if (!root.filtered) return
        const q = root._query("")
        delete q.cursor; delete q.limit
        root._delete(q)
    }
    function clearAll() { root._delete({ all: true }) }
    function _delete(req) {
        Anod.call("notifhistory.delete", req, (res, err) => {
            if (err) root.error = err.message ?? err.code
            root.refresh()
        })
    }
    // Counts for the confirmation: the matches need no extra call (total), an app's come from apps.
    function countFor(app) { return root.apps.find(a => a.app === app)?.count ?? 0 }

    function copy(entry) {
        Quickshell.clipboardText = [entry.summary, entry.body].filter(t => !!t).join("\n")
    }
    function appEntry(entry) {
        if (entry?.desktop) return DesktopEntries.byId(entry.desktop) ?? DesktopEntries.heuristicLookup(entry.desktop)
        return entry?.app ? DesktopEntries.heuristicLookup(entry.app) : null
    }
    function openApp(entry) { root.appEntry(entry)?.execute() }

    onActiveChanged: if (active) refresh()
    onTextChanged: refreshDebounce.restart()
    onAppChanged: refresh()
    onUrgencyChanged: refresh()
    onRangeChanged: refresh()
    Timer { id: refreshDebounce; interval: 200; onTriggered: root.refresh() }

    Connections {
        target: Anod
        function onEvent(name, data) { if (name === "notifhistory_changed" && root.active) changedDebounce.restart() }
        function onAvailableChanged() { if (root.active) root.refresh() }
    }
    // A burst of notifications refreshes once.
    Timer { id: changedDebounce; interval: 400; onTriggered: root.refresh() }
}
