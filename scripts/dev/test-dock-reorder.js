// Check for modules/dock/reorder.js (dock pinned-app reordering).
// Run: node scripts/dev/test-dock-reorder.js
const fs = require('fs'), path = require('path')
const src = fs.readFileSync(path.join(__dirname, '../../modules/dock/reorder.js'), 'utf8').replace('.pragma library', '')
const R = new Function(src + ';return {move, target, shift};')()
const a = (c, m) => { if (!c) throw new Error(m) }
const L = ['a', 'b', 'c', 'd']

a(R.move(L, 0, 2).join() === 'b,c,a,d', 'forward')
a(R.move(L, 3, 0).join() === 'd,a,b,c', 'backward')
a(R.move(L, 1, 1).join() === L.join(), 'same slot')
a(R.move(L, 1, 99).join() === 'a,c,d,b', 'clamped to the end')
a(R.move(L, 9, 0).join() === L.join() && L.join() === 'a,b,c,d', 'bad index; input untouched')

a(R.target(0, 10, 50, 4) === 0, 'under half a slot stays')
a(R.target(0, 30, 50, 4) === 1, 'past half a slot moves')
a(R.target(1, -500, 50, 4) === 0 && R.target(1, 500, 50, 4) === 3, 'clamped to the pinned range')
a(R.target(2, 40, 0, 4) === 2, 'no slot size')

// b (1) dragged over d (3): c and d slide back one slot, a stays.
a([0, 1, 2, 3].map(i => R.shift(i, 1, 3, 50)).join() === '0,0,-50,-50', 'drag forward')
a([0, 1, 2, 3].map(i => R.shift(i, 3, 1, 50)).join() === '0,50,50,0', 'drag backward')
a([0, 1, 2].map(i => R.shift(i, -1, -1, 50)).join() === '0,0,0', 'no drag')
// The slides agree with move(): every other entry ends where move() puts it.
for (const [f, t] of [[0, 3], [3, 0], [1, 2], [2, 2]]) {
    const m = R.move(L, f, t)
    L.forEach((x, i) => { if (i !== f) a(m[i + R.shift(i, f, t, 1)] === x, `shift matches move ${f}->${t} for ${x}`) })
}
console.log('dock reorder: ok')
