// Check for performance mode's Hyprland levers. Run: node scripts/dev/test-hyprperf.js
const fs=require('fs'); const src=fs.readFileSync(require('path').join(__dirname,'../../services/hyprperf.js'),'utf8').replace('.pragma library','');
const H=new Function(src+';return {wanted,parse,lua,configCall,reconcile,take,same};')();
const a=(c,m)=>{if(!c)throw new Error(m)};
const eq=(x,y)=>JSON.stringify(x)===JSON.stringify(y);

// defaults: animations, blur, shadows on; gaps, rounding, tearing off
a(eq(Object.keys(H.wanted({})).sort(),['animations:enabled','decoration:blur:enabled','decoration:shadow:enabled']),'default levers');
const all=H.wanted({hyprGaps:true,hyprRounding:true,hyprTearing:true,hyprBlur:false});
a(!('decoration:blur:enabled' in all)&&all['general:gaps_in']===0&&all['general:gaps_out']===0&&all['decoration:rounding']===0&&all['general:allow_tearing']===true,'switches');

// hyprctl getoption text (as Hyprland 0.57 prints it)
const cur=H.parse(['@animations:enabled','bool: true','set: true','@general:gaps_in','css gap data: 3 3 3 3','set: true',
  '@general:gaps_out','css gap data: 10 20 10 5','set: true','@decoration:rounding','int: 3','set: true',
  '@general:allow_tearing','bool: false','set: false','@decoration:blur:enabled','bool: false','set: true'].join('\n'));
a(cur['animations:enabled']===true&&cur['decoration:rounding']===3&&cur['general:allow_tearing']===false,'parse scalars');
a(eq(cur['general:gaps_out'],{top:10,right:20,bottom:10,left:5}),'parse gaps');
a(H.same(cur['general:gaps_in'],{top:3,right:3,bottom:3,left:3})&&!H.same(cur['general:gaps_in'],0)&&H.same({top:0,right:0,bottom:0,left:0},0),'same');

// lua
a(H.lua(cur['general:gaps_in'])==='3','even gaps as int');
a(H.lua(cur['general:gaps_out'])==='{ top = 10, right = 20, bottom = 10, left = 5 }','uneven gaps as table');
a(H.configCall({})==='','no call for nothing');
a(H.configCall({'animations:enabled':false,'decoration:blur:enabled':false,'decoration:rounding':0,'general:gaps_in':0})
  ==='hl.config({ animations = { enabled = false }, decoration = { blur = { enabled = false }, rounding = 0 }, general = { gaps_in = 0 } })','nested call');
let threw=false; try{H.lua('x; os.execute()')}catch(e){threw=true} a(threw,'strings are never put into Lua');

// take: only what we change is remembered; blur already off is left alone
const want=H.wanted({hyprGaps:true,hyprRounding:true,hyprTearing:true});
let r=H.reconcile({},want);
a(r.toRead.length===7&&eq(r.restore,{}),'first reconcile reads all');
let t=H.take(r.snapshot,want,cur);
a(!('decoration:blur:enabled' in t.snapshot)&&!('decoration:blur:enabled' in t.apply),'already-off blur untouched');
a(t.apply['general:allow_tearing']===true&&t.snapshot['general:allow_tearing']===false,'tearing remembered');
a(eq(t.snapshot['general:gaps_out'],{top:10,right:20,bottom:10,left:5}),'gaps remembered');
const restoreAll=H.configCall(H.reconcile(t.snapshot,{}).restore);
a(restoreAll.includes('allow_tearing = false')&&restoreAll.includes('rounding = 3')&&restoreAll.includes('gaps_out = { top = 10')&&restoreAll.includes('animations = { enabled = true }')&&!restoreAll.includes('blur'),'restore only what changed: '+restoreAll);

// a lever switched off mid-mode: only it is restored, the rest stays held
const fewer=H.wanted({hyprGaps:true,hyprRounding:false,hyprTearing:true});
r=H.reconcile(t.snapshot,fewer);
a(eq(r.restore,{'decoration:rounding':3})&&!('decoration:rounding' in r.snapshot)&&r.toRead.join()==='decoration:blur:enabled,decoration:shadow:enabled','mid-mode lever off');
// shell restarted mid-mode: the saved snapshot comes back, and reading the
// (now off) values again doesn't overwrite the originals
const saved=JSON.parse(JSON.stringify(t.snapshot));
const offNow={'animations:enabled':false,'decoration:rounding':0,'general:allow_tearing':true};
t=H.take(saved,want,offNow);
a(t.snapshot['animations:enabled']===true&&t.snapshot['decoration:rounding']===3&&eq(t.apply,{}),'snapshot survives restart');
console.log('hyprperf ok');
