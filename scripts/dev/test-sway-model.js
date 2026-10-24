// Check for services/compositor/SwayModel.js against the sway-ipc(7) 1.12
// examples in fixtures/sway (MIT, swaywm/sway; syntax slips repaired: trailing
// commas, one `","` for `:`). Run: node scripts/dev/test-sway-model.js
const fs = require('fs'), path = require('path')
const src = fs.readFileSync(path.join(__dirname, '../../services/compositor/SwayModel.js'), 'utf8').replace('.pragma library', '')
const M = new Function(src + ';return {occupied, fullscreen, windows, layouts, layoutsFromEvent};')()
const fx = n => JSON.parse(fs.readFileSync(path.join(__dirname, 'fixtures/sway', n + '.json'), 'utf8'))
const a = (c, m) => { if (!c) throw new Error(m) }

const tree = fx('get_tree')
a(JSON.stringify(M.occupied(tree)) === '{"1":true}', 'workspace 1 holds the two windows; the scratchpad is left out')
a(Object.keys(M.fullscreen(tree)).length === 0, 'nothing fullscreen in the example')
const w = M.windows(tree)
a(w.length === 2 && w.every(x => x.output === 'eDP-1' && x.workspace === 1), 'two windows on eDP-1, workspace 1')
const term = w.find(x => x.appId === 'termite'), urxvt = w.find(x => x.id === 5)
a(term && term.focused && !term.floating, 'termite: focused, tiled, app_id')
a(urxvt && urxvt.appId === 'URxvt', 'XWayland window: appId from window_properties.class')

// Fullscreen: mark termite fullscreen (mode 1) on the shown workspace.
const t2 = JSON.parse(JSON.stringify(tree))
t2.nodes[1].nodes[0].nodes[1].fullscreen_mode = 1
a(JSON.stringify(M.fullscreen(t2)) === '{"eDP-1":true}', 'fullscreen window → its output')
t2.nodes[1].current_workspace = '2'
a(Object.keys(M.fullscreen(t2)).length === 0, 'not when its workspace is not the one shown')

const lay = M.layouts(fx('get_inputs'))
a(lay.current === 'English (US)' && lay.names.length === 0, 'GET_INPUTS example: active layout, no list')
const ev = M.layoutsFromEvent(fx('event_input'))
a(ev && ev.current === 'English (Dvorak)' && ev.names.join('|') === 'English (US)|English (Dvorak)', 'INPUT xkb_layout event')
a(M.layoutsFromEvent({ change: 'libinput_config', input: { type: 'pointer' } }) === null, 'non-keyboard event ignored')

// Workspace and window events carry what the backend refreshes on.
a(fx('event_workspace').change === 'init' && fx('event_window').change === 'new', 'event fixtures as documented')
const ws = fx('get_workspaces')
a(ws[0].num === 1 && ws[0].output === 'eDP-1' && ws[0].focused, 'GET_WORKSPACES example')
console.log('sway model ok')
