pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.modules.common
import "lrcparser.js" as Lrc

/**
 * Synchronized lyrics for the currently playing Mpris track.
 *
 * Backends (Config.options.lyrics.backend):
 *   "Auto"    — default. Try Local first; fall back to LRCLIB; then NetEase
 *   "Local"   — only read .lrc files from <lyrics.dir>; no network
 *   "LRCLIB"  — query lrclib.net (cleanest public API, MIT-licensed corpus)
 *   "NetEase" — query music.163.com (broad Chinese-music coverage; needs
 *               browser-style headers)
 *
 * Local file resolution: searches <lyrics.dir> for "<artist> - <title>.lrc"
 * (case-insensitive, recursive) before any network call.
 *
 * Public surface:
 *   model            ListModel of { time, lyricLine }
 *   currentIndex     index of the line currently playing (or -1)
 *   loading          true while a fetch is in flight
 *   backend          which backend produced the current model
 *   offset           per-track offset in seconds (saved to lyricsMap)
 *   candidatesModel  alternate candidate songs from the online backend
 *                    so the user can manually pick when auto-match is wrong
 *   loadLyrics(force) look up the current track (force: even if it was
 *                    just looked up)
 *   acquire/release(name)  leases (ServiceLease): nothing is fetched while
 *                    no lyrics view is shown
 *   selectCandidate(songId, source)
 *   jumpTo(index, time)
 *   savePrefs()      persist offset + chosen backend + chosen songId
 *
 * Adapter changes from caelestia/services/LyricsService.qml:
 *   - Players.active                 → MprisController.activePlayer
 *   - Requests.get(url, cb, err, hdr) → Process(curl) per-fetcher (3 procs)
 *   - GlobalConfig.services.{showLyrics,lyricsBackend,paths.lyricsDir}
 *                                    → Config.options.lyrics.{visible,backend,dir}
 *   - Paths.absolutePath(...)        → manual ~ expansion via Quickshell.env("HOME")
 *   - LRCLIB primary online backend, NetEase secondary (caelestia did
 *     NetEase only). Auto mode tries LRCLIB before falling back to NetEase
 *   - Service is dormant when Config.options.lyrics.enable is false
 *     (default false). Auto-fetch on track change is gated on this.
 */
