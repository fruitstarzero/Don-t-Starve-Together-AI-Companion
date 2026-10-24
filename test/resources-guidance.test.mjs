import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {lua,lauxlib,lualib,to_luastring,to_jsstring} from 'fengari';
const src=file=>fs.readFileSync(new URL('../mod/scripts/'+file,import.meta.url),'utf8');
function run(code){const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);const status=lauxlib.luaL_dostring(L,to_luastring(`package.preload.ai_reservations=function()${fs.readFileSync(new URL('../mod/scripts/ai_reservations.lua',import.meta.url),'utf8')}end
 package.preload.ai_navigation=function()${fs.readFileSync(new URL('../mod/scripts/ai_navigation.lua',import.meta.url),'utf8')}end
`+code));const error=status?to_jsstring(lua.lua_tostring(L,-1)):undefined;lua.lua_close(L);assert.equal(status,lua.LUA_OK,error);}

test('ordinary ingredients in separate stacks can fill all four crockpot slots',()=>run(`
 unpack=table.unpack;ACTIONS={AI_COOKSTORE={}};FOODTYPE={MEAT='meat'}
 package.preload.ai_inventory=function()return {
   Items=function()return {{prefab='meat',count=1},{prefab='berries',count=2},{prefab='berries',count=1}}end,
   Find=function()return {}end}end
 package.preload.ai_resources=function()return {precious={},Count=function()return 3 end}end
 package.preload.cooking=function()return {ingredients={meat={},berries={}},
   recipes={cookpot={meatballs={foodtype='meat',health=3,sanity=5,hunger=62.5}}},
   CalculateRecipe=function(_,items)
     assert(#items==4);local meat=0;for _,v in ipairs(items)do if v=='meat' then meat=meat+1 end end
     return meat==1 and 'meatballs' or nil
   end}end
 local pot={GUID=1,components={stewer={IsCooking=function()return false end,IsDone=function()return false end},
   container={IsOpenedByOthers=function()return false end,IsEmpty=function()return true end,IsFull=function()return false end}}}
 local c={inst={components={health={GetPercent=function()return 1 end}}},Find=function()return pot end,Act=function()return true end}
 local L=(function()${src('ai_life.lua')}end)()
 assert(L.CrockPot(c),'two berry stacks must combine normally')
 assert(#c.cookingredients==4)
 `));

test('real builder entry hooks stop consumption and leave human builders unchanged',()=>run(`
 local hook;GLOBAL={};package.preload.ai_private=function()return {}end
 local allowed=false
 package.preload.ai_resources=function()return {CheckRecipe=function(c,name,report)
   assert(name=='panflute' and report);return allowed end}end
 AddComponentPostInit=function(name,fn)assert(name=='builder');hook=fn end
 AddPrefabPostInit=function()end;AddAction=function()return {}end;AddStategraphActionHandler=function()end
 GLOBAL.ActionHandler=function()return {}end;AddModRPCHandler=function()end;AddClientModRPCHandler=function()end
 GLOBAL.TheNet={IsDedicated=function()return true end}
 ${fs.readFileSync(new URL('../mod/modmain.lua',import.meta.url),'utf8')}
 local spent=0;local buffered=false
 local c={ownerid='owner'};local b={inst={components={aicompanion=c}},
   IsBuildBuffered=function()return buffered end,
   DoBuild=function()spent=spent+1;return true end,BufferBuild=function()spent=spent+1;return true end}
 hook(b);assert(not b:DoBuild('panflute') and not b:BufferBuild('panflute') and spent==0)
 allowed=true;assert(b:DoBuild('panflute') and spent==1)
 allowed=false;buffered=true;assert(b:DoBuild('panflute') and spent==2,'already paid buffer must stay usable')
 buffered=false;c.ownerid=nil;assert(b:DoBuild('panflute') and spent==3,'human Wendy must be unaffected')
 `));
test('precious resources preserve stock and only permit a genuine surplus',()=>run(`
 local R=(function()${src('ai_resources.lua')}end)()
 local amount=2;local c={stock={},inst={components={inventory={ForEachItem=function(self,fn)
   fn({prefab='mandrake',components={stackable={StackSize=function()return amount end}}})
 end}}}}
 assert(not R.CanUse(c,'mandrake',1))
 amount=5;assert(R.CanUse(c,'mandrake',1));assert(not R.CanUse(c,'mandrake',3))
 amount=4;assert(not R.CanUse(c,'mandrake',1))
 assert(R.CanUse(c,'twigs',100))
 c.stock={old={current=false,counts={mandrake=100}}};amount=1
 assert(not R.CanUse(c,'mandrake',1),'stale base inventory must not permit spending')
 `));
test('persistent problems become remote help topics, and stop once solved',()=>run(`
 local S=(function()${src('ai_social.lua')}end)()
 local state=S.New(0)
 local f={near=false,safe=true,health=1,hunger=1,phase='day',events={},
   problem={kind='missing_materials',since=40,updated=100,detail={recipe='panflute'}}}
 local notice=S.Observe(state,f,100)
 assert(notice.candidate.kind=='need_help' and notice.canSpeak)
 assert(S.Accept(state,notice.candidate.id,'缺芦苇，你能帮我带几根回来吗？',100))
 assert(not S.Observe(state,f,101).candidate)
 f.problem.updated=200
 assert(not S.Observe(state,f,200).candidate,'same help topic should not spam')
 f.problem=nil;assert(not S.Observe(state,f,201).candidate)
 `));
test('Abigail uses normal actions, honors recent owner recall and withdraws when weak',()=>run(`
 local now=100;GetTime=function()return now end
 ACTIONS={CASTSUMMON={id='summon'},CASTUNSUMMON={id='recall'},COMMUNEWITHSUMMONED={id='mode'}}
 local hp=1;local ghost={IsValid=function()return true end,is_defensive=true,
   components={health={GetPercent=function()return hp end}}}
 local enemy={IsValid=function()return true end,HasTag=function()return false end,
   components={health={IsDead=function()return false end}}}
 local bond={ghost=ghost,notsummoned=true,summoned=false}
 local action;local c={mode='auto',threat=enemy,Owner=function()return nil end,
   inst={GetDistanceSqToInst=function()return 4 end,components={ghostlybond=bond,
   inventory={FindItem=function()return {}end},health={GetPercent=function()return 1 end}}},
   Act=function(self,a)action=a.id;return true end}
 local A=(function()${src('ai_abigail.lua')}end)()
 assert(A.Tick(c) and action=='summon')
 now=106;c.abigail_manual_until=120;assert(not A.Tick(c))
 now=107;bond.notsummoned=false;bond.summoned=true;hp=.15
 assert(A.Tick(c) and action=='recall','critical Abigail health must override manual grace period')
 now=121;c.abigail_next=nil;bond.notsummoned=false;bond.summoned=true;hp=.2
 assert(A.Tick(c) and action=='recall')
 `));
