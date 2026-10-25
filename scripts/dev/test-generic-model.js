// Check for services/compositor/GenericModel.js (the generic backend's
// mapping; sway and labwc build on it). Run: node scripts/dev/test-generic-model.js
const fs = require('fs'), path = require('path')
const src = fs.readFileSync(path.join(__dirname, '../../services/compositor/GenericModel.js'), 'utf8').replace('.pragma library', '')
const M = new Function(src + ';return {sets, workspaces, outputsWhere};')()
const a = (c, m) => { if (!c) throw new Error(m) }

// Numeric names win, then the first coordinate, then the smallest free number;
// hidden windowsets (shouldDisplay false) are left out.
const e = M.sets([
    { name: 'eDP-1', windowsets: [{ name: '2', active: true }, { name: 'web', coordinates: [7] }, { name: 'mail' }, { name: 'x', shouldDisplay: false }] },
    { name: 'HDMI-A-1', windowsets: [{ name: 'chat', urgent: true }] },
])
a(e.map(x => x.number).join(',') === '1,1,2,7' && e.length === 4, 'numbers: name, coordinate, then the smallest free; hidden left out')
a(e.find(x => x.set.name === 'mail').number === 1 && e.find(x => x.set.name === 'chat').number === 1, 'free numbers are per screen')

const ws = M.workspaces(e, 'eDP-1', x => x.set.name === 'web')
const two = ws.find(w => w.name === '2'), chat = ws.find(w => w.name === 'chat')
a(two.focused && two.active && two.id === 'eDP-1:2', 'shown on the focused output')
a(chat.urgent && !chat.focused && chat.output === 'HDMI-A-1', 'urgent, other output')
a(ws.find(w => w.name === 'web').occupied && !two.occupied, 'occupied from the backend')

const tl = [{ fullscreen: true, screens: [{ name: 'eDP-1' }] }, { maximized: true, screens: [{ name: 'HDMI-A-1' }] }, null]
a(JSON.stringify(M.outputsWhere(tl, t => t.fullscreen)) === '{"eDP-1":true}', 'fullscreen outputs')
a(JSON.stringify(M.outputsWhere(tl, t => t.fullscreen || t.maximized)) === '{"eDP-1":true,"HDMI-A-1":true}', 'covered outputs')
// A named workspace never takes a number a numbered one has (sway: "1",
// "chat", "2" → chat would have been 2 and clicks on "2" went to it).
const c = M.sets([{ name: 'eDP-1', windowsets: [{ name: '1' }, { name: 'chat' }, { name: '2' }] }])
a(c.map(x => `${x.set.name}=${x.number}`).join(',') === '1=1,2=2,chat=3', 'positional numbers skip taken ones')
console.log('generic model ok')
