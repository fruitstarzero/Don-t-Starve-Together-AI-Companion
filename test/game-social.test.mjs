import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {lua,lauxlib,lualib,to_luastring,to_jsstring} from 'fengari';
const source=file=>fs.readFileSync(new URL('../mod/scripts/'+file,import.meta.url),'utf8');
function run(code){const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);const status=lauxlib.luaL_dostring(L,to_luastring(`package.preload.ai_reservations=function()${fs.readFileSync(new URL('../mod/scripts/ai_reservations.lua',import.meta.url),'utf8')}end
 package.preload.ai_navigation=function()${fs.readFileSync(new URL('../mod/scripts/ai_navigation.lua',import.meta.url),'utf8')}end
package.preload.ai_actions=function()${fs.readFileSync(new URL('../mod/scripts/ai_actions.lua',import.meta.url),'utf8')}end
`+code));const error=status?to_jsstring(lua.lua_tostring(L,-1)):undefined;lua.lua_close(L);assert.equal(status,lua.LUA_OK,error);}
test('actual game Apply speaks without changing follow, plan or pending owner chat',()=>run(`
 local clock=400;GetTime=function()return clock end
 Class=function(ctor)local c={};c.__index=c;return c end
 package.preload.ai_policy=function()${source('ai_policy.lua')}end
 package.preload.ai_social=function()${source('ai_social.lua')}end
 package.preload.ai_memory=function()${source('ai_memory.lua')}end
 package.preload.ai_speechhistory=function()${source('ai_speechhistory.lua')}end
 package.preload.ai_capabilities=function()return {}end
 package.preload.ai_inventory=function()return {}end
 package.preload.ai_resources=function()return {}end
 local Manager=(function()${source('components/aicompanionmanager.lua')}end)()
 local S=require('ai_social');local spoken={}
 local c={revision=1,mode='follow',plan={activity='collect'},awaiting_chat=500}
 local m=setmetatable({session='s',seen_results={},responses={},social=S.New(0),
   bot={IsValid=function()return true end,GetSaveRecord=function()return {}end,
     components={aicompanion=c,talker={Say=function(self,text,duration)
       assert(duration==8,'readable speech should last eight seconds');table.insert(spoken,text)
     end}}}},Manager)
 m.Snapshot=function()return {social={canSpeak=true}}end
 local notice=S.Observe(m.social,{near=true,safe=true,health=1,hunger=1,phase='day',events={}},clock).candidate
 m:Apply({id='speech',session='s',revision=1,source='social',expires=500,
   speechId=notice.id,taskStatus='complete',reply='我在旁边看着呢。'})
 assert(#spoken==1 and #m.responses==1)
 assert(c.mode=='follow' and c.plan.activity=='collect' and c.awaiting_chat==500)
 m:Apply({id='again',session='s',revision=1,source='social',expires=500,speechId=notice.id,reply='重复'})
 assert(#spoken==1)
 m:Apply({id='bad',session='s',revision=1,source='social',expires=500,command='teleport',reply='越权'})
 assert(#spoken==1 and c.mode=='follow')
 local saved=m:OnSave()
 local restored=setmetatable({},Manager)
 restored:OnLoad({ownerid='owner',responses=saved.responses})
 assert(#restored.responses==1 and restored.responses[1].text=='我在旁边看着呢。')
 assert(restored.responses[1].context.topic=='idle')
 `));
test('teleport uses a safe landing point and refuses other owners, boats and dead players',()=>run(`
 GetTime=function()return 100 end
 TheShard={GetShardId=function()return '1'end}
 local pos=setmetatable({x=10,z=20},{__add=function(a,b)return {x=a.x+b.x,z=a.z+b.z}end})
 local owner={userid='owner',IsValid=function()return true end,HasTag=function()return false end,
   GetCurrentPlatform=function()return nil end,GetPosition=function()return pos end}
 local moved=false;local stopped=false
 local inst={HasTag=function()return false end,GetCurrentPlatform=function()return nil end,
   components={health={IsDead=function()return false end}},sg={HasStateTag=function()return false end},
   Physics={Teleport=function(self,x,y,z)assert(x==12 and z==20);moved=true end}}
 local c={inst=inst,ownerid='owner',Stop=function()stopped=true end,Event=function()end}
 local T=(function()${source('ai_travel.lua')}end)()
 FindWalkableOffset=function()return nil end
 assert(not T.ToOwner(c,owner) and not moved)
 FindWalkableOffset=function()return {x=2,z=0}end
 assert(T.ToOwner(c,owner) and moved and stopped and c.mode=='stay')
 moved=false;assert(not T.ToOwner(c,owner) and not moved)
 c.lastteleport=nil;owner.userid='other';assert(not T.ToOwner(c,owner))
 owner.userid='owner';owner.GetCurrentPlatform=function()return {}end;assert(not T.ToOwner(c,owner))
 `));
