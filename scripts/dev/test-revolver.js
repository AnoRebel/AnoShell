// Check for modules/revolver/revolver.js (the corner revolver's geometry). Run: node scripts/dev/test-revolver.js
const fs = require('fs'), path = require('path')
const src = fs.readFileSync(path.join(__dirname, '../../modules/revolver/revolver.js'), 'utf8').replace('.pragma library', '')
const R = new Function(src + ';return {mod, setCount, quarterSet, slots, angle, point, shown, opposite};')()
const a = (c, m) => { if (!c) throw new Error(m) }
const ids = ['lock', 'wallpaperPicker', 'shuffleWallpaper', 'nightLight', 'settings', 'restartShell']

const visible = (turns) => { const s = R.slots(ids, turns), q = R.mod(turns, 4); return s.slice(q * 3, q * 3 + 3) }
a(visible(0).join() === 'lock,wallpaperPicker,shuffleWallpaper', 'default chambers')
a(visible(1).join() === 'nightLight,settings,restartShell', 'one turn down')
a(visible(2).join() === visible(0).join() && visible(-1).join() === visible(1).join(), 'wraps both ways')
// The next set already waits in the quarter that turns in, so nothing changes under the eye mid-turn.
const s0 = R.slots(ids, 0)
a(s0.slice(3, 6).join() === visible(1).join() && s0.slice(9, 12).join() === visible(-1).join(), 'neighbours prepared')
const twelve = Array.from({ length: 12 }, (_, i) => `a${i}`)
a([0, 1, 2, 3, 4].map(t => R.slots(twelve, t)[R.mod(t, 4) * 3]).join() === 'a0,a3,a6,a9,a0', 'twelve: four sets in turn')
a(R.slots(['x'], 3).filter(v => v === 'x').length >= 1 && R.setCount(0) === 1, 'one action, none')
a(R.slots(['p', 'q', 'r', 's'], 1).slice(3, 6).join() === 's,,', 'a partial set leaves empty chambers')

// Angles: after one turn (disc -90) slot 3 sits where slot 0 sat.
a(R.angle(3, -90) === R.angle(0, 0) && R.angle(0, 0) === 15 && R.angle(2, 0) === 75, 'angles')
a(R.shown(15) && R.shown(75) && !R.shown(105) && !R.shown(-75) && R.shown(-0.5), 'visible quarter')

const p = R.point('bottomLeft', 0, 100, 300, 300), q = R.point('topRight', 90, 100, 300, 300)
a(Math.abs(p.x - 100) < 1e-9 && Math.abs(p.y - 300) < 1e-9, 'bottom-left along the bottom edge')
a(Math.abs(q.x - 300) < 1e-9 && Math.abs(q.y - 100) < 1e-9, 'top-right along the side')
a(R.opposite('bottomLeft') === 'topRight' && R.opposite('topRight') === 'bottomLeft', 'opposite')
console.log('revolver ok')
