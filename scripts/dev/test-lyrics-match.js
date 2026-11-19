// Check for the LRCLIB matching in services/lrcparser.js. Run: node scripts/dev/test-lyrics-match.js
const fs = require('fs'), path = require('path')
const src = fs.readFileSync(path.join(__dirname, '../../services/lrcparser.js'), 'utf8').replace('.pragma library', '')
const L = new Function(src + ';return {lrclibPick, overlaps};')()
const a = (c, m) => { if (!c) throw new Error(m) }
const r = (id, trackName, artistName, duration) => ({ id, trackName, artistName, duration, syncedLyrics: '[00:01.00] x' })
const list = [r(1, 'Song (Live)', 'Band', 301), r(2, 'Song', 'Band', 241), r(3, 'Song', 'Band', 243), r(4, 'Other', 'Band', 240)]
a(L.lrclibPick(list, 'Song', 'Band', 240).id === 2, 'closest length wins')
a(L.lrclibPick(list, 'Song', 'Band', 280) === null, 'every cut more than 3 s off: none')
a(L.lrclibPick(list, 'Song', 'Band', 0).id === 1, 'length unknown: first match')
a(L.lrclibPick([r(5, 'Song', 'Band', 0)], 'Song', 'Band', 200).id === 5, 'result without a length still counts')
a(L.lrclibPick([{ ...r(6, 'Song', 'Band', 200), syncedLyrics: null }], 'Song', 'Band', 200) === null, 'unsynced is skipped')
a(L.overlaps('Song (Remastered 2011)', 'song') && !L.overlaps('Band', 'Other'), 'title/artist matching')
console.log('lyrics match: ok')
