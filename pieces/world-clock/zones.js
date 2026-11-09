.pragma library

// The world clock piece's arithmetic, plain JavaScript (no QML) so
// scripts/dev/test-pieces-logic.js can check it under node.
// Offsets are minutes east of UTC (services/Chrono's `offsets`).

const ZONE_RE = /^[A-Za-z0-9_+-]+(\/[A-Za-z0-9_+-]+)*$/;
const DAY = 86400000;

// "Asia/Kolkata" → "Kolkata", "America/New_York" → "New York"
function cityOf(zone) { return String(zone).split("/").pop().replace(/_/g, " "); }

// The setting: "Area/City=Label" entries separated by commas, semicolons or
// new lines; the label is optional. Malformed and repeated zones are skipped.
function parse(text) {
    const out = [], seen = {};
    for (const part of String(text == null ? "" : text).split(/[,;\n]/)) {
        const i = part.indexOf("=");
        const zone = (i < 0 ? part : part.slice(0, i)).trim();
        const label = i < 0 ? "" : part.slice(i + 1).trim();
        if (!ZONE_RE.test(zone) || seen[zone]) continue;
        seen[zone] = true;
        out.push({ zone: zone, label: label || cityOf(zone) });
    }
    return out;
}

// Whole days between the zone's calendar date and the local one at t (ms):
// +1 when it's already tomorrow there, −1 when still yesterday.
function dayOffset(t, zoneMin, localMin) {
    return Math.floor((t + zoneMin * 60000) / DAY) - Math.floor((t + localMin * 60000) / DAY);
}

// Hour of the day (0–23.99) in the zone at t.
function hourIn(t, zoneMin) {
    const ms = ((t + zoneMin * 60000) % DAY + DAY) % DAY;
    return ms / 3600000;
}

// A rough day/night hint from the hour (no sun position: the piece doesn't
// know where the city is): "day" 7–19, "twilight" 5–7 and 19–21, else "night".
function phase(hour) {
    if (hour >= 7 && hour < 19) return "day";
    if (hour >= 5 && hour < 21) return "twilight";
    return "night";
}

// The zone's difference from local time: "Same time", "+9 h", "−3:30 h".
function diffText(zoneMin, localMin) {
    const d = zoneMin - localMin;
    if (d === 0) return "Same time";
    const a = Math.abs(d), m = a % 60;
    return (d > 0 ? "+" : "−") + Math.floor(a / 60) + (m ? ":" + String(m).padStart(2, "0") : "") + " h";
}
