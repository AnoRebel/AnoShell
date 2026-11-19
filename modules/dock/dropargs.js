.pragma library
// Files and links dropped on a dock icon → the argv lists to launch
// (scripts/dev/test-dock-drop.js). Quickshell's DesktopEntry.command is the
// Exec line with its field codes removed, so where they stood comes from
// execString, tokenized the same way: a code alone as a token marks the slot.
// %F/%U: every item in one launch; %f/%u: one launch per item. %f/%F take
// local files only (file:// URLs become paths); %u/%U also take other URLs.
// An entry with no file code takes no drops (a terminal given a dropped
// script as an argument would run it).

// Tokens of an Exec string: whitespace splits outside quotes; inside double
// quotes \" \` \$ \\ escape (single quotes: none, as Quickshell); a token is { text, code } where code is the field
// code letter when the whole unquoted token is one ("%U" → "U").
function tokens(exec) {
    const out = []
    let cur = "", quoted = false, inQuote = "", i = 0
    const s = String(exec || "")
    const push = () => {
        if (cur.length || quoted) {
            const m = !quoted && /^%([fFuUdDnNickvm])$/.exec(cur)
            out.push({ text: cur, code: m ? m[1] : "" })
        }
        cur = ""; quoted = false
    }
    for (; i < s.length; i++) {
        const c = s[i]
        if (inQuote) {
            if (inQuote === '"' && c === "\\" && i + 1 < s.length) cur += s[++i]
            else if (c === inQuote) inQuote = ""
            else cur += c
        } else if (c === '"' || c === "'") { inQuote = c; quoted = true }
        else if (c === " " || c === "\t") push()
        else cur += c
    }
    push()
    return out
}

function localPath(url) {
    const u = String(url)
    if (!u.startsWith("file://")) return u.startsWith("/") ? u : ""
    let p = u.slice(7)
    if (!p.startsWith("/")) p = p.slice(p.indexOf("/")) // file://host/path
    try { return decodeURIComponent(p) } catch (e) { return "" }
}

// The file code an Exec line has: "F", "U", "f", "u" or "" (none).
function fileCode(exec) {
    const t = tokens(exec).find(t => "FUfu".includes(t.code) && t.code)
    return t ? t.code : ""
}

// The items an entry takes, as they will be passed: local paths for files,
// URLs as given where it takes URLs; [] when it takes none of them.
function accepted(exec, urls) {
    const code = fileCode(exec)
    if (!code) return []
    const takesUrls = code === "u" || code === "U"
    const out = []
    for (const u of urls || []) {
        const p = localPath(u)
        if (p) out.push(p)
        else if (takesUrls && /^[a-z][a-z0-9+.-]*:\/\//i.test(String(u))) out.push(String(u))
    }
    return out
}

// argv lists to run for `urls` dropped on an entry ([] when it takes none).
// command is DesktopEntry.command (codes removed), exec its execString.
function launches(exec, command, urls) {
    const items = accepted(exec, urls)
    if (!items.length) return []
    const toks = tokens(exec)
    // The code's slot in `command`: tokens before it, minus other codes (removed there too).
    let slot = command.length
    const at = toks.findIndex(t => "FUfu".includes(t.code) && t.code)
    if (at >= 0) slot = toks.slice(0, at).filter(t => !t.code).length
    slot = Math.min(slot, command.length)
    const make = list => command.slice(0, slot).concat(list, command.slice(slot))
    const code = toks[at].code
    return code === "F" || code === "U" ? [make(items)] : items.map(it => make([it]))
}
