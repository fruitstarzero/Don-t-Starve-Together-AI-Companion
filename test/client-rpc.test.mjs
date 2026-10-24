import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {lua,lauxlib,lualib,to_luastring,to_jsstring} from 'fengari';

test('client snapshot RPC runs in the restricted DST mod environment',()=>{
 const source=fs.readFileSync(process.env.DST_MODMAIN_PATH||new URL('../mod/modmain.lua',import.meta.url),'utf8');
 const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);
 // Vanilla mods.lua CreateEnvironment exposes this Lua whitelist, not _G.
 // In particular, pcall is intentionally absent; GLOBAL.pcall is available.
 const code=`
 local callbacks={}; local refreshes=0; local requests=0; local opened
 local panel={name='AICompanionScreen',Refresh=function(self,s)
   refreshes=refreshes+1; assert(s.status=='first' or s.status=='second')
 end}
 local active=panel
 local hud={}
 ThePlayer={HUD=hud}
 TheFrontEnd={GetActiveScreen=function()return active end,
   PushScreen=function(self,s) opened=s end}
 TheNet={IsDedicated=function()return false end}
 TheInput={AddKeyUpHandler=function(self,key,fn) callbacks.open=fn end}
 json={decode=function(encoded)
   if encoded=='bad' then error('invalid JSON') end
   if encoded=='scalar' then return 1 end
   return {status=encoded}
 end}
 ActionHandler=function()return {}end
 local env={pairs=pairs,ipairs=ipairs,print=print,math=math,table=table,
   type=type,string=string,tostring=tostring,GLOBAL=_G,Class=function()end,
   require=function(name)
     if name=='ai_private' then return {} end
     if name=='screens/aicompanionscreen' then
       return function(send,snapshot)return {snapshot=snapshot}end
     end
     error('unexpected require '..name)
   end,
   GetModConfigData=function()return false end,
   AddPrefabPostInit=function()end,AddAction=function()return {}end,
   AddStategraphActionHandler=function()end,AddModRPCHandler=function()end,
   AddComponentPostInit=function()end,
   AddClientModRPCHandler=function(ns,name,fn)callbacks[name]=fn end,
   AddClassPostConstruct=function()end,
   GetModRPC=function()return {}end,
   SendModRPCToServer=function()requests=requests+1 end}
 assert(env.pcall==nil)
 assert(load([==[${source}]==],'@modmain.lua','t',env))()
 callbacks.snapshot('first') -- Exact failing client receive path.
 assert(refreshes==1)
 callbacks.snapshot('bad');callbacks.snapshot('scalar')
 assert(refreshes==1) -- Invalid input must not replace the last good snapshot.
 active=nil;callbacks.snapshot('second');assert(refreshes==1)
 active=hud;callbacks.open()
 assert(opened.snapshot.status=='second' and requests==1)
 `;
 const status=lauxlib.luaL_dostring(L,to_luastring(code));
 const error=status===lua.LUA_OK?undefined:to_jsstring(lua.lua_tostring(L,-1));
 lua.lua_close(L);
 assert.equal(status,lua.LUA_OK,error);
});
