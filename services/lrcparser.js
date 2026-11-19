function parseLrc(text) {
    if (!text) return [];
    let lines = text.split("\n");
    let result = [];

    let timeRegex = /\[(\d+):(\d+\.\d+|\d+)\]/g;

    // Blacklist for credits/metadata often found in NetEase lyrics
    const creditKeywords = [
        "作词", "作曲", "编曲", "制作", "收录", "演奏", "词：", "曲：", "Lyricist", "Composer", "Arranger", "Producer", "Mixing", "Mastering"
    ];

    for (let line of lines) {

        timeRegex.lastIndex = 0;
        let matches = [];
        let match;

        while ((match = timeRegex.exec(line)) !== null) {
            matches.push(match);
        }

        if (matches.length === 0) continue;

        let lyric = line.replace(timeRegex, "").trim();

        let min = parseInt(matches[0][1]);
        let sec = parseFloat(matches[0][2]);
        let totalTime = min * 60 + sec;

        // Only filter credits if they appear in the first 20 seconds
        if (totalTime < 20) {
            let isCreditFormat = creditKeywords.some(k => lyric.includes(k));
            if (isCreditFormat && (lyric.includes(":") || lyric.includes("：") || lyric.length < 25)) {
                continue;
            }
        }

        for (let match of matches) {
            let min = parseInt(match[1]);
            let sec = parseFloat(match[2]);

            result.push({
                time: min * 60 + sec,
                text: lyric
            });
        }
    }

    result.sort((a, b) => a.time - b.time);
    return result;
}

function getCurrentLine(lyrics, position) {
    const epsilon = 0.1; // 100ms tolerance
    for (let i = lyrics.length - 1; i >= 0; i--) {
        if ((position + epsilon) >= lyrics[i].time) {
            return i;
        }
    }
    return -1;
}

// ─── LRCLIB search matching (LyricsService) ─────────────────────────────
// Lower-case, without brackets ("(Remastered)", "[Live]") and punctuation.
function norm(v) {
    return String(v || "").toLowerCase().replace(/[(\[][^)\]]*[)\]]/g, " ")
        .replace(/[^0-9a-z\u00c0-\uffff]+/g, " ").trim();
}
function overlaps(wanted, got) {
    wanted = norm(wanted); got = norm(got);
    if (!wanted || !got) return false;
    if (wanted.includes(got) || got.includes(wanted)) return true;
    const words = got.split(" ");
    return wanted.split(" ").some(w => w.length > 3 && words.includes(w));
}
// A search result is only taken when title and artist plausibly match.
function lrclibMatch(c, title, artist) {
    return !!c && !!c.syncedLyrics && overlaps(title, c.trackName) && overlaps(artist, c.artistName);
}
// The matching result closest in length to the track (secs, 0 when unknown);
// one more than 3 s off is another cut and would run out of sync.
function lrclibPick(list, title, artist, secs) {
    const ok = (list || []).filter(c => lrclibMatch(c, title, artist));
    if (!(secs > 0)) return ok[0] ?? null;
    const off = c => c.duration > 0 ? Math.abs(c.duration - secs) : 0;
    return ok.filter(c => off(c) <= 3).sort((a, b) => off(a) - off(b))[0] ?? null;
}
