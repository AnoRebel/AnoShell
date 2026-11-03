# Reader

Three side panels for reading and watching: **novels** (FreeWebNovel or NovelArrow, picked
from the source menu at the top of Browse),
**manga** (WeebCentral) and **anime** (AllAnime; episodes play in mpv). Each
has Browse (popular, latest, search, filters) and Library tabs, a detail page,
and a reader or player.

They are off by default. Turn them on in Settings → Modules → Reader, or set
`reader.enable: true`.

## Opening them

| Keybind (bundled configs) | Command | Panel |
| --- | --- | --- |
| Ctrl+Super+N | `ano reader novel` | novels (right edge) |
| Ctrl+Super+M | `ano reader manga` | manga (left edge) |
| Ctrl+Super+A | `ano reader anime` | anime (left edge) |

`ano reader <kind>` toggles; add `open` or `close` to be explicit. Underneath
it is `qs -c ano ipc call reader toggle <kind>` (`open`, `close` and
`minimize` too).

Each reader has an edge (`reader.<kind>.edge`: `left` or `right`). Only one
reader shows per edge: opening another there **minimises** the first. It stays
loaded, so it comes back where you left it. The minimise button in a panel's
header does the same. Two readers on opposite edges that don't fit side by
side behave the same way. Toggling a reader that is showing closes it, which
unloads it.

## The backend

The panels talk to **anod** (see [anod.md](anod.md)), which runs a small HTTP
server only while a reader is in use:

- It starts when the first panel opens. It listens on `127.0.0.1` with a
  random port, and every request must carry a random per-session token, so no
  other program can use it and no fixed port can clash.
- After `reader.idleTimeout` seconds (default 120) with every panel closed and
  nothing playing, it stops. A minimised panel counts as open.
- If it can't start, anod tries 3 times and then the panel shows the error
  with a Retry button. Nothing retries in the background.
- Covers and pages go through its image cache (`reader.cacheMB`, default 64,
  least recently used first). The panels decode images at the size they are
  shown, and pages scrolled away in a long chapter are released.
- One source failing (the site changed, or it is down) shows
  "source unavailable" in that panel only.

`ano reader status` shows whether it is running, which panels are open, and
whether something is playing. `ano doctor` checks it when the readers are on.

### Playback

Episodes play in **mpv**, which anod starts. Playback keeps going when you
close the panel or leave the episode list, and the backend waits for it to
end before its idle stop.

anod follows mpv over a private IPC socket (`$XDG_RUNTIME_DIR/anoshell/`)
and saves the position of each episode in
`~/.local/share/anoshell/reader/anime-progress.json`: playing it again starts
where you stopped (`reader.anime.resume`), and past `reader.anime.finishedRatio`
(90%) the episode list marks it watched; partly watched episodes show how far
you got. With `reader.anime.skipIntro`, openings and endings are skipped once
each, with community-submitted times from [AniSkip](https://api.aniskip.com)
looked up by the show's MyAnimeList id (no times: nothing is skipped).

### Airing

The anime reader's **Airing** tab lists this week's episodes (with when each
airs), this season's shows and the top airing shows from
[AniList](https://anilist.co)'s public API (no account; anod asks at most
every 2 s, caches answers for 10 minutes and gives up after three
rate-limited tries). Picking one searches the anime source for its title.
Library shows get a **NEW** badge when AniList says a newer episode has aired
than the last one you watched (matched by MyAnimeList id).
`reader.anime.airing` turns both off.

### Library and progress

Each reader's library (with the chapter or episode you reached) is kept in
`~/.local/share/anoshell/reader/<kind>-library.json`. Every save replaces the
file atomically, so a crash leaves the old or the new version, never half of
one.

The first time a library is read, an existing **novelmangareader** library is
copied in from `~/.local/share/quickshell/{anime_library,manga_library,new_novel_library}.json`.
The old files are left as they were.

## The Python fallback

The sources are scraped, and sites change. Until every Go source has been
verified live over time, the original Python servers stay available per
source:

```json
"reader": {
  "providers": {
    "weebcentral": { "backend": "python" }
  },
  "python": "/home/you/.local/share/qs-novelmangareader/venv/bin/python3"
}
```

anod then starts that source's server (from `scripts/reader/`) on a free port
when its panel opens, and serves it through the same token-checked address;
the other sources stay on Go. The servers need `flask`, `requests` and
`curl_cffi`. Point `reader.python` at a venv that has them, or install them
system-wide. Changes apply the next time the backend starts.

## Dependencies

- `mpv` for anime playback.
- Only for sources set to Python: `python3` with `flask`, `requests`,
  `curl_cffi`.

## Settings

| Key | Default | |
| --- | --- | --- |
| `reader.enable` | `false` | the readers at all |
| `reader.<novel\|manga\|anime>.enable` | `true` | each reader |
| `reader.<kind>.edge` | novel `right`, others `left` | where it opens |
| `reader.anime.resume` | `true` | start episodes where you stopped |
| `reader.anime.skipIntro` | `false` | skip openings/endings (AniSkip) |
| `reader.anime.finishedRatio` | `0.9` | from what fraction an episode is watched |
| `reader.anime.airing` | `true` | the Airing tab and new-episode badges (AniList) |
| `reader.idleTimeout` | `120` | seconds before the backend stops |
| `reader.cacheMB` | `64` | image cache size |
| `reader.metaCacheEntries` | `512` | lists, details and chapters kept in memory |
| `reader.providers.<freewebnovel\|weebcentral\|allanime>.backend` | `go` | `go` or `python` (the novel one covers both novel sources) |
| `reader.python` | `python3` | interpreter for the Python fallback |

The readers come from [novelmangareader](https://github.com/dhrruvsharma/shell)
(GPL-3.0).
