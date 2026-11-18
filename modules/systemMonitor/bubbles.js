.pragma library

// Bubble physics for the Bubble Monitor: soft circle collisions, a gentle pull to the middle, slow wander, damping,
// walls, and a squash that rings out after a knock. Nodes are plain objects mutated in place:
//   { id, x, y, vx, vy, r, target, squash, seed, held }   (world coordinates, the world's centre at 0,0)

function node(id, target, w, h, seed) {
    const s = seed === undefined ? Math.random() : seed
    const a = s * Math.PI * 2
    const d = 0.3 * Math.min(w, h) * (0.4 + 0.6 * ((s * 7.13) % 1))
    return { id: id, x: Math.cos(a) * d, y: Math.sin(a) * d, vx: 0, vy: 0, r: target * 0.3, target: target, squash: 0, seed: s, held: false }
}

// One step of dt seconds in a w×h world. Returns the knocks: [{ a, b, speed }] (closing speed in px/s).
function step(nodes, w, h, dt, t) {
    dt = Math.min(dt, 1 / 20)
    const knocks = []
    for (const n of nodes) {
        n.r += (n.target - n.r) * Math.min(1, dt * 3)
        n.squash *= Math.exp(-dt * 6)
        if (n.held) continue
        // Wander: a slow force turning with time, different for each bubble; and a pull to the middle.
        const ang = n.seed * 40 + t * (0.15 + n.seed * 0.2)
        n.vx += (Math.cos(ang) * 14 - n.x * 0.12) * dt
        n.vy += (Math.sin(ang) * 14 - n.y * 0.12) * dt
        const damp = Math.exp(-dt * 0.9)
        n.vx *= damp; n.vy *= damp
        n.x += n.vx * dt; n.y += n.vy * dt
        // Walls.
        const hw = w / 2 - n.r, hh = h / 2 - n.r
        if (n.x < -hw) { n.x = -hw; n.vx = Math.abs(n.vx) * 0.5 }
        if (n.x > hw) { n.x = hw; n.vx = -Math.abs(n.vx) * 0.5 }
        if (n.y < -hh) { n.y = -hh; n.vy = Math.abs(n.vy) * 0.5 }
        if (n.y > hh) { n.y = hh; n.vy = -Math.abs(n.vy) * 0.5 }
    }
    for (let i = 0; i < nodes.length; i++) {
        for (let j = i + 1; j < nodes.length; j++) {
            const a = nodes[i], b = nodes[j]
            let dx = b.x - a.x, dy = b.y - a.y
            let d = Math.hypot(dx, dy)
            const min = a.r + b.r + 6
            if (d >= min) continue
            if (d < 0.001) { dx = 1; dy = 0; d = 1 }
            const nx = dx / d, ny = dy / d
            const over = min - d
            // Push apart; a held bubble doesn't move, the other takes the whole push.
            const wa = a.held ? 0 : b.held ? 1 : 0.5
            const wb = b.held ? 0 : a.held ? 1 : 0.5
            a.x -= nx * over * wa; a.y -= ny * over * wa
            b.x += nx * over * wb; b.y += ny * over * wb
            const closing = (a.vx - b.vx) * nx + (a.vy - b.vy) * ny
            if (closing > 0) {
                const imp = closing * 0.8
                if (!a.held) { a.vx -= nx * imp * (wa * 2); a.vy -= ny * imp * (wa * 2) }
                if (!b.held) { b.vx += nx * imp * (wb * 2); b.vy += ny * imp * (wb * 2) }
                const sq = Math.min(0.18, closing / 900)
                a.squash = Math.max(a.squash, sq); b.squash = Math.max(b.squash, sq)
                if (closing > 40) knocks.push({ a: a.id, b: b.id, speed: closing })
            }
        }
    }
    return knocks
}

// Sparks: pairs whose gap is under `reach`, strongest first, at most `max`. [{ a, b, strength 0..1 }]
function sparks(nodes, reach, max) {
    const out = []
    for (let i = 0; i < nodes.length; i++)
        for (let j = i + 1; j < nodes.length; j++) {
            const a = nodes[i], b = nodes[j]
            const gap = Math.hypot(b.x - a.x, b.y - a.y) - a.r - b.r
            if (gap < reach) out.push({ a: a, b: b, strength: 1 - Math.max(0, gap) / reach })
        }
    out.sort((p, q) => q.strength - p.strength)
    return out.slice(0, max)
}

// The bubble under a world point, the topmost (last) first.
function hit(nodes, x, y) {
    for (let i = nodes.length - 1; i >= 0; i--)
        if (Math.hypot(nodes[i].x - x, nodes[i].y - y) <= nodes[i].r) return nodes[i]
    return null
}

// A process bubble's size from its CPU share of one core (0..1+): small when idle, growing with the square root.
function radiusFor(coreShare, small, big) {
    return small + (big - small) * Math.sqrt(Math.max(0, Math.min(1, coreShare)))
}
