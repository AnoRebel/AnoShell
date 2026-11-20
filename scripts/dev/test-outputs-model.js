// Check for services/compositor/OutputsModel.js. Run: node scripts/dev/test-outputs-model.js
const fs = require('fs'), path = require('path')
const src = fs.readFileSync(path.join(__dirname, '../../services/compositor/OutputsModel.js'), 'utf8').replace('.pragma library', '')
const M = new Function(src + ';return {niri, sway, niriApply, swayApply};')()
const a = (c, m) => { if (!c) throw new Error(m) }

// niri's JSON shape (niri msg -j outputs, 26.04).
const n = M.niri({
    "DP-1": { name: "DP-1", modes: [{ width: 2560, height: 1440, refresh_rate: 143998 }, { width: 1920, height: 1080, refresh_rate: 60000 }],
        current_mode: 0, vrr_enabled: true, logical: { x: 1920, y: 0, width: 2560, height: 1440, scale: 1.25, transform: "Normal" } },
    "HDMI-A-1": { name: "HDMI-A-1", modes: [{ width: 1920, height: 1080, refresh_rate: 60000 }], current_mode: 0, logical: null },
}, "DP-1")
a(n.length === 1 && n[0].name === "DP-1", "off outputs left out")
a(n[0].width === 2560 && Math.abs(n[0].refreshRate - 143.998) < 1e-6 && n[0].scale === 1.25 && n[0].x === 1920 && n[0].focused && n[0].vrr, "niri fields")
a(n[0].availableModes[0] === "2560x1440@144.00Hz" && n[0].availableModes.length === 2, "niri modes: " + n[0].availableModes)

// sway GET_OUTPUTS (sway-ipc(7)).
const s = M.sway([
    { name: "eDP-1", active: true, rect: { x: 0, y: 0, width: 1280, height: 800 }, scale: 1.5, focused: true,
      current_mode: { width: 1920, height: 1200, refresh: 59950 }, modes: [{ width: 1920, height: 1200, refresh: 59950 }], adaptive_sync_status: "disabled" },
    { name: "DP-2", active: false },
])
a(s.length === 1 && s[0].width === 1920 && Math.abs(s[0].refreshRate - 59.95) < 1e-6 && s[0].scale === 1.5 && !s[0].vrr && s[0].availableModes[0] === "1920x1200@59.95Hz", "sway fields")

// Apply: argv / one command; a bad name or mode applies nothing.
const cfg = { name: "DP-1", width: 1920, height: 1080, rate: 60, scale: 1, x: 0, y: 0 }
const argv = M.niriApply([cfg])
a(argv.length === 3 && argv[0].join(" ") === "niri msg output DP-1 mode 1920x1080@60.000" && argv[2].slice(-3).join(" ") === "set 0 0", "niri argv")
a(M.niriApply([Object.assign({}, cfg, { x: null })]).length === 2, "niri: no position")
a(M.swayApply([cfg]) === "output DP-1 mode 1920x1080@60.000Hz scale 1 position 0 0", "sway command: " + M.swayApply([cfg]))
a(M.swayApply([Object.assign({}, cfg, { name: "DP-1; exec rm" })]) === "" && M.niriApply([Object.assign({}, cfg, { width: "1920x" })]).length === 0, "malformed refused")
a(M.swayApply([Object.assign({}, cfg, { rate: 0 })]).startsWith("output DP-1 mode 1920x1080 scale"), "rate 0: sway picks")
console.log("outputs model: ok")
