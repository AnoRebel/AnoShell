// Check for the bar form geometry. Run: node scripts/dev/test-bar-layout.js
const fs=require('fs'); const src=fs.readFileSync(require('path').join(__dirname,'../../modules/bar/BarLayout.js'),'utf8').replace('.pragma library','');
const B=new Function(src+';return {place,bodies,sepTarget,groupsFromModules,formOf,neckK};')();
const a=(c,m)=>{if(!c)throw new Error(m)};
const groups=[{id:'start',zone:'start',len:200},{id:'center',zone:'center',len:120},{id:'end',zone:'end',len:300}];
const o={length:1280,padding:8,spacing:8,gap:10,islandPad:4,margin:6};
const live=(form,seps)=>{const p=B.place({...o,form},groups);return groups.map(g=>({id:g.id,len:g.len,pos:p[g.id],sep:seps[g.id]??0}));};

let p=B.place({...o,form:'full'},groups);
a(p.start===8 && p.end===1280-8-300 && p.center===(1280-120)/2,'full placement');
let b=B.bodies({...o,form:'full'},live('full',{}));
a(b.length===1 && b[0].pos===0 && b[0].len===1280 && !b[0].island,'full, all attached: one edge-to-edge body');

// Detaching the end group (clock): one body + one island, separated by the gap.
b=B.bodies({...o,form:'full'},live('full',{end:1}));
a(b.length===2 && !b[0].island && b[1].island && b[1].id==='end','full + detached end: body + island');
a(Math.abs((b[1].pos)-(b[0].pos+b[0].len)-10)<1e-9,'gap of 10 between body and island');
// Halfway: half the gap.
b=B.bodies({...o,form:'full'},live('full',{end:0.5}));
a(Math.abs(b[1].pos-(b[0].pos+b[0].len)-5)<1e-9,'gap follows sep');
// Detached centre splits the body in two.
b=B.bodies({...o,form:'full'},live('full',{center:1}));
a(b.filter(x=>!x.island).length===2 && b.filter(x=>x.island).length===1,'detached centre splits the body');

// Islands: no body, one island per group.
b=B.bodies({...o,form:'islands'},live('islands',{start:1,center:1,end:1}));
a(b.length===3 && b.every(x=>x.island),'islands: three islands');
a(B.sepTarget('islands',{attached:true})===1 && B.sepTarget('full',{attached:true})===0 && B.sepTarget('full',{attached:false})===1,'sep targets');

// Notch: packed and centred, body shrinks to content.
p=B.place({...o,form:'notch'},groups);
const total=200+120+300+16;
a(p.start===(1280-total)/2 && p.center===p.start+208 && p.end===p.center+128,'notch packs in zone order, centred');
b=B.bodies({...o,form:'notch'},live('notch',{}));
a(b.length===1 && b[0].pos===p.start-8 && b[0].len===total+16,'notch body hugs the content');

// Fit: inset by the margin.
b=B.bodies({...o,form:'fit'},live('fit',{}));
a(b.length===1 && b[0].pos===6 && b[0].len===1280-12,'fit body is inset');
a(B.formOf('bogus')==='full','unknown form falls back to full');
a(B.groupsFromModules({left:['a'],right:['b']}).map(g=>g.id).join()==='start,center,end','migration');
a(B.neckK(14,0)===14 && B.neckK(14,1)===0 && B.neckK(14,0.5)===7,'neck thins to nothing as the island separates');
console.log('bar layout ok');
