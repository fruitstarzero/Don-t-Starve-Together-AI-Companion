import test from 'node:test';
import fs from 'node:fs';
import assert from 'node:assert/strict';
import {lua,lauxlib,lualib,to_luastring,to_jsstring} from 'fengari';
test('survival reserves, partial deposits, container sorting and stale plans',()=>{
 const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);
 const code=`package.preload.ai_actions=function()${fs.readFileSync(new URL('../mod/scripts/ai_actions.lua',import.meta.url),'utf8')}end
local P=(function() ${fs.readFileSync(new URL('../mod/scripts/ai_policy.lua',import.meta.url),'utf8')} end)()
 local items={{id=1,prefab='berries',count=10,food=true,calories=10},{id=2,prefab='log',count=40},
 {id=3,prefab='axe',count=1,gear=true},{id=4,prefab='abigail_flower',count=1,personal=true},
 {id=5,prefab='cutgrass',count=20}}
 local keep=P.KeepCounts(items,{calories=35,materials={log=6,cutgrass=2}})
 assert(keep[1]==4 and keep[2]==6 and keep[3]==1 and keep[4]==1 and keep[5]==2)
 assert(items[1].count-keep[1]==6)
 local item={prefab='log'}
 assert(P.ChestScore(item,{available=false,room=9,prefabs={}})<0)
 assert(P.ChestScore(item,{available=true,room=9,prefabs={log=true},category='wood'})>10)
 assert(P.ChestScore(item,{available=true,room=9,prefabs={},ice=true})<0)
 assert(not P.CanApply({session='s',revision=1,expires=20,source='autonomy'},'s',2,'auto',10))
 assert(not P.CanApply({session='s',revision=1,expires=20,source='autonomy'},'s',1,'follow',10))
 assert(P.CanApply({session='s',revision=1,expires=20,source='chat'},'s',1,'follow',10))
 assert(not P.ValidPlan({activity='burn',reason='bad'}))
 `;
 const status=lauxlib.luaL_dostring(L,to_luastring(code));
 assert.equal(status,lua.LUA_OK,status?to_jsstring(lua.lua_tostring(L,-1)):undefined);
 lua.lua_close(L);
});
