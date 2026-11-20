.pragma library
// Outputs for the display overlay (supports.outputConfig) from niri's and sway's own
// reports, in the shape Hyprland's j/monitors gives: { name, width, height,
// refreshRate, scale, x, y, focused, transform, vrr, availableModes: ["WxH@R.RRHz"] },
// and the commands that apply an overlay config { name, width, height, rate, scale, x, y }
// (x null = leave the position). Checked by scripts/dev/test-outputs-model.js.

// niri: `niri msg -j outputs` (name → output; refresh in mHz; logical null = off).
function niri(map, focusedName) {
    const out = []
    for (const name of Object.keys(map ?? {})) {
        const o = map[name], l = o?.logical
        if (!l) continue
        const cur = o.modes?.[o.current_mode] ?? { width: l.width, height: l.height, refresh_rate: 60000 }
        out.push({ name: name, width: cur.width, height: cur.height, refreshRate: cur.refresh_rate / 1000,
            scale: l.scale ?? 1, x: l.x ?? 0, y: l.y ?? 0, focused: name === focusedName, transform: l.transform ?? "Normal",
            vrr: !!o.vrr_enabled,
            availableModes: (o.modes ?? []).map(m => `${m.width}x${m.height}@${(m.refresh_rate / 1000).toFixed(2)}Hz`) })
    }
    return out.sort((a, b) => a.name < b.name ? -1 : 1)
}

// sway: GET_OUTPUTS objects (refresh in mHz; inactive outputs left out).
function sway(list) {
    const out = []
    for (const o of list ?? []) {
        if (!o || !o.active || !o.rect) continue
        const cur = o.current_mode ?? { width: o.rect.width, height: o.rect.height, refresh: 60000 }
        out.push({ name: o.name, width: cur.width, height: cur.height, refreshRate: cur.refresh / 1000,
            scale: o.scale ?? 1, x: o.rect.x, y: o.rect.y, focused: !!o.focused, transform: o.transform ?? "normal",
            vrr: o.adaptive_sync_status === "enabled",
            availableModes: (o.modes ?? []).map(m => `${m.width}x${m.height}@${(m.refresh / 1000).toFixed(2)}Hz`) })
    }
    return out.sort((a, b) => a.name < b.name ? -1 : 1)
}

const NAME = /^[A-Za-z0-9._-]+$/
function _ok(c) {
    return c && NAME.test(String(c.name)) && Number.isInteger(+c.width) && Number.isInteger(+c.height) && +c.width > 0 && +c.height > 0
        && +c.rate >= 0 && +c.scale > 0
}

// niri: argv lists for `niri msg output <name> …`; [] when a config is malformed.
function niriApply(configs) {
    const out = []
    for (const c of configs ?? []) {
        if (!_ok(c)) return []
        const base = ["niri", "msg", "output", String(c.name)]
        out.push(base.concat(["mode", +c.rate > 0 ? `${+c.width}x${+c.height}@${(+c.rate).toFixed(3)}` : `${+c.width}x${+c.height}`]))
        out.push(base.concat(["scale", String(+c.scale)]))
        if (c.x !== null && c.x !== undefined) out.push(base.concat(["position", "set", String(Math.round(c.x)), String(Math.round(c.y))]))
    }
    return out
}

// sway: one command (`output <name> mode … scale … position …` per config, joined by ";").
function swayApply(configs) {
    const out = []
    for (const c of configs ?? []) {
        if (!_ok(c)) return ""
        let s = `output ${c.name} mode ${+c.width}x${+c.height}${+c.rate > 0 ? `@${(+c.rate).toFixed(3)}Hz` : ""} scale ${+c.scale}`
        if (c.x !== null && c.x !== undefined) s += ` position ${Math.round(c.x)} ${Math.round(c.y)}`
        out.push(s)
    }
    return out.join("; ")
}
