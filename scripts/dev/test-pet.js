// Check for modules/pet/pet.js (the desktop pet's behaviours, poses, floors and fall). Run: node scripts/dev/test-pet.js
const fs = require('fs'), path = require('path')
const src = fs.readFileSync(path.join(__dirname, '../../modules/pet/pet.js'), 'utf8').replace('.pragma library', '')
const P = new Function(src + ';return {KINDS, PRESETS, presetOf, pick, behaviours, ownBehaviours, pose, mix, floors, floorUnder, clampTo, fall, throwVelocity, SLEEP_AFTER, onHead, bodyBox};')()
const a = (c, m) => { if (!c) throw new Error(m) }

// Presets: three per kind, with fallbacks.
for (const k of P.KINDS) a(Object.keys(P.PRESETS[k]).length === 3, `${k} presets`)
a(P.presetOf('cat', 'calico').pattern === 'patches' && P.presetOf('cat', 'nope').label === 'Tabby', 'preset fallback')
a(P.presetOf('ferret', 'x').label === 'White', 'unknown kind: duck')

// Every behaviour is picked over the range, each kind's own ones included; no sleep while the user is around.
for (const k of P.KINDS) {
    const seen = new Set()
    for (let i = 0; i < 1000; i++) seen.add(P.pick(k, i / 1000, 0.5, 0).name)
    for (const own of P.ownBehaviours(k)) a(seen.has(own), `${k} picks ${own}`)
    a(seen.has('walk') && seen.has('idle') && !seen.has('sleep'), `${k} common behaviours, no sleep`)
    let sleeps = 0
    for (let i = 0; i < 100; i++) if (P.pick(k, i / 100, 0.5, P.SLEEP_AFTER).name === 'sleep') sleeps++
    a(sleeps >= 50, `${k} sleeps after a quiet spell (${sleeps})`)
    for (const b of P.behaviours(k).concat(['carry', 'fall', 'happy'])) {
        const p = P.pose(k, b, 1.3)
        for (const v of Object.values(p)) a([].concat(v).every(Number.isFinite), `${k} ${b} pose finite`)
    }
}
const m = P.mix(P.pose('cat', 'idle', 0), P.pose('cat', 'sleep', 0), 0.5)
a(m.lie === 0.5 && m.eye === 0.5 && m.legs.length === 4, 'mix halfway')

// Floors: ground plus wide, low-enough windows, in usable-area coordinates.
const wins = [{ key: 'term', x: 200, y: 540, width: 600, height: 400 }, { key: 'narrow', x: 1000, y: 500, width: 80, height: 300 },
              { key: 'top', x: 0, y: 40, width: 1920, height: 1000 }, { key: 'fs', x: 0, y: 300, width: 1920, height: 1080, fullscreen: true }]
const fl = P.floors(wins, 0, 40, 1920, 1040, 128)
a(fl.length === 2 && fl[1].id === 'term' && fl[1].y === 500 && fl[1].x1 === 200 && fl[1].x2 === 800, 'window top as floor')
a(P.floorUnder(fl, 400, 300).id === 'term' && P.floorUnder(fl, 400, 600).id === 'ground' && P.floorUnder(fl, 100, 300).id === 'ground', 'floor under')
a(P.clampTo(fl[1], 190, 64) === 264 && P.clampTo(fl[0], 5000, 64) === 1856, 'never past a floor end')

// A throw to the right lands on the terminal's top; walls bounce; the ceiling holds.
let s = { x: 300, y: 200, vx: 400, vy: -300 }, landed = null
for (let i = 0; i < 200 && !landed; i++) { const r = P.fall(s, 1 / 60, fl, 1920, 64, 110); s = r.s; landed = r.landed }
a(landed && landed.id === 'term' && s.y === 500 && s.x > 300, `thrown right onto the terminal (${landed?.id} ${s.x})`)
s = { x: 1900, y: 900, vx: 2000, vy: 0 }; landed = null
for (let i = 0; i < 200 && !landed; i++) { const r = P.fall(s, 1 / 60, fl, 1920, 64, 110); s = r.s; landed = r.landed }
a(landed.id === 'ground' && s.x <= 1856, 'bounces off the wall, stays on screen')
s = { x: 900, y: 120, vx: 0, vy: -3000 }
a(P.fall(s, 1 / 60, fl, 1920, 64, 110).s.y >= 110, 'never above the top')
// Throw velocity from the last 90 ms only.
const v = P.throwVelocity([{ x: 0, y: 0, t: 0 }, { x: 10, y: 0, t: 920 }, { x: 40, y: -20, t: 950 }, { x: 70, y: -40, t: 980 }], 990)
a(Math.round(v.vx) === 1000 && Math.round(v.vy) === -667, `throw velocity ${v.vx},${v.vy}`)
// Petting the head vs carrying by the body, either way it faces.
a(P.onHead('cat', 100, 50, 128, 1) && !P.onHead('cat', 30, 100, 128, 1) && P.onHead('cat', 28, 50, 128, -1), 'head hit both ways')
a(P.bodyBox(100, -1).x === 0 && P.bodyBox(100, 1).x === 12, 'body box mirrors')
console.log('pet: ok')
