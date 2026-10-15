.pragma library
// Editing a bar's groups (Settings and the in-bar right-click menu share this).
// Pure: callers write the result with Config.setNestedValue(`bars.${i}.groups`, …).

.import "BarLayout.js" as BarLayout

// A deep copy of the bar's groups, migrating legacy modules on first edit.
function editable(barConfig) {
    var groups = (barConfig && barConfig.groups && barConfig.groups.length) ? barConfig.groups
        : BarLayout.groupsFromModules(barConfig ? barConfig.modules : null);
    return JSON.parse(JSON.stringify(groups));
}

function patch(groups, id, fields) {
    return groups.map(function (g) {
        if (g.id !== id) return g;
        var c = JSON.parse(JSON.stringify(g));
        for (var k in fields) c[k] = fields[k];
        return c;
    });
}

// Move a module to a group (at index, default end); no-op onto itself.
function moveModule(groups, moduleId, fromId, toId, index) {
    var out = JSON.parse(JSON.stringify(groups));
    var from = out.filter(function (g) { return g.id === fromId; })[0];
    var to = out.filter(function (g) { return g.id === toId; })[0];
    if (!from || !to) return out;
    var i = from.modules.indexOf(moduleId);
    if (i < 0) return out;
    from.modules.splice(i, 1);
    var at = index === undefined || index < 0 || index > to.modules.length ? to.modules.length : index;
    to.modules.splice(at, 0, moduleId);
    return out;
}

function addGroup(groups, zone) {
    var n = 1, ids = groups.map(function (g) { return g.id; });
    while (ids.indexOf("group" + n) >= 0) n++;
    return groups.concat([{ id: "group" + n, zone: zone || "end", modules: [], attached: true }]);
}

// Removing a group hands its modules to the first remaining group in its zone
// (or the first group), so nothing silently disappears.
function removeGroup(groups, id) {
    var gone = groups.filter(function (g) { return g.id === id; })[0];
    var rest = JSON.parse(JSON.stringify(groups.filter(function (g) { return g.id !== id; })));
    if (!gone || rest.length === 0) return gone ? groups : rest;
    var heir = rest.filter(function (g) { return g.zone === gone.zone; })[0] || rest[0];
    heir.modules = heir.modules.concat(gone.modules || []);
    return rest;
}
