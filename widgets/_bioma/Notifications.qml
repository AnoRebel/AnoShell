pragma Singleton

import QtQuick
import Quickshell
import qs.services as Ano

// Adapted from Bioma (GPL-3.0), services/Notifications.qml: only what the
// vacuole organism reads, over AnoShell's own notification server.
//
// AnoShell keeps a count of unread notifications (raised by each one that
// popped up, cleared when the sidebar is opened) over the history `list`,
// newest last; the unread ones are the last `unread` of that list.
Singleton {
    id: root

    function hold(owner, wanted) {}

    function isCritical(urgency) {
        return urgency === "critical" || String(urgency) === "2";
    }

    // Oldest first: [{ appName, critical, at }], `at` in ms since the epoch.
    readonly property var unread: {
        const list = Ano.Notifications.list;
        const count = Math.min(Ano.Notifications.unread, list.length);
        const out = [];
        for (let i = list.length - count; i < list.length; i++) {
            const n = list[i];
            out.push({ "appName": n.appName, "critical": root.isCritical(n.urgency), "at": n.time });
        }
        return out;
    }
}
