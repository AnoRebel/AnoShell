// Check for services/compositor/UmbrielModel.js against fixtures/umbriel
// (`umbriel subscribe` lines recorded from umbriel 0.1.0, nested: output WL-1
// plus a virtual HEADLESS-9). Run: node scripts/dev/test-umbriel-model.js
const fs = require('fs'), path = require('path')
const src = fs.readFileSync(path.join(__dirname, '../../services/compositor/UmbrielModel.js'), 'utf8').replace('.pragma library', '')
const M = new Function(src + ';return {parse, workspaces, focusedOutput, fullscreen, covered, windows, layouts, msg, validId};')()
const lines = fs.readFileSync(path.join(__dirname, 'fixtures/umbriel/subscribe.jsonl'), 'utf8').split('\n').filter(Boolean)
const ev = name => lines.map(M.parse).find(o => o && o.event === name).data
const a = (c, m) => { if (!c) throw new Error(m) }

const wsRaw = ev('workspaces')
const ws = M.workspaces(wsRaw)
a(ws.length === 5, 'three workspaces on WL-1, two on HEADLESS-9')
const w12 = ws.find(w => w.id === 'WL-1:2'), h1 = ws.find(w => w.id === 'HEADLESS-9:1'), w13 = ws.find(w => w.id === 'WL-1:3')
a(w12.number === 2 && w12.active && !w12.focused && w12.occupied, 'WL-1:2 shown, not focused (other output focused)')
a(h1.number === 1 && h1.focused && h1.active && h1.output === 'HEADLESS-9', 'HEADLESS-9:1 focused')
a(!w13.occupied && !w13.active, 'empty workspace')
a(M.focusedOutput(wsRaw) === 'HEADLESS-9', 'focused output from the focused workspace')

const winRaw = ev('windows')
a(JSON.stringify(M.fullscreen(winRaw)) === '{"WL-1":true}', 'shown fullscreen window → its output')
a(JSON.stringify(M.covered(winRaw)) === '{"WL-1":true}', 'covered')
const hiddenMax = winRaw.map(w => Object.assign({}, w, { maximized_to_edges: true, fullscreen: false }))
a(JSON.stringify(M.covered(hiddenMax)) === '{"HEADLESS-9":true,"WL-1":true}', 'only shown windows cover')
const win = M.windows(winRaw, wsRaw)
a(win.length === 3, 'three windows')
const third = win.find(w => w.id === '8c55e19565c76651868602e1a0041f7e')
a(third.focused && third.workspace === 1 && third.output === 'HEADLESS-9' && third.width === 700, 'focused = active, not per-workspace focused')
a(win.filter(w => w.focused).length === 1, 'one focused window')
a(win.find(w => w.fullscreen).workspace === 2, 'workspace number from the workspace id')
a(M.windows([{ id: 'ab', scratchpad: 'music', visible: false }], []).length === 0, 'hidden scratchpad window left out')

const l = M.layouts(ev('keyboard_layout'))
a(l.current === 'German' && l.names.length === 2, 'layouts')
a(M.layouts(null).current === '' && M.layouts({}).names.length === 0, 'no layouts')

a(JSON.stringify(M.msg('workspace-switch', [3], { output: 'HEADLESS-9' })) === '["umbriel","msg","workspace-switch","3","--output","HEADLESS-9"]', 'switch on an output')
a(JSON.stringify(M.msg('session-quit', ['skip-confirmation'])) === '["umbriel","msg","session-quit","skip-confirmation"]', 'quit')
a(M.msg('workspace-switch', ['--output']) === null && M.msg('window-close', ['']) === null, 'flag-like or empty value refused')
a(M.msg('workspace-switch', [1], { output: '' }) === null, 'empty option refused')
a(M.validId('8c55e19565c76651868602e1a0041f7e') && !M.validId('--all') && !M.validId(3), 'window ids')
a(M.parse('{"data":[') === null && M.parse('{"x":1}') === null, 'partial or eventless line → null')
console.log('umbriel model ok')
