pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.services

/**
 * Wallhaven (wallhaven.cc) for the wallpaper picker: search results page by
 * page, and download-then-apply into the wallpaper folder.
 * Ported from wallpaperpicker's services/Wallhaven.qml.
 *
 * The API key lives only in $XDG_DATA_HOME/anoshell/secrets/wallhaven (0600),
 * written by anod (secret.set) and read here; it never goes into config.json
 * or onto a command line: searches use XMLHttpRequest with an X-API-Key
 * header, downloads run curl with an argv (the full-size image URLs need no
 * key).
 */
Singleton {
    id: root

    readonly property var filters: Config.options?.background?.wallhaven
    property string apiKey: ""
    readonly property bool hasKey: root.apiKey.length > 0

    property string query: ""
    property var results: []      // [{ id, thumbUrl, fullUrl, resolution, fileType, fileSize, favorites, colors }]
    property bool fetching: false
    property int page: 1
    property bool hasMorePages: false
    property string error: ""
    property bool used: false     // searched since the last reset (filter changes then refetch)
    property string _seed: ""     // random order pages through one shuffle
    property int _generation: 0   // drops replies to superseded requests
    property var _xhr: null

    property string downloadingId: ""
    property real downloadProgress: 0
    property string downloadError: ""
    property string _part: ""
    property string _dest: ""

    // Where a result is (or would be) saved, or "" when its URL looks wrong.
    function savePathFor(w) {
        if (!w || !/^[a-z0-9]+$/.test(w.id ?? "")) return ""
        const m = /^https:\/\/w\.wallhaven\.cc\/full\/[a-z0-9]+\/wallhaven-[a-z0-9]+\.(jpg|jpeg|png|webp)$/.exec(w.fullUrl ?? "")
        return m ? `${Wallpapers.effectiveDirectory}/wallhaven-${w.id}.${m[1]}` : ""
    }

    // NSFW needs the key: without one it's dropped (SFW if nothing's left).
    function _purity() {
        const p = root.filters?.purity ?? "100"
        const q = root.hasKey ? p : p.substring(0, 2) + "0"
        return q === "000" ? "100" : q
    }

    function _url(page) {
        const f = root.filters
        const p = [
            "categories=" + encodeURIComponent(f?.categories ?? "111"),
            "purity=" + encodeURIComponent(root._purity()),
            "sorting=" + encodeURIComponent(f?.sorting ?? "date_added"),
            "order=" + encodeURIComponent(f?.order ?? "desc"),
            "page=" + page
        ]
        if ((f?.sorting ?? "") === "toplist") p.push("topRange=" + encodeURIComponent(f?.topRange ?? "1M"))
        if (root.query.length > 0) p.push("q=" + encodeURIComponent(root.query))
        if ((f?.sorting ?? "") === "random" && page > 1 && root._seed.length > 0) p.push("seed=" + encodeURIComponent(root._seed))
        return "https://wallhaven.cc/api/v1/search?" + p.join("&")
    }

    // A fresh search (page 1), or the next page.
    function fetch(reset) {
        if (reset) {
            if (root._xhr) root._xhr.abort()
            root._xhr = null
            root.fetching = false
            root.hasMorePages = false // before the list: an empty list reads as "at the end"
            root.page = 1
            root._seed = ""
            root.results = []
            root.error = ""
        } else if (root.fetching) return
        root.used = true
        root.fetching = true
        const gen = ++root._generation
        const page = root.page
        const xhr = new XMLHttpRequest()
        root._xhr = xhr
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE || gen !== root._generation) return
            root._xhr = null
            root.fetching = false
            if (xhr.status === 401) { root.error = "Wallhaven rejected the API key"; return }
            if (xhr.status === 429) { root.error = "Wallhaven rate limit: try again in a minute"; return }
            if (xhr.status !== 200) { root.error = xhr.status === 0 ? "Network error: check your connection" : `Wallhaven error ${xhr.status}`; return }
            try {
                const data = JSON.parse(xhr.responseText)
                const parsed = (data.data ?? []).map(item => ({
                    id: item.id, thumbUrl: item.thumbs?.large ?? "", fullUrl: item.path ?? "",
                    resolution: item.resolution ?? "", fileType: item.file_type ?? "",
                    fileSize: item.file_size ?? 0, favorites: item.favorites ?? 0, colors: item.colors ?? []
                }))
                root.results = page === 1 ? parsed : root.results.concat(parsed)
                if (page === 1) root._seed = data.meta?.seed ?? ""
                root.hasMorePages = (data.meta?.current_page ?? 1) < (data.meta?.last_page ?? 1)
                root.error = ""
            } catch (e) {
                root.error = "Couldn't read Wallhaven's reply"
            }
        }
        xhr.open("GET", root._url(page))
        if (root.hasKey) xhr.setRequestHeader("X-API-Key", root.apiKey)
        xhr.send()
    }

    function fetchNextPage() {
        if (!root.hasMorePages || root.fetching) return
        root.page++
        root.fetch(false)
    }

    function search(text) {
        root.query = text.trim()
        root.fetch(true)
    }

    // Back to a blank search (the picker calls this when it closes).
    function reset() {
        root.cancelDownload()
        if (root._xhr) root._xhr.abort()
        root._xhr = null
        root._generation++
        root.fetching = false
        root.hasMorePages = false
        root.query = ""
        root.results = []
        root.page = 1
        root._seed = ""
        root.error = ""
        root.used = false
    }

    // A filter or the key changed: search again if the list is in use.
    readonly property string _filterKey: JSON.stringify([root.filters?.categories, root.filters?.purity,
        root.filters?.sorting, root.filters?.order, root.filters?.topRange, root.hasKey])
    on_FilterKeyChanged: if (root.used) root.fetch(true)

    // ── Download, then apply through Wallpapers (anod's pipeline) ───────────
    function downloadAndApply(w) {
        if (root.downloadingId !== "") return false
        const dest = root.savePathFor(w)
        if (dest === "") { root.downloadError = "Unexpected image URL"; return false }
        root._dest = dest
        root._part = dest + ".part" // the folder lists only image extensions, so a half file never shows
        root._monitor = GlobalStates.wallpaperSelectorTargetMonitor // the picker may close meanwhile
        root._cancelled = false
        root.downloadingId = w.id
        root.downloadProgress = 0
        root.downloadError = ""
        // argv, no shell: the URL was checked by savePathFor (https://w.wallhaven.cc/…).
        downloader.exec(["curl", "-L", "--fail", "--progress-bar", "--create-dirs",
            "--connect-timeout", "15", "--speed-limit", "1024", "--speed-time", "30",
            "--proto", "=https", "--proto-redir", "=https", "-o", root._part, w.fullUrl])
        return true
    }

    // Esc on the waiting card, or the picker closing: stop, and don't apply.
    property bool _cancelled: false
    property string _monitor: ""
    function cancelDownload() {
        if (root.downloadingId === "") return
        root._cancelled = true
        if (downloader.running) downloader.running = false // its onExited cleans up
    }

    Process {
        id: downloader
        // curl's progress bar redraws "###   42.3%" with carriage returns.
        stderr: SplitParser {
            splitMarker: "\r"
            onRead: data => {
                const m = data.match(/([0-9]+(?:\.[0-9]+)?)%/)
                if (m) root.downloadProgress = Math.min(1, parseFloat(m[1]) / 100)
            }
        }
        onExited: exitCode => {
            if (exitCode !== 0 || root._cancelled) {
                root.downloadError = root._cancelled ? "" : `Download failed (curl exit ${exitCode})`
                if (!root._cancelled) console.warn(`[Wallhaven] ${root.downloadError}: ${root._dest}`)
                Quickshell.execDetached(["rm", "-f", "--", root._part])
                root.downloadingId = ""
                return
            }
            mover.exec(["mv", "-f", "--", root._part, root._dest])
        }
    }
    Process {
        id: mover
        onExited: exitCode => {
            if (exitCode === 0) {
                root.downloadProgress = 1
                // Saved either way; applied only if nobody cancelled meanwhile.
                if (!root._cancelled) Wallpapers.apply(root._dest, root._monitor, true)
            } else {
                root.downloadError = "Couldn't save the download"
            }
            root.downloadingId = ""
        }
    }

    // ── The key ─────────────────────────────────────────────────────────────
    // cb(errorMessage or "") once anod has written it.
    function setApiKey(value, cb) {
        // Without anod, Anod.call answers at once with an "unavailable" error.
        Anod.call("secret.set", { name: "wallhaven", value: value.trim() }, (res, err) => {
            keyFile.reload()
            if (cb) cb(err ? (err.code === "unavailable" ? "anod isn't running: start it to save the key" : err.message) : "")
        })
    }

    FileView {
        id: keyFile
        path: `${Directories.secretsDir}/wallhaven`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.apiKey = keyFile.text().trim()
        onLoadFailed: root.apiKey = ""
    }
}