Singleton {
    id: root

    // ─── Config-driven properties ─────────────────────────────────────────
    readonly property bool serviceEnabled: Config.options?.lyrics?.enable ?? false
    readonly property bool lyricsVisible: Config.options?.lyrics?.visible ?? true
    readonly property string preferredBackend: Config.options?.lyrics?.backend ?? "Auto"
    readonly property string lyricsDir: {
        const raw = Config.options?.lyrics?.dir ?? "~/.config/anoshell/lyrics";
        const home = Quickshell.env("HOME") || "";
        return raw.replace(/^~(\/|$)/, home + "/").replace(/\/$/, "");
    }
    readonly property string lyricsMapFile: lyricsDir + "/lyrics_map.json"

    // ─── State ────────────────────────────────────────────────────────────
    property var player: MprisController.activePlayer
    property int currentIndex: -1
    property bool loading: false
    // A fetch running or about to (the track just changed): not "no lyrics" yet.
    readonly property bool pending: root.loading || loadDebounce.running
    property bool isManualSeeking: false
    property string backend: "Local"        // backend that produced the current model
    property real currentSongId: 0          // backend-specific id (NetEase) or 0
    property string loadedLocalFile: ""
    property real offset: 0
    property int currentRequestId: 0
    property var lyricsMap: ({})            // { "Artist - Title": { offset, backend, neteaseId } }

    // Leases from visible lyrics views (ServiceLease): no lookups without one.
    property var _leases: ({})
    property int leaseCount: 0
    function acquire(name) { root._leases[name] = (root._leases[name] ?? 0) + 1; root.leaseCount++ }
    function release(name) {
        if (!root._leases[name]) return
        if (--root._leases[name] <= 0) delete root._leases[name]
        root.leaseCount--
    }
    readonly property bool active: root.serviceEnabled && root.leaseCount > 0
    onActiveChanged: if (root.active) root.loadLyrics()

    // The track the model belongs to (or was last tried), and when: play/pause
    // and repeated metadata signals must not wipe and refetch the same track.
    property string _loadedKey: ""
    property real _lastAttempt: 0
    readonly property int _retryCooldownMs: 30000

    readonly property alias model: lyricsModel
    readonly property alias candidatesModel: fetchedCandidatesModel

    // Browser-style headers for NetEase (it 403s a bare curl).
    readonly property var _netEaseHeaders: [
        "-H", "User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:120.0) Gecko/20100101 Firefox/120.0",
        "-H", "Referer: https://music.163.com/"
    ]

    // ─── Public API ───────────────────────────────────────────────────────
    function getMetadata() {
        if (!player || !player.metadata) return null;
        let artist = player.metadata["xesam:artist"];
        const title = player.metadata["xesam:title"];
        if (Array.isArray(artist)) artist = artist.join(", ");
        return { artist: artist || "Unknown", title: title || "Unknown" };
    }

    function _metaKey(meta) {
        return `${meta.artist} - ${meta.title}`;
    }

    function savePrefs() {
        const meta = getMetadata();
        if (!meta) return;
        const key = _metaKey(meta);
        const existing = root.lyricsMap[key] ?? {};
        root.lyricsMap[key] = {
            offset: root.offset,
            backend: root.backend,
            neteaseId: existing.neteaseId ?? null
        };
        root.lyricsMap = root.lyricsMap;  // notify bindings
        lyricsMapFileView.setText(JSON.stringify(root.lyricsMap));
    }

    function toggleVisibility() {
        Config.setNestedValue("lyrics.visible", !root.lyricsVisible);
    }

    function loadLyrics(force) {
        if (!root.active) return;
        if (force) root._loadedKey = "";
        loadDebounce.restart();
    }

    // Starts a fetch process, or queues it behind the one still running:
    // `running = true` on a running Process does nothing, so the new request
    // would otherwise never start and the old reply would land on it.
    function _run(proc, command, reqId) {
        if (proc.running) {
            proc._next = { command: command, reqId: reqId };
            proc.running = false;
            return;
        }
        proc._reqId = reqId;
        proc._buf = "";
        proc.command = command;
        proc.running = true;
    }
    function _runNext(proc) {
        if (proc.running || !proc._next) return;
        const n = proc._next;
        proc._next = null;
        if (n.reqId === root.currentRequestId) _run(proc, n.command, n.reqId);
    }

    function _doLoadLyrics() {
        const meta = getMetadata();
        if (!meta) {
            lyricsModel.clear();
            root.currentIndex = -1;
            root._loadedKey = "";
            return;
        }
        const trackKey = _metaKey(meta);
        if (trackKey === root._loadedKey
                && (lyricsModel.count > 0 || root.loading || Date.now() - root._lastAttempt < root._retryCooldownMs))
            return;
        root._loadedKey = trackKey;
        root._lastAttempt = Date.now();

        loading = true;
        lyricsModel.clear();
        currentIndex = -1;
        root.currentSongId = 0;

        root.currentRequestId++;
        const requestId = root.currentRequestId;

        const key = _metaKey(meta);
        const saved = root.lyricsMap[key];
        root.offset = saved?.offset ?? 0.0;

        // Pinned-backend modes go straight to that backend.
        if (root.preferredBackend === "LRCLIB") {
            root.backend = "LRCLIB";
            fetchLrclib(meta.title, meta.artist, requestId);
            return;
        }
        if (root.preferredBackend === "NetEase") {
            root.backend = "NetEase";
            fetchNetEase(meta.title, meta.artist, requestId);
            return;
        }
        if (root.preferredBackend === "Local") {
            root.backend = "Local";
            _findLocal(meta, requestId);
            return;
        }

        // Auto: try local, with LRCLIB+NetEase candidates queued for fallback.
        root.backend = "Local";
        _findLocal(meta, requestId);
        // Pre-populate candidates so the user can manually pick if auto-match is wrong.
        fetchNetEaseCandidates(meta.title, meta.artist, requestId);
    }

    function _findLocal(meta, requestId) {
        const cleanDir = lyricsDir;
        const flatPath = `${cleanDir}/${meta.artist} - ${meta.title}.lrc`;

        const artistStr = Array.isArray(meta.artist) ? meta.artist.join(", ") : String(meta.artist || "");
        const titleStr = Array.isArray(meta.title) ? meta.title.join(", ") : String(meta.title || "");
        // Track metadata is untrusted (any player, any title): passed as
        // arguments, never spliced into the shell string.
        const cmd = ["sh", "-c",
            'find "$1" -type f -iname "*$2*$3*.lrc" 2>/dev/null | head -n 1',
            "sh", cleanDir, artistStr, titleStr
        ];
        if (findLyricsInSubdirs.running) {
            findLyricsInSubdirs._next = { command: cmd, reqId: requestId };
            findLyricsInSubdirs.running = false;
        } else {
            findLyricsInSubdirs.command = cmd;
            findLyricsInSubdirs.requestId = requestId;
            findLyricsInSubdirs.foundFile = false;
            findLyricsInSubdirs.running = true;
        }

        // Fast path: try the flat-file location directly. Even if find takes
        // a beat, an exact filename hit lands first.
        lrcFile.path = "";
        lrcFile.path = flatPath;
    }

    function updateModel(parsedArray) {
        root.currentIndex = -1;
        lyricsModel.clear();
        for (const line of parsedArray) {
            lyricsModel.append({ time: line.time, lyricLine: line.text });
        }
    }

    function fallbackToOnline() {
        const meta = getMetadata();
        if (!meta) return;
        // Auto mode: try LRCLIB first, NetEase second.
        root.backend = "LRCLIB";
        fetchLrclib(meta.title, meta.artist, root.currentRequestId);
    }

    // ─── LRCLIB backend ───────────────────────────────────────────────────
    // LRCLIB asks clients to identify themselves.
    readonly property string _userAgent: "AnoShell (https://github.com/anorebel/anoshell)"

    // Lower-case, without brackets ("(Remastered)", "[Live]") and punctuation.
    function _norm(v) {
        return String(v || "").toLowerCase().replace(/[(\[][^)\]]*[)\]]/g, " ")
            .replace(/[^0-9a-z\u00c0-\uffff]+/g, " ").trim();
    }
    function _overlaps(wanted, got) {
        wanted = _norm(wanted); got = _norm(got);
        if (!wanted || !got) return false;
        if (wanted.includes(got) || got.includes(wanted)) return true;
        const words = got.split(" ");
        return wanted.split(" ").some(w => w.length > 3 && words.includes(w));
    }
    // Search results are only taken when title and artist plausibly match.
    function _lrclibMatch(c, title, artist) {
        return !!c && !!c.syncedLyrics && _overlaps(title, c.trackName) && _overlaps(artist, c.artistName);
    }

    // Exact lookup with album + duration first (the most precise), then a
    // field search, then a free-text search (ported from Ryoku's lyrics.py).
    function fetchLrclib(title, artist, reqId) {
        const q = encodeURIComponent;
        const md = player?.metadata ?? {};
        const album = md["xesam:album"] || "";
        const secs = Math.round((player?.length ?? 0) || (md["mpris:length"] ?? 0) / 1e6);
        const api = "https://lrclib.net/api";
        const urls = [];
        if (album && secs > 0)
            urls.push(`${api}/get?track_name=${q(title)}&artist_name=${q(artist)}&album_name=${q(album)}&duration=${secs}`);
        else
            urls.push(`${api}/get?track_name=${q(title)}&artist_name=${q(artist)}`);
        urls.push(`${api}/search?track_name=${q(title)}&artist_name=${q(artist)}`);
        urls.push(`${api}/search?q=${q(title + " " + artist)}`);
        lrclibProc._urls = urls;
        lrclibProc._title = title;
        lrclibProc._artist = artist;
        _lrclibStep(0, reqId);
    }
    function _lrclibStep(i, reqId) {
        lrclibProc._step = i;
        _run(lrclibProc, ["curl", "-sL", "--max-time", "12", "-A", root._userAgent, lrclibProc._urls[i]], reqId);
    }

    Process {
        id: lrclibProc
        property int _reqId: -1
        property string _buf: ""
        property var _next: null
        property var _urls: []
        property int _step: 0
        property string _title: ""
        property string _artist: ""
        running: false
        stdout: SplitParser {
            splitMarker: ""
            onRead: data => { lrclibProc._buf += data; }
        }
        onRunningChanged: root._runNext(lrclibProc)
        onExited: (code, _) => {
            if (_reqId !== root.currentRequestId) return;
            let found = null;
            if (code === 0 && _buf) {
                try {
                    const res = JSON.parse(_buf);
                    // /get returns one record (trusted: exact fields); /search a list.
                    found = Array.isArray(res)
                        ? res.find(c => root._lrclibMatch(c, _title, _artist))
                        : (res?.syncedLyrics ? res : null);
                } catch (e) {
                    // fall through
                }
            }
            const parsed = found ? Lrc.parseLrc(found.syncedLyrics) : [];
            if (parsed.length > 0) {
                updateModel(parsed);
                root.backend = "LRCLIB";
                root.loading = false;
                return;
            }
            if (_step + 1 < _urls.length) {
                root._lrclibStep(_step + 1, _reqId);
                return;
            }
            _onLrclibFail();
        }

        function _onLrclibFail() {
            // In Auto mode, fall back to NetEase. In LRCLIB-pinned mode, stop.
            if (root.preferredBackend === "Auto") {
                const meta = getMetadata();
                if (meta) {
                    root.backend = "NetEase";
                    fetchNetEase(meta.title, meta.artist, root.currentRequestId);
                    return;
                }
            }
            root.loading = false;
        }
    }

    // ─── NetEase backend ──────────────────────────────────────────────────
    // NetEase has two stages: search → pick best match → fetch lyrics by id.
    function _searchNetEase(title, artist, reqId, onResults) {
        neteaseSearchProc._onResults = onResults;
        const query = encodeURIComponent(`${title} ${artist}`);
        const url = `https://music.163.com/api/search/get?s=${query}&type=1&limit=5`;
        _run(neteaseSearchProc, ["curl", "-sL", "--max-time", "15"].concat(_netEaseHeaders).concat([url]), reqId);
    }

    function fetchNetEaseCandidates(title, artist, reqId) {
        _searchNetEase(title, artist, reqId, _songs => {});
    }

    function fetchNetEase(title, artist, reqId) {
        _searchNetEase(title, artist, reqId, songs => {
            const bestMatch = songs.find(s => {
                const inputArtist = String(artist || "").toLowerCase();
                const sArtist = String(s.artists?.[0]?.name || "").toLowerCase();
                return inputArtist.includes(sArtist) || sArtist.includes(inputArtist);
            });
            if (!bestMatch) {
                root.loading = false;
                return;
            }
            const meta = getMetadata();
            if (meta) {
                const key = _metaKey(meta);
                root.lyricsMap[key] = {
                    offset: root.lyricsMap[key]?.offset ?? 0.0,
                    backend: "NetEase",
                    neteaseId: bestMatch.id
                };
            }
            root.currentSongId = bestMatch.id;
            savePrefs();
            fetchNetEaseLyrics(bestMatch.id, reqId);
        });
    }

    Process {
        id: neteaseSearchProc
        property int _reqId: -1
        property string _buf: ""
        property var _onResults: null
        property var _next: null
        running: false
        stdout: SplitParser {
            splitMarker: ""
            onRead: data => { neteaseSearchProc._buf += data; }
        }
        onRunningChanged: root._runNext(neteaseSearchProc)
        onExited: (code, _) => {
            if (_reqId !== root.currentRequestId) return;
            if (code !== 0 || !_buf) {
                if (typeof _onResults === "function") _onResults([]);
                return;
            }
            let songs = [];
            try {
                const res = JSON.parse(_buf);
                songs = res.result?.songs || [];
            } catch (e) {
                // empty
            }
            fetchedCandidatesModel.clear();
            for (const s of songs) {
                fetchedCandidatesModel.append({
                    id: s.id,
                    title: s.name || "Unknown Title",
                    artist: s.artists?.map(a => a.name).join(", ") || "Unknown Artist"
                });
            }
            if (typeof _onResults === "function") _onResults(songs);
        }
    }

    function fetchNetEaseLyrics(id, reqId) {
        const url = `https://music.163.com/api/song/lyric?id=${encodeURIComponent(id)}&lv=1&kv=1&tv=-1`;
        _run(neteaseLyricsProc, ["curl", "-sL", "--max-time", "15"].concat(_netEaseHeaders).concat([url]), reqId);
    }

    Process {
        id: neteaseLyricsProc
        property int _reqId: -1
        property string _buf: ""
        property var _next: null
        running: false
        stdout: SplitParser {
            splitMarker: ""
            onRead: data => { neteaseLyricsProc._buf += data; }
        }
        onRunningChanged: root._runNext(neteaseLyricsProc)
        onExited: (code, _) => {
            if (_reqId !== root.currentRequestId) return;
            if (code !== 0 || !_buf) {
                root.loading = false;
                return;
            }
            try {
                const res = JSON.parse(_buf);
                if (res.lrc?.lyric) {
                    updateModel(Lrc.parseLrc(res.lrc.lyric));
                    root.backend = "NetEase";
                }
            } catch (e) {
                // empty
            }
            root.loading = false;
        }
    }

    // ─── Manual selection / position tracking ─────────────────────────────
    function selectCandidate(songId, source) {
        const meta = getMetadata();
        if (!meta) return;
        // For now NetEase is the only backend with browseable candidates.
        const sourceBackend = source || "NetEase";
        root.backend = sourceBackend;
        root.currentSongId = songId;
        const key = _metaKey(meta);
        root.lyricsMap[key] = {
            offset: root.lyricsMap[key]?.offset ?? 0.0,
            backend: sourceBackend,
            neteaseId: sourceBackend === "NetEase" ? songId : (root.lyricsMap[key]?.neteaseId ?? null)
        };
        savePrefs();
        if (sourceBackend === "NetEase") {
            fetchNetEaseLyrics(songId, currentRequestId);
        }
    }

    function updatePosition() {
        if (isManualSeeking || loading || !player || lyricsModel.count === 0) return;
        const pos = (player.position ?? 0) - root.offset;
        let newIdx = -1;
        for (let i = lyricsModel.count - 1; i >= 0; i--) {
            if (pos >= lyricsModel.get(i).time - 0.1) { newIdx = i; break; }
        }
        if (newIdx !== currentIndex) root.currentIndex = newIdx;
    }

    function jumpTo(index, time) {
        root.isManualSeeking = true;
        root.currentIndex = index;
        // Per Quickshell.Services.Mpris docs, position is only writable
        // when both positionSupported and canSeek are true. Silently no-op
        // otherwise (most players will at least preserve currentIndex).
        if (player && player.positionSupported && player.canSeek) {
            player.position = time + root.offset + 0.01;
        }
        seekTimer.restart();
    }

    // ─── Models ───────────────────────────────────────────────────────────
    ListModel { id: lyricsModel }
    ListModel { id: fetchedCandidatesModel }

    Timer {
        id: seekTimer
        interval: 500
        onTriggered: root.isManualSeeking = false
    }

    // MprisPlayer.position is not reactive by default — it only emits
    // positionChanged on nonlinear changes (seeks). To advance the
    // highlighted line during normal playback, manually emit
    // positionChanged at 1Hz while playing, then bind updatePosition()
    // to it. Pattern from quickshell.org/docs/master/types/.../MprisPlayer.
    Timer {
        id: positionPoll
        running: !!root.player && root.player.playbackState === MprisPlaybackState.Playing
                 && root.model.count > 0   // was root.lyricsModel: undefined, so the poll never ran
        interval: 250  // 4Hz — smooth enough for line-level highlight, light on CPU
        repeat: true
        onTriggered: {
            if (root.player) root.player.positionChanged();
        }
    }
    Connections {
        target: root.player
        ignoreUnknownSignals: true
        function onPositionChanged() { root.updatePosition(); }
    }

    // If the local file lookup didn't yield anything within the interval,
    // fall back to the online backends (Auto mode only).
    Timer {
        id: fallbackTimer
        interval: 200
        onTriggered: {
            if (lyricsModel.count === 0 && root.preferredBackend === "Auto") {
                fallbackToOnline();
            }
        }
    }

    Timer {
        id: loadDebounce
        interval: 50
        onTriggered: root._doLoadLyrics()
    }

    // ─── Persistent maps + local LRC reads ────────────────────────────────
    FileView {
        id: lyricsMapFileView
        path: root.lyricsMapFile
        printErrors: false
        onLoaded: {
            try {
                root.lyricsMap = JSON.parse(text());
            } catch (e) {
                root.lyricsMap = {};
            }
        }
    }

    FileView {
        id: lrcFile
        printErrors: false
        onLoaded: {
            fallbackTimer.stop();
            const parsed = Lrc.parseLrc(text());
            if (parsed.length > 0) {
                root.backend = "Local";
                root.loadedLocalFile = path;
                updateModel(parsed);
                root.loading = false;
            } else if (root.preferredBackend === "Local") {
                // Local-pinned: nothing else to do.
                root.loading = false;
            }
            // In Auto mode, the Process onExited / fallbackTimer handle the next step.
        }
    }

    Process {
        id: findLyricsInSubdirs
        property int requestId: -1
        property bool foundFile: false
        property var _next: null
        running: false
        onRunningChanged: {
            if (running || !_next) return;
            const n = _next;
            _next = null;
            if (n.reqId !== root.currentRequestId) return;
            command = n.command;
            requestId = n.reqId;
            foundFile = false;
            running = true;
        }
        stdout: SplitParser {
            onRead: data => {
                if (findLyricsInSubdirs.requestId === root.currentRequestId) {
                    const foundPath = data.trim();
                    if (foundPath && foundPath.length > 0) {
                        findLyricsInSubdirs.foundFile = true;
                        fallbackTimer.stop();
                        root.loadedLocalFile = foundPath;
                        lrcFile.path = "";
                        lrcFile.path = foundPath;
                    }
                }
            }
        }
        onExited: (code, _) => {
            if (requestId === root.currentRequestId && !foundFile && root.preferredBackend === "Auto") {
                if (lyricsModel.count === 0) {
                    fallbackTimer.restart();
                }
            }
            foundFile = false;
        }
    }

    // ─── Track-change wiring ──────────────────────────────────────────────
    Connections {
        target: MprisController
        function onActivePlayerChanged() {
            root.player = MprisController.activePlayer;
            loadLyrics();
        }
    }

    Connections {
        target: root.player
        ignoreUnknownSignals: true
        function onMetadataChanged() { loadLyrics(); }
    }
}
