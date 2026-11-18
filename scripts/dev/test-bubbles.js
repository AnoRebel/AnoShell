// Check for modules/systemMonitor/bubbles.js (Bubble Monitor physics).
// Run: node scripts/dev/test-bubbles.js
const fs = require('fs'), path = require('path')
const src = fs.readFileSync(path.join(__dirname, '../../modules/systemMonitor/bubbles.js'), 'utf8').replace('.pragma library', '')
const B = new Function(src + ';return {node, step, sparks, hit, radiusFor};')()
const a = (c, m) => { if (!c) throw new Error(m) }

// Two bubbles placed overlapping end apart, and the knock is reported once they close on each other.
const p = B.node('p', 40, 800, 600, 0.1), q = B.node('q', 40, 800, 600, 0.2)
p.r = q.r = 40
Object.assign(p, { x: -30, y: 0, vx: 200, vy: 0 })
Object.assign(q, { x: 30, y: 0, vx: -200, vy: 0 })
const knocks = B.step([p, q], 800, 600, 1 / 60, 0)
a(knocks.length === 1 && knocks[0].speed > 300, 'head-on knock reported')
a(q.x - p.x >= 85.9, 'pushed apart to touching')
a(p.vx < 0 && q.vx > 0, 'they bounce')
a(p.squash > 0 && q.squash > 0, 'both squash')

// A held bubble stays put; the other takes the whole push.
const h = B.node('h', 40, 800, 600, 0.3), o = B.node('o', 40, 800, 600, 0.4)
h.r = o.r = 40; h.held = true
Object.assign(h, { x: 0, y: 0 }); Object.assign(o, { x: 50, y: 0, vx: 0, vy: 0 })
B.step([h, o], 800, 600, 1 / 60, 0)
a(h.x === 0 && h.y === 0 && o.x >= 85.9, 'held stays, other moves')

// Many bubbles settle inside the walls without overlapping much.
const ns = Array.from({ length: 17 }, (_, i) => B.node(`n${i}`, 30 + i * 3, 1200, 800, i / 17))
for (let k = 0; k < 600; k++) B.step(ns, 1200, 800, 1 / 60, k / 60)
for (const n of ns) {
    a(Math.abs(n.x) <= 600 - n.r + 0.01 && Math.abs(n.y) <= 400 - n.r + 0.01, `inside walls ${n.id}`)
    a(Math.abs(n.r - n.target) < 1, `grown to size ${n.id}`)
    a(Number.isFinite(n.x + n.y + n.vx + n.vy), 'finite')
}
let worst = 0
for (let i = 0; i < ns.length; i++)
    for (let j = i + 1; j < ns.length; j++)
        worst = Math.max(worst, ns[i].r + ns[j].r - Math.hypot(ns[i].x - ns[j].x, ns[i].y - ns[j].y))
a(worst < 12, `settled without deep overlaps (${worst.toFixed(1)})`)

// Sparks: close pairs only, strongest first, capped.
const s1 = { x: 0, y: 0, r: 10 }, s2 = { x: 25, y: 0, r: 10 }, s3 = { x: 300, y: 0, r: 10 }, s4 = { x: -40, y: 0, r: 10 }
const sp = B.sparks([s1, s2, s3, s4], 40, 5)
a(sp.length === 2 && sp[0].a === s1 && sp[0].b === s2 && sp[0].strength > sp[1].strength, 'sparks')
a(B.sparks([s1, s2, s4], 40, 1).length === 1, 'sparks capped')

a(B.hit([s1, s3], 305, 2) === s3 && B.hit([s1, s3], 150, 0) === null, 'hit')
a(B.radiusFor(0, 20, 60) === 20 && B.radiusFor(1, 20, 60) === 60 && B.radiusFor(4, 20, 60) === 60 && B.radiusFor(0.25, 20, 60) === 40, 'radius')
console.log('bubbles ok')
