pragma Singleton
import QtQuick
import Quickshell
import qs.modules.common

/**
 * Reader — the shell side of anod's reader backend (novel, manga, anime).
 *
 * A panel calls open(kind) when it shows and close(kind) when it goes away
 * (minimised panels stay open). anod starts its local HTTP server on the
 * first open and answers with `base` (127.0.0.1, random port, per-session
 * token); after reader.idleTimeout with nothing open it stops, and the next
 * open gets a new base. anod tries a start 3 times, then reports the error
 * here; nothing retries on its own (the panel offers Retry).
 *
 * The ReaderAnime/ReaderManga/ReaderNovel services build their URLs from
 * `base` and react to ready(kind).
 */
Singleton {
    id: root

    property string base: ""               // http://127.0.0.1:<port>/<token>/
    property var states: ({ anime: "idle", manga: "idle", novel: "idle" }) // idle | starting | ready | error
    property string error: ""
    signal ready(string kind)

    function state(kind) { return root.states[kind] ?? "idle" }
    function _set(kind, st) {
        const s = Object.assign({}, root.states)
        s[kind] = st
        root.states = s
    }

    function open(kind) {
        if (root.state(kind) === "starting") return
        if (!Anod.available) {
            root.error = "AnoShell's daemon (anod) isn't running, so the reader can't start. Run `ano doctor`."
            root._set(kind, "error")
            return
        }
        root._set(kind, "starting")
        Anod.call("reader.open", { kind: kind }, (res, err) => {
            // Closed while it was starting: anod applied the close first, so undo the open.
            if (root.state(kind) !== "starting") {
                if (res?.url) Anod.call("reader.close", { kind: kind })
                return
            }
            if (err || !res?.url) {
                root.error = err?.message ?? "The reader backend did not start. Run `ano doctor`."
                root._set(kind, "error")
                return
            }
            root.error = ""
            root.base = res.url
            root._set(kind, "ready")
            root.ready(kind)
        })
    }

    function close(kind) {
        if (root.state(kind) === "idle") return
        root._set(kind, "idle")
        Anod.call("reader.close", { kind: kind })
    }

    // A shell that died with panels open never said close; once anod is
    // (re)connected, everything this shell doesn't show is closed, so the
    // backend's idle stop isn't held off by a dead shell.
    Connections {
        target: Anod
        function onAvailableChanged() { root.sweep() }
    }
    // Also: a reader showing across an anod restart reopens, getting the new base.
    function sweep() {
        if (!Anod.available) return
        for (const k of ["anime", "manga", "novel"]) {
            if (root.state(k) === "idle") Anod.call("reader.close", { kind: k })
            else if (root.state(k) === "ready") { root._set(k, "idle"); root.open(k) }
        }
    }

    // A source URL through the backend's image cache. Accepts raw http(s)
    // URLs and proxied ones from an earlier session (whose port and token
    // are gone): those are re-pointed at the current base.
    function image(u) {
        const s = String(u ?? "")
        if (s === "" || s.startsWith("file:") || s.startsWith("qrc:")) return s
        const m = s.match(/^http:\/\/127\.0\.0\.1:\d+\/.*[?&]url=([^&]+)/)
        const raw = m ? decodeURIComponent(m[1]) : s
        return root.base === "" ? "" : root.base + "image?url=" + encodeURIComponent(raw)
    }
    // The source URL behind a proxied one (what the library stores).
    function rawUrl(u) {
        const m = String(u ?? "").match(/[?&]url=([^&]+)/)
        return m ? decodeURIComponent(m[1]) : String(u ?? "")
    }

    // ── HTTP ─────────────────────────────────────────────────────────────
    // onDone(err, body): err is null on success, else a short message
    // ("source unavailable: …" when the site failed, so the panel can say so).
    function _send(method, url, data, onDone) {
        const xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status === 200) { onDone(null, xhr.responseText); return }
            let msg = xhr.status === 0 ? "the reader backend is not reachable" : "HTTP " + xhr.status
            try {
                const e = JSON.parse(xhr.responseText)
                if (e.error) msg = (e.unavailable ? "source unavailable: " : "") + e.error
            } catch (e) {}
            onDone(msg, null)
        }
        xhr.open(method, url)
        if (data !== undefined) {
            xhr.setRequestHeader("Content-Type", "application/json")
            xhr.send(JSON.stringify(data))
        } else {
            xhr.send()
        }
    }
    function get(url, onDone) { root._send("GET", url, undefined, onDone) }
    function post(url, data, onDone) { root._send("POST", url, data, onDone) }

    // ── Library (atomic JSON store in anod) ──────────────────────────────
    function loadLibrary(kind, cb) {
        root.get(root.base + "library/" + kind, (err, body) => {
            if (err) { console.warn(`[Reader] ${kind} library: ${err}`); cb(null); return }
            try { const d = JSON.parse(body); cb(Array.isArray(d) ? d : []) }
            catch (e) { console.warn(`[Reader] ${kind} library parse: ${e}`); cb(null) }
        })
    }
    function saveLibrary(kind, list) {
        if (root.base === "") return
        root._send("PUT", root.base + "library/" + kind, list, err => {
            if (err) console.warn(`[Reader] saving the ${kind} library failed: ${err}`)
        })
    }

    // ── Playback (mpv owned by anod, so it outlives the panel) ───────────
    // show/episode (optional) let anod save the position: resume, watched,
    // AniSkip (reader.anime.resume/skipIntro/finishedRatio).
    // Emitted as playback starts: the host minimises the panels so the video shows.
    signal playStarted()
    function play(link, title, show, episode) {
        root.playStarted()
        const a = Config.options?.reader?.anime ?? {}
        root.post(root.base + "anime/play", {
            url: link.url, referer: link.referer ?? "", subtitle: link.subtitle ?? "", title: title ?? "",
            show: show ?? "", episode: episode !== undefined ? String(episode) : "",
            resume: a.resume ?? true, skipIntro: a.skipIntro ?? false, finishedRatio: a.finishedRatio ?? 0.9
        }, err => { if (err) console.warn(`[Reader] mpv: ${err}`) })
    }
}
