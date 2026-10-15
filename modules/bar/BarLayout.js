.pragma library

// Bar form geometry (bar-forms spec, design D12e). Pure functions over one
// axis: "pos"/"len" run along the bar, "off" is the distance from the screen
// edge. The caller animates group positions and each group's `sep` (0 =
// attached to the bar body, 1 = its own island); bodies() is evaluated on the
// live values every frame, so attach/detach is continuous.

var FORMS = ["full", "fit", "islands", "notch"];

function formOf(f) {
    return FORMS.indexOf(f) >= 0 ? f : "full";
}

// Default groups from the legacy modules.{left,center,right} lists.
function groupsFromModules(modules) {
    var m = modules || {};
    return [
        { id: "start", zone: "start", modules: m.left || [], attached: true },
        { id: "center", zone: "center", modules: m.center || [], attached: true },
        { id: "end", zone: "end", modules: m.right || [], attached: true }
    ];
}

// Each group's separation target: islands detaches everything, otherwise the
// group's own attached flag decides.
function sepTarget(form, group) {
    return formOf(form) === "islands" || group.attached === false ? 1 : 0;
}

// Target positions along the axis.
//   opts: { length, padding, spacing, form }
//   groups: [{ id, zone, len }] (empty groups have len 0 and are skipped)
// Returns { id: pos }.
function place(opts, groups) {
    var L = opts.length, p = opts.padding, s = opts.spacing;
    var form = formOf(opts.form);
    var out = {};
    var live = groups.filter(function (g) { return g.len > 0; });
    if (form === "notch") {
        // Everything packed together and centred: the body shrinks to it.
        var order = ["start", "center", "end"];
        var packed = [];
        order.forEach(function (z) { live.forEach(function (g) { if (g.zone === z) packed.push(g); }); });
        var total = packed.reduce(function (a, g) { return a + g.len; }, 0) + s * Math.max(0, packed.length - 1);
        var x = (L - total) / 2;
        packed.forEach(function (g) { out[g.id] = x; x += g.len + s; });
        return out;
    }
    var inset = form === "fit" ? opts.margin || 0 : 0;
    var x0 = inset + p;
    live.forEach(function (g) { if (g.zone === "start") { out[g.id] = x0; x0 += g.len + s; } });
    var x1 = L - inset - p;
    live.slice().reverse().forEach(function (g) { if (g.zone === "end") { x1 -= g.len; out[g.id] = x1; x1 -= s; } });
    var mids = live.filter(function (g) { return g.zone === "center"; });
    var midTotal = mids.reduce(function (a, g) { return a + g.len; }, 0) + s * Math.max(0, mids.length - 1);
    var xm = (L - midTotal) / 2;
    mids.forEach(function (g) { out[g.id] = xm; xm += g.len + s; });
    return out;
}

// Bodies from live geometry.
//   opts: { length, padding, form, gap, islandPad, margin, minLen }
//   live: [{ id, pos, len, sep }]
// Returns [{ pos, len, island, id, sep }]: the attached bar body (possibly split
// into segments around islands) followed by the islands. Separation opens a
// gap of gap*sep on each side of an island; below sep 0.02 the group counts as
// attached so the shapes merge without a sliver.
function bodies(opts, live) {
    var form = formOf(opts.form);
    var L = opts.length, g = opts.gap, ip = opts.islandPad || 0;
    var minLen = opts.minLen || 2 * ip;
    var items = live.filter(function (it) { return it.len > 0; })
                    .sort(function (a, b) { return a.pos - b.pos; });
    var islands = [], attached = [];
    items.forEach(function (it) { (it.sep > 0.02 ? islands : attached).push(it); });

    var span = null;
    if (form === "full") span = [0, L];
    else if (form === "fit") span = [opts.margin || 0, L - (opts.margin || 0)];
    else if (form === "notch" && items.length) {
        var lo = items[0].pos, hi = items[items.length - 1].pos + items[items.length - 1].len;
        span = [lo - opts.padding, hi + opts.padding];
    }
    // islands form: no body, only islands (span stays null).

    var out = [];
    if (span) {
        var holes = islands.map(function (it) {
            var cut = g * Math.min(1, it.sep);
            return [it.pos - ip - cut, it.pos + it.len + ip + cut];
        }).sort(function (a, b) { return a[0] - b[0]; });
        var cur = span[0];
        holes.forEach(function (h) {
            if (h[0] - cur >= minLen) out.push({ pos: cur, len: h[0] - cur, island: false });
            cur = Math.max(cur, h[1]);
        });
        if (span[1] - cur >= minLen) out.push({ pos: cur, len: span[1] - cur, island: false });
    }
    islands.forEach(function (it) {
        out.push({ pos: it.pos - ip, len: it.len + 2 * ip, island: true, id: it.id, sep: Math.min(1, it.sep) });
    });
    return out;
}

// The liquid neck between an island and its neighbours: full while the group
// is still joined, gone once it is fully separated (so a k larger than the gap
// can't keep bridging it).
function neckK(base, sep) {
    var t = Math.max(0, Math.min(1, sep === undefined ? 1 : sep));
    return base * (1 - t);
}
