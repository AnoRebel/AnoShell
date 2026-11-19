// Check for modules/dock/dropargs.js. Run: node scripts/dev/test-dock-drop.js
const fs = require('fs'), path = require('path')
const src = fs.readFileSync(path.join(__dirname, '../../modules/dock/dropargs.js'), 'utf8').replace('.pragma library', '')
const D = new Function(src + ';return {tokens, fileCode, accepted, launches};')()
const a = (c, m) => { if (!c) throw new Error(m) }
const eq = (x, y, m) => a(JSON.stringify(x) === JSON.stringify(y), `${m}: ${JSON.stringify(x)}`)

const pics = ['file:///home/u/a.png', 'file:///home/u/b%20c.png']
// %F: one launch with every path, at the code's place (paths decoded)
eq(D.launches('imv %F', ['imv'], pics), [['imv', '/home/u/a.png', '/home/u/b c.png']], '%F')
// %f: one launch per file
eq(D.launches('gimp-2.10 %f', ['gimp-2.10'], pics), [['gimp-2.10', '/home/u/a.png'], ['gimp-2.10', '/home/u/b c.png']], '%f')
// %u: a link is passed as given; a file as its path
eq(D.launches('firefox %u', ['firefox'], ['https://example.org/x?y=1']), [['firefox', 'https://example.org/x?y=1']], '%u link')
// %f takes no remote URL
eq(D.launches('imv %F', ['imv'], ['https://example.org/p.png']), [], '%F refuses a remote URL')
// the code mid-line: items go there, not at the end
eq(D.launches('code --new-window %F --wait', ['code', '--new-window', '--wait'], pics.slice(0, 1)), [['code', '--new-window', '/home/u/a.png', '--wait']], 'slot mid-line')
// other codes before it are removed from command too
eq(D.launches('app --icon %i --name %c %U', ['app', '--icon', '--name'], pics.slice(0, 1)), [['app', '--icon', '--name', '/home/u/a.png']], 'other codes')
// no file code: no drop (a terminal would run a dropped script)
eq(D.launches('kitty', ['kitty'], ['file:///tmp/evil.sh']), [], 'no code, no drop')
// an unsafe name stays one argument
eq(D.launches('imv %F', ['imv'], ['file:///tmp/a%3B%20rm%20-rf%20~.png']), [['imv', '/tmp/a; rm -rf ~.png']], 'unsafe name is one arg')
// quoted "%U" is literal, not a code
eq(D.fileCode('sh -c "echo %U"'), '', 'quoted code is not a code')
eq(D.tokens(`a "b c" 'd e' %U`).map(t => t.text), ['a', 'b c', 'd e', '%U'], 'quotes')
console.log('dock drop: ok')
