pragma Singleton

import QtQuick
import Quickshell
import qs.modules.common

/**
 * Glass material settings and the maths it needs (design D7).
 *
 * - Where the wallpaper sits: awww draws it with the recorded resize mode
 *   (background.resize: crop/fit/stretch/no), so a surface can sample the
 *   exact pixels behind it (`wallRect`).
 * - Contrast: anod's palette cache has a 16x10 luminance map of the current
 *   wallpaper; the tint thickens over bright areas so text stays ≥ 4.5:1
 *   (`tintAlpha`).
 * - Refraction is off for video wallpapers (the shell can't sample awww's
 *   video); `refractionReason` says why.
 */
Singleton {
    id: root

    readonly property var cfg: Config.options?.appearance?.glass ?? ({})
    readonly property bool enabled: cfg.enable ?? false
    readonly property real tint: cfg.tint ?? 0.55          // base tint strength
    readonly property real edgeLight: cfg.edgeLight ?? 0.6
    readonly property real refractionSetting: cfg.refraction ?? 0.5

    // ponytail: one wallpaper for every screen; per-screen rotation makes the
    // other screens refract/contrast-check this one (needs a per-screen map).
    readonly property string wallpaper: Config.options?.background?.wallpaperPath ?? ""
    readonly property bool isVideo: /\.(mp4|mkv|webm|mov|avi|m4v|ogv)$/i.test(root.wallpaper)
    readonly property string refractionReason: root.isVideo ? "Not with a video wallpaper (awww draws it; the shell can't sample it)" : ""
    readonly property real refraction: root.refractionReason ? 0 : root.refractionSetting
    readonly property string resize: Config.options?.background?.resize ?? "fit"

    // 16x10 luminance map of the wallpaper (0..255), from anod.
    property var lumaMap: []
    function _fetch() {
        root.lumaMap = []
        if (!root.enabled || !root.wallpaper) return
        Anod.call("palette.get", { path: root.wallpaper }, (res, err) => {
            if (res && res.path === root.wallpaper) root.lumaMap = res.lumaMap ? Array.from(Qt.atob(res.lumaMap), ch => ch.charCodeAt(0)) : []
        })
    }
    onWallpaperChanged: _fetch()
    onEnabledChanged: _fetch()
    Connections { target: Anod; function onAvailableChanged() { if (Anod.available) root._fetch() } }

    /// The item's screen rect (x, y, w, h) in the wallpaper's UV space, for a
    /// screen of size sw×sh showing an image of size iw×ih.
    function wallRect(x, y, w, h, sw, sh, iw, ih) {
        if (iw <= 0 || ih <= 0 || sw <= 0 || sh <= 0) return Qt.vector4d(0, 0, 1, 1)
        let s, dw, dh
        if (root.resize === "stretch") { dw = sw; dh = sh }
        // ponytail: iw/ih come from a 1280-wide decode (SurfaceMaterial), so "no"
        // places it at that size, not the file's; pass the real size if "no" matters.
        else if (root.resize === "no") { dw = iw; dh = ih }
        else {
            s = root.resize === "crop" ? Math.max(sw / iw, sh / ih) : Math.min(sw / iw, sh / ih)
            dw = iw * s; dh = ih * s
        }
        const ox = (sw - dw) / 2, oy = (sh - dh) / 2   // image placement on screen
        return Qt.vector4d((x - ox) / dw, (y - oy) / dh, w / dw, h / dh)
    }

    /// Luminance (0..1) of the bright end of the wallpaper under a UV rect
    /// (90th percentile of the cells: text can sit over the brightest part);
    /// 0.6 when unknown.
    function luminanceUnder(r) {
        const m = root.lumaMap
        if (!m || m.length < 160) return 0.6
        const x0 = Math.max(0, Math.floor(r.x * 16)), x1 = Math.min(15, Math.ceil((r.x + r.z) * 16) - 1)
        const y0 = Math.max(0, Math.floor(r.y * 10)), y1 = Math.min(9, Math.ceil((r.y + r.w) * 10) - 1)
        const cells = []
        for (let yy = y0; yy <= y1; yy++)
            for (let xx = x0; xx <= x1; xx++) cells.push(m[yy * 16 + xx])
        if (!cells.length) return 0.6
        cells.sort((a, b) => a - b)
        return cells[Math.min(cells.length - 1, Math.floor(cells.length * 0.9))] / 255
    }

    function _lin(v) { return Math.pow(Math.max(0, Math.min(1, v)), 2.2) }
    function _lum(c) { return 0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b) }

    /// Smallest tint alpha (≥ base) keeping text ≥ 4.5:1 over tint-on-wallpaper.
    function tintAlpha(base, bgLuma, tintColor, textColor) {
        const lb = _lin(bgLuma), lt = _lum(tintColor), lx = _lum(textColor)
        for (let a = base; a <= 1.0001; a += 0.02) {
            const l = (1 - a) * lb + a * lt
            const hi = Math.max(l, lx), lo = Math.min(l, lx)
            // 5:1 in this model for a real ≥ 4.5:1 (blur and gamma make
            // the estimate optimistic).
            if ((hi + 0.05) / (lo + 0.05) >= 5) return Math.min(1, a)
        }
        return 1
    }
}
