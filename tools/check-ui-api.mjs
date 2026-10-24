// Cross-check the custom screen's widget calls against the installed game's
// actual Lua classes and their inheritance, without inventing a mock UI API.
import fs from 'node:fs';
const sources=['screens/aicompanionscreen.lua','widgets/aicompanionhistory.lua','widgets/aistyle.lua'].map(f=>fs.readFileSync(new URL('../mod/scripts/'+f,import.meta.url),'utf8'));
const chains={Widget:['widget'],Text:['text','widget'],TextEdit:['textedit','text','widget'],Image:['image','widget'],TextButton:['textbutton','button','widget'],ImageButton:['imagebutton','button','widget']};
let checked=0;
for(const source of sources){
const fields=new Map([...source.matchAll(/((?:(?:self|row|w)\.)?\w+)\s*=\s*[^\n]*?AddChild\((Widget|TextEdit|TextButton|Text|Image)\(/g)].map(m=>[m[1],m[2]==='TextButton'&&source.includes('TextButton=Style.Button')?'ImageButton':m[2]]));
for(const m of source.matchAll(/(\w+)\s*=\s*ImageButton\(/g))fields.set(m[1],'ImageButton');
// Panel.SetSize is our own method; its children still use the installed Image API.
for(const [field,type] of [...fields]){
 if(type==='TextButton'||type==='ImageButton')fields.set(field+'.text','Text');
 if(field.startsWith('w.'))fields.set(field.replace(/^w\./,'self.'),type);
}
for(const [field,type] of fields){
 const api=chains[type].map(name=>fs.readFileSync(new URL(`../reference/scripts/widgets/${name}.lua`,import.meta.url),'utf8')).join('\n');
 for(const match of source.matchAll(new RegExp(`(?<![\\w.])${field.replaceAll('.','\\.')}:(\\w+)\\(`,'g'))){
  const method=match[1];
  if(!new RegExp(`(?:function\\s+\\w+[:.]${method}\\s*\\(|\\.${method}\\s*=)`).test(api))throw Error(`Unknown installed widget API: ${type}:${method}`);
  checked++;
 }
}
}
console.log(`Installed widget APIs: ${checked} screen calls checked`);
