// Check for the wallpaper deck's sort, search and colour helpers. Run: node scripts/dev/test-wallpaper-deck.js
const fs=require('fs'); const src=fs.readFileSync(require('path').join(__dirname,'../../modules/wallpaperSelector/deck.js'),'utf8').replace('.pragma library','');
const D=new Function(src+';return {hexToHsl,hslToHex,hueKey,sorted,filtered,dressFrom,chipsFrom,kind};')();
const a=(c,m)=>{if(!c)throw new Error(m)};
const w=(name,modified)=>({name,path:'/w/'+name,modified});
const list=[w('b10.jpg',3),w('B2.png',1),w('a.jpg',2),w('grey.jpg',4),w('new.jpg',5)];
a(D.sorted(list,'name').map(x=>x.name).join()==='a.jpg,b10.jpg,B2.png,grey.jpg,new.jpg'.replace('b10.jpg,B2.png','B2.png,b10.jpg'),'name: natural, case-insensitive');
a(D.sorted(list,'date').map(x=>x.modified).join()==='5,4,3,2,1','date: newest first');
const pal={'/w/a.jpg':{source:'#2050e0',hue:225,luminance:.4},'/w/b10.jpg':{source:'#e02020',hue:0,luminance:.4},
  '/w/B2.png':{source:'#20e040',hue:130,luminance:.5},'/w/grey.jpg':{source:'#808080',hue:-1,luminance:.6}};
a(D.sorted(list,'hue',pal).map(x=>x.name).join()==='b10.jpg,B2.png,a.jpg,grey.jpg,new.jpg','hue: wheel from red, greys, then unread');
a(D.filtered(list,'B 1',false,[]).map(x=>x.name).join()==='b10.jpg','search: every word in the name');
a(D.filtered(list,'',true,['/w/a.jpg']).map(x=>x.name).join()==='a.jpg','favourites only');
a(D.hslToHex(0,1,.5)==='#ff0000'&&Math.abs(D.hexToHsl('#00ff00').h-1/3)<1e-9,'hsl round trip');
a(/^#[0-9a-f]{6}$/.test(D.dressFrom(['#334455','#ff8800']).accent),'dress from colours');
a(D.dressFrom([])===null&&D.chipsFrom('nope').length===0,'no colours: no dress');
a(D.chipsFrom('#2050e0').length===5,'five chips');
a(D.kind('x.MP4')==='video'&&D.kind('x.gif')==='animated'&&D.kind('x.png')==='image','kind');
console.log('wallpaper deck ok');
