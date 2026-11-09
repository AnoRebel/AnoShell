pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs
import qs.services
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

/**
 * Notification service with persistent storage, popup management,
 * grouping by app, and timeout handling.
 */
Singleton {
    id: root

    component Notif: QtObject {
        id: wrapper
        required property int notificationId
        property Notification notification
        property list<var> actions: notification?.actions.map(action => ({
            "identifier": action.identifier,
            "text": action.text,
        })) ?? []
        property bool popup: false
        property bool isTransient: notification?.hints.transient ?? false
        property string appIcon: notification?.appIcon ?? ""
        property string appName: notification?.appName ?? ""
        property string body: notification?.body ?? ""
        property string image: notification?.image ?? ""
        property string summary: notification?.summary ?? ""
        property double time
        property string urgency: notification?.urgency.toString() ?? "normal"
        property Timer timer

        onNotificationChanged: {
            if (notification === null) root.discardNotification(notificationId)
        }
    }

    function notifToJSON(notif) {
        return {
            "notificationId": notif.notificationId,
            "actions": notif.actions,
            "appIcon": notif.appIcon,
            "appName": notif.appName,
            "body": notif.body,
            "image": notif.image,
            "summary": notif.summary,
            "time": notif.time,
            "urgency": notif.urgency,
        }
    }

    component NotifTimer: Timer {
        required property int notificationId
        interval: 7000
        running: true
        onTriggered: () => {
            const index = root.list.findIndex(notif => notif.notificationId === notificationId)
            const notifObject = root.list[index]
            if (notifObject?.isTransient) root.discardNotification(notificationId)
            else root.timeoutNotification(notificationId)
            destroy()
        }
    }

    property bool silent: false
    property int unread: 0
    property var filePath: Directories.notificationsPath
    property list<Notif> list: []
    // notifications.silent: no popups (history still records them);
    // notifications.maxVisible: newest N popups on screen at once.
    // Performance mode holds popups; they still reach the centre.
    // Critical ones (low battery, …) still show, under DND too.
    readonly property bool dnd: root.silent || (Config.options?.notifications?.silent ?? false)
    property var popupList: list.filter(notif => notif.popup && (root.isCritical(notif) || (!root.dnd && !GameMode.holdPopups)))
            .slice(-Math.max(1, Config.options?.notifications?.maxVisible ?? 5))
    // urgency is kept as text: the enum's string (a number) or a name from older files
    function isCritical(n) { return String(n?.urgency) === String(NotificationUrgency.Critical) || /critical/i.test(String(n?.urgency)) }
    property bool popupInhibited: (GlobalStates?.sidebarRightOpen ?? false) || silent
    property var latestTimeForApp: ({})

    // Per-app rules (notifications.silentApps / blockedApps): matched,
    // case-insensitively, against the desktop entry or the app name.
    // "blocked" drops it; "silent" keeps it in the history only.
    function ruleFor(n) {
        const ids = [n.desktopEntry, n.appName].filter(s => s).map(s => String(s).toLowerCase())
        const has = list => Array.from(list ?? []).some(a => ids.includes(String(a).trim().toLowerCase()))
        if (has(Config.options?.notifications?.blockedApps)) return "blocked"
        if (has(Config.options?.notifications?.silentApps)) return "silent"
        return ""
    }

    Component { id: notifComponent; Notif {} }
    Component { id: notifTimerComponent; NotifTimer {} }

    function stringifyList(list) {
        return JSON.stringify(list.map(notif => notifToJSON(notif)), null, 2)
    }

    onListChanged: {
        root.list.forEach(notif => {
            if (!root.latestTimeForApp[notif.appName] || notif.time > root.latestTimeForApp[notif.appName]) {
                root.latestTimeForApp[notif.appName] = Math.max(root.latestTimeForApp[notif.appName] || 0, notif.time)
            }
        })
        Object.keys(root.latestTimeForApp).forEach(appName => {
            if (!root.list.some(notif => notif.appName === appName)) {
                delete root.latestTimeForApp[appName]
            }
        })
    }

    function appNameListForGroups(groups) {
        return Object.keys(groups).sort((a, b) => groups[b].time - groups[a].time)
    }

    function groupsForList(list) {
        const groups = {}
        list.forEach(notif => {
            if (!groups[notif.appName]) {
                groups[notif.appName] = { appName: notif.appName, appIcon: notif.appIcon, notifications: [], time: 0 }
            }
            groups[notif.appName].notifications.push(notif)
            groups[notif.appName].time = latestTimeForApp[notif.appName] || notif.time
        })
        return groups
    }

    property var groupsByAppName: groupsForList(root.list)
    property var popupGroupsByAppName: groupsForList(root.popupList)
    property list<string> appNameList: appNameListForGroups(root.groupsByAppName)
    property list<string> popupAppNameList: appNameListForGroups(root.popupGroupsByAppName)

    property int idOffset
    signal initDone()
    signal notify(notification: var)
    signal discard(id: int)
    signal discardAll()
    signal timeout(id: var)

    NotificationServer {
        id: notifServer
        actionsSupported: true
        bodyHyperlinksSupported: true
        // Inline <img> in body text is not rendered in the compact bar/sidebar
        // popups (a plain Text element can't resolve the img base URL, which
        // spams "Invalid base url in img tag" warnings). The separate
        // notification image hint (imageSupported, shown as the notif icon) is
        // still honoured.
        bodyImagesSupported: false
        bodyMarkupSupported: true
        bodySupported: true
        imageSupported: true
        keepOnReload: false
        persistenceSupported: true

        onNotification: notification => {
            const rule = root.ruleFor(notification)
            if (rule === "blocked") return // untracked: the server discards it
            notification.tracked = true
            const newNotifObject = notifComponent.createObject(root, {
                "notificationId": notification.id + root.idOffset,
                "notification": notification,
                "time": Date.now(),
            })
            root.list = [...root.list, newNotifObject]

            if (rule !== "silent" && (!root.popupInhibited || (root.isCritical(notification) && !(GlobalStates?.sidebarRightOpen ?? false)))) {
                newNotifObject.popup = true
                if (notification.expireTimeout !== 0) {
                    newNotifObject.timer = notifTimerComponent.createObject(root, {
                        "notificationId": newNotifObject.notificationId,
                        "interval": notification.expireTimeout < 0 ? (Config?.options.notifications.timeout ?? 7000) : notification.expireTimeout,
                    })
                }
                root.unread++
            }
            // A sound only for one that pops up (not silent, not held by performance mode).
            if (newNotifObject.popup && root.popupList.includes(newNotifObject)) Sounds.notification(notification)
            if (rule !== "silent") root.notify(newNotifObject)
            notifFileView.setText(stringifyList(root.list))
        }
    }

    // A notification from the shell itself (no D-Bus round trip): listed,
    // persisted and popped up like any other. Ids are negative so they never
    // meet the server's (which count up from idOffset).
    function post(summary, body, critical) {
        const id = Math.min(0, ...root.list.map(n => n.notificationId)) - 1
        const n = notifComponent.createObject(root, {
            "notificationId": id, "appName": "AnoShell", "summary": summary ?? "", "body": body ?? "",
            "time": Date.now(), "urgency": String(critical ? NotificationUrgency.Critical : NotificationUrgency.Normal),
        })
        root.list = [...root.list, n]
        if (!root.popupInhibited) {
            n.popup = true
            n.timer = notifTimerComponent.createObject(root, { "notificationId": id, "interval": Config.options?.notifications?.timeout ?? 7000 })
            root.unread++
        }
        root.notify(n)
        notifFileView.setText(stringifyList(root.list))
        return id
    }

    function markAllRead() { root.unread = 0 }

    function discardNotification(id) {
        const index = root.list.findIndex(notif => notif.notificationId === id)
        const notifServerIndex = notifServer.trackedNotifications.values.findIndex(notif => notif.id + root.idOffset === id)
        if (index !== -1) {
            root.list.splice(index, 1)
            notifFileView.setText(stringifyList(root.list))
            triggerListChange()
        }
        if (notifServerIndex !== -1) notifServer.trackedNotifications.values[notifServerIndex].dismiss()
        root.discard(id)
    }

    function discardAllNotifications() {
        root.list = []
        triggerListChange()
        notifFileView.setText(stringifyList(root.list))
        notifServer.trackedNotifications.values.forEach(notif => notif.dismiss())
        root.discardAll()
    }

    function cancelTimeout(id) {
        const index = root.list.findIndex(notif => notif.notificationId === id)
        if (root.list[index] != null) root.list[index].timer.stop()
    }

    function timeoutNotification(id) {
        const index = root.list.findIndex(notif => notif.notificationId === id)
        if (root.list[index] != null) root.list[index].popup = false
        root.timeout(id)
    }

    function timeoutAll() {
        root.popupList.forEach(notif => { root.timeout(notif.notificationId) })
        root.popupList.forEach(notif => { notif.popup = false })
    }

    function attemptInvokeAction(id, notifIdentifier) {
        const notifServerIndex = notifServer.trackedNotifications.values.findIndex(notif => notif.id + root.idOffset === id)
        if (notifServerIndex !== -1) {
            const notifServerNotif = notifServer.trackedNotifications.values[notifServerIndex]
            const action = notifServerNotif.actions.find(a => a.identifier === notifIdentifier)
            if (action) action.invoke()
        }
        root.discardNotification(id)
    }

    function triggerListChange() { root.list = root.list.slice(0) }
    function refresh() { notifFileView.reload() }
    Component.onCompleted: refresh()

    FileView {
        id: notifFileView
        path: Qt.resolvedUrl(filePath)
        onLoaded: {
            const fileContents = notifFileView.text()
            root.list = JSON.parse(fileContents).map(notif => {
                return notifComponent.createObject(root, {
                    "notificationId": notif.notificationId,
                    "actions": [],
                    "appIcon": notif.appIcon,
                    "appName": notif.appName,
                    "body": notif.body,
                    "image": notif.image,
                    "summary": notif.summary,
                    "time": notif.time,
                    "urgency": notif.urgency,
                })
            })
            let maxId = 0
            root.list.forEach(notif => { maxId = Math.max(maxId, notif.notificationId) })
            root.idOffset = maxId
            root.initDone()
        }
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) {
                root.list = []
                // A write from inside the load handler is dropped; defer it.
                Qt.callLater(() => notifFileView.setText(stringifyList(root.list)))
            }
        }
    }
    // Do Not Disturb from keybinds and scripts (qs ipc call notifications toggleDnd).
    IpcHandler {
        target: "notifications"
        function toggleDnd(): void { root.silent = !root.silent }
        function setDnd(on: bool): void { root.silent = on }
        function clearAll(): void { root.discardAllNotifications() }
        function status(): string { return JSON.stringify({ dnd: root.silent, count: root.list.length, unread: root.unread }) }
    }
}
