// Check for the connected-frame slot packing (meniscus swell, detached neck). Run: node scripts/dev/test-frame-geometry.js
const fs=require('fs'); const src=fs.readFileSync(require('path').join(__dirname,'../../modules/anoScreen/ConnectedSurfaceGeometry.js'),'utf8').replace('.pragma library','');
const G=new Function(src+';return {packSlot,meniscusK};')();
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
console.log('geometry ok');
