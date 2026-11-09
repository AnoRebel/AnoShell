// Check for services/piecesArrange.js (moving and resizing desktop pieces).
// Run: node scripts/dev/test-pieces-arrange.js
const fs = require('fs'), path = require('path')
const src = fs.readFileSync(path.join(__dirname, '../../services/piecesArrange.js'), 'utf8').replace('.pragma library', '')
const P = new Function(src + ';return {overlap, inside, nearestFree, drop, push, resize};')()
const a = (c, m) => { if (!c) throw new Error(m) }
const at = (page, uid) => { const o = page.find(p => p.uid === uid); return `${o.x},${o.y} ${o.w}x${o.h}` }
const valid = (page, cols, rows) => page.every((o, i) => P.inside(o, cols, rows) && page.every((q, j) => i === j || !P.overlap(o, q)))
const pc = (uid, x, y, w = 1, h = 1) => ({ uid, x, y, w, h })

// nearest free spot, ties to the upper then left one
a(JSON.stringify(P.nearestFree([pc('a', 1, 1)], 1, 1, 3, 3, 1, 1)) === '{"x":1,"y":0}', 'nearest: tie goes up')
a(JSON.stringify(P.nearestFree([pc('a', 0, 0, 2, 1)], 1, 1, 3, 1, 0, 0)) === '{"x":2,"y":0}', 'nearest: the only free cell')
a(P.nearestFree([pc('a', 0, 0, 2, 2)], 1, 1, 2, 2, 0, 0) === null, 'nearest: full grid')
a(P.nearestFree([], 3, 1, 2, 2, 0, 0) === null, 'nearest: bigger than the grid')

// drop on a taken cell lands on the nearest free one that fits
let page = [pc('a', 0, 0), pc('b', 2, 0, 2, 2)]
let r = P.drop(page, 'a', { x: 3, y: 1, w: 1, h: 1 }, 5, 3)
a(at(r, 'a') === '4,1 1x1', 'drop: next to the taken cell')
a(at(page, 'a') === '0,0 1x1', 'drop: input untouched')
r = P.drop(page, 'a', { x: 2, y: 0, w: 2, h: 1 }, 4, 3)
a(at(r, 'a') === '0,0 2x1' && valid(r, 4, 3), 'drop: a 2-wide piece finds a 2-wide hole (tie: the upper one)')
a(at(P.drop([pc('a', 0, 0), pc('b', 1, 0)], 'a', { x: 1, y: 0, w: 1, h: 1 }, 2, 1), 'a') === '0,0 1x1', 'drop: back where it was when that is nearest')

// push: a chain along the direction
page = [pc('a', 0, 0), pc('b', 1, 0), pc('c', 2, 0)]
r = P.push(page, 'a', { x: 0, y: 0, w: 2, h: 1 }, 4, 1, { dx: 1, dy: 0 })
a(at(r, 'b') === '2,0 1x1' && at(r, 'c') === '3,0 1x1' && valid(r, 4, 1), 'push: chain right')
// the last of the chain hits the edge: it goes to the nearest free spot instead
r = P.push(page, 'a', { x: 0, y: 0, w: 2, h: 1 }, 3, 2, { dx: 1, dy: 0 })
a(r && valid(r, 3, 2) && at(r, 'a') === '0,0 2x1' && at(r, 'b') === '2,0 1x1' && at(r, 'c') === '2,1 1x1', 'push: edge → nearest free')
// nowhere to go
a(P.push(page, 'a', { x: 0, y: 0, w: 2, h: 1 }, 3, 1, { dx: 1, dy: 0 }) === null, 'push: no room → null')
a(P.push(page, 'a', { x: 0, y: 0, w: 5, h: 1 }, 4, 1, { dx: 1, dy: 0 }) === null, 'push: out of bounds → null')
// downward, and both ways (the shorter shove wins)
page = [pc('a', 0, 0), pc('b', 0, 1), pc('d', 1, 0)]
r = P.push(page, 'a', { x: 0, y: 0, w: 1, h: 2 }, 3, 3, { dx: 0, dy: 1 })
a(at(r, 'b') === '0,2 1x1' && at(r, 'd') === '1,0 1x1', 'push: down')
r = P.push(page, 'a', { x: 0, y: 0, w: 2, h: 2 }, 3, 3, { dx: 1, dy: 1 })
a(valid(r, 3, 3) && at(r, 'd') === '2,0 1x1' && at(r, 'b') === '0,2 1x1', 'push: both ways')
// a move one cell with the keyboard pushes the neighbour along
r = P.push([pc('a', 0, 0), pc('b', 1, 0)], 'a', { x: 1, y: 0, w: 1, h: 1 }, 3, 1, { dx: 1, dy: 0 })
a(at(r, 'a') === '1,0 1x1' && at(r, 'b') === '2,0 1x1', 'push: keyboard move')
r = P.push([pc('a', 1, 0), pc('b', 0, 0)], 'a', { x: 0, y: 0, w: 1, h: 1 }, 2, 1, { dx: -1, dy: 0 })
a(at(r, 'a') === '0,0 1x1' && at(r, 'b') === '1,0 1x1', 'push: left into the edge → swaps via nearest free')

