// Check for services/anoSpotLogic.js (pill transient ranks, the timer
// activity, finished downloads). Run: node scripts/dev/test-anospot-logic.js
const fs = require('fs'), path = require('path')
const src = fs.readFileSync(path.join(__dirname, '../../services/anoSpotLogic.js'), 'utf8').replace('.pragma library', '')
const L = new Function(src + ';return {replaces, clock, timer, newlyFinished};')()
const a = (c, m) => { if (!c) throw new Error(m) }

// Transient ranks
a(L.replaces('', 'notification'), 'anything shows on an idle pill')
a(L.replaces('volume', 'notification'), 'a notification replaces a level')
a(L.replaces('download', 'volume'), 'a level replaces a job-done transient')
a(!L.replaces('download', 'notification'), 'a notification does not hide a download')
a(!L.replaces('recording', 'notification'), "the recorder's own notification does not hide 'Recording saved'")
a(!L.replaces('screenshot', 'charging'), 'charging does not hide a screenshot')
a(L.replaces('notification', 'notification'), 'a newer notification replaces the last')
a(L.replaces('charging', 'screenshot'), 'a job-done transient replaces charging')
a(L.replaces('download', 'screenshot'), 'job-done transients replace each other')

// Clock
a(L.clock(0) === '0:00' && L.clock(65) === '1:05' && L.clock(3723) === '1:02:03', 'clock format')

// Timer activity
const idle = { enabled: true, running: false, phase: 'focus', remaining: 1500, cdRunning: false, cdLeft: 300000, swRunning: false, swElapsed: 0 }
a(L.timer(idle) === null, 'nothing runs: no activity')
a(L.timer(Object.assign({}, idle, { running: true, enabled: false })) === null, 'service off: no activity')
let t = L.timer(Object.assign({}, idle, { running: true, remaining: 61 }))
a(t.mode === 'focus' && t.text === '1:01' && t.icon === 'self_improvement', 'pomodoro focus')
a(L.timer(Object.assign({}, idle, { running: true, phase: 'break' })).icon === 'coffee', 'pomodoro break icon')
t = L.timer(Object.assign({}, idle, { running: true, swRunning: true, cdRunning: true, cdLeft: 1500 }))
a(t.mode === 'countdown' && t.text === '0:02', 'countdown wins, rounded up')
t = L.timer(Object.assign({}, idle, { swRunning: true, swElapsed: 125900 }))
a(t.mode === 'stopwatch' && t.text === '2:05', 'stopwatch')

// Finished downloads
const f = [{ path: '/d/b.zip' }, { path: '/d/a.iso' }]
a(L.newlyFinished(null, f).length === 0, 'the first list is not news')
a(L.newlyFinished(['/d/a.iso'], f).length === 1 && L.newlyFinished(['/d/a.iso'], f)[0].path === '/d/b.zip', 'one new')
a(L.newlyFinished(['/d/a.iso', '/d/b.zip'], f.slice(1)).length === 0, 'cleared ones are not news')

// ── Shelf ──
const S = new Function(src + ';return {fileUri, addShot, shelf};')()
a(S.fileUri('/tmp/a b/#1?.png') === 'file:///tmp/a%20b/%231%3F.png', 'file uri encodes')
let shots = []
for (let i = 1; i <= 10; i++) shots = S.addShot(shots, `/s/${i}.png`, i, 8)
a(shots.length === 8 && shots[0].path === '/s/10.png' && shots[7].path === '/s/3.png', 'shots: newest first, pruned to n')
shots = S.addShot(shots, '/s/5.png', 11, 8)
a(shots.length === 8 && shots[0].path === '/s/5.png' && shots.filter(s => s.path === '/s/5.png').length === 1, 'a shot again moves to the front, once')
a(S.addShot(shots, '/s/x.png', 12, 0).length === 0, 'n = 0 keeps none')

const pins = [
    { key: 'p1', kind: 'image', file: '/pins/p1.png', source: '/s/5.png' },
    { key: 'p2', kind: 'text', text: 'hello', from: '41' },
    { key: 'p3', kind: 'text', text: 'pinned elsewhere' },
]
const clip = (id, kind, text) => ({ line: `${id}\t${text}`, info: { id: id, kind: kind, text: text } })
const clips = [clip('42', 'text', 'new'), clip('41', 'text', 'hello'), clip('40', 'text', 'pinned elsewhere'), clip('39', 'image', '[[ binary ]]'), clip('38', 'text', 'old')]
const rows = S.shelf(pins, shots, clips, 3)
const keys = rows.map(r => r.key)
a(keys.slice(0, 3).join() === 'pin:p1,pin:p2,pin:p3', 'pins first, all of them')
a(!keys.includes('shot:/s/5.png'), 'a pinned screenshot is not listed twice')
a(rows.filter(r => r.src === 'shot').length === 3 && keys[3] === 'shot:/s/10.png', 'n newest screenshots')
a(!keys.includes('clip:41') && !keys.includes('clip:40'), 'pinned entries (by id or text) are not listed twice')
a(rows.filter(r => r.src === 'clip').map(r => r.key).join() === 'clip:42,clip:39,clip:38', 'n newest other entries, in order')
a(S.shelf(pins, shots, clips, 0).length === 3, 'n = 0: pins only')
a(S.shelf(null, null, null, 8).length === 0, 'empty')

console.log('anoSpotLogic: ok')
