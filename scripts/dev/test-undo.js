// Check for services/undoLogic.js (the Undo toast's stack).
// Run: node scripts/dev/test-undo.js
const fs = require('fs'), path = require('path')
const src = fs.readFileSync(path.join(__dirname, '../../services/undoLogic.js'), 'utf8').replace('.pragma library', '')
const U = new Function(src + ';return {push, expire, take, same};')()
const a = (c, m) => { if (!c) throw new Error(m) }

let r = U.push([], { label: 'a' }, 0, 3, 6000)
r = U.push(r.stack, { label: 'b' }, 1000, 3, 6000)
r = U.push(r.stack, { label: 'c' }, 2000, 3, 6000)
a(r.stack.length === 3 && r.dropped.length === 0, 'three kept')
r = U.push(r.stack, { label: 'd' }, 3000, 3, 6000)
a(r.stack.map(e => e.label).join() === 'b,c,d' && r.dropped[0].label === 'a', 'the oldest drops out past max')
r = U.push(r.stack, { label: 'e' }, 7500, 3, 6000)
a(r.stack.map(e => e.label).join() === 'c,d,e' && r.dropped.map(e => e.label).join() === 'b', 'expired ones drop on push')

let t = U.take(r.stack, 7600, 6000)
a(t.entry.label === 'e' && t.stack.map(e => e.label).join() === 'c,d', 'take: newest first')
t = U.take(t.stack, 7600, 6000)
a(t.entry.label === 'd', 'then the one before')
t = U.take(t.stack, 8000, 6000)
a(t.entry === null && t.dropped[0].label === 'c', 'an expired entry is not undone, it is dropped')
a(U.take([], 0, 6000).entry === null, 'empty stack')

let x = U.expire([{ label: 'p', at: 0 }, { label: 'q', at: 5000 }], 6000, 6000)
a(x.stack.length === 1 && x.stack[0].label === 'q' && x.dropped[0].label === 'p', 'expire splits live and gone')

a(U.same({ a: 1, b: [1, { c: 2, d: 3 }] }, { b: [1, { d: 3, c: 2 }], a: 1 }), 'same ignores key order')
a(!U.same({ a: [1, 2] }, { a: [2, 1] }), 'same keeps array order')
a(!U.same({ a: 1 }, { a: 1, b: 2 }), 'same sees an extra key')

console.log('undo logic: ok')
