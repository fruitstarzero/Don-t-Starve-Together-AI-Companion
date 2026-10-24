import fs from 'node:fs';
import luaparse from 'luaparse';
import {lua,lauxlib,lualib,to_luastring,to_jsstring} from 'fengari';

export const workshop=process.env.DST_WORKSHOP_ROOT||'';
export const showme=['666155465','3436020204'];
const parse=text=>luaparse.parse(text,{luaVersion:'5.1',ranges:true});
const stringValue=node=>node?.value??(node?.type==='StringLiteral'?node.raw.slice(1,-1):undefined);
function walk(node,visit){if(!node || typeof node!=='object')return;visit(node);for(const [k,v] of Object.entries(node)){
 if(k==='range')continue;if(Array.isArray(v))for(const n of v)walk(n,visit);else if(v&&typeof v==='object')walk(v,visit);
}}
export function enabledMods(text){
 const ast=parse(text),out=new Set();
 const table=ast.body.find(n=>n.type==='ReturnStatement')?.arguments[0];
 for(const field of table?.fields||[]){
  const name=stringValue(field.key)||field.key?.name;
  const enabled=field.value?.fields?.find(f=>f.key?.name==='enabled')?.value?.value;
  if(enabled===true)out.add(name);
 }
 return out;
}
export function disableOrigin(text){
 const active=enabledMods(text);
 if(!showme.every(id=>active.has('workshop-'+id)))return text;
 const table=parse(text).body.find(n=>n.type==='ReturnStatement').arguments[0];
 const origin=table.fields.find(f=>stringValue(f.key)==='workshop-666155465');
 const enabled=origin.value.fields.find(f=>f.key?.name==='enabled').value;
 return text.slice(0,enabled.range[0])+'false'+text.slice(enabled.range[1]);
}
export function callbackSource(id){
 const source=fs.readFileSync(`${workshop}/${id}/modmain.lua`,'utf8');
 const functions=[];
 walk(parse(source),node=>{
  if(node.type==='CallExpression' && node.base?.name==='AddPrefabPostInit'
    && stringValue(node.arguments?.[0])==='player_classified'){
   const callback=node.arguments[1];
   if(source.slice(...callback.range).includes('showme_hintbua.'))functions.push(source.slice(...callback.range));
  }
 });
 if(functions.length!==1)throw Error(`Expected one hint registration in ${id}, found ${functions.length}`);
 return functions[0];
}
export function replay(ids){
 const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);
 const setup=`_G=_G or {}; CLIENT_SIDE=true; local registered={};
 net_string=function(guid,name,event)
   assert(not registered[guid..'/'..name], 'Registering duplicate lua network variable '..name..' in entity player_classified['..guid..']')
   registered[guid..'/'..name]=true
   return {value=function()return '' end}
 end
 local inst={GUID=1,ListenForEvent=function()end};
 `+ids.map(id=>`(${callbackSource(id)})(inst);`).join('\n');
 const status=lauxlib.luaL_dostring(L,to_luastring(setup));
 const error=status!==lua.LUA_OK?to_jsstring(lua.lua_tostring(L,-1)):null;
 lua.lua_close(L);return {ok:status===lua.LUA_OK,error};
}
if(process.argv[1]?.endsWith('probe-showme-conflict.mjs')){
 const file=process.argv[2];if(!file||!workshop)throw Error('Set DST_WORKSHOP_ROOT and pass your own modoverrides.lua path');
 const active=showme.filter(id=>enabledMods(fs.readFileSync(file,'utf8')).has('workshop-'+id));
 const result=replay(active);console.log(JSON.stringify({activeShowMe:active,...result},null,2));if(!result.ok)process.exitCode=1;
}