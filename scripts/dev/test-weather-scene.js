// Check for modules/weather/scene.js (the weather scene's logic). Run: node scripts/dev/test-weather-scene.js
const fs = require('fs'), path = require('path')
const src = fs.readFileSync(path.join(__dirname, '../../modules/weather/scene.js'), 'utf8').replace('.pragma library', '')
const W = new Function(src + ';return {condition, look, minutesOf, sun, sky, moonPhase, step};')()
const a = (c, m) => { if (!c) throw new Error(m) }

a(W.condition(113) === 'clear' && W.condition('116') === 'cloudy' && W.condition(122) === 'overcast', 'clear/cloudy/overcast')
a(W.condition(248) === 'mist' && W.condition(389) === 'storm' && W.condition(338) === 'snow' && W.condition(302) === 'rain' && W.condition(311) === 'rain', 'mist/storm/snow/rain')
a(W.minutesOf('06:45 AM') === 405 && W.minutesOf('12:05 PM') === 725 && W.minutesOf('12:30 am') === 30 && W.minutesOf('18:05') === 1085 && isNaN(W.minutesOf('')), 'minutesOf')

// Winter afternoon: sunset 16:05, now 16:30 → sun down, dusk colours.
const s = W.sun(16 * 60 + 30, 8 * 60, 16 * 60 + 5)
a(!s.up && s.dawn > 0.3, 'after sunset: down, dusk')
const noon = W.sun(720, 360, 1080)
a(noon.up && Math.abs(noon.t - 0.5) < 1e-9 && noon.dawn === 0, 'noon: up, middle of the arc, no dusk')
a(W.sun(720, NaN, NaN).up && !W.sun(1200, NaN, NaN).up, 'unknown times: 06:00-18:00')
const mid = W.sun(0, 360, 1080)
a(!mid.up && Math.abs(mid.t - 0.5) < 1e-9, 'midnight: the moon mid-arc')
a(W.sky(noon)[0] === '#4a90d9' && W.sky(s)[0] !== W.sky(W.sun(0, 360, 1080))[0], 'sky colours')

a(Math.abs(W.moonPhase(new Date(Date.UTC(2000, 0, 6, 18, 14)))) < 1e-6, 'new moon reference')
const full = W.moonPhase(new Date(Date.UTC(2026, 10, 24, 15, 0))) // full moon 24 Nov 2026 (approx.)
a(Math.abs(full - 0.5) < 0.04, `full moon (${full.toFixed(3)})`)

// Cloudy → rain: clouds darken and thicken first, then rain begins; done in about 2.5 s.
let cur = W.look('cloudy'), target = W.look('rain'), t = 0, rainStart = -1, cloudsDone = -1
while (t < 4) {
    cur = W.step(cur, target, 1 / 60); t += 1 / 60
    if (rainStart < 0 && cur.rain > 0) rainStart = t
    if (cloudsDone < 0 && cur.clouds >= target.clouds - 0.05 && cur.dark >= target.dark - 0.05) cloudsDone = t
}
a(rainStart > 0 && cloudsDone > 0 && rainStart >= cloudsDone - 1e-9, 'rain waits for the clouds')
a(JSON.stringify(cur) === JSON.stringify(target), 'reached rain')
// Rain → clear: rain stops before the clouds clear.
target = W.look('clear'); t = 0; let rainEnd = -1, clearStart = -1
const before = cur.clouds
while (t < 4) {
    cur = W.step(cur, target, 1 / 60); t += 1 / 60
    if (rainEnd < 0 && cur.rain === 0) rainEnd = t
    if (clearStart < 0 && cur.clouds < before) clearStart = t
}
a(rainEnd > 0 && clearStart >= rainEnd - 1e-9, 'clouds clear after the rain stops')
a(JSON.stringify(cur) === JSON.stringify(target) && t < 4.1, 'reached clear')
console.log('weather scene ok')
