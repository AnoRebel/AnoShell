// Check for the connected-frame slot packing (meniscus swell, detached neck). Run: node scripts/dev/test-frame-geometry.js
const fs=require('fs'); const src=fs.readFileSync(require('path').join(__dirname,'../../modules/anoScreen/ConnectedSurfaceGeometry.js'),'utf8').replace('.pragma library','');
const G=new Function(src+';return {packSlot,meniscusK,fillets};')();
const ctx={cutL:5,cutT:5,cutR:1275,cutB:795,connectedRadius:18,surfaceRadius:12,dpr:1.5};
const a=(c,m)=>{if(!c)throw new Error(m)};
const full=G.packSlot({side:'left',x:0,y:42,w:460,h:758},ctx);
a(full.k[0]===18,'full open: k = connectedRadius');
const half=G.packSlot({side:'left',x:-230,y:42,w:460,h:758,progress:0.5},ctx);
a(Math.abs(half.k[0]-18*1.6)<1e-9,'half open: k swells 60%');
const young=G.packSlot({side:'left',x:-455,y:42,w:460,h:758,progress:0.02},ctx);
a(young.k[0]>18,'young body keeps swollen k despite tiny depth');
const isl=G.packSlot({side:'top',x:100,y:50,w:80,h:30,detached:true,neckK:24},ctx);
a(isl.rect[1]===50&&isl.k.every(k=>k===24),'detached keeps near edge, neck k on all corners');
// Fillets: a popout under a top bar fillets into the bar's bottom edge on both
// sides; one flush with the right band fillets into it below its far corner.
const fc={...ctx,width:1280,height:800};
const bar=G.packSlot({side:'top',x:0,y:0,w:1280,h:42},fc);
const pop=G.packSlot({side:'top',x:900,y:42,w:300,h:385},fc);
let f=G.fillets([bar,pop],fc);
a(f.some(q=>q.x===900-18&&q.y===42&&q.cx===900-18&&q.cy===60),'popout start fillet under the bar');
a(f.some(q=>q.x===1200&&q.y===42),'popout end fillet under the bar');
const flush=G.packSlot({side:'top',x:980,y:42,w:300,h:385,omitEndConnector:true},fc);
f=G.fillets([bar,flush],fc);
a(f.some(q=>q.x===1275-12&&Math.abs(q.y-427)<1&&q.cx===1263&&Math.abs(q.cy-439)<1),'flush end fillets into the right band');
const sb=G.packSlot({side:'left',x:5,y:42,w:460,h:753,omitStartConnector:true,omitEndConnector:true},fc);
f=G.fillets([bar,sb],fc);
a(f.some(q=>Math.abs(q.x-465)<1&&q.y===42&&Math.abs(q.cx-477)<1&&q.cy===54),'sidebar fillets into the bar');
a(f.some(q=>Math.abs(q.x-465)<1&&Math.abs(q.y-(795-12))<1),'sidebar fillets into the bottom band');
console.log('geometry ok');
