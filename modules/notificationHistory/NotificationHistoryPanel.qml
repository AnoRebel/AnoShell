import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

/**
 * Notification history panel: everything the shell received (NotificationHistory, anod's notifhistory store),
 * searched by text and filtered by app, urgency and time, newest first, 50 at a time. One entry is deleted at once;
 * an app's, the matches' or all entries only after a confirmation naming how many go.
 * Opened from the notification center's History button, or `qs -c ano ipc call notificationHistory toggle`.
 */
Scope {
    id: root
    readonly property bool open: GlobalStates.notificationHistoryOpen

    // What the confirmation bar asks about: { kind: "app" | "matching" | "all", app, count } or null.
    property var pending: null
    onOpenChanged: { NotificationHistory.active = open; if (!open) root.pending = null }

    IpcHandler {
        target: "notificationHistory"
        function toggle(): void { GlobalStates.notificationHistoryOpen = !GlobalStates.notificationHistoryOpen }
        function open(): void { GlobalStates.notificationHistoryOpen = true }
        function close(): void { GlobalStates.notificationHistoryOpen = false }
        // Open it showing what matches a search (scripts, keybinds).
        function search(text: string): void { NotificationHistory.text = text; GlobalStates.notificationHistoryOpen = true }
    }

    function ask(kind, app) {
        const count = kind === "app" ? NotificationHistory.countFor(app) : kind === "matching" ? NotificationHistory.total : (NotificationHistory.stats.count ?? NotificationHistory.total)
        if (count > 0) root.pending = { kind: kind, app: app ?? "", count: count }
    }
    function confirmPending() {
        const p = root.pending
        root.pending = null
        if (!p) return
        if (p.kind === "app") { NotificationHistory.deleteApp(p.app); if (NotificationHistory.app === p.app) NotificationHistory.app = "" }
        else if (p.kind === "matching") NotificationHistory.deleteMatching()
        else NotificationHistory.clearAll()
    }

    PanelWindow {
        id: win
        visible: root.open || card.opacity > 0.01
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell:notificationHistory"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        mask: Region { x: card.x; y: card.y; width: card.width; height: card.height }
        anchors { top: true; bottom: true; left: true; right: true }
        Shortcut { sequence: "Escape"; autoRepeat: false; onActivated: root.pending ? root.pending = null : GlobalStates.notificationHistoryOpen = false }

        PanelDragHandle { panelCard: card; key: "notificationHistory" }

        SurfaceMaterial {
            id: card
            surface: "notificationHistory"
            anchors.centerIn: parent
            width: Math.min(560, parent.width * 0.6)
            height: Math.min(720, parent.height * 0.82)
            radius: Appearance?.rounding.windowRounding ?? 20
            color: Appearance?.m3colors.m3background ?? "#1C1B1F"
            clip: true

            opacity: root.open ? 1 : 0
            scale: root.open ? 1 : 0.92
            Behavior on opacity { id: opacityMotion; NumberAnimation { duration: AnimationConfig.scaledDuration(250); easing.type: Easing.BezierSpline; easing.bezierCurve: (opacityMotion.targetValue > 0.5 ? Appearance.animationCurves.emphasizedDecel : Appearance.animationCurves.emphasizedAccel) } }
            Behavior on scale { id: scaleMotion; NumberAnimation { duration: AnimationConfig.scaledDuration(250); easing.type: Easing.BezierSpline; easing.bezierCurve: (scaleMotion.targetValue > 0.96 ? Appearance.animationCurves.emphasizedDecel : Appearance.animationCurves.emphasizedAccel) } }

            ColumnLayout {
                anchors { fill: parent; margins: 20 }
                spacing: 10

                // ── Header ──
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    MaterialSymbol { text: "history"; iconSize: 22; color: Appearance.colors.colPrimary }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText { text: "Notification history"; font.pixelSize: Appearance.font.pixelSize.large; font.weight: Font.DemiBold }
                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideMiddle
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            readonly property var st: NotificationHistory.stats
                            readonly property int days: Config.options?.notifications?.history?.keepDays ?? 30
                            text: !NotificationHistory.enabled ? "The history is off (Settings → General → Notifications)"
                                : `${st.count ?? 0} kept · ${days > 0 ? `${days} days` : "forever"} · ${FileUtils.trimFileProtocol(st.dir ?? "")}`
                        }
                    }
                    ToolbarButton {
                        iconName: "settings"; iconSize: 18
                        toolTipText: "History settings"
                        onClicked: { GlobalStates.notificationHistoryOpen = false; Quickshell.execDetached(["qs", "-c", "ano", "ipc", "call", "settings", "palette", "Notification history"]) }
                    }
                    ToolbarButton {
                        iconName: "close"; iconSize: 18
                        toolTipText: "Close"
                        onClicked: GlobalStates.notificationHistoryOpen = false
                    }
                }

                // ── Search ──
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 40; radius: 20
                    color: Appearance.colors.colLayer1
                    RowLayout {
                        anchors { fill: parent; leftMargin: 14; rightMargin: 8 }
                        spacing: 8
                        MaterialSymbol { text: "search"; iconSize: 20; opacity: 0.5 }
                        StyledTextInput {
                            id: search
                            Layout.fillWidth: true
                            verticalAlignment: TextInput.AlignVCenter
                            font.pixelSize: Appearance.font.pixelSize.small
                            focus: root.open
                            text: NotificationHistory.text
                            onTextChanged: NotificationHistory.text = text
                            StyledText {
                                anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                                text: "Search summaries, text and apps…"; opacity: 0.4; font.pixelSize: Appearance.font.pixelSize.small
                                visible: search.text.length === 0
                            }
                        }
                        ToolbarButton {
                            iconName: "close"; iconSize: 16
                            visible: search.text.length > 0
                            toolTipText: "Clear the search"
                            onClicked: search.text = ""
                        }
                    }
                }

                // ── Filters ──
                StyledFlickable {
                    Layout.fillWidth: true
                    implicitHeight: appChips.implicitHeight
                    contentWidth: appChips.implicitWidth
                    flickableDirection: Flickable.HorizontalFlick
                    clip: true
                    visible: NotificationHistory.apps.length > 1
                    Chips {
                        id: appChips
                        model: [{ value: "", label: "All apps" }].concat(NotificationHistory.apps.map(a => ({ value: a.app, label: `${a.app || "Unknown"} · ${a.count}` })))
                        current: NotificationHistory.app
                        onChose: value => NotificationHistory.app = value
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Chips {
                        model: [{ value: "all", label: "Any time" }, { value: "today", label: "Today" }, { value: "7d", label: "7 days" }, { value: "30d", label: "30 days" }]
                        current: NotificationHistory.range
                        onChose: value => NotificationHistory.range = value
                    }
                    Item { Layout.fillWidth: true }
                    Chips {
                        model: [{ value: "", label: "All" }, { value: "critical", label: "Critical" }, { value: "low", label: "Low" }]
                        current: NotificationHistory.urgency
                        onChose: value => NotificationHistory.urgency = value
                    }
                }

                // ── Problems and the delete confirmation ──
                NoticeBox {
                    Layout.fillWidth: true
                    visible: NotificationHistory.error !== "" || (NotificationHistory.stats.error ?? "") !== ""
                    level: "error"
                    text: NotificationHistory.error || NotificationHistory.stats.error || ""
                }
                Rectangle {
                    Layout.fillWidth: true
                    visible: root.pending !== null
                    implicitHeight: confirmRow.implicitHeight + 16
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colErrorContainer ?? Appearance.colors.colLayer2
                    RowLayout {
                        id: confirmRow
                        anchors { fill: parent; margins: 8; leftMargin: 14 }
                        spacing: 8
                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            color: Appearance.colors.colOnErrorContainer ?? Appearance.colors.colOnLayer2
                            readonly property var p: root.pending
                            text: !p ? "" : `Delete ${p.count} notification${p.count === 1 ? "" : "s"}${p.kind === "app" ? ` from ${p.app || "Unknown"}` : p.kind === "matching" ? (p.count === 1 ? " that matches" : " that match") : ""} from the history? This can't be undone.`
                        }
                        RippleButton { buttonText: "Cancel"; onClicked: root.pending = null }
                        RippleButton { buttonText: "Delete"; toggled: true; onClicked: root.confirmPending() } // filled: the main action
                    }
                }

                // ── The list ──
                ListView {
                    id: list
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 6
                    model: NotificationHistory.entries
                    boundsBehavior: Flickable.StopAtBounds
                    onAtYEndChanged: if (atYEnd) NotificationHistory.loadMore()
                    delegate: HistoryEntry {
                        required property var modelData
                        width: list.width
                        entry: modelData
                    }
                    footer: Item {
                        width: list.width
                        height: NotificationHistory.next ? 36 : 0
                        StyledText {
                            anchors.centerIn: parent
                            visible: NotificationHistory.next !== ""
                            text: NotificationHistory.loading ? "Loading…" : `${NotificationHistory.entries.length} of ${NotificationHistory.total}`
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.smaller
                        }
                    }
                    EmptyState {
                        anchors.centerIn: parent
                        width: parent.width * 0.8
                        visible: list.count === 0 && !NotificationHistory.loading && NotificationHistory.error === ""
                        icon: NotificationHistory.filtered ? "search_off" : "notifications_off"
                        title: NotificationHistory.filtered ? "Nothing matches" : NotificationHistory.enabled ? "No notifications yet" : "The history is off"
                        hint: NotificationHistory.filtered ? "Try other words or fewer filters." : NotificationHistory.enabled ? "Notifications you receive are kept here, even after you dismiss them." : "Turn it on in Settings → General → Notifications."
                        actionText: NotificationHistory.filtered ? "Clear search and filters" : ""
                        onAction: { search.text = ""; NotificationHistory.app = ""; NotificationHistory.urgency = ""; NotificationHistory.range = "all" }
                    }
                }

                // ── Bulk deletes ──
                RowLayout {
                    Layout.fillWidth: true
                    visible: NotificationHistory.total > 0
                    spacing: 8
                    StyledText {
                        Layout.fillWidth: true
                        text: NotificationHistory.filtered ? `${NotificationHistory.total} match` : `${NotificationHistory.total} notifications`
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                    RippleButton {
                        visible: NotificationHistory.app !== ""
                        buttonText: `Delete all from ${NotificationHistory.app || "Unknown"}`
                        onClicked: root.ask("app", NotificationHistory.app)
                    }
                    RippleButton {
                        visible: NotificationHistory.filtered && NotificationHistory.app === ""
                        buttonText: "Delete matches"
                        onClicked: root.ask("matching")
                    }
                    RippleButton {
                        buttonText: "Clear all…"
                        onClicked: root.ask("all")
                    }
                }
            }
        }
    }

    // A row of text chips, one selected (ChoiceRow is for icons).
    component Chips: Row {
        id: chips
        property var model: []
        property var current
        signal chose(var value)
        spacing: 4
        Repeater {
            model: chips.model
            RippleButton {
                required property var modelData
                buttonText: modelData.label
                toggled: chips.current === modelData.value
                buttonRadius: height / 2
                implicitHeight: 30
                leftPadding: 12; rightPadding: 12
                onClicked: chips.chose(modelData.value)
            }
        }
    }

    // One history entry: icon, app and time, summary and body (click to expand), and its actions.
    component HistoryEntry: Rectangle {
        id: entryItem
        property var entry
        property bool expanded: false
        readonly property bool critical: entry?.urgency === "critical"
        implicitHeight: entryRow.implicitHeight + 20
        radius: Appearance.rounding.normal
        color: hover.hovered ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1
        border.width: critical ? 1 : 0
        border.color: Appearance.colors.colError

        HoverHandler { id: hover }
        TapHandler { onTapped: entryItem.expanded = !entryItem.expanded }

        RowLayout {
            id: entryRow
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
            spacing: 10

            Rectangle {
                Layout.alignment: Qt.AlignTop
                width: 34; height: 34; radius: 17
                color: Appearance.colors.colSecondaryContainer
                StyledImage {
                    id: icon
                    anchors.centerIn: parent
                    width: 22; height: 22
                    source: FileUtils.iconSource(entryItem.entry?.icon || "")
                    visible: status === Image.Ready
                }
                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: !icon.visible
                    text: entryItem.critical ? "priority_high" : "notifications"
                    iconSize: 18
                    color: Appearance.m3colors.m3onSecondaryContainer
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                RowLayout {
                    Layout.fillWidth: true
                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: entryItem.entry?.app || "Unknown"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                    StyledText {
                        visible: !actions.visible
                        text: DateUtils.timeAgo(new Date(entryItem.entry?.time ?? 0))
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                    // On hover the actions take the time's place, so the entry keeps its height.
                    Row {
                        id: actions
                        visible: hover.hovered
                        Layout.preferredHeight: 0 // overhangs the header line instead of growing it
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 0
                        ToolbarButton { anchors.verticalCenter: parent.verticalCenter; iconName: "content_copy"; iconSize: 16; toolTipText: "Copy"; onClicked: NotificationHistory.copy(entryItem.entry) }
                        ToolbarButton {
                            anchors.verticalCenter: parent.verticalCenter
                            iconName: "open_in_new"; iconSize: 16; toolTipText: "Open the app"
                            visible: NotificationHistory.appEntry(entryItem.entry) !== null
                            onClicked: { NotificationHistory.openApp(entryItem.entry); GlobalStates.notificationHistoryOpen = false }
                        }
                        ToolbarButton { anchors.verticalCenter: parent.verticalCenter; iconName: "filter_alt"; iconSize: 16; toolTipText: "Only this app"; onClicked: NotificationHistory.app = entryItem.entry?.app ?? "" }
                        ToolbarButton { anchors.verticalCenter: parent.verticalCenter; iconName: "delete"; iconSize: 16; toolTipText: "Delete"; onClicked: NotificationHistory.deleteIds([entryItem.entry.id]) }
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    text: entryItem.entry?.summary ?? ""
                    font.weight: Font.DemiBold
                    wrapMode: Text.Wrap
                    maximumLineCount: entryItem.expanded ? 10 : 2
                    elide: Text.ElideRight
                    visible: text !== ""
                }
                StyledText {
                    Layout.fillWidth: true
                    text: entryItem.entry?.body ?? ""
                    textFormat: Text.StyledText
                    wrapMode: Text.Wrap
                    maximumLineCount: entryItem.expanded ? 40 : 2
                    elide: Text.ElideRight
                    color: Appearance.colors.colSubtext
                    visible: text !== ""
                }
            }
        }
    }
}
