import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

/**
 * App launcher & search overlay. Searches .desktop applications
 * via DesktopEntries, supports keyboard navigation, fuzzy matching and
 * recent apps; optional result providers (calculator, emoji, packages,
 * actions, schemes, looks) come first (Providers.qml).
 *
 * Opens centered, focuses search input immediately. Escape to close.
 */
Scope {
    id: root
    property string query: ""
    property int selectedIndex: 0

    readonly property var allApps: DesktopEntries.applications.values
    // The home list (recent apps, then A–Z) is kept while closed, rebuilt only
    // once DesktopEntries / recents settle, so opening doesn't build ~50 rows
    // (with icons) in its first frame. Searching builds as before.
    property var _home: []
    function _computeHome() {
        const recentIds = Config.options?.search?.recentApps ?? []
        const recents = recentIds.map(id => allApps.find(a => a.id === id)).filter(a => !!a)
        const rest = allApps.filter(a => !recentIds.includes(a.id)).sort((a, b) => (a.name ?? "").localeCompare(b.name ?? ""))
        return [...recents, ...rest].slice(0, 50)
    }
    Timer { id: homeDebounce; interval: 300; onTriggered: root._home = root._computeHome() }
    onAllAppsChanged: homeDebounce.restart()
    Connections { target: Config.options?.search ?? null; ignoreUnknownSignals: true; function onRecentAppsChanged() { homeDebounce.restart() } }
    Component.onCompleted: homeDebounce.restart()

    readonly property var filteredApps: {
        if (query.length === 0) return root._home.filter(a => !!a && !!a.id) // an entry gone before the rebuild
        const q = query.toLowerCase()
        return allApps.filter(app => {
            const name = (app.name ?? "").toLowerCase()
            const desc = (app.comment ?? "").toLowerCase()
            const exec = (app.exec ?? "").toLowerCase()
            const id = (app.id ?? "").toLowerCase()
            return name.includes(q) || desc.includes(q) || exec.includes(q) || id.includes(q)
        }).sort((a, b) => {
            // Exact prefix match first
            const aName = (a.name ?? "").toLowerCase()
            const bName = (b.name ?? "").toLowerCase()
            const aStarts = aName.startsWith(q) ? 0 : 1
            const bStarts = bName.startsWith(q) ? 0 : 1
            if (aStarts !== bStarts) return aStarts - bStarts
            return aName.localeCompare(bName)
        }).slice(0, 30)
    }

    Providers { id: providers; query: root.query }

    // A provider row (leading or trailing); `offset` is its place in the flat list.
    component ProviderRow: Rectangle {
        required property var modelData
        required property int index
        property int offset: 0
        readonly property bool isSelected: root.selectedIndex === index + offset
        Layout.fillWidth: true
        implicitHeight: 44
        radius: Appearance?.rounding.small ?? 8
        color: isSelected ? Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.15)
            : provMA.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"
        border.width: isSelected ? 1 : 0
        border.color: Appearance.colors.colPrimary
        RowLayout {
            anchors { fill: parent; margins: 6 }
            spacing: 10
            Item {
                implicitWidth: 32; implicitHeight: 32
                MaterialSymbol { anchors.centerIn: parent; visible: !modelData.text; text: modelData.icon ?? "bolt"; iconSize: 24; color: Appearance.colors.colPrimary }
                Text { anchors.centerIn: parent; visible: !!modelData.text; text: modelData.text ?? ""; textFormat: Text.PlainText; font.pixelSize: 24 }
            }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 0
                // Plain text: results carry what plugins and the clipboard give.
                StyledText { text: modelData.title ?? ""; textFormat: Text.PlainText; font.pixelSize: Appearance.font.pixelSize.small; font.weight: isSelected ? Font.DemiBold : Font.Normal; elide: Text.ElideRight; Layout.fillWidth: true }
                StyledText { text: modelData.subtitle ?? ""; textFormat: Text.PlainText; visible: text !== ""; font.pixelSize: Appearance.font.pixelSize.smaller; opacity: 0.45; elide: Text.ElideRight; Layout.fillWidth: true }
            }
        }
        MouseArea {
            id: provMA
            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: root.activate(index + offset)
            onEntered: root.selectedIndex = index + offset
        }
    }
    // One list for keyboard navigation: leading provider results, the apps,
    // then trailing ones (emoji typed without ":"), so "fire" + Enter still
    // launches Firefox.
    readonly property int providerCount: providers.results.length
    readonly property int appEnd: providerCount + filteredApps.length
    readonly property int totalCount: appEnd + providers.trailing.length
    function activate(i) {
        const r = i < root.providerCount ? providers.results[i] : i >= root.appEnd ? providers.trailing[i - root.appEnd] : null
        if (r) {
            if (r.run() === false) return // e.g. a guarded action: stay and say why
            // The query is reset once closed (closeReset): cleared now, the
            // list would swap to the home rows and change height mid-close.
            GlobalStates.searchOpen = false
            return
        }
        root.launch(root.filteredApps[i - root.providerCount])
    }

    function launch(app) {
        if (app) {
            DefaultApps.launchEntry(app)
            // Track in recents
            const recents = [...(Config.options?.search?.recentApps ?? [])]
            const idx = recents.indexOf(app.id)
            if (idx >= 0) recents.splice(idx, 1)
            recents.unshift(app.id)
            Config.setNestedValue("search.recentApps", recents.slice(0, 10))
        }
        GlobalStates.searchOpen = false // query reset once closed (closeReset)
    }

    Connections {
        target: GlobalStates
        function onSearchOpenChanged() {
            if (GlobalStates.searchOpen) { closeReset.stop(); root.query = ""; root.selectedIndex = 0 }
            else closeReset.restart()
        }
    }
    // Back to the home list once closed (not at the next open, where swapping
    // the list would build its rows in the opening frame).
    Timer { id: closeReset; interval: 450; onTriggered: { searchInput.text = ""; root.query = ""; root.selectedIndex = 0 } }

    IpcHandler {
        target: "search"
        function toggle(): void { GlobalStates.searchOpen = !GlobalStates.searchOpen }
        function open(): void { GlobalStates.searchOpen = true }
        function close(): void { GlobalStates.searchOpen = false }
    }

    PanelWindow {
        id: searchWindow
        // One spring drives the open/close; the window stays mapped until the
        // card has retracted, and reversing mid-flight retargets smoothly.
        property real shown: GlobalStates.searchOpen ? 1 : 0
        Behavior on shown { id: shownMotion; MotionSpring { token: shownMotion.targetValue > 0.5 ? "liquid" : "settle" } }
        visible: GlobalStates.searchOpen || shown > 0.01
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell:search"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: GlobalStates.searchOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        anchors { top: true; bottom: true; left: true; right: true }

        // Keys can't attach to a window; the focused input forwards here.
        function handleKey(event) {
            if (event.key === Qt.Key_Escape) { GlobalStates.searchOpen = false; event.accepted = true; return }
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                if (root.selectedIndex < root.totalCount) root.activate(root.selectedIndex)
                event.accepted = true; return
            }
            if (event.key === Qt.Key_Down || (event.key === Qt.Key_Tab && !(event.modifiers & Qt.ShiftModifier))) {
                root.selectedIndex = Math.min(root.selectedIndex + 1, root.totalCount - 1)
                event.accepted = true
            }
            if (event.key === Qt.Key_Up || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
                root.selectedIndex = Math.max(root.selectedIndex - 1, 0)
                event.accepted = true
            }
        }

        // Click outside to close; nothing dims the desktop behind the launcher.
        MouseArea { anchors.fill: parent; onClicked: GlobalStates.searchOpen = false }

        // Search card — positioned in upper third of screen
        SurfaceMaterial {
            id: searchCard
            surface: "search"
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height * 0.15
            width: Math.min(560, parent.width * 0.65)
            height: Math.min(searchContent.implicitHeight + 32, parent.height * 0.65)
            radius: Appearance?.rounding.windowRounding ?? 20
            color: Appearance?.m3colors.m3background ?? "#1C1B1F"
            clip: true

            // Grows down from its top edge (a drop-in, not a fade): scale from the
            // top, with the content fading in once the card has some size.
            transformOrigin: Item.Top
            scale: 0.9 + 0.1 * searchWindow.shown
            opacity: Math.max(0, Math.min(1, searchWindow.shown * 1.6 - 0.2))

            ColumnLayout {
                id: searchContent
                anchors { fill: parent; margins: 16 }
                spacing: 12

                // Search input
                Rectangle {
                    Layout.fillWidth: true; implicitHeight: 48; radius: 24
                    color: Appearance?.colors.colLayer1 ?? "#E5E1EC"

                    RowLayout {
                        anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                        spacing: 10
                        MaterialSymbol { text: "search"; iconSize: 24; color: Appearance?.colors.colPrimary ?? "#65558F" }
                        StyledTextInput {
                            id: searchInput
                            Layout.fillWidth: true
                            verticalAlignment: TextInput.AlignVCenter
                            font.pixelSize: Appearance.font.pixelSize.normal
                            focus: GlobalStates.searchOpen
                            onTextChanged: { root.query = text; root.selectedIndex = 0 }
                            Keys.onPressed: event => searchWindow.handleKey(event)

                            StyledText {
                                anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                                text: "Search apps..."; opacity: 0.3; font.pixelSize: Appearance.font.pixelSize.normal
                                visible: !searchInput.text || searchInput.text.length === 0
                            }
                        }
                        ToolbarButton {
                            iconName: "close"; iconSize: 18
                            visible: root.query.length > 0
                            onClicked: { searchInput.text = "" }
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: providers.message !== ""
                    text: providers.message
                    wrapMode: Text.Wrap
                    color: Appearance.m3colors.m3error
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }

                // App list
                StyledFlickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredHeight: Math.min(appColumn.implicitHeight, 400)
                    contentHeight: appColumn.implicitHeight
                    clip: true

                    ColumnLayout {
                        id: appColumn
                        width: parent.width; spacing: 2

                        // Section header for recents
                        StyledText {
                            visible: root.query.length === 0 && (Config.options?.search?.recentApps ?? []).length > 0
                            text: "Recent"
                            font.pixelSize: Appearance.font.pixelSize.smaller; opacity: 0.4; font.weight: Font.DemiBold
                            Layout.fillWidth: true; Layout.topMargin: 4
                        }

                        // Provider results (calculator, emoji, actions, …)
                        Repeater {
                            model: providers.results
                            ProviderRow {}
                        }

                        Repeater {
                            model: root.filteredApps

                            Rectangle {
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                implicitHeight: 44
                                radius: Appearance?.rounding.small ?? 8

                                property bool isSelected: root.selectedIndex === index + root.providerCount
                                color: isSelected
                                    ? Qt.rgba((Appearance?.colors.colPrimary ?? "#65558F").r, (Appearance?.colors.colPrimary ?? "#65558F").g, (Appearance?.colors.colPrimary ?? "#65558F").b, 0.15)
                                    : appItemMA.containsMouse ? Appearance?.colors.colLayer1Hover ?? "#E5DFED" : "transparent"
                                border.width: isSelected ? 1 : 0
                                border.color: Appearance?.colors.colPrimary ?? "#65558F"

                                RowLayout {
                                    anchors { fill: parent; margins: 6 }
                                    spacing: 10
                                    IconImage {
                                        implicitWidth: 32; implicitHeight: 32
                                        source: FileUtils.themedIcon(modelData.icon || modelData.id)
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true; spacing: 0
                                        StyledText {
                                            text: modelData.name ?? modelData.id ?? ""
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.weight: isSelected ? Font.DemiBold : Font.Normal
                                            elide: Text.ElideRight; Layout.fillWidth: true
                                        }
                                        StyledText {
                                            text: modelData.comment ?? ""
                                            font.pixelSize: Appearance.font.pixelSize.smaller; opacity: 0.4
                                            elide: Text.ElideRight; Layout.fillWidth: true
                                            visible: (modelData.comment ?? "").length > 0
                                        }
                                    }
                                }

                                MouseArea {
                                    id: appItemMA
                                    anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.launch(modelData)
                                    onEntered: root.selectedIndex = index + root.providerCount
                                }
                            }
                        }

                        // Emoji typed without ":" come after the apps.
                        Repeater {
                            model: providers.trailing
                            ProviderRow { offset: root.appEnd }
                        }

                        StyledText {
                            visible: root.totalCount === 0
                            text: providers.searchingPackages ? "Searching packages…"
                                : providers.pkgQuery.length > 0 ? "No packages found"
                                : root.query.length > 0 ? "No apps found" : "No applications"
                            font.pixelSize: Appearance.font.pixelSize.small; opacity: 0.4
                            Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 20
                        }
                    }
                }

                // Footer
                StyledText {
                    text: "↑↓ Navigate • Enter to launch • Esc to close"
                    font.pixelSize: Appearance.font.pixelSize.smallest; opacity: 0.3
                    Layout.alignment: Qt.AlignHCenter
                }
            }
        }
    }

    // Super tap toggles search (Hyprland: the bundled binds send
    // searchToggleRelease on Super, and an interrupt on Ctrl/click combos).
    // 0.56 has no global catchall, so a combo is also recognised by its
    // effect: a long hold, or a workspace/focus change while Super was down.
    property bool _superArmed: false
    property real _superAt: 0
    property int _superWs: 0
    property var _superFocus: null
    Loader {
        active: CompositorService.compositor === "hyprland"
        sourceComponent: Item {
            GlobalShortcut {
                name: "searchToggleRelease"; description: "Toggle search (tap Super)"
                onPressed: {
                    root._superArmed = true
                    root._superAt = Date.now()
                    root._superWs = CompositorService.activeWorkspaceIndex
                    root._superFocus = ToplevelManager.activeToplevel
                }
                onReleased: {
                    const tap = root._superArmed && Date.now() - root._superAt < 500
                        && CompositorService.activeWorkspaceIndex === root._superWs
                        && ToplevelManager.activeToplevel === root._superFocus
                    root._superArmed = false
                    if (tap) GlobalStates.searchOpen = !GlobalStates.searchOpen
                }
            }
            GlobalShortcut {
                name: "searchToggleReleaseInterrupt"; description: "Cancel the Super-tap search"
                onPressed: root._superArmed = false
            }
        }
    }
}
