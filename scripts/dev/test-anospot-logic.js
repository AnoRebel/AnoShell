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

console.log('anoSpotLogic: ok')
