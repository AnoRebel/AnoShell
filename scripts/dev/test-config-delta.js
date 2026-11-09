// Check for the user-delta merge. Run: node scripts/dev/test-config-delta.js
const fs=require('fs'); const src=fs.readFileSync(require('path').join(__dirname,'../../modules/common/ConfigDelta.js'),'utf8').replace('.pragma library','');
const D=new Function(src+';return {applyOps};')();
const a=(c,m)=>{if(!c)throw new Error(m)};
const eq=(x,y)=>JSON.stringify(x)===JSON.stringify(y);

// An external edit (dock.position) survives our pending change (bar.height).
const disk={dock:{position:'left'},bar:{style:'pill'}};
let r=D.applyOps(disk,[{key:'bar.height',value:40}]);
a(eq(r,{dock:{position:'left'},bar:{style:'pill',height:40}}),'merge keeps the external key');
a(eq(disk,{dock:{position:'left'},bar:{style:'pill'}}),'input not mutated');
// Our pending change wins on the same key.
r=D.applyOps({bar:{height:30}},[{key:'bar.height',value:40}]);
a(r.bar.height===40,'pending wins on conflict');
// Reset removes and prunes the emptied parent; missing paths are no-ops.
r=D.applyOps({a:{b:{c:1}},x:1},[{key:'a.b.c',reset:true},{key:'q.r',reset:true}]);
a(eq(r,{x:1}),'reset prunes empty parents');
// Order matters: set then reset, reset then set.
a(eq(D.applyOps({},[{key:'k.v',value:1},{key:'k.v',reset:true}]),{}),'set then reset');
a(eq(D.applyOps({},[{key:'k.v',reset:true},{key:'k.v',value:2}]),{k:{v:2}}),'reset then set');
// Arrays are values, not paths; a scalar in the way is replaced by an object.
a(eq(D.applyOps({bars:[1]},[{key:'bars',value:[{a:1}]}]),{bars:[{a:1}]}),'array value');
a(eq(D.applyOps({n:5},[{key:'n.m',value:true}]),{n:{m:true}}),'scalar replaced by object');
// Reset all, then a later change.
a(eq(D.applyOps({a:1,b:2},[{all:true},{key:'c',value:3}]),{c:3}),'reset all');
console.log('config-delta: ok');
