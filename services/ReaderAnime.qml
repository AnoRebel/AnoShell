pragma Singleton
import QtQuick
import Quickshell
import qs.services

Singleton {
    id: root

    readonly property string apiUrl: Reader.base + "anime"

    property list<var> animeList: []
    property bool isFetchingAnime: false
    property string animeError: ""
    property bool hasMoreAnime: false
    property int popularPage: 1
    property int latestPage: 1
    property string currentSearchText: ""
    property string currentMode: "sub"
    property string currentCountry: "ALL"
    property string currentView: ""

    property var currentAnime: null
    property bool isFetchingDetail: false
    property string detailError: ""

    property list<var> streamLinks: []
    property var selectedLink: null
    property bool isFetchingLinks: false
    property string linksError: ""
    property string currentEpisode: ""
    // episode number → { pos, dur, watched } for currentAnime (anod)
    property var progress: ({})
    function refreshProgress() {
        const id = root.currentAnime?.id
        if (!id || !Reader.base) return
        Reader.get(Reader.base + "anime/progress?show=" + encodeURIComponent(id), function(err, body) {
            if (err || root.currentAnime?.id !== id) return
            try { root.progress = JSON.parse(body) || {} } catch (e) {}
        })
    }
    onCurrentAnimeChanged: { root.progress = ({}); root.refreshProgress() }

    // ── Library ───────────────────────────────────────────────────────────────
    // Each entry: { id, name, englishName, thumbnail, score,
    //               lastWatchedEpId, lastWatchedEpNum,
    //               bookmarked, addedAt }
    property list<var> libraryList: []
    property bool libraryLoaded: false

    function _saveLibrary() {
        if (root.libraryLoaded) Reader.saveLibrary("anime", root.libraryList)
    }

    function addToLibrary(anime) {
        if (isInLibrary(anime.id)) return
        var entry = {
            id:                 anime.id,
            name:               anime.name               || "",
            englishName:        anime.englishName         || anime.name || "",
            thumbnail:          anime.thumbnail           || "",
            score:              anime.score               || null,
            lastWatchedEpId:    "",
            lastWatchedEpNum:   "",
            bookmarked:         true,
            addedAt:            new Date().toISOString()
        }
        root.libraryList = [entry, ...root.libraryList]
        _saveLibrary()
        console.log("[ServiceAnime] Added to library:", entry.name)
    }

    function removeFromLibrary(animeId) {
        root.libraryList = root.libraryList.filter(function(e) { return e.id !== animeId })
        _saveLibrary()
        console.log("[ServiceAnime] Removed from library:", animeId)
    }

    function isInLibrary(animeId) {
        return root.libraryList.some(function(e) { return e.id === animeId })
    }

    function isBookmarked(animeId) {
        var entry = getLibraryEntry(animeId)
        return entry ? entry.bookmarked : false
    }

    function toggleBookmark(anime) {
        if (!isInLibrary(anime.id)) {
            addToLibrary(anime)
            return
        }
        root.libraryList = root.libraryList.map(function(e) {
            if (e.id !== anime.id) return e
            return Object.assign({}, e, { bookmarked: !e.bookmarked })
        })
        _saveLibrary()
    }

    function updateLastWatched(animeId, episodeId, episodeNum) {
        if (!isInLibrary(animeId)) return
        root.libraryList = root.libraryList.map(function(e) {
            if (e.id !== animeId) return e
            return Object.assign({}, e, {
                lastWatchedEpId:  episodeId,
                lastWatchedEpNum: String(episodeNum)
            })
        })
        _saveLibrary()
        console.log("[ServiceAnime] Last watched updated —", animeId, "ep.", episodeNum)
    }

    function getLibraryEntry(animeId) {
        for (var i = 0; i < root.libraryList.length; i++) {
            if (root.libraryList[i].id === animeId) return root.libraryList[i]
        }
        return null
    }

    function bookmarkedList() {
        return root.libraryList.filter(function(e) { return e.bookmarked })
    }

    // ── Backend (anod's reader; Reader.open/close come from the panel) ──────
    property bool serverReady: false

    Connections {
        target: Reader
        function onReady(kind) {
            if (kind !== "anime") return
            root.serverReady = true
            Reader.loadLibrary("anime", list => {
                root.libraryLoaded = list !== null
                if (list !== null) root.libraryList = list
            })
            fetchPopular()
        }
        function onStatesChanged() { if (Reader.state("anime") !== "ready") root.serverReady = false }
    }

    function fetchPopular(reset) {
        if (isFetchingAnime) return
        if (reset === undefined || reset) {
            animeList = []
            popularPage = 1
        }
        currentView = "popular"
        currentSearchText = ""
        isFetchingAnime = true
        animeError = ""

        const url = root.apiUrl + "/popular?size=20&page=" + popularPage + "&date_range=1"
        Reader.get(url, function(err, body) {
            if (err) { animeError = "Request failed: " + err; isFetchingAnime = false; return }
            _parsePopularResults(body)
        })
    }

    function _parsePopularResults(json) {
        try {
            const data = JSON.parse(json)
            if (data.error) { animeError = data.error; isFetchingAnime = false; return }

            const items = data.shows || []
            animeList = [...animeList, ...items.map(function(s) {
                return _normaliseShow(s)
            })]

            // popular endpoint has a fixed total of 500, paged by `size`
            const fetched = popularPage * 20
            hasMoreAnime = fetched < (data.total || 0)
            animeError = ""
        } catch (e) {
            animeError = "Parse error: " + e
            console.error("[ServiceAnime]", e)
        }
        isFetchingAnime = false
    }

    function fetchLatest(reset) {
        if (isFetchingAnime) return
        if (reset === undefined || reset) {
            animeList = []
            latestPage = 1
        }
        currentView = "latest"
        currentSearchText = ""
        isFetchingAnime = true
        animeError = ""

        const url = root.apiUrl + "/latest?limit=26&page=" + latestPage
            + "&mode=" + currentMode
            + "&country=" + currentCountry
        Reader.get(url, function(err, body) {
            if (err) { animeError = "Request failed: " + err; isFetchingAnime = false; return }
            _parseLatestResults(body)
        })
    }

    function _parseLatestResults(json) {
        try {
            const data = JSON.parse(json)
            if (data.error) { animeError = data.error; isFetchingAnime = false; return }

            const items = data.shows || []
            animeList = [...animeList, ...items.map(function(s) {
                return _normaliseShow(s)
            })]

            const fetched = latestPage * 26
            hasMoreAnime = fetched < (data.total || 0)
            animeError = ""
        } catch (e) {
            animeError = "Parse error: " + e
            console.error("[ServiceAnime]", e)
        }
        isFetchingAnime = false
    }

    function searchAnime(query, reset) {
        if (isFetchingAnime) return
        if (reset === undefined || reset) { animeList = [] }
        currentView = "search"
        currentSearchText = query
        isFetchingAnime = true
        animeError = ""

        const url = root.apiUrl + "/search?q=" + encodeURIComponent(query)
            + "&mode=" + currentMode
        Reader.get(url, function(err, body) {
            if (err) { animeError = "Request failed: " + err; isFetchingAnime = false; return }
            _parseSearchResults(body)
        })
    }

    function _parseSearchResults(json) {
        try {
            const data = JSON.parse(json)
            if (data.error) { animeError = data.error; isFetchingAnime = false; return }

            const items = data.results || []
            animeList = [...animeList, ...items.map(function(s) {
                return _normaliseShow(s)
            })]

            // search endpoint returns all matches at once
            hasMoreAnime = false
            animeError = ""
        } catch (e) {
            animeError = "Parse error: " + e
            console.error("[ServiceAnime]", e)
        }
        isFetchingAnime = false
    }

    function fetchNextPage() {
        if (!hasMoreAnime || isFetchingAnime) return
        if (currentView === "popular") {
            popularPage++
            fetchPopular(false)
        } else if (currentView === "latest") {
            latestPage++
            fetchLatest(false)
        }
    }

    function _normaliseShow(s) {
        var avail = s.available_episodes || {}
        return {
            id:          s.id          || "",
            name:        s.name        || "",
            englishName: s.english_name || s.englishName || s.name || "",
            nativeName:  s.native_name  || s.nativeName  || "",
            thumbnail:   s.thumbnail   || "",
            score:       s.score       !== undefined ? s.score : null,
            type:        s.type        || "",
            episodeCount: s.episode_count || "",
            availableEpisodes: {
                sub: avail.sub || 0,
                dub: avail.dub || 0,
                raw: avail.raw || 0
            },
            // /popular extras
            views:       s.views       || null,
            // /latest extras
            season:      s.season      || null,
            lastEpisode: s.last_episode || null
        }
    }

    function fetchAnimeDetail(show) {
        if (isFetchingDetail) return
        isFetchingDetail = true
        currentAnime = null
        detailError = ""

        // Seed what we already know from the list card immediately
        currentAnime = Object.assign({}, show, { episodes: [] })

        const url = root.apiUrl + "/episodes?id=" + encodeURIComponent(show.id)
            + "&mode=" + currentMode
        Reader.get(url, function(err, body) {
            if (err) { detailError = "Request failed: " + err; isFetchingDetail = false; return }
            _parseAnimeDetail(show, body)
        })
    }

    function _parseAnimeDetail(show, json) {
        try {
            const data = JSON.parse(json)
            if (data.error) { detailError = data.error; isFetchingDetail = false; return }

            const eps = (data.episodes || []).map(function(epNum, idx) {
                return {
                    id:     show.id + "-" + epNum,   // synthetic id: showId-epNumber
                    number: epNum,
                    index:  idx
                }
            })

            currentAnime = Object.assign({}, show, {
                episodes: eps,
                episodeCount: data.count || eps.length
            })
            detailError = ""
        } catch (e) {
            detailError = "Parse error: " + e
            console.error("[ServiceAnime]", e)
        }
        isFetchingDetail = false
    }

    function clearDetail() {
        currentAnime = null
        detailError = ""
        clearStreamLinks()
    }

    function fetchStreamLinks(showId, episodeNum, quality) {
        if (isFetchingLinks) return
        isFetchingLinks = true
        streamLinks = []
        selectedLink = null
        linksError = ""
        currentEpisode = String(episodeNum)

        const q = quality || "best"
        const url = root.apiUrl + "/links?id=" + encodeURIComponent(showId)
            + "&ep=" + encodeURIComponent(episodeNum)
            + "&mode=" + currentMode
            + "&quality=" + encodeURIComponent(q)
        Reader.get(url, function(err, body) {
            if (err) { linksError = "Request failed: " + err; isFetchingLinks = false; return }
            _parseStreamLinks(body)
        })
    }

    function _parseStreamLinks(json) {
        try {
            const data = JSON.parse(json)
            if (data.error) { linksError = data.error; isFetchingLinks = false; return }

            const validLinks = (data.all_links || []).filter(function(l) {
                return !l.error && l.url && l.url.length > 0
            })

            streamLinks = validLinks.map(function(l) {
                return {
                    url:      l.url      || "",
                    quality:  l.quality  || "?",
                    type:     l.type     || "mp4",
                    provider: l.provider || "",
                    referer:  l.referer  || "",
                    subtitle: l.subtitle || ""
                }
            })

            if (streamLinks.length === 0) {
                // All providers failed — surface a meaningful error instead of
                // silently doing nothing.
                linksError = "No working stream found for this episode"
                isFetchingLinks = false
                return
            }

            var sel = data.selected
            if (sel && sel.error) sel = null
            if (sel && (!sel.url || sel.url.length === 0)) sel = null

            selectedLink = sel ? {
                url:      sel.url      || "",
                quality:  sel.quality  || "?",
                type:     sel.type     || "mp4",
                provider: sel.provider || "",
                referer:  sel.referer  || "",
                subtitle: sel.subtitle || ""
            } : streamLinks[0]

            linksError = ""
        } catch (e) {
            linksError = "Parse error: " + e
            console.error("[ServiceAnime]", e)
        }
        isFetchingLinks = false
    }

    function selectLink(link) {
        selectedLink = link
    }

    function clearStreamLinks() {
        streamLinks = []
        selectedLink = null
        linksError = ""
        currentEpisode = ""
    }

    function clearAnimeList() {
        animeList = []
        hasMoreAnime = false
        popularPage = 1
        latestPage = 1
        animeError = ""
    }

    function setMode(mode) {
        if (mode === currentMode) return
        currentMode = mode
        if (currentView === "popular")      fetchPopular(true)
        else if (currentView === "latest")  fetchLatest(true)
        else if (currentView === "search" && currentSearchText.length > 0)
            searchAnime(currentSearchText, true)
    }

    function setCountry(country) {
        if (country === currentCountry) return
        currentCountry = country
        if (currentView === "latest") fetchLatest(true)
    }
}
