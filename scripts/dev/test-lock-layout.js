// Check for modules/lock/lockLayout.js (lock layouts, the editor's snapping and undo).
// Run: node scripts/dev/test-lock-layout.js
const fs = require('fs'), path = require('path')
const src = fs.readFileSync(path.join(__dirname, '../../modules/lock/lockLayout.js'), 'utf8').replace('.pragma library', '')
const L = new Function(src + ';return {DEFAULTS, normalize, resolve, rectOf, migrate, snap, record, undo, redo, defaultsFor};')()
const a = (c, m) => { if (!c) throw new Error(m) }

// normalize: unknown types out, ranges clamped, uids unique, the field always there
let n = L.normalize([{ type: 'clock', x: 2, y: -1, scale: 9, rot: 450, opacity: 0 }, { type: 'bogus' }, { type: 'clock' },
                     { type: 'piece', settings: {} }], 'default')
a(n.length === 3, 'bogus and an id-less piece dropped, field added')
a(n[0].x === 1 && n[0].y === 0 && n[0].scale === 4 && n[0].rot === 90 && n[0].opacity === 0.2, 'clamped')
a(n[0].uid !== n[1].uid, 'unique uids')
a(n.some(e => e.type === 'field'), 'field always present')
a(L.normalize('x', 'default').length === L.DEFAULTS.default.length, 'garbage → the defaults')
const own = [{ type: 'clock', x: 0.5, y: 0.2, scale: 1.3 }, { type: 'field', x: 0.5, y: 0.7 }]
a(L.normalize('x', 'simple', own).length === 2, "garbage → the package's own")
a(L.normalize([{ type: 'clock' }], 'simple', own).find(e => e.type === 'field').y === 0.7, "a missing field comes back where the package puts it")

const listLike = { length: 1, 0: { type: 'field', x: 0.1, y: 0.1 } }
a(L.normalize(listLike, 'default')[0].x === 0.1, 'a list from a QML signal argument is taken as a list')

// resolve: saved or defaults, and defaults are copies
const r = L.resolve({}, 'default'); r[0].x = 0.1
a(L.DEFAULTS.default[0].x === 0.5, 'defaults not mutated')
a(L.resolve({}, 'simple', own)[0].scale === 1.3, "a package's own arrangement")
a(L.resolve({ simple: [{ type: 'field', x: 0.2, y: 0.2 }] }, 'simple', own).length === 1, 'saved layout used')

// rectOf: scaled by the screen height, turned sides swapped
const f = L.rectOf({ type: 'field', x: 0.5, y: 0.5, scale: 1, rot: 0 }, 1920, 1080)
a(Math.abs(f.w - 340) < 1e-6 && Math.abs(f.x - (960 - 170)) < 1e-6, 'field at 1080p')
const g = L.rectOf({ type: 'field', x: 0.5, y: 0.5, scale: 1, rot: 90 }, 3840, 2160)
a(Math.abs(g.w - 224) < 1e-6 && Math.abs(g.h - 680) < 1e-6, 'turned and doubled at 2160p')

const edge = L.rectOf({ type: 'clock', x: 0.02, y: 0.99, scale: 1, rot: 0 }, 1280, 1700)
a(edge.x === 0 && Math.abs(edge.y + edge.h - 1700) < 1e-6, 'kept whole on the screen')

// migrate: the old blocks, the user block split
a(L.migrate({}) === null && L.migrate(null) === null, 'nothing to migrate')
const m = L.migrate({ clock: { x: 0.2, y: 0.15, scale: 1.8 }, user: { x: 0.8, y: 0.5, scale: 1 }, status: { x: 0.5, y: 0.9, scale: 1 } })
const by = t => m.find(e => e.type === t)
a(by('clock').x === 0.2 && by('clock').scale === 1.8, 'clock moved')
a(by('avatar').x === 0.8 && by('avatar').y < 0.5 && by('name').y > 0.5, 'user → avatar over name')
a(by('battery') && by('battery').y === 0.9, 'status → battery')
a(by('field').x === 0.5, 'field kept where the defaults put it')

// snap: centre line, another box's edge, the grid
let s = L.snap({ x: 955, y: 300, w: 10, h: 10 }, [], 1920, 1080, 8, 0)
a(s.x === 955 && s.guides.length === 1, 'already on the centre line: kept, guide shown')
s = L.snap({ x: 948, y: 300, w: 10, h: 10 }, [], 1920, 1080, 8, 0)
a(s.x === 950 && s.guides[0].axis === 'x' && s.guides[0].at === 960, 'snapped centre to the screen centre')
s = L.snap({ x: 100, y: 203, w: 50, h: 50 }, [{ x: 400, y: 200, w: 80, h: 80 }], 1920, 1080, 8, 0)
a(s.y === 200, 'top to another top')
s = L.snap({ x: 37, y: 296, w: 50, h: 50 }, [], 1920, 1080, 4, 24)
a(s.x === 48 && s.y === 288, 'grid when nothing is near')

// undo/redo
let h = { past: [], future: [] }
h = L.record(h, 'A'); h = L.record(h, 'B')
let u = L.undo(h, 'C'); a(u.layout === 'B', 'undo gives the last'); h = u.h
u = L.undo(h, 'B'); a(u.layout === 'A', 'twice'); h = u.h
a(L.undo(h, 'A') === null, 'nothing more')
let d = L.redo(h, 'A'); a(d.layout === 'B', 'redo'); h = d.h
h = L.record(h, 'B'); a(h.future.length === 0, 'a new change drops the redo')
let big = { past: [], future: [] }; for (let i = 0; i < 60; i++) big = L.record(big, i, 50)
a(big.past.length === 50 && big.past[0] === 10, 'capped')

console.log('lock layout: ok')