// resize stops at the last size that fits
page = [pc('a', 0, 0), pc('b', 2, 0)]
r = P.resize(page, 'a', 4, 1, 4, 1)
a(at(r, 'a') === '0,0 3x1' && at(r, 'b') === '3,0 1x1', 'resize: clamps to 3 wide')
r = P.resize(page, 'a', 2, 3, 3, 2)
a(at(r, 'a') === '0,0 2x2' && valid(r, 3, 2), 'resize: clamps height to the grid, keeps the width')
r = P.resize([pc('a', 0, 0, 3, 3)], 'a', 1, 1, 4, 4)
a(at(r, 'a') === '0,0 1x1', 'resize: shrink')

// fuzz: always valid, input untouched, deterministic
let seed = 7
const rnd = n => { seed = (seed * 1103515245 + 12345) % 2147483648; return seed % n }
for (let t = 0; t < 3000; t++) {
    const cols = 2 + rnd(6), rows = 2 + rnd(5)
    let pg = []
    for (let i = 0; i < 1 + rnd(8); i++) {
        const w = 1 + rnd(2), h = 1 + rnd(2), s = P.nearestFree(pg, w, h, cols, rows, rnd(cols), rnd(rows))
        if (s) pg.push(pc('p' + i, s.x, s.y, w, h))
    }
    const before = JSON.stringify(pg), o = pg[rnd(pg.length)]
    const tx = rnd(cols), ty = rnd(rows), mx = rnd(3) - 1, my = rnd(3) - 1, ddx = rnd(3) - 1, ddy = rnd(3) - 1, nw = 1 + rnd(cols), nh = 1 + rnd(rows)
    const ops = [
        () => P.drop(pg, o.uid, { x: tx, y: ty, w: o.w, h: o.h }, cols, rows),
        () => P.push(pg, o.uid, { x: o.x + mx, y: o.y + my, w: o.w, h: o.h }, cols, rows, { dx: ddx, dy: ddy }),
        () => P.resize(pg, o.uid, nw, nh, cols, rows)
    ]
    const op = ops[rnd(3)], out = op()
    a(JSON.stringify(pg) === before, 'fuzz: input untouched')
    if (out) {
        a(valid(out, cols, rows), `fuzz: overlap or out of bounds ${before} → ${JSON.stringify(out)}`)
        a(out.length === pg.length && out.every(q => pg.some(p => p.uid === q.uid && p.w === q.w && p.h === q.h) || q.uid === o.uid), 'fuzz: only the mover changes size')
        a(JSON.stringify(op()) === JSON.stringify(out), 'fuzz: deterministic')
    }
    if (op === ops[2]) a(out, 'fuzz: resize always lands (the current size fits)')
}
console.log('pieces-arrange: ok')
