// Check for the world clock and palette pieces' helpers. Run: node scripts/dev/test-pieces-logic.js
const fs = require('fs'), path = require('path');
const load = (f, names) => new Function(fs.readFileSync(path.join(__dirname, '../../pieces', f), 'utf8').replace('.pragma library', '') + `;return {${names}};`)();
const a = (c, m) => { if (!c) throw new Error(m); };

const Z = load('world-clock/zones.js', 'parse,cityOf,dayOffset,hourIn,phase,diffText');
const z = Z.parse('America/New_York=NYC, Asia/Tokyo;Europe/Paris = Paris ;bad zone,Asia/Tokyo=again,\nEtc/GMT+3,;rm -rf /');
a(z.map(x => x.zone).join() === 'America/New_York,Asia/Tokyo,Europe/Paris,Etc/GMT+3', 'parse: valid, deduped, in order');
a(z[0].label === 'NYC' && z[1].label === 'Tokyo' && z[2].label === 'Paris', 'parse: labels, city fallback');
a(Z.parse('').length === 0 && Z.parse(null).length === 0, 'parse: empty');
a(Z.cityOf('America/Port_of_Spain') === 'Port of Spain', 'city');
const t = Date.UTC(2026, 10, 10, 22, 30); // 22:30 UTC
a(Z.dayOffset(t, 540, 60) === 1, 'Tokyo (+9) is tomorrow from Paris (+1) at 22:30 UTC');
a(Z.dayOffset(t, -300, 60) === 0, 'New York (−5) same day as Paris');
a(Z.dayOffset(Date.UTC(2026, 10, 10, 2), -300, 60) === -1, 'New York still yesterday at 02:00 UTC');
a(Z.dayOffset(t, 0, 0) === 0, 'same zone');
a(Math.abs(Z.hourIn(t, 330) - 4) < 1e-9, 'Kolkata hour wraps past midnight');
a(Math.abs(Z.hourIn(Date.UTC(2026, 0, 1, 1), -300) - 20) < 1e-9, 'negative offset wraps back');
a(Z.phase(12) === 'day' && Z.phase(6) === 'twilight' && Z.phase(20.5) === 'twilight' && Z.phase(23) === 'night' && Z.phase(0) === 'night', 'phase');
a(Z.diffText(60, 60) === 'Same time' && Z.diffText(540, 60) === '+8 h' && Z.diffText(-300, 330) === '−10:30 h', 'diff text');

const P = load('palette/swatches.js', 'layout,label,hex,onDark');
const big = P.layout(4, 5);
a(big.length === 5 && big.every(r => r.length === 4) && big[0][0] === 'm3primary' && big[4][0] === 'm3error', 'roomy: five families of four');
a(P.layout(6, 3).length === 3 && P.layout(6, 3)[0].length === 4, 'roomy: never more than a family');
const tight = P.layout(5, 1);
a(tight.length === 1 && tight[0].join() === 'm3primary,m3secondary,m3tertiary,m3surface,m3error', 'tight: key colours first');
a(P.layout(3, 2).map(r => r.length).join() === '3,3', 'tight: wraps into rows');
a(P.layout(0, 0).length === 1 && P.layout(0, 0)[0][0] === 'm3primary', 'at least one');
a(P.layout(100, 2).flat().length === 12, 'no more than there are keys');
a(P.label('m3onPrimaryContainer') === 'On primary container' && P.label('m3primary') === 'Primary', 'label');
a(P.hex(1, 0.5, 0) === '#ff8000' && P.hex(-1, 2, 0.2) === '#00ff33', 'hex, clamped');
a(P.onDark(0.1, 0.1, 0.2) && !P.onDark(0.95, 0.9, 0.8), 'text colour by luminance');
console.log('pieces logic ok');
