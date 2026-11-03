import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import "."

/**
 * Settings → Atelier (spec atelier): themes, looks, pieces, plugins, lock screens, wallpapers and
 * rices from the shell (built-in), your folders and online catalogs, in one
 * searchable grid per type. A card opens its detail: Apply for what you
 * have, Install / Update / Remove for catalog items (installing never
 * applies). Pieces run code, so installing one first shows anod's audit and
 * asks. Rices apply their look; keybinds and compositor layers only when
 * ticked, and Undo puts the previous setup back.
 *
 *   ano atelier [type]   ·   qs -c ano ipc call atelier open wallpapers
 */
ColumnLayout {
    id: root
    spacing: 16

    property string query: ""
    property var selected: null        // the item whose detail is open
    property string stage: ""          // "", "preparing", "confirm", "installing", "failed"
    property var prepared: null        // atelier.prepare's answer
    property string message: ""
    property bool messageIsError: false
    property var layers: ({ keybinds: false })

    function say(text, error) { root.message = text; root.messageIsError = !!error }

    readonly property string tab: Atelier.tab
    readonly property var shown: {
        const q = root.query.trim().toLowerCase()
        const match = it => !q || `${it.name ?? ""} ${it.id} ${it.author ?? ""} ${it.description ?? ""}`.toLowerCase().includes(q)
        const local = Atelier.items.filter(it => it.type === root.tab && match(it))
        // Catalog entries not already local (an installed one shows as local, with its update).
        const remote = Atelier.catalog.filter(it => it.type === root.tab && !it.installed && match(it))
            .map(it => Object.assign({ source: "catalog" }, it))
        return local.concat(remote)
    }
    readonly property var catalogsOffline: Atelier.catalogs.filter(c => c.offline || !c.ok)

    function sourceLabel(it) {
        switch (it.source) {
        case "builtin": return "Built-in"
        case "user": return "Yours"
        case "installed": return `Installed · ${it.catalogName || Atelier.catalogs.find(c => c.url === it.catalog)?.name || it.catalog || "catalog"}`
        case "catalog": return it.catalogName || it.catalog || "Catalog"
        }
        return it.source ?? ""
    }
    function open(it) { root.selected = it; root.stage = ""; root.prepared = null; root.say("") }
    function close() {
        if (root.prepared?.token) Atelier.cancel(root.prepared.token)
        root.selected = null; root.stage = ""; root.prepared = null; root.say("")
    }

    // Install / update: prepare, then commit at once for data, or after the
    // confirmation for code (and for an update over files you changed).
    function install(it) {
        root.stage = "preparing"; root.say("")
        const want = `${it.type}/${it.id}`
        Atelier.prepare(it.type, it.id, it.catalog, (r, e) => {
            // The answer for an item that is no longer open (Back, another
            // item or tab meanwhile) is dropped, and its download with it.
            if (!root.selected || `${root.selected.type}/${root.selected.id}` !== want || root.stage !== "preparing") {
                if (r?.token) Atelier.cancel(r.token)
                return
            }
            if (!r) { root.stage = "failed"; root.say(e?.message ?? "anod didn't answer", true); return }
            root.prepared = r
            if (r.code || (r.modifiedFiles ?? []).length || r.capabilitiesChanged) { root.stage = "confirm"; return }
            root.commit()
        })
    }
    function commit() {
        const t = root.prepared?.token
        root.stage = "installing"
        Atelier.commit(t, (r, e) => {
            if (!r) { root.stage = "failed"; root.say(e?.message ?? "anod didn't answer", true); return }
            root.stage = ""; root.prepared = null
            root.say(`Installed. ${root.selected?.type === "rices" ? "Apply it when you like." : "Apply it from here when you like."}`)
            Atelier.list()
        })
    }
    function remove(it) {
        Atelier.remove(it.type, it.id, (r, e) => {
            if (e) { root.say(e.message, true); return }
            root.say(`Removed ${it.name || it.id}.`)
            root.selected = null
            Atelier.list()
        })
    }
    function apply(it) {
        if (it.type === "rices") {
            const l = Object.keys(root.layers).filter(k => root.layers[k])
            root.say("Applying…")
            Atelier.riceApply(it.id, l, (r, e) => {
                if (e) { root.say(e.message, true); return }
                root.say(`Applied ${it.name || it.id}${l.length ? ` with ${l.join(" and ")}` : ""}. Undo puts your previous setup back.`)
                Atelier.list()
            })
            return
        }
        const m = Atelier.apply(it)
        const name = it.name || it.id
        root.say(m || (it.type === "plugins" ? `${name} is ${LauncherPlugins.isEnabled(it.id) ? "on: try it in the launcher" : "off"}.`
            : it.type === "lockscreens" ? `${name} is your lock screen.` : it.type === "pieces" ? `${name} is on the desktop page you're on.` : `${name} applied.`), !!m)
    }

    // On the Pieces tab the registry compile-checks pieces, so a broken one
    // says why instead of offering "Add to desktop".
    readonly property bool _checkPieces: root.tab === "pieces"
    on_CheckPiecesChanged: Pieces.hold(_checkPieces)
    Component.onDestruction: if (_checkPieces) Pieces.hold(false)

    // After an install or remove the list changes: the open detail follows
    // the item (the catalog entry becomes the installed copy and back).
    Connections {
        target: Atelier
        function onItemsChanged() {
            const sel = root.selected
            if (!sel) return
            const local = Atelier.items.find(x => x.type === sel.type && x.id === sel.id)
            if (local) root.selected = local
            else if (sel.source !== "catalog") root.selected = Atelier.catalog.find(x => x.type === sel.type && x.id === sel.id) ? Object.assign({ source: "catalog" }, Atelier.catalog.find(x => x.type === sel.type && x.id === sel.id)) : null
        }
    }
    Component.onCompleted: { if (_checkPieces) Pieces.hold(true); Atelier.list(); if (Atelier.catalogs.length === 0 && (Config.options?.atelier?.catalogs ?? []).length) Atelier.refresh() }

    SettingsPageHeader {
        title: "Atelier"
        subtitle: "Themes, looks, pieces, launcher plugins, lock screens, wallpapers and rices: built-in, yours and from catalogs"
        configRoots: ["atelier"]
    }

    // ═══ Browse ═══
    SettingsCard {
        icon: "storefront"
        title: Atelier.typeName(root.tab)
        subtitle: `${root.shown.length} item(s)` + (Atelier.refreshing ? " · checking catalogs…" : "")
        collapsible: false
        configKeys: ["atelier"]

        // Tabs
        Flow {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: Atelier.types
                delegate: RippleButtonWithIcon {
                    required property var modelData
                    iconName: modelData.icon
                    buttonText: modelData.name
                    toggled: root.tab === modelData.id
                    onClicked: { Atelier.tab = modelData.id; root.close() }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            ConfigTextInput {
                Layout.fillWidth: true
                placeholderText: `Search ${Atelier.typeName(root.tab).toLowerCase()}…`
                text: root.query
                onTextChanged: root.query = text
                iconAction: text.length > 0 ? "close" : "search"
                onIconClicked: { if (text.length > 0) text = "" }
            }
            RippleButton {
                buttonText: Atelier.refreshing ? "Checking…" : "Check catalogs"
                enabled: !Atelier.refreshing && Anod.available
                onClicked: Atelier.refresh()
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: !Anod.available || Atelier.error.length > 0
            wrapMode: Text.Wrap
            color: Appearance.m3colors.m3error
            text: !Anod.available ? "The Atelier needs anod (the AnoShell daemon), which isn't running." : Atelier.error
        }
        StyledText {
            Layout.fillWidth: true
            visible: root.catalogsOffline.length > 0
            wrapMode: Text.Wrap
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
            text: `Offline: ${root.catalogsOffline.map(c => c.name || c.url).join(", ")} — showing what was fetched last.`
        }
        StyledText {
            Layout.fillWidth: true
            visible: root.message.length > 0 && !root.selected
            wrapMode: Text.Wrap
            color: root.messageIsError ? Appearance.m3colors.m3error : Appearance.colors.colSubtext
            text: root.message
        }

        // Grid
        Flow {
            id: grid
            Layout.fillWidth: true
            visible: !root.selected
            spacing: 10
            readonly property real cardW: Math.max(150, (width - spacing * (cols - 1)) / cols)
            readonly property int cols: Math.max(2, Math.floor((width + spacing) / (180 + spacing)))
            Repeater {
                model: root.selected ? [] : root.shown
                delegate: AtelierCard {
                    required property var modelData
                    item: modelData
                    width: grid.cardW
                    onClicked: root.open(modelData)
                }
            }
        }
        StyledText {
            Layout.fillWidth: true
            visible: !root.selected && root.shown.length === 0 && !Atelier.loading
            horizontalAlignment: Text.AlignHCenter
            color: Appearance.colors.colSubtext
            wrapMode: Text.Wrap
            text: root.query ? "Nothing matches." : (root.tab === "rices" ? "No rices yet. Export your setup below, or add a catalog." : "Nothing here yet.")
        }

        // Detail
        Loader {
            Layout.fillWidth: true
            active: !!root.selected
            visible: active
            sourceComponent: detail
        }
    }

    Component {
        id: detail
        ColumnLayout {
            spacing: 12
            readonly property var it: root.selected
            readonly property bool isLocal: it.source !== "catalog"
            readonly property bool active: isLocal && Atelier.isActive(it)

            RowLayout {
                Layout.fillWidth: true
                RippleButtonWithIcon { iconName: "arrow_back"; buttonText: "Back"; onClicked: root.close() }
                Item { Layout.fillWidth: true }
                StyledText { text: root.sourceLabel(it); color: Appearance.colors.colSubtext }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 16
                AtelierPreview {
                    entry: it
                    Layout.preferredWidth: 260
                    Layout.preferredHeight: 170
                    Layout.alignment: Qt.AlignTop
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    spacing: 4
                    StyledText { text: it.name || it.id; font.pixelSize: Appearance.font.pixelSize.larger; font.weight: Font.DemiBold; Layout.fillWidth: true; elide: Text.ElideRight }
                    StyledText {
                        Layout.fillWidth: true
                        color: Appearance.colors.colSubtext
                        text: [it.author ? `by ${it.author}` : "", it.version ? `v${it.version}` : "", it.licence ?? ""].filter(s => s).join(" · ")
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: (it.description ?? "").length > 0
                        wrapMode: Text.Wrap
                        text: it.description ?? ""
                    }
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        color: Appearance.colors.colWarning
                        visible: text.length > 0
                        text: it.revoked ? "The catalog revoked this item: remove it." : it.unavailable ? `Not available here (${it.unavailable}).`
                            : (isLocal && Atelier.problems(it).length) ? `It doesn't load: ${Atelier.problems(it).join("; ")}`
                            : it.modified ? "You changed its files since installing; an update asks first." : ""
                    }
                }
            }

            // Rice layers
            ColumnLayout {
                visible: it.type === "rices" && isLocal
                Layout.fillWidth: true
                spacing: 2
                StyledText { text: "Also apply (off unless you tick them):"; color: Appearance.colors.colSubtext }
                Repeater {
                    // (a compositor layer isn't applied yet: raw Hyprland Lua / niri KDL is code)
                    model: (it.keybinds ?? []).length ? [{ key: "keybinds", label: `Its keybinds (${it.keybinds.length})` }] : []
                    delegate: ConfigSwitch {
                        required property var modelData
                        Layout.fillWidth: true
                        label: modelData.label
                        checked: root.layers[modelData.key] ?? false
                        onCheckedChanged: { const l = Object.assign({}, root.layers); l[modelData.key] = checked; root.layers = l }
                    }
                }
            }

            // What the keybinds layer would set (commands spelled out).
            ColumnLayout {
                visible: it.type === "rices" && isLocal && (it.keybinds ?? []).length > 0
                Layout.fillWidth: true
                spacing: 1
                Repeater {
                    model: (it.keybinds ?? []).slice(0, 30)
                    delegate: StyledText {
                        required property var modelData
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: modelData.command ? Appearance.colors.colWarning : Appearance.colors.colOnLayer1
                        text: `${modelData.chord}  →  ${modelData.command ? "runs " + modelData.command : (modelData.label || modelData.action)}`
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: (it.keybinds ?? []).length > 30
                    color: Appearance.colors.colSubtext
                    text: `…and ${(it.keybinds ?? []).length - 30} more`
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: (it.keybindsDropped ?? []).length > 0
                    wrapMode: Text.Wrap
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                    text: `Left out: ${(it.keybindsDropped ?? []).join("; ")}`
                }
            }

            // Code confirmation
            Rectangle {
                Layout.fillWidth: true
                visible: root.stage === "confirm"
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2
                implicitHeight: confirmCol.implicitHeight + 24
                ColumnLayout {
                    id: confirmCol
                    anchors { fill: parent; margins: 12 }
                    spacing: 6
                    readonly property var p: root.prepared ?? {}
                    StyledText {
                        Layout.fillWidth: true; wrapMode: Text.Wrap; font.weight: Font.DemiBold
                        text: confirmCol.p.code
                            ? `This ${Atelier.typeName(it.type).toLowerCase().replace(/s$/, "")} runs code with your rights, without a sandbox.`
                            : "Your changes to this item will be replaced."
                    }
                    StyledText {
                        Layout.fillWidth: true; wrapMode: Text.Wrap; color: Appearance.colors.colSubtext
                        text: `By ${confirmCol.p.author || "an unknown author"}, from ${confirmCol.p.catalogName || confirmCol.p.catalog || "a catalog"}. Catalog review is not a security audit.`
                            + (confirmCol.p.capabilitiesChanged ? " This update declares different network hosts or commands than the installed version." : "")
                    }
                    StyledText {
                        Layout.fillWidth: true; wrapMode: Text.Wrap
                        visible: (confirmCol.p.hosts ?? []).length + (confirmCol.p.commands ?? []).length > 0
                        text: [(confirmCol.p.hosts ?? []).length ? `Talks to: ${confirmCol.p.hosts.join(", ")}` : "",
                               (confirmCol.p.commands ?? []).length ? `Runs: ${confirmCol.p.commands.join(", ")}` : ""].filter(s => s).join("\n")
                    }
                    StyledText {
                        Layout.fillWidth: true; wrapMode: Text.Wrap
                        visible: (confirmCol.p.modifiedFiles ?? []).length > 0
                        text: `Files you changed: ${(confirmCol.p.modifiedFiles ?? []).join(", ")}`
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: !!confirmCol.p.code
                        color: (confirmCol.p.findings ?? []).length ? Appearance.m3colors.m3error : Appearance.colors.colSubtext
                        text: (confirmCol.p.findings ?? []).length ? `The check found ${confirmCol.p.findings.length} thing(s) to look at:` : "The check found nothing suspicious."
                    }
                    Repeater {
                        model: confirmCol.p.findings ?? []
                        delegate: StyledText {
                            required property var modelData
                            Layout.fillWidth: true; wrapMode: Text.Wrap
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: modelData.severity === "high" ? Appearance.m3colors.m3error : Appearance.colors.colOnLayer1
                            text: `• ${modelData.detail || modelData.rule} — ${modelData.file}${modelData.line ? ":" + modelData.line : ""}`
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Item { Layout.fillWidth: true }
                        RippleButton { buttonText: "Cancel"; onClicked: { Atelier.cancel(root.prepared?.token); root.prepared = null; root.stage = "" } }
                        RippleButton {
                            buttonText: (confirmCol.p.findings ?? []).length ? "Install anyway" : "Install"
                            toggled: true // the primary fill
                            onClicked: root.commit()
                        }
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.stage === "preparing" || root.stage === "installing" || root.message.length > 0
                wrapMode: Text.Wrap
                color: root.stage === "failed" || root.messageIsError ? Appearance.m3colors.m3error : Appearance.colors.colSubtext
                text: root.stage === "preparing" ? "Downloading and checking…" : root.stage === "installing" ? "Installing…" : root.message
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                visible: root.stage !== "confirm"
                Item { Layout.fillWidth: true }
                RippleButton {
                    visible: it.source === "installed"
                    buttonText: "Remove"
                    enabled: root.stage === "" || root.stage === "failed"
                    onClicked: root.remove(it)
                }
                RippleButton {
                    visible: it.source === "installed" && !!it.update
                    buttonText: `Update to ${it.update}`
                    enabled: root.stage === "" || root.stage === "failed"
                    onClicked: root.install(it)
                }
                RippleButton {
                    visible: !isLocal
                    buttonText: root.stage === "failed" ? "Retry" : "Install"
                    toggled: true // the primary fill
                    enabled: (root.stage === "" || root.stage === "failed") && !it.revoked && !it.unavailable
                    onClicked: root.install(it)
                }
                RippleButton {
                    visible: isLocal && it.type === "lockscreens" && (Config.options?.lock?.enable ?? true)
                    buttonText: "Preview"
                    enabled: Atelier.problems(it).length === 0
                    onClicked: LockScreens.preview(it.id)
                }
                RippleButton {
                    visible: isLocal && it.type !== "rices"
                    buttonText: ({ pieces: active ? "Add another" : "Add to desktop", plugins: active ? "Turn off" : "Turn on",
                        lockscreens: active ? "In use" : "Use" })[it.type] ?? (active ? "Applied" : "Apply")
                    enabled: (!active || it.type === "pieces" || it.type === "plugins") && !it.revoked
                        && (it.type === "pieces" ? Pieces.usable(it.id) : active || Atelier.problems(it).length === 0)
                    toggled: true // the primary fill
                    onClicked: root.apply(it)
                }
                RippleButton {
                    visible: isLocal && it.type === "rices"
                    buttonText: "Apply rice"
                    toggled: true // the primary fill
                    onClicked: root.apply(it)
                }
            }
        }
    }

    // ═══ Wallhaven (Wallpapers tab) ═══
    SettingsCard {
        id: wh
        visible: root.tab === "wallpapers"
        icon: "travel_explore"
        title: "Wallhaven"
        subtitle: "Search wallhaven.cc and install a wallpaper into your wallpaper folder (atelier/). Safe-for-work only unless your Wallhaven key is set."
        configKeys: ["background.wallhaven"]
        property var results: []
        property int page: 1
        property int lastPage: 1
        property bool busy: false
        property string note: ""
        property string installing: ""
        function search(p) {
            wh.busy = true; wh.note = ""
            Atelier.wallhaven(whQuery.text.trim(), p, (r, e) => {
                wh.busy = false
                if (!r) { wh.note = e?.message ?? "anod didn't answer"; return }
                if (r.error) wh.note = r.error
                wh.results = r.items ?? []; wh.page = r.page ?? p; wh.lastPage = r.lastPage ?? p
            })
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            ConfigTextInput {
                id: whQuery
                Layout.fillWidth: true
                placeholderText: "Search Wallhaven (empty: latest)…"
            }
            RippleButton { buttonText: wh.busy ? "Searching…" : "Search"; enabled: !wh.busy && Anod.available; onClicked: wh.search(1) }
        }
        StyledText { Layout.fillWidth: true; visible: wh.note.length > 0; wrapMode: Text.Wrap; color: Appearance.m3colors.m3error; text: wh.note }
        Flow {
            id: whGrid
            Layout.fillWidth: true
            spacing: 8
            readonly property int cols: Math.max(2, Math.floor((width + spacing) / (170 + spacing)))
            readonly property real cardW: (width - spacing * (cols - 1)) / cols
            Repeater {
                model: wh.results
                delegate: RippleButton {
                    id: whCard
                    required property var modelData
                    width: whGrid.cardW
                    implicitHeight: width * 0.62 + 30
                    buttonRadius: Appearance.rounding.small
                    colBackground: Appearance.colors.colLayer2
                    enabled: !modelData.installed && wh.installing === ""
                    onClicked: {
                        const id = modelData.id // the card may be gone when the answer comes (a new search)
                        wh.installing = id
                        Atelier.wallhavenInstall(id, (r, e) => {
                            wh.installing = ""
                            if (!r) { wh.note = e?.message ?? "Install failed"; return }
                            const l = wh.results.slice(); const i = l.findIndex(x => x.id === id)
                            if (i >= 0) l[i] = Object.assign({}, l[i], { installed: true })
                            wh.results = l
                            root.say(`Installed ${r.path}: find it above to apply.`)
                            Atelier.list()
                        })
                    }
                    ColumnLayout {
                        anchors { fill: parent; margins: 4 }
                        spacing: 2
                        Image {
                            Layout.fillWidth: true; Layout.fillHeight: true
                            source: /^https:\/\//.test(whCard.modelData.thumb ?? "") ? whCard.modelData.thumb : ""
                            asynchronous: true; fillMode: Image.PreserveAspectCrop; sourceSize.width: 340; clip: true
                        }
                        StyledText {
                            Layout.fillWidth: true; elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            text: wh.installing === whCard.modelData.id ? "Installing…" : whCard.modelData.installed ? `${whCard.modelData.resolution} · installed` : `${whCard.modelData.resolution} · install`
                        }
                    }
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            visible: wh.results.length > 0
            Item { Layout.fillWidth: true }
            RippleButton { buttonText: "Previous"; enabled: !wh.busy && wh.page > 1; onClicked: wh.search(wh.page - 1) }
            StyledText { text: `${wh.page} / ${wh.lastPage}`; color: Appearance.colors.colSubtext }
            RippleButton { buttonText: "Next"; enabled: !wh.busy && wh.page < wh.lastPage; onClicked: wh.search(wh.page + 1) }
        }
    }

    // ═══ Rices: undo + export ═══
    SettingsCard {
        visible: root.tab === "rices"
        icon: "history"
        title: "Your setup"
        subtitle: "Undo the last rice, or save what you have now as one"
        configKeys: []
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            ConfigTextInput {
                id: riceName
                Layout.fillWidth: true
                placeholderText: "Name for your rice…"
            }
            RippleButton {
                buttonText: "Export"
                enabled: riceName.text.trim().length > 0 && Anod.available
                onClicked: Atelier.riceExport(riceName.text.trim(), (r, e) => {
                    if (e) { root.say(e.message, true); return }
                    root.say(`Saved as ${r.id} (${r.path}).`); riceName.text = ""; Atelier.list()
                })
            }
            RippleButton {
                buttonText: Atelier.lastRice ? `Undo ${Atelier.lastRice.name || Atelier.lastRice.id} (${Qt.formatDateTime(new Date(Atelier.lastRice.appliedAt * 1000), "d MMM, hh:mm")})` : "Nothing to undo"
                enabled: Anod.available && !!Atelier.lastRice
                onClicked: Atelier.riceUndo((r, e) => { root.say(e ? e.message : (r?.kept ?? []).length ? `Your previous setup is back, except what you changed since: ${r.kept.join(", ")}.` : "Your previous setup is back.", !!e); Atelier.list() })
            }
        }
    }

    // ═══ Catalogs ═══
    SettingsCard {
        id: catalogsCard
        icon: "public"
        title: "Catalogs"
        subtitle: "Online lists of themes, pieces and more. Anyone can publish one: add only those you trust"
        configKeys: ["atelier.catalogs"]
        readonly property var urls: Array.from(Config.options?.atelier?.catalogs ?? [])

        Repeater {
            model: catalogsCard.urls
            delegate: RowLayout {
                required property string modelData
                Layout.fillWidth: true
                readonly property var info: Atelier.catalogs.find(c => c.url === modelData)
                MaterialSymbol { text: info?.ok ? "cloud_done" : info ? "cloud_off" : "cloud"; iconSize: 18; color: Appearance.colors.colSubtext }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText { Layout.fillWidth: true; text: info?.name || modelData; elide: Text.ElideRight }
                    StyledText {
                        Layout.fillWidth: true; elide: Text.ElideRight
                        color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.small
                        text: info?.error ? `${modelData} — ${info.error}` : modelData
                    }
                }
                RippleButtonWithIcon {
                    iconName: "delete"
                    buttonText: "Remove"
                    onClicked: Config.setNestedValue("atelier.catalogs", Array.from(Config.options?.atelier?.catalogs ?? []).filter(u => u !== modelData))
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            ConfigTextInput {
                id: catalogUrl
                Layout.fillWidth: true
                placeholderText: "https://…/index.json"
            }
            RippleButton {
                buttonText: "Add"
                enabled: /^https:\/\/[^\s]+$/.test(catalogUrl.text.trim())
                onClicked: {
                    const u = catalogUrl.text.trim()
                    const list = Array.from(Config.options?.atelier?.catalogs ?? [])
                    if (!list.includes(u)) Config.setNestedValue("atelier.catalogs", list.concat([u]))
                    catalogUrl.text = ""
                    Atelier.refresh()
                }
            }
        }
        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
            text: "Only https catalogs. Downloads are checked against the catalog's checksum before anything is installed; pieces show what they do and ask first."
        }
    }

    // ── Pieces ──────────────────────────────────────────────────────────
    component AtelierPreview: Rectangle {
        property var entry
        radius: Appearance.rounding.small
        color: Appearance.colors.colLayer2
        clip: true
        readonly property string src: {
            const p = entry?.preview ?? ""
            if (/^https:\/\//.test(p)) return p
            if (p.startsWith("/")) return "file://" + p
            if (entry?.type === "wallpapers" && (entry?.path ?? "").startsWith("/")) return "file://" + entry.path
            return ""
        }
        Image {
            id: img
            anchors.fill: parent
            source: parent.src
            asynchronous: true
            // Pieces and lock screens whole (a tall piece cropped shows only its middle); pictures fill.
            fillMode: ["pieces", "lockscreens"].includes(parent.entry?.type) ? Image.PreserveAspectFit : Image.PreserveAspectCrop
            sourceSize.width: 400
            cache: true
        }
        // Themes in their own colours, looks in their own shape and material:
        // a small bar, popup and notification (MiniScene).
        Loader {
            id: swatches
            anchors.fill: parent
            active: img.status !== Image.Ready && ["themes", "looks"].includes(entry?.type) && (entry?.path ?? "").endsWith(".json")
            sourceComponent: Item {
                id: sw
                property var t: ({})
                FileView {
                    path: entry.path
                    onLoaded: { try { sw.t = JSON.parse(text()) } catch (e) { sw.t = {} } }
                }
                MiniScene {
                    anchors { fill: parent; margins: 8 }
                    visible: Object.keys(sw.t).length > 0
                    tokens: entry?.type === "themes" ? sw.t : ({})
                    look: entry?.type === "looks" ? sw.t : Looks.current
                }
            }
        }
        MaterialSymbol {
            anchors.centerIn: parent
            visible: img.status !== Image.Ready && Object.keys(swatches.item?.t ?? {}).length === 0
            text: Atelier.types.find(t => t.id === entry?.type)?.icon ?? "extension"
            iconSize: 36
            color: Appearance.colors.colSubtext
        }
    }

    component AtelierCard: RippleButton {
        id: card
        property var item
        implicitHeight: cardCol.implicitHeight + 16
        buttonRadius: Appearance.rounding.normal
        colBackground: Appearance.colors.colLayer2
        ColumnLayout {
            id: cardCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
            spacing: 4
            AtelierPreview { entry: card.item; Layout.fillWidth: true; Layout.preferredHeight: width * 0.6 }
            StyledText { Layout.fillWidth: true; text: card.item.name || card.item.id; elide: Text.ElideRight; font.weight: Font.DemiBold }
            RowLayout {
                Layout.fillWidth: true
                spacing: 4
                StyledText {
                    Layout.fillWidth: true; elide: Text.ElideRight
                    color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.smaller
                    text: root.sourceLabel(card.item)
                }
                StyledText {
                    readonly property bool on: card.item.source !== "catalog" && Atelier.isActive(card.item)
                    visible: text.length > 0
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: card.item.revoked ? Appearance.m3colors.m3error : Appearance.colors.colPrimary
                    text: card.item.revoked ? "Revoked" : on ? "Active" : card.item.update ? "Update" : ""
                }
            }
        }
    }
}
