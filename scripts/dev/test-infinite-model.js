// Check for services/infiniteModel.js. Run: node scripts/dev/test-infinite-model.js
const fs = require('fs'), path = require('path')
const src = fs.readFileSync(path.join(__dirname, '../../services/infiniteModel.js'), 'utf8').replace('.pragma library', '')
const M = new Function(src + ';return {intersects, pan, place, changed, follow, centred, arrange, bounds};')()
const a = (c, m) => { if (!c) throw new Error(m) }

const view = { x: 0, y: 0, width: 1920, height: 1080 }
const right = { x: 1920, y: 0, width: 1280, height: 1024 }
const wins = [{ id: 'a', x: 100, y: 100, width: 800, height: 600 }, { id: 'b', x: 1000, y: 200, width: 700, height: 500 }]

// Dragging the wallpaper 300 px left moves every window 300 px left.
const p = M.pan(wins, -300, 0)
a(p[0].x === -200 && p[1].x === 700 && p[1].y === 200 && wins[0].x === 100, 'pan moves all, leaves the input alone')

// One output: off-screen windows stay where the canvas puts them.
const far = M.pan(wins, 3000, 0)
a(M.place(far, view, []).every(q => !q.parked && q.x === far.find(w => w.id === q.id).x), 'single output: no parking')
// Two outputs: a window that left the view onto the other output is parked past both.
const pl = M.place(M.pan(wins, 1000, 0), view, [right])
a(pl.find(q => q.id === 'a').parked === false, 'a still overlaps the view')
a(pl.find(q => q.id === 'b').parked && pl.find(q => q.id === 'b').x === 3200 + 2000, 'b parked past every output')
// Still overlapping the view, but its centre is on the other output (sway would move it there).
const half = M.place([{ id: 'c', x: 1600, y: 100, width: 800, height: 600 }], view, [right])
a(half[0].parked, 'centre on the other output: parked')
a(!M.place([{ id: 'd', x: 1500, y: 100, width: 800, height: 600 }], view, [])[0].parked, 'no other output: not parked')

a(M.changed([{ id: 'a', x: 1, y: 2 }, { id: 'b', x: 3, y: 4 }], [{ id: 'a', x: 1, y: 2 }]).map(q => q.id).join() === 'b', 'only changed placements are sent')

// Follow: a window off to the right comes in with the margin; a huge one is centred.
let f = M.follow({ x: 2000, y: 100, width: 600, height: 400 }, view, 20)
a(f.dx === 1920 - 20 - 2600 && f.dy === 0, `follow right ${JSON.stringify(f)}`)
f = M.follow({ x: -50, y: -30, width: 300, height: 300 }, view, 20)
a(f.dx === 70 && f.dy === 50, 'follow up-left')
f = M.follow({ x: 0, y: 0, width: 3000, height: 200 }, view, 20)
a(f.dx === (1920 - 3000) / 2, 'too wide: centred')
a(JSON.stringify(M.follow(wins[0], view, 20)) === '{"dx":0,"dy":0}', 'visible: no pan')

a(JSON.stringify(M.centred(view, 800, 600)) === '{"x":560,"y":240}', 'new window centred')

// Arrange: no overlaps, all inside a block centred on the view.
const many = Array.from({ length: 7 }, (_, i) => ({ id: 'w' + i, x: 0, y: 0, width: 400 + 50 * i, height: 300 + 30 * (i % 3) }))
const ar = M.arrange(many, view, 24)
a(ar.length === 7, 'every window placed')
const rects = ar.map(q => Object.assign({}, many.find(w => w.id === q.id), q))
for (let i = 0; i < rects.length; i++) for (let j = i + 1; j < rects.length; j++) a(!M.intersects(rects[i], rects[j]), `overlap ${rects[i].id} ${rects[j].id}`)
const bb = M.bounds(rects, rects[0])
a(Math.abs((bb.x + bb.width / 2) - 960) <= 1 && Math.abs((bb.y + bb.height / 2) - 540) <= 1, 'block centred on the view')
a(M.arrange([], view).length === 0, 'nothing to arrange')
// Three tall windows fit side by side on a wide screen: one row, all on screen.
const tall = [0, 1, 2].map(i => ({ id: 't' + i, x: 0, y: 0, width: 418, height: 756 }))
const tr = M.arrange(tall, { x: 0, y: 0, width: 1266, height: 757 }, 24)
a(new Set(tr.map(q => q.y)).size === 1 && tr.every(q => q.y >= 0), `tall windows in one row ${JSON.stringify(tr)}`)

const b = M.bounds(wins, { x: -500, y: 0, width: 100, height: 100 })
a(b.x === -500 && b.width === 2200 && b.height === 700, 'bounds include the view')
console.log('infinite model: ok')
