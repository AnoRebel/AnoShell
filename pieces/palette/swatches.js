.pragma library

// Which Material roles the palette piece shows, in what order, for the room
// it has; plain JavaScript so scripts/dev/test-pieces-logic.js can check it.
// Keys are Appearance.m3colors property names.

// Roomy: one row per family, colour → on-colour → container → on-container.
const GROUPS = [
    ["m3primary", "m3onPrimary", "m3primaryContainer", "m3onPrimaryContainer"],
    ["m3secondary", "m3onSecondary", "m3secondaryContainer", "m3onSecondaryContainer"],
    ["m3tertiary", "m3onTertiary", "m3tertiaryContainer", "m3onTertiaryContainer"],
    ["m3surface", "m3surfaceContainer", "m3surfaceContainerHighest", "m3onSurface"],
    ["m3error", "m3onError", "m3errorContainer", "m3onErrorContainer"]
];
// Tight: the most telling colours first.
const KEY = ["m3primary", "m3secondary", "m3tertiary", "m3surface", "m3error",
    "m3primaryContainer", "m3secondaryContainer", "m3tertiaryContainer",
    "m3surfaceContainerHighest", "m3outline", "m3onSurface", "m3inversePrimary"];

// Rows of keys for a grid of at most cols × rows swatches.
function layout(cols, rows) {
    cols = Math.max(1, Math.floor(cols)); rows = Math.max(1, Math.floor(rows));
    if (cols >= 4 && rows >= 3)
        return GROUPS.slice(0, rows).map(g => g.slice(0, cols));
    const flat = KEY.slice(0, cols * rows), out = [];
    for (let i = 0; i < flat.length; i += cols) out.push(flat.slice(i, i + cols));
    return out;
}

// "m3onPrimaryContainer" → "On primary container"
function label(key) {
    const s = String(key).replace(/^m3/, "").replace(/([A-Z])/g, " $1").trim().toLowerCase();
    return s.charAt(0).toUpperCase() + s.slice(1);
}

// Channels 0–1 → "#rrggbb"
function hex(r, g, b) {
    const h = v => Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16).padStart(2, "0");
    return "#" + h(r) + h(g) + h(b);
}

// Text on the swatch: dark on light colours, light on dark (relative luminance).
function onDark(r, g, b) {
    const lin = v => v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b) < 0.35;
}
