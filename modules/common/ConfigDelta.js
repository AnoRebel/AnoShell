.pragma library

// Replays the changes made since the last write onto a delta read from disk,
// so an edit made to the file meanwhile survives our next write.
// ops: { key: "a.b", value } sets, { key: "a.b", reset: true } removes (and
// prunes emptied parents), { all: true } clears everything.
function applyOps(delta, ops) {
    let out = JSON.parse(JSON.stringify(delta || {}))
    for (const op of ops) {
        if (op.all) { out = {}; continue }
        const keys = op.key.split(".")
        if (op.reset) {
            const trail = [out]
            for (let i = 0; i < keys.length - 1; ++i) {
                const next = trail[trail.length - 1][keys[i]]
                if (!next || typeof next !== "object" || Array.isArray(next)) { trail.length = 0; break }
                trail.push(next)
            }
            if (!trail.length) continue
            delete trail[trail.length - 1][keys[keys.length - 1]]
            for (let i = trail.length - 1; i > 0 && Object.keys(trail[i]).length === 0; --i)
                delete trail[i - 1][keys[i - 1]]
            continue
        }
        let cur = out
        for (let i = 0; i < keys.length - 1; ++i) {
            const v = cur[keys[i]]
            if (!v || typeof v !== "object" || Array.isArray(v)) cur[keys[i]] = {}
            cur = cur[keys[i]]
        }
        cur[keys[keys.length - 1]] = JSON.parse(JSON.stringify(op.value === undefined ? null : op.value))
    }
    return out
}
