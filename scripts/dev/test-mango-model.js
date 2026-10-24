// Check for services/compositor/MangoModel.js against fixtures/mango (lines
// shaped as mango 0.18.3's IPC sends them). Run: node scripts/dev/test-mango-model.js
const fs = require('fs'), path = require('path')
const src = fs.readFileSync(path.join(__dirname, '../../services/compositor/MangoModel.js'), 'utf8').replace('.pragma library', '')
const M = new Function(src + ';return {parse, workspaces, focusedOutput, keyboardLayout, fullscreen, covered, windows, dispatchLine};')()
const line = n => fs.readFileSync(path.join(__dirname, 'fixtures/mango', n + '.jsonl'), 'utf8').split('\n')[0]
const a = (c, m) => { if (!c) throw new Error(m) }

const mons = M.parse(line('all-monitors')).monitors
const ws = M.workspaces(mons)
a(ws.length === 18, 'nine tags on each of two monitors')
const e1 = ws.find(w => w.id === 'eDP-1:1'), h2 = ws.find(w => w.id === 'HDMI-A-1:2'), h5 = ws.find(w => w.id === 'HDMI-A-1:5')
a(e1.focused && e1.active && e1.occupied, 'eDP-1 tag 1: shown on the selected monitor, holds windows')
a(h2.active && !h2.focused && h2.occupied, 'HDMI-A-1 tag 2: shown, not focused (monitor not selected)')
a(h5.active && h5.urgent && !h5.occupied, 'two tags shown at once on HDMI-A-1; tag 5 urgent and empty')
a(ws.find(w => w.id === 'eDP-1:3').occupied && !ws.find(w => w.id === 'eDP-1:3').active, 'hidden tag with a window counts as occupied')
a(M.focusedOutput(mons) === 'eDP-1' && M.keyboardLayout(mons) === 'us', 'selected monitor and layout')

const cl = M.parse(line('all-clients')).clients
a(JSON.stringify(M.fullscreen(cl)) === '{"HDMI-A-1":true}', 'visible fullscreen client → its monitor')
a(JSON.stringify(M.covered(cl)) === '{"HDMI-A-1":true}', 'a hidden maximised client covers nothing')
const w = M.windows(cl)
a(w.length === 4 && w.find(x => x.id === 4).focused && w.find(x => x.id === 9).fullscreen && w.find(x => x.id === 11).workspace === 3, 'windows')

a(M.dispatchLine('view', [3]) === 'dispatch view,3\n', 'view a tag')
a(M.dispatchLine('viewcrossmon', [2, 'HDMI-A-1']) === 'dispatch viewcrossmon,2,HDMI-A-1\n', 'view a tag on a monitor')
a(M.dispatchLine('focusid', [], 7) === 'dispatch focusid client,7\n', 'focus by client id')
a(M.dispatchLine('view', ['1\ndispatch quit']) === null && M.dispatchLine('view', ['1,2']) === null, 'separators refused')
a(M.dispatchLine('killclient', [], -1) === null, 'bad client id refused')
a(M.parse('{"monitors":[') === null, 'partial line → null')
console.log('mango model ok')
