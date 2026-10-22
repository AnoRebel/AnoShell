pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import "deck.js" as Deck

// The wallpaper deck: every wallpaper is a paint-chip card (DeckCard) held
// fanned out like a hand along the foot of the screen; behind them the whole
// screen previews the card in front at full size (DeckPreview), and the
// deck's own accents take on its colours, so browsing is trying each
// wallpaper on. Ported from wallpaperpicker's Wallpaper.qml (GPL-3.0).
//
// Sources: Local (background.wallpaperDir), Favourites (hearted ones,
// background.favourites) and Wallhaven (search results fetched page by page
// as you reach the end; choosing one downloads it into the folder first).
// Local cards sort by name, colour (round the hue wheel from anod's palette:
// the deck becomes a spectrum) or newest first, and filter by name. The
// ribbon under the head is the whole deck in colour: hover for a glimpse,
// click or drag to go there.
//
// Choosing a card: it leaves the hand for the middle of the screen while the
// rest is put away, it's applied (Wallpapers.apply, no awww transition),
// lights up, then its picture grows into the wallpaper and the deck goes. A
// Wallhaven result waits in the middle while it downloads (Esc sends it back).
//
// Keys: ←→ browse, Home/End, PgUp/PgDn, R random, Enter set, F favourite,
// S sort, Space peek (hold, or tap to keep), V live preview, Tab source,
// / search, , settings, Esc close. Mouse: wheel or drag anywhere to browse,
// click a card to bring it to the front, click the front card (or
// double-click any) to set it, click the picture itself to peek.
//
// Virtualised: the hand is `slots` items (17) whatever the folder's size;
// each slot takes the card nearest the deck's position of those it can hold
// and changes card only out of sight. Created per opening, destroyed when
// closed (WallpaperSelector's Loader), so its pictures don't stay in memory.
Item {
    id: root

    signal closed      // the close animation finished: the window can go

    // ── What's in the deck ───────────────────────────────────────────────
    property string mode: "local"
    readonly property var modes: ["local", "favourites", "wallhaven"]
    readonly property bool online: mode === "wallhaven"
    readonly property string sort: Wallpapers.deckSort
    readonly property var sorts: ["name", "hue", "date"]
    property string query: ""
    property bool settingsOpen: false

    // Every local wallpaper in the chosen order (set by resort(): the hue
    // sort waits for the palette rather than reshuffling as it arrives).
    property var sortedLocal: []
    readonly property var displayed: online
        ? Wallhaven.results.map(w => ({ name: w.id, url: w.thumbUrl, fullUrl: w.fullUrl, resolution: w.resolution,
            colors: w.colors ?? [], favorites: w.favorites ?? 0, fileSize: w.fileSize ?? 0, item: w }))
        : Deck.filtered(sortedLocal, query, mode === "favourites", Wallpapers.favourites)
    readonly property var localPaths: {
        const set = {}
        for (const w of Wallpapers.entries) set[w.path] = true
        return set
    }
    property string lastDownload: ""   // the Wallhaven result last downloaded (for "retry")

    readonly property int count: displayed.length
    property int currentIndex: -1
    readonly property var currentEntry: currentIndex >= 0 && currentIndex < count ? displayed[currentIndex] : null
    readonly property string activePath: Config.options?.background?.wallpaperPath ?? ""
    property string frontKey: ""       // the card in front, kept across re-sorts and filtering
    property bool modeChanging: false

    // ── The hand ─────────────────────────────────────────────────────────
    // Design pixels scale with the screen (1920×1200 is 1).
    readonly property real u: Math.max(0.6, Math.min(width / 1920, height / 1200))
    property real pos: 0               // the index in front, fractional while it moves
    property bool posInstant: false    // set pos without the spring (drag, scrub, place)
    Behavior on pos {
        enabled: !root.posInstant
        MotionSpring { token: "settle"; epsilon: AnimationConfig.transitions ? 0.002 : 1000 }
    }
    readonly property int side: 7      // cards each side of the front one
    readonly property int slots: 2 * side + 3 // two spare: a slot changes card only out of sight
    readonly property real cardW: 212 * u
    readonly property real cardH: gauge.implicitHeight
    // The cards turn round a pivot far below the screen, like a hand.
    readonly property real pivotX: width / 2
    readonly property real pivotY: height + 1650 * u
    readonly property real handR: pivotY - (height - 196 * u)
    readonly property real lift: 66 * u
    readonly property real frontScale: 1.22
    readonly property real step1: 204 * u / handR
    readonly property real stepN: 132 * u / handR
    readonly property real frontTop: pivotY - handR - lift - cardH * frontScale / 2

    // ── Choreography, 0..1 ───────────────────────────────────────────────
    property real shown: 0
    property real deal: 0              // cards being dealt (rise from below, the middle first)
    readonly property bool closing: closeAnim.running
    property bool peekHeld: false
    property bool peekKept: false
    property real peekPressedAt: 0
    property real peek: peekHeld || peekKept ? 1 : 0
    Behavior on peek { NumberAnimation { duration: AnimationConfig.scaledDuration(300); easing.type: Easing.OutCubic } }

    // ── Live preview ─────────────────────────────────────────────────────
    readonly property bool live: Config.options?.background?.picker?.livePreview ?? true
    readonly property bool hasMotion: Wallpapers.entries.some(w => Deck.kind(w.name) !== "image")

    // ── Choosing ─────────────────────────────────────────────────────────
    property var chosen: null
    readonly property bool choosing: chosen !== null
    property bool awaiting: false      // in the middle, waiting for its download
    property bool chosenSet: false     // applied (the card wears "current" from then)
    property bool chosenLive: false    // it was playing in the preview when chosen
    property real hush: 0              // the deck steps back
    property real spot: 0              // the screen dims behind the card
    readonly property real midScale: Math.max(1.4, Math.min(2.4, 0.5 * height / Math.max(1, cardH)))

    // ── Helpers ──────────────────────────────────────────────────────────
    function keyOf(e) { return !e ? "" : e.item ? "wh:" + e.name : e.path }
    function savedPath(e) { return e && e.item ? Wallhaven.savePathFor(e.item) : "" }
    function isSaved(e) { return !!e && (!e.item || localPaths[savedPath(e)] === true) }
    function isActive(e) { return !!e && activePath !== "" && activePath === (e.item ? savedPath(e) : e.path) }
    function isFavourite(e) { return !!e && !e.item && Wallpapers.favourites.indexOf(e.path) >= 0 }
    function paletteOf(e) { return e && !e.item ? (Wallpapers.palette[e.path] ?? null) : null }
    function dressOf(e) {
        if (!e) return null
        if (e.item) return e.colors.length > 0 ? Deck.dressFrom(e.colors) : null
        const p = paletteOf(e)
        return p && p.source ? Deck.dressFrom([p.source]) : null
    }
    function chipsOf(e) {
        if (!e) return []
        if (e.item) return e.colors.slice(0, 5).map(c => ({ label: "", fill: c }))
        const p = paletteOf(e)
        return p && p.source ? Deck.chipsFrom(p.source) : []
    }
    // The ribbon's colour for an entry ("" while unread).
    function swatchOf(e) {
        if (!e) return ""
        if (e.item) return e.colors.length > 0 ? e.colors[0] : ""
        const p = paletteOf(e)
        return p && p.source ? p.source : ""
    }
    // What a card and the preview show: a video's still (from anod), the file otherwise.
    function pictureOf(e) {
        if (!e) return ""
        if (e.item || Deck.kind(e.name) !== "video") return e.url
        const p = paletteOf(e)
        return p && p.still ? Wallpapers.fileUrl(p.still) : ""
    }
    // What the live preview plays for a card: the file, when it moves.
    function motionOf(e) { return e && !e.item && Deck.kind(e.name) !== "image" ? e.url : "" }
    function titleOf(e) { return !e ? "" : e.item ? "wallhaven " + e.name : Deck.baseName(e.name) }
    function metaOf(e) {
        if (!e) return ""
        if (e.item) return e.resolution + "  ·  ♥ " + Deck.compact(e.favorites) + (e.fileSize ? "  ·  " + Deck.bytes(e.fileSize) : "")
        const parts = []
        const dot = e.name.lastIndexOf(".")
        if (dot > 0) parts.push(e.name.substring(dot + 1).toUpperCase())
        if (e.size > 0) parts.push(Deck.bytes(e.size))
        return parts.join("  ·  ")
    }

    // ── The list ─────────────────────────────────────────────────────────
    function resort() { sortedLocal = Deck.sorted(Wallpapers.entries, sort, Wallpapers.palette) }

    function setSort(s) {
        if (s === sort) return
        Wallpapers.deckSort = s
        reshuffle(resort)
    }

    function setMode(m) {
        if (m === mode) return
        reshuffle(() => {
            modeChanging = true
            mode = m
            query = ""
            header.searchField.text = ""
            if (m === "wallhaven" && Wallhaven.results.length === 0 && !Wallhaven.fetching) Wallhaven.fetch(true)
            Qt.callLater(refocus)
        })
    }

    // After the list changes: a new source (or a first list) starts on the
    // wallpaper on screen, or its first card; otherwise the card in front
    // stays in front wherever it went (or, gone, its place does).
    function refocus() {
        const list = displayed
        let i = -1
        if (modeChanging || frontKey === "") {
            modeChanging = false
            i = online ? -1 : list.findIndex(w => isActive(w))
        } else {
            i = list.findIndex(w => keyOf(w) === frontKey)
            if (i < 0) i = Math.min(currentIndex, list.length - 1)
        }
        if (i < 0) i = list.length > 0 ? 0 : -1
        if (i !== currentIndex || Math.abs(pos - Math.max(0, i)) > 0.001) place(i)
        frontKey = i >= 0 ? keyOf(list[i]) : ""
    }

    // ── Moving through the deck ──────────────────────────────────────────
    function setPosInstant(p) { posInstant = true; pos = p; posInstant = false }
    function place(i) { currentIndex = i; setPosInstant(Math.max(0, i)) }

    // To a card, the deck turning on its spring; a long way is cut short.
    function go(i) {
        if (count === 0 || choosing) return
        i = Math.max(0, Math.min(count - 1, i))
        currentIndex = i
        if (Math.abs(i - pos) > side + 2) setPosInstant(i - Math.sign(i - pos) * 3)
        pos = i
    }
    function step(d) { go(currentIndex < 0 ? 0 : currentIndex + d) }
    function random() { if (count > 1) go((currentIndex + 1 + Math.floor(Math.random() * (count - 1))) % count) }

    // A new source or order: the hand is put away, `change` made out of
    // sight, and the new hand dealt.
    function reshuffle(change) {
        if (shuffleAnim.running && shuffleAnim.change) {
            const pending = shuffleAnim.change
            shuffleAnim.change = null
            pending()
        }
        if (closing || openAnim.running || choosing) { change(); return }
        shuffleAnim.change = change
        shuffleAnim.restart()
    }

    // ── Acting on the card in front ──────────────────────────────────────
    function pickCurrent() {
        const e = currentEntry
        if (!e || isActive(e) || choosing || closing) return
        const downloading = Wallhaven.downloadingId
        if (e.item && !isSaved(e) && downloading !== "" && downloading !== e.name) return // another one is downloading
        choose(e)
        const monitor = GlobalStates.wallpaperSelectorTargetMonitor
        if (!e.item) Wallpapers.apply(e.path, monitor, true)
        else if (isSaved(e)) Wallpapers.apply(savedPath(e), monitor, true)
        else if (downloading === "") {
            lastDownload = e.name
            if (!Wallhaven.downloadAndApply(e.item)) returnCard()
        }
    }

    // The slot holding an entry, if it's in the hand.
    function slotOf(e) {
        const k = keyOf(e)
        for (let i = 0; i < hand.count; i++) {
            const s = hand.itemAt(i)
            if (s && s.live && keyOf(s.entry) === k) return s
        }
        return null
    }

    function frontPlace() {
        return { x: pivotX - cardW / 2, y: pivotY - handR - lift - cardH / 2 + peek * (cardH * 1.25 + 120 * u), rotation: 0, scale: frontScale }
    }

    // The card goes from the hand to the middle of the screen.
    function choose(e) {
        if (shuffleAnim.running) {
            const change = shuffleAnim.change
            shuffleAnim.change = null
            shuffleAnim.stop()
            if (change) change()
        }
        openAnim.stop()
        backdropTimer.stop()
        hiresTimer.stop()
        motionTimer.stop()
        const from = slotOf(e) ?? frontPlace()
        flight.x = from.x
        flight.y = from.y
        flight.rotation = from.rotation
        flight.scale = from.scale
        flight.glow = 0; flight.ring = 0; flight.pulse = 0; flight.shine = -1; flight.fade = 0; flight.bloom = 0
        chosenLive = preview.playing !== "" && preview.playing === motionOf(e) && preview.motionShown > 0.99
        if (!chosenLive) preview.motionPaused = true // nothing new starts playing behind it
        const picture = e.fullUrl || pictureOf(e)
        if (picture) preview.show(picture, !!e.fullUrl)
        if (settingsOpen) setSettingsOpen(false)
        else focusKeys()
        chosenSet = false
        awaiting = false
        chosen = e
        riseAnim.restart()
    }

    // In the middle: on to the wallpaper, or wait for the download.
    function arrived() {
        if (isActive(chosen)) bloomAnim.restart()
        else awaiting = true
    }

    // Back into the hand (its download failed, or Esc while it waited).
    function returnCard() {
        if (!choosing || backAnim.running) return
        riseAnim.stop()
        bloomAnim.stop()
        awaiting = false
        Wallhaven.cancelDownload()
        place(currentIndex)
        const to = frontPlace()
        backAnim.toX = to.x
        backAnim.toY = to.y
        backAnim.toScale = to.scale
        backAnim.restart()
    }

    function resetChoice() {
        riseAnim.stop(); bloomAnim.stop(); backAnim.stop()
        chosen = null
        awaiting = false
        chosenSet = false
        chosenLive = false
        hush = 0
        spot = 0
        flight.bloom = 0
    }

    function toggleFavourite(e) { if (e && !e.item) Wallpapers.toggleFavourite(e.path) }
    function togglePeek() { peekKept = !peekKept }
    function toggleLive() { Config.setNestedValue("background.picker.livePreview", !live) }
    function focusKeys() { keys.forceActiveFocus() }
    function setSettingsOpen(on) {
        settingsOpen = on
        if (on) settingsCard.reset()
        else focusKeys()
    }

    // ── Opening and closing ──────────────────────────────────────────────
    function open() {
        if (closing || choosing) {
            // Reopened while the close animation plays.
            closeAnim.stop()
            if (choosing) { resetChoice(); place(currentIndex) }
        }
        openAnim.restart()
    }
    function close() {
        if (closing) return
        openAnim.stop()
        closeAnim.restart()
    }

    property bool dying: false
    Component.onCompleted: {
        resort()
        Wallpapers.scanPalette()
        refocus()
        preview.show(currentEntry ? pictureOf(currentEntry) : "", true)
        motionTimer.restart()
        focusKeys()
        open()
    }
    Component.onDestruction: {
        dying = true
        Wallhaven.reset()
    }

    // The card in front is whatever the deck moves to, never what a new list
    // happens to put at its index (read from the list: currentEntry may lag).
    onCurrentIndexChanged: frontKey = keyOf(displayed[currentIndex])
    onDisplayedChanged: if (!dying) Qt.callLater(refocus)
    onLiveChanged: {
        if (choosing) return
        preview.motion = live ? motionOf(currentEntry) : ""
        preview.motionPaused = false
    }
    onActivePathChanged: {
        // A chosen Wallhaven result, downloaded and applied.
        if (awaiting && isActive(chosen)) {
            awaiting = false
            bloomAnim.restart()
        }
    }
    onCurrentEntryChanged: {
        if (choosing) return // a chosen card keeps the preview as it is
        // The picture behind waits for the deck to slow down, the live
        // preview for it to stop (the one playing pauses and fades meanwhile).
        backdropTimer.restart()
        preview.motionPaused = preview.playing !== motionOf(currentEntry)
        motionTimer.restart()
        if (online && currentIndex >= count - 8) Wallhaven.fetchNextPage() // the next page as the end comes into view
    }

    Connections {
        target: Wallpapers
        function onEntriesChanged() { root.resort(); Wallpapers.scanPalette() }
        function onPaletteChanged() {
            if (root.sort === "hue") root.reshuffle(root.resort)
            else if (!root.choosing && root.currentEntry && Deck.kind(root.currentEntry.name) === "video") backdropTimer.restart() // its still arrived
        }
    }
    Connections {
        target: Wallhaven
        // A chosen result whose download failed goes back.
        function onDownloadingIdChanged() {
            if (root.choosing && Wallhaven.downloadingId === "" && Wallhaven.downloadError !== "") root.returnCard()
        }
    }

    SequentialAnimation {
        id: shuffleAnim
        property var change: null
        NumberAnimation { target: root; property: "deal"; to: 0.1; duration: AnimationConfig.scaledDuration(170); easing.type: Easing.InQuad }
        ScriptAction {
            script: {
                const c = shuffleAnim.change
                shuffleAnim.change = null
                if (c) c()
            }
        }
        NumberAnimation { target: root; property: "deal"; to: 1; duration: AnimationConfig.scaledDuration(560); easing.type: Easing.OutCubic }
    }
    ParallelAnimation {
        id: openAnim
        NumberAnimation { target: root; property: "shown"; to: 1; duration: AnimationConfig.scaledDuration(380); easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "deal"; to: 1; duration: AnimationConfig.scaledDuration(760); easing.type: Easing.OutCubic }
    }
    ParallelAnimation {
        id: closeAnim
        NumberAnimation { target: root; property: "shown"; to: 0; duration: AnimationConfig.scaledDuration(root.choosing ? 340 : 240); easing.type: Easing.InCubic }
        NumberAnimation { target: root; property: "deal"; to: 0; duration: AnimationConfig.scaledDuration(220); easing.type: Easing.InCubic }
        onFinished: root.closed()
    }

    // ── Choosing, in three moves ─────────────────────────────────────────
    // 1. Out of the hand to the middle, upright and larger, while the rest
    // of the hand is put away and the deck steps back.
    ParallelAnimation {
        id: riseAnim
        NumberAnimation { target: root; property: "shown"; to: 1; duration: AnimationConfig.scaledDuration(300); easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "deal"; to: 0; duration: AnimationConfig.scaledDuration(560); easing.type: Easing.InCubic }
        NumberAnimation { target: root; property: "hush"; to: 1; duration: AnimationConfig.scaledDuration(420); easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "spot"; to: 1; duration: AnimationConfig.scaledDuration(1000); easing.type: Easing.InOutQuad }
        NumberAnimation { target: flight; property: "x"; to: root.width / 2 - root.cardW / 2; duration: AnimationConfig.scaledDuration(1250); easing.type: Easing.InOutCubic }
        NumberAnimation { target: flight; property: "y"; to: root.height / 2 - root.cardH / 2; duration: AnimationConfig.scaledDuration(1250); easing.type: Easing.InOutCubic }
        NumberAnimation { target: flight; property: "rotation"; to: 0; duration: AnimationConfig.scaledDuration(900); easing.type: Easing.OutCubic }
        NumberAnimation { target: flight; property: "scale"; to: root.midScale; duration: AnimationConfig.scaledDuration(1250); easing.type: Easing.InOutCubic }
        NumberAnimation { target: flight; property: "glow"; to: 1; duration: AnimationConfig.scaledDuration(1250); easing.type: Easing.InQuad }
        onFinished: root.arrived()
    }
    // 2. Set: the tag pops, a ring goes out and light crosses the picture;
    // 3. the picture grows into the wallpaper, and the deck goes.
    SequentialAnimation {
        id: bloomAnim
        ScriptAction { script: { root.chosenSet = true; chosenCard.popTag() } }
        ParallelAnimation {
            NumberAnimation { target: flight; property: "ring"; from: 0; to: 1; duration: AnimationConfig.scaledDuration(800); easing.type: Easing.OutCubic }
            NumberAnimation { target: flight; property: "shine"; from: -0.35; to: 1.35; duration: AnimationConfig.scaledDuration(820); easing.type: Easing.InOutSine }
            SequentialAnimation {
                NumberAnimation { target: flight; property: "pulse"; to: 1; duration: AnimationConfig.scaledDuration(170); easing.type: Easing.OutCubic }
                NumberAnimation { target: flight; property: "pulse"; to: 0; duration: AnimationConfig.scaledDuration(480); easing.type: Easing.InOutQuad }
            }
        }
        PauseAnimation { duration: AnimationConfig.scaledDuration(100) }
        ParallelAnimation {
            NumberAnimation { target: flight; property: "fade"; to: 1; duration: AnimationConfig.scaledDuration(320); easing.type: Easing.OutQuad }
            NumberAnimation { target: flight; property: "glow"; to: 0; duration: AnimationConfig.scaledDuration(380); easing.type: Easing.OutQuad }
            NumberAnimation { target: flight; property: "bloom"; to: 1; duration: AnimationConfig.scaledDuration(1000); easing.type: Easing.InOutCubic }
        }
        ScriptAction { script: { root.spot = 0; root.close() } }
    }
    // Back into the hand.
    ParallelAnimation {
        id: backAnim
        property real toX: 0
        property real toY: 0
        property real toScale: 1
        NumberAnimation { target: root; property: "deal"; to: 1; duration: AnimationConfig.scaledDuration(620); easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "hush"; to: 0; duration: AnimationConfig.scaledDuration(420); easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "spot"; to: 0; duration: AnimationConfig.scaledDuration(420); easing.type: Easing.OutCubic }
        NumberAnimation { target: flight; property: "x"; to: backAnim.toX; duration: AnimationConfig.scaledDuration(620); easing.type: Easing.InOutCubic }
        NumberAnimation { target: flight; property: "y"; to: backAnim.toY; duration: AnimationConfig.scaledDuration(620); easing.type: Easing.InOutCubic }
        NumberAnimation { target: flight; property: "rotation"; to: 0; duration: AnimationConfig.scaledDuration(620); easing.type: Easing.OutCubic }
        NumberAnimation { target: flight; property: "scale"; to: backAnim.toScale; duration: AnimationConfig.scaledDuration(620); easing.type: Easing.InOutCubic }
        NumberAnimation { target: flight; property: "glow"; to: 0; duration: AnimationConfig.scaledDuration(300) }
        onFinished: {
            root.chosen = null
            root.chosenLive = false
            motionTimer.restart()
        }
    }

    // Full resolution once the selection settles; a local picture as soon
    // as browsing slows down.
    Timer {
        id: backdropTimer
        interval: 110
        onTriggered: {
            const e = root.currentEntry
            if (root.choosing) return
            if (!e) preview.show("")
            else if (e.fullUrl) { preview.show(e.url); hiresTimer.restart() }
            else preview.show(root.pictureOf(e))
        }
    }
    Timer {
        id: hiresTimer
        interval: 550
        onTriggered: {
            const e = root.currentEntry
            if (root.choosing || !e?.fullUrl) return
            // The thumbnail first: replacing it before it's up would leave the
            // previous picture on screen for the whole download.
            if (!preview.failed && String(preview.front.source) !== e.url) { hiresTimer.restart(); return }
            preview.show(e.fullUrl, true)
        }
    }
    // The live preview changes only once the deck has been still for a
    // moment (a player loading stalls the shell briefly: not mid-motion).
    Timer {
        id: motionTimer
        interval: 700
        onTriggered: {
            if (root.choosing) return
            preview.motion = root.live ? root.motionOf(root.currentEntry) : ""
            preview.motionPaused = false
        }
    }

    // Measures a card (the hand's geometry needs its height).
    DeckCard { id: gauge; visible: false; u: root.u; title: "Wallpaper"; meta: "JPG" }

    // ── The try-on: the deck wears the front card's colours ─────────────
    Item {
        id: tintColors
        visible: false
        readonly property var dress: root.dressOf(root.currentEntry)
        property color accent: dress ? dress.accent : Appearance.colors.colPrimary
        property color accentInk: dress ? dress.accentInk : Appearance.colors.colOnPrimary
        property color surface: dress ? dress.low : Appearance.colors.colSurfaceContainerLow
        property color ink: dress ? dress.ink : Appearance.colors.colOnSurface
        property color muted: dress ? dress.muted : Appearance.colors.colOnSurfaceVariant
        Behavior on accent { ColorAnimation { duration: AnimationConfig.scaledDuration(420); easing.type: Easing.OutCubic } }
        Behavior on accentInk { ColorAnimation { duration: AnimationConfig.scaledDuration(420); easing.type: Easing.OutCubic } }
        Behavior on surface { ColorAnimation { duration: AnimationConfig.scaledDuration(420); easing.type: Easing.OutCubic } }
        Behavior on ink { ColorAnimation { duration: AnimationConfig.scaledDuration(420); easing.type: Easing.OutCubic } }
        Behavior on muted { ColorAnimation { duration: AnimationConfig.scaledDuration(420); easing.type: Easing.OutCubic } }
    }
    readonly property Item tint: tintColors

    // ── The picture ──────────────────────────────────────────────────────
    Rectangle { // the desktop dimmed, until the picture is in
        anchors.fill: parent
        color: Appearance.colors.colScrim
        opacity: 0.55 * root.shown * (1 - root.hush)
    }
    DeckPreview {
        id: preview
        anchors.fill: parent
        opacity: root.shown
    }
    // Shade at the head and the foot, so the head and the hand read on any
    // picture; it lifts while peeking.
    Rectangle {
        anchors.fill: parent
        opacity: root.shown * (1 - 0.85 * root.peek) * (1 - root.hush)
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.66) }
            GradientStop { position: 0.13; color: Qt.rgba(0, 0, 0, 0.32) }
            GradientStop { position: 0.24; color: Qt.rgba(0, 0, 0, 0.06) }
            GradientStop { position: 0.5; color: Qt.rgba(0, 0, 0, 0) }
            GradientStop { position: 0.78; color: Qt.rgba(0, 0, 0, 0.18) }
            GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.6) }
        }
    }
    Rectangle { // dimmed behind a chosen card
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 1)
        visible: opacity > 0
        opacity: 0.55 * root.spot * root.shown
    }

    // The wheel browses wherever it turns; a click on the picture peeks.
    MouseArea {
        property real acc: 0
        anchors.fill: parent
        onClicked: root.togglePeek()
        onWheel: wheel => {
            const d = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : -wheel.angleDelta.x
            if (Math.sign(d) !== Math.sign(acc)) acc = 0
            acc += d
            while (acc >= 120) { root.step(-1); acc -= 120 }
            while (acc <= -120) { root.step(1); acc += 120 }
            wheelReset.restart()
        }
        Timer { id: wheelReset; interval: 400; onTriggered: parent.acc = 0 }
    }

    // ── Keys ─────────────────────────────────────────────────────────────
    Item {
        id: keys
        anchors.fill: parent
        focus: true

        Keys.onPressed: event => {
            const k = event.key
            // While a card is chosen: Esc sends a waiting one back, or skips to the end.
            if (root.choosing) {
                if (k === Qt.Key_Escape && !event.isAutoRepeat) {
                    // Waiting, or still rising with its download running: back to the deck.
                    if (root.awaiting || (Wallhaven.downloadingId !== "" && !root.chosenSet)) root.returnCard()
                    else if (!backAnim.running) root.close()
                }
                event.accepted = true
                return
            }
            if (k === Qt.Key_Escape) {
                if (root.settingsOpen) root.setSettingsOpen(false)
                else if (root.peekKept) root.peekKept = false
                else root.close()
            } else if (k === Qt.Key_Left || k === Qt.Key_Up) root.step(-1)
            else if (k === Qt.Key_Right || k === Qt.Key_Down) root.step(1)
            else if (k === Qt.Key_Home) root.go(0)
            else if (k === Qt.Key_End) root.go(root.count - 1)
            else if (k === Qt.Key_PageUp) root.step(-root.side)
            else if (k === Qt.Key_PageDown) root.step(root.side)
            else if (k === Qt.Key_Return || k === Qt.Key_Enter) root.pickCurrent()
            else if (k === Qt.Key_Space) {
                if (!event.isAutoRepeat) { root.peekHeld = true; root.peekPressedAt = Date.now() }
            } else if (k === Qt.Key_F && !root.online) root.toggleFavourite(root.currentEntry)
            else if (k === Qt.Key_S && !root.online) root.setSort(root.sorts[(root.sorts.indexOf(root.sort) + 1) % root.sorts.length])
            else if (k === Qt.Key_R) root.random()
            else if (k === Qt.Key_V && root.hasMotion) root.toggleLive()
            else if (k === Qt.Key_Tab || k === Qt.Key_Backtab)
                root.setMode(root.modes[(root.modes.indexOf(root.mode) + (k === Qt.Key_Tab ? 1 : 2)) % 3])
            else if (k === Qt.Key_Slash) header.searchField.forceActiveFocus()
            else if (k === Qt.Key_Comma) root.setSettingsOpen(!root.settingsOpen)
            else return
            event.accepted = true
        }
        Keys.onReleased: event => {
            if (event.key !== Qt.Key_Space || event.isAutoRepeat || root.choosing) return
            root.peekHeld = false
            if (Date.now() - root.peekPressedAt < 240) root.peekKept = !root.peekKept // a tap keeps the peek
            event.accepted = true
        }
    }

    // ── The hand ─────────────────────────────────────────────────────────
    Item {
        id: hold
        anchors.fill: parent

        // Drag anywhere to turn the root.
        DragHandler {
            property real from: 0
            target: null
            yAxis.enabled: false
            enabled: !root.choosing
            onActiveChanged: {
                if (active) {
                    root.posInstant = true
                    from = root.pos
                } else {
                    root.posInstant = false
                    const v = centroid.velocity.x / (root.stepN * root.handR) // a flick carries on a little
                    root.go(Math.round(root.pos - v * 0.2))
                }
            }
            onActiveTranslationChanged: {
                if (!active || root.count === 0) return
                root.pos = Math.max(-0.45, Math.min(root.count - 0.55, from - activeTranslation.x / (root.stepN * root.handR)))
                root.currentIndex = Math.max(0, Math.min(root.count - 1, Math.round(root.pos)))
            }
        }

        Repeater {
            id: hand
            model: root.slots

            Item {
                id: slot
                required property int index
                // The card this slot holds: the one nearest the deck's position
                // of those it can hold (every `slots`-th).
                readonly property int idx: index + root.slots * Math.round((root.pos - index) / root.slots)
                readonly property real d: idx - root.pos
                readonly property real ad: Math.abs(d)
                readonly property bool live: idx >= 0 && idx < root.count && ad < root.side + 1
                readonly property var entry: live ? root.displayed[idx] : null
                readonly property bool lifted: root.choosing && !!entry && root.keyOf(entry) === root.keyOf(root.chosen)
                readonly property bool playing: !!entry && preview.playing !== "" && preview.playing === root.motionOf(entry)
                readonly property real near: Math.max(0, 1 - ad)
                readonly property real dealt: {
                    const t = Math.max(0, Math.min(1, root.deal * (1 + 0.09 * root.side) - 0.09 * ad))
                    return 1 - Math.pow(1 - t, 3)
                }
                readonly property real theta: (d < 0 ? -1 : 1) * (Math.min(ad, 1) * root.step1 + Math.max(0, ad - 1) * root.stepN)
                property real hoverLift: card.hovered && near < 0.5 ? 20 * root.u : 0
                Behavior on hoverLift { MotionSpring { token: "snappy" } }
                readonly property real r: root.handR + root.lift * near + hoverLift
                readonly property real lower: (1 - dealt) * (root.cardH * 1.35 + 140 * root.u) + root.peek * (root.cardH * 1.25 + 120 * root.u)

                width: root.cardW
                height: root.cardH
                x: root.pivotX + r * Math.sin(theta) - width / 2
                y: root.pivotY - r * Math.cos(theta) - height / 2 + lower
                rotation: (theta + (1 - dealt) * (d < 0 ? -0.1 : 0.1)) * 180 / Math.PI
                scale: 1 + (root.frontScale - 1) * near
                z: 100 - ad
                opacity: Math.max(0, Math.min(1, root.side + 1 - ad))
                visible: live && opacity > 0.01 && y < root.height && !lifted

                DeckCard {
                    id: card
                    anchors.fill: parent
                    u: root.u
                    entry: slot.entry
                    picture: root.pictureOf(slot.entry)
                    front: slot.near
                    dim: Math.min(0.3, Math.max(0, slot.ad - 0.6) * 0.065)
                    dress: root.dressOf(slot.entry)
                    chips: root.chipsOf(slot.entry)
                    current: root.isActive(slot.entry)
                    favourite: root.isFavourite(slot.entry)
                    saved: !!slot.entry?.item && root.isSaved(slot.entry)
                    download: !!slot.entry?.item && Wallhaven.downloadingId === slot.entry.name ? Wallhaven.downloadProgress : -1
                    title: root.titleOf(slot.entry)
                    meta: root.metaOf(slot.entry)
                    art: slot.playing && preview.motionShown > 0 ? liveTexture : null
                    artAspect: root.width / Math.max(1, root.height)
                    artOpacity: preview.motionShown
                    onClicked: slot.idx === root.currentIndex ? root.pickCurrent() : root.go(slot.idx)
                    onDoubleClicked: { root.go(slot.idx); root.pickCurrent() }
                }
            }
        }
    }

    // ── Above the card in front: what Enter does ─────────────────────────
    Row {
        id: actions
        readonly property var entry: root.currentEntry
        readonly property bool active: root.isActive(entry)
        readonly property bool mine: !!entry?.item && Wallhaven.downloadingId === entry.name
        readonly property bool busy: Wallhaven.downloadingId !== "" && !mine
        readonly property bool saved: root.isSaved(entry)
        readonly property bool failed: !!entry?.item && root.lastDownload === entry.name && Wallhaven.downloadError !== "" && Wallhaven.downloadingId === ""
        readonly property bool fav: root.isFavourite(entry)

        anchors.horizontalCenter: parent.horizontalCenter
        y: root.frontTop - height - 20 * root.u + (1 - root.deal) * 60 * root.u + root.peek * 40 * root.u
        spacing: 8 * root.u
        visible: root.count > 0 && !!entry && opacity > 0.05 // faded out is gone too
        opacity: Math.max(0, root.deal * 1.6 - 0.6) * (1 - root.peek)

        DeckButton {
            deck: root
            visible: !root.online
            icon: "favorite"
            toolTip: actions.fav ? "Remove from favourites (F)" : "Favourite (F)"
            checked: actions.fav
            onClicked: root.toggleFavourite(root.currentEntry)
        }

        Rectangle {
            id: setButton
            readonly property bool idle: !actions.active && !actions.mine && !actions.busy
            width: setRow.implicitWidth + 32 * root.u
            height: 40 * root.u
            radius: height / 2
            clip: true
            color: actions.active ? Qt.rgba(tintColors.surface.r, tintColors.surface.g, tintColors.surface.b, 0.82)
                : actions.mine || actions.busy ? Qt.rgba(tintColors.accent.r, tintColors.accent.g, tintColors.accent.b, 0.35)
                : setMa.containsMouse ? Qt.lighter(tintColors.accent, 1.08) : tintColors.accent
            border.width: actions.active ? 1 : 0
            border.color: Qt.rgba(tintColors.ink.r, tintColors.ink.g, tintColors.ink.b, 0.14)

            Rectangle { // download progress fills the button
                visible: actions.mine
                width: parent.width * Wallhaven.downloadProgress
                height: parent.height
                color: tintColors.accent
                Behavior on width { NumberAnimation { duration: AnimationConfig.scaledDuration(200) } }
            }
            Row {
                id: setRow
                anchors.centerIn: parent
                spacing: 8 * root.u
                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    text: actions.active ? "check_circle" : actions.mine || actions.busy ? "downloading"
                        : actions.failed ? "refresh" : actions.saved ? "wallpaper" : "download"
                    fill: actions.active ? 1 : 0
                    iconSize: 19 * root.u
                    color: actions.active ? tintColors.accent : tintColors.accentInk
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: actions.active ? "On your desktop"
                        : actions.mine ? "Downloading " + Math.round(Wallhaven.downloadProgress * 100) + "%"
                        : actions.busy ? "Another download running…"
                        : actions.failed ? "Download failed · retry"
                        : actions.saved ? "Set wallpaper" : "Download & set"
                    font.pixelSize: (Appearance?.font.pixelSize.small ?? 15) * root.u
                    font.weight: Font.DemiBold
                    color: actions.active ? tintColors.ink : tintColors.accentInk
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: setButton.idle
                    width: enterKey.implicitWidth + 10 * root.u
                    height: 20 * root.u
                    radius: (Appearance?.rounding.unsharpenmore ?? 6) * root.u
                    color: Qt.rgba(tintColors.accentInk.r, tintColors.accentInk.g, tintColors.accentInk.b, 0.14)
                    StyledText {
                        id: enterKey
                        anchors.centerIn: parent
                        text: "⏎"
                        font.pixelSize: (Appearance?.font.pixelSize.smaller ?? 12) * root.u
                        font.weight: Font.Bold
                        color: tintColors.accentInk
                    }
                }
            }
            MouseArea {
                id: setMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: setButton.idle ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.pickCurrent()
            }
        }
    }

    // ── The head ─────────────────────────────────────────────────────────
    DeckHeader {
        id: header
        deck: root
        x: 40 * root.u
        y: 28 * root.u - (1 - root.shown) * 18 * root.u - Math.max(root.peek, root.hush) * 24 * root.u
        width: parent.width - 80 * root.u
        opacity: root.shown * (1 - root.peek) * (1 - root.hush)
        visible: opacity > 0.01
    }

    SpectrumRibbon {
        id: ribbon
        z: 5 // its glimpse hangs over the hints and filters
        x: header.x
        y: header.y + header.height + 18 * root.u
        width: header.width
        opacity: header.opacity
        visible: root.count > 0 && opacity > 0.01
        u: root.u
        pos: root.pos
        span: root.side
        accent: tintColors.accent
        ink: Qt.rgba(1, 1, 1, 1)
        colors: root.displayed.map(e => root.swatchOf(e))
        favourites: {
            if (root.online || root.mode === "favourites") return []
            const out = []
            root.displayed.forEach((e, i) => { if (root.isFavourite(e)) out.push(i) })
            return out
        }
        activeIndex: root.displayed.findIndex(e => root.isActive(e))
        thumbAt: index => root.pictureOf(root.displayed[index])
        nameAt: index => { const e = root.displayed[index]; return !e ? "" : e.item ? "wallhaven " + e.name : e.name }
        onScrub: index => {
            root.setPosInstant(index)
            root.currentIndex = Math.round(index)
        }
        onSettle: index => root.go(index)
    }

    // Under the ribbon: Wallhaven's filters, or the keys.
    WallhavenFilters {
        id: filters
        deck: root
        x: header.x
        y: ribbon.y + ribbon.height + 14 * root.u
        width: header.width
        visible: root.online && opacity > 0.01
        opacity: header.opacity
    }
    DeckGlass {
        deck: root
        anchors.horizontalCenter: parent.horizontalCenter
        y: ribbon.y + ribbon.height + 14 * root.u
        visible: !root.online && root.count > 0 && opacity > 0.01
        opacity: header.opacity
        width: hints.implicitWidth + 28 * root.u
        height: 28 * root.u
        color: Qt.rgba(tintColors.surface.r, tintColors.surface.g, tintColors.surface.b, 0.6)
        StyledText {
            id: hints
            anchors.centerIn: parent
            text: "←→ or wheel browse  ·  Enter set  ·  F favourite  ·  S sort  ·  R random  ·  Space peek  ·  "
                + (root.hasMotion ? "V live preview  ·  " : "") + "Tab source  ·  / search  ·  Esc close"
            font.pixelSize: (Appearance?.font.pixelSize.smaller ?? 12) * root.u
            color: Qt.rgba(tintColors.ink.r, tintColors.ink.g, tintColors.ink.b, 0.78)
        }
    }

    // ── Loading, failed, empty, peeking ──────────────────────────────────
    DeckGlass { // full resolution on its way (Wallhaven), in the corner
        deck: root
        anchors.right: parent.right
        anchors.rightMargin: 40 * root.u
        y: (root.online ? filters.y + filters.height : ribbon.y + ribbon.height) + 16 * root.u
        visible: preview.loading && preview.upgrading && root.shown > 0.5 && !root.choosing
        width: hiresText.implicitWidth + 24 * root.u
        height: 34 * root.u
        StyledText {
            id: hiresText
            anchors.centerIn: parent
            text: "Full resolution" + (preview.progress > 0.01 ? "  " + Math.round(preview.progress * 100) + "%" : "…")
            font.pixelSize: (Appearance?.font.pixelSize.smaller ?? 12) * root.u
            color: tintColors.ink
        }
    }
    DeckGlass {
        deck: root
        anchors.right: parent.right
        anchors.rightMargin: 40 * root.u
        y: (root.online ? filters.y + filters.height : ribbon.y + ribbon.height) + 16 * root.u
        visible: (preview.failed || (root.online && Wallhaven.error !== "" && root.count > 0)) && root.shown > 0.5 && !root.choosing
        width: failedRow.implicitWidth + 24 * root.u
        height: 34 * root.u
        Row {
            id: failedRow
            anchors.centerIn: parent
            spacing: 8 * root.u
            MaterialSymbol { anchors.verticalCenter: parent.verticalCenter; text: "broken_image"; iconSize: 16 * root.u; color: tintColors.ink }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: preview.failed ? "Couldn't load this picture" : Wallhaven.error
                font.pixelSize: (Appearance?.font.pixelSize.smaller ?? 12) * root.u
                color: tintColors.ink
            }
        }
    }

    // Nothing to deal.
    Column {
        anchors.centerIn: parent
        visible: root.count === 0 && root.shown > 0
        opacity: root.shown
        spacing: 12 * root.u

        MaterialSymbol {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.online ? (Wallhaven.fetching ? "progress_activity" : Wallhaven.error ? "cloud_off" : "travel_explore")
                : root.mode === "favourites" ? "heart_plus" : "hide_image"
            iconSize: 52 * root.u
            color: Qt.rgba(1, 1, 1, 0.85)
            RotationAnimation on rotation { running: root.online && Wallhaven.fetching; from: 0; to: 360; duration: 1000; loops: Animation.Infinite }
        }
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.online ? (Wallhaven.error || (Wallhaven.fetching ? "Searching Wallhaven…" : "No results"))
                : root.mode === "favourites" ? "No favourites yet: press F on a wallpaper you like"
                : root.query !== "" ? "Nothing matches “" + root.query + "”"
                : "No wallpapers in " + Wallpapers.effectiveDirectory.replace(FileUtils.trimFileProtocol(Directories.home), "~")
            font.pixelSize: (Appearance?.font.pixelSize.normal ?? 16) * root.u
            color: Qt.rgba(1, 1, 1, 1)
        }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.mode === "local" && root.query === "" && !root.settingsOpen
            width: folderRow.implicitWidth + 32 * root.u
            height: 40 * root.u
            radius: height / 2
            color: folderMa.containsMouse ? Qt.lighter(tintColors.accent, 1.08) : tintColors.accent
            Row {
                id: folderRow
                anchors.centerIn: parent
                spacing: 8 * root.u
                MaterialSymbol { anchors.verticalCenter: parent.verticalCenter; text: "folder_open"; iconSize: 18 * root.u; color: tintColors.accentInk }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Choose another folder"
                    font.pixelSize: (Appearance?.font.pixelSize.small ?? 15) * root.u
                    font.weight: Font.DemiBold
                    color: tintColors.accentInk
                }
            }
            MouseArea { id: folderMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.setSettingsOpen(true) }
        }
    }

    DeckSettings {
        id: settingsCard
        deck: root
        anchors.right: parent.right
        anchors.rightMargin: 40 * root.u
        y: header.y + header.height + 12 * root.u
        z: 10
        visible: root.settingsOpen && header.visible
        opacity: header.opacity
        onCloseRequested: root.setSettingsOpen(false)
    }

    // While peeking: how to get back.
    DeckGlass {
        deck: root
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 30 * root.u
        visible: opacity > 0.01
        opacity: root.peekKept ? root.peek * (1 - root.hush) : 0
        width: peekRow.implicitWidth + 28 * root.u
        height: 36 * root.u
        Row {
            id: peekRow
            anchors.centerIn: parent
            spacing: 10 * root.u
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: root.currentEntry ? (root.currentEntry.item ? "wallhaven " : "") + root.currentEntry.name : ""
                font.pixelSize: (Appearance?.font.pixelSize.smallie ?? 13) * root.u
                font.weight: Font.DemiBold
                color: tintColors.ink
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: "←→ browse  ·  Space or Esc: back to the deck"
                font.pixelSize: (Appearance?.font.pixelSize.smaller ?? 12) * root.u
                color: tintColors.muted
            }
        }
    }

    // ── The chosen card ──────────────────────────────────────────────────
    // The live preview as a texture, so the card in front (and a chosen one)
    // shows the video playing too.
    ShaderEffectSource {
        id: liveTexture
        width: root.width
        height: root.height
        visible: false
        sourceItem: preview.motionShown > 0 ? preview.motionItem : null
        live: true
        mipmap: true
    }

    // What a chosen card's picture is drawn from: the video that was playing
    // behind it, or the preview's image once that shows the card.
    readonly property var chosenArt: {
        const e = chosen
        if (!e) return null
        if (chosenLive && preview.motionShown > 0) return liveTexture
        const f = preview.front
        const src = String(f.source)
        return f.status === Image.Ready && src !== "" && (src === pictureOf(e) || src === (e.fullUrl ?? "")) ? f : null
    }
    readonly property real chosenArtAspect: chosenArt === liveTexture ? width / Math.max(1, height)
        : chosenArt ? chosenArt.implicitWidth / Math.max(1, chosenArt.implicitHeight) : 16 / 10

    // The card out of the hand: placed where it was, then moved by riseAnim,
    // bloomAnim and backAnim.
    Item {
        id: flight
        // Each 0..1: the glow behind the card, the ring going out from it, its
        // pulse as it's set, the card gone from round its picture, the picture
        // grown into the wallpaper; and the light across it (-0.35..1.35).
        property real glow: 0
        property real ring: 0
        property real pulse: 0
        property real fade: 0
        property real bloom: 0
        property real shine: -1

        z: 20
        width: root.cardW
        height: root.cardH
        visible: root.choosing
        opacity: root.shown

        RectangularShadow {
            anchors.fill: chosenCard
            radius: chosenCard.radius
            blur: (34 + 22 * flight.pulse) * root.u
            spread: 5 * root.u * flight.pulse
            color: Qt.rgba(chosenCard.colAccent.r, chosenCard.colAccent.g, chosenCard.colAccent.b, 0.6)
            visible: opacity > 0.01
            opacity: flight.glow
        }
        Rectangle { // goes out from the card as it's set
            readonly property real grow: 64 * root.u * flight.ring
            anchors.centerIn: parent
            width: parent.width + grow * 2
            height: parent.height + grow * 2
            radius: chosenCard.radius + grow
            antialiasing: true
            color: "transparent"
            border.width: Math.max(1, 2.4 * root.u * (1 - 0.6 * flight.ring))
            border.color: chosenCard.colAccent
            visible: opacity > 0.01
            opacity: flight.ring > 0 && flight.ring < 1 ? Math.pow(1 - flight.ring, 1.3) : 0
        }
        DeckCard {
            id: chosenCard
            anchors.fill: parent
            scale: 1 + 0.035 * flight.pulse
            opacity: 1 - flight.fade
            u: root.u
            entry: root.chosen
            picture: root.pictureOf(root.chosen)
            front: 1
            dress: root.dressOf(root.chosen)
            chips: root.chipsOf(root.chosen)
            current: root.chosenSet
            favourite: root.isFavourite(root.chosen)
            saved: !!root.chosen?.item && root.isSaved(root.chosen)
            download: !!root.chosen?.item && Wallhaven.downloadingId === root.chosen.name ? Wallhaven.downloadProgress : -1
            title: root.titleOf(root.chosen)
            meta: root.metaOf(root.chosen)
            art: root.chosenArt
            artAspect: root.chosenArtAspect
            shine: flight.shine
        }
        // The picture, from its place on the card (upright by then) to the
        // whole screen: the wallpaper.
        Loader {
            active: flight.bloom > 0 && !!root.chosenArt
            sourceComponent: CardPicture {
                readonly property rect from: chosenCard.pictureRect
                readonly property real k: Math.max(0.01, flight.scale)
                readonly property real toX: flight.width / 2 - (flight.x + flight.width / 2) / k // the screen, in the card's units
                readonly property real toY: flight.height / 2 - (flight.y + flight.height / 2) / k
                readonly property real e: flight.bloom
                x: from.x + (toX - from.x) * e
                y: from.y + (toY - from.y) * e
                width: from.width + (root.width / k - from.width) * e
                height: from.height + (root.height / k - from.height) * e
                radius: chosenCard.thumbRadius * (1 - e)
                pixelScale: k
                source: root.chosenArt
                sourceAspect: root.chosenArtAspect
            }
        }
    }

    // A Wallhaven result in the middle while it downloads.
    DeckGlass {
        deck: root
        z: 21
        anchors.horizontalCenter: parent.horizontalCenter
        y: flight.y + flight.height / 2 + flight.height * flight.scale / 2 + 28 * root.u
        visible: opacity > 0.01
        opacity: root.awaiting ? root.shown : 0
        Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(220) } }
        width: waitRow.implicitWidth + 28 * root.u
        height: 36 * root.u
        Row {
            id: waitRow
            anchors.centerIn: parent
            spacing: 10 * root.u
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: "Downloading " + Math.round(Wallhaven.downloadProgress * 100) + "%"
                font.pixelSize: (Appearance?.font.pixelSize.smallie ?? 13) * root.u
                font.weight: Font.DemiBold
                color: tintColors.ink
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: "Esc: back to the deck"
                font.pixelSize: (Appearance?.font.pixelSize.smaller ?? 12) * root.u
                color: tintColors.muted
            }
        }
    }

    // Nothing under a chosen card takes the pointer.
    MouseArea {
        z: 30
        anchors.fill: parent
        visible: root.choosing
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
        onWheel: wheel => wheel.accepted = true
    }
}
