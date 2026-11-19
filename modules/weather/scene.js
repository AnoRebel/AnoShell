.pragma library

// The weather scene's logic: wttr.in codes to conditions, the sun's place and the sky's colours from the real sunrise
// and sunset, the moon's phase, and the eased, staged change between weathers.

// A wttr.in code → clear | cloudy | overcast | mist | rain | snow | storm.
function condition(code) {
    const c = +code
    if (c === 113) return "clear"
    if (c === 116) return "cloudy"
    if (c === 119 || c === 122) return "overcast"
    if ([143, 248, 260].includes(c)) return "mist"
    if ([200, 386, 389, 392, 395].includes(c)) return "storm"
    if ([179, 227, 230, 323, 326, 329, 332, 335, 338, 350, 368, 371, 374, 377].includes(c)) return "snow"
    if ([182, 185, 281, 284, 311, 314, 317, 320, 362, 365].includes(c)) return "rain" // sleet and freezing rain: rain
    return c ? "rain" : "clear"
}

// What each condition looks like, 0..1 each.
const LOOKS = {
    clear:    { clouds: 0.15, dark: 0,    rain: 0, snow: 0, mist: 0,   storm: 0 },
    cloudy:   { clouds: 0.55, dark: 0.1,  rain: 0, snow: 0, mist: 0,   storm: 0 },
    overcast: { clouds: 1,    dark: 0.45, rain: 0, snow: 0, mist: 0.1, storm: 0 },
    mist:     { clouds: 0.4,  dark: 0.2,  rain: 0, snow: 0, mist: 1,   storm: 0 },
    rain:     { clouds: 0.9,  dark: 0.5,  rain: 1, snow: 0, mist: 0.1, storm: 0 },
    snow:     { clouds: 0.8,  dark: 0.25, rain: 0, snow: 1, mist: 0.1, storm: 0 },
    storm:    { clouds: 1,    dark: 0.8,  rain: 1, snow: 0, mist: 0,   storm: 1 }
}
function look(cond) { return LOOKS[cond] ?? LOOKS.clear }

// "06:45 AM" / "18:05" → minutes after midnight, or NaN.
function minutesOf(text) {
    const m = /^(\d{1,2}):(\d{2})\s*([AaPp][Mm])?/.exec(String(text ?? "").trim())
    if (!m) return NaN
    let h = +m[1] % 24
    if (m[3]) h = (h % 12) + (/p/i.test(m[3]) ? 12 : 0)
    return h * 60 + +m[2]
}

// The sun at `now` minutes with sunrise/sunset (06:00/18:00 when unknown):
// { up, t (0..1 along the day arc, or along the night arc for the moon), dawn (0..1 how much dawn/dusk colour) }.
function sun(now, rise, set) {
    if (!(rise >= 0) || !(set > rise)) { rise = 360; set = 1080 }
    const twilight = 45
    const up = now >= rise && now < set
    let t
    if (up) t = (now - rise) / (set - rise)
    else {
        const night = 1440 - (set - rise)
        t = ((now - set + 1440) % 1440) / night
    }
    const near = Math.min(Math.abs(now - rise), Math.abs(now - set))
    const dawn = Math.max(0, 1 - near / twilight)
    return { up: up, t: t, dawn: dawn }
}

// Sky gradient [top, bottom] for the sun's state, before weather darkening.
function sky(s) {
    const day = ["#4a90d9", "#a6d1f2"], night = ["#0b1430", "#1f2d55"], dusk = ["#3b3f7a", "#f2a65a"]
    const base = s.up ? day : night
    const mix = (a, b, k) => {
        const pa = parseInt(a.slice(1), 16), pb = parseInt(b.slice(1), 16)
        const ch = sh => Math.round(((pa >> sh) & 255) * (1 - k) + ((pb >> sh) & 255) * k)
        return "#" + ((1 << 24) + (ch(16) << 16) + (ch(8) << 8) + ch(0)).toString(16).slice(1)
    }
    return [mix(base[0], dusk[0], s.dawn), mix(base[1], dusk[1], s.dawn)]
}

// The moon's phase for a date: 0 new, 0.25 first quarter, 0.5 full, 0.75 last quarter.
function moonPhase(date) {
    const synodic = 29.530588853
    const ref = Date.UTC(2000, 0, 6, 18, 14) // a new moon
    const days = (date.getTime() - ref) / 86400000
    return ((days % synodic) + synodic) % synodic / synodic
}

// One step of the eased, staged change from `cur` to `target` (both look() shapes) over dt seconds; ~2.5 s in all.
// Getting worse, clouds and darkness come first and precipitation follows; getting better, precipitation stops
// before the clouds clear.
// cur has reached target (the scene's numeric channels).
function same(cur, target) {
    for (const p of ["clouds", "dark", "rain", "snow", "storm", "mist"])
        if (cur[p] !== target[p]) return false
    return true
}

function step(cur, target, dt) {
    const k = dt / 1.25 // each stage takes about half the change
    const toward = (a, b) => Math.abs(b - a) <= k ? b : a + Math.sign(b - a) * k
    const out = Object.assign({}, cur)
    const stopping = ["rain", "snow", "storm"].some(p => cur[p] > target[p])
    for (const p of ["clouds", "dark"])
        if (!(target[p] < cur[p] && stopping)) out[p] = toward(cur[p], target[p])
    const gathered = out.clouds >= target.clouds - 0.05 && out.dark >= target.dark - 0.05
    for (const p of ["rain", "snow", "storm"])
        if (target[p] < cur[p] || gathered) out[p] = toward(cur[p], target[p])
    out.mist = toward(cur.mist, target.mist)
    return out
}
