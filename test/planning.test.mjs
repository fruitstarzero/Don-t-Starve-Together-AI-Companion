import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {lua,lauxlib,lualib,to_luastring,to_jsstring} from 'fengari';
import {validateDecision} from '../bridge/schema.mjs';
const src=f=>fs.readFileSync(new URL('../mod/scripts/'+f,import.meta.url),'utf8');
function run(body){const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);
 const result=lauxlib.luaL_dostring(L,to_luastring(`
 local clock=100;GetTime=function()return clock end
 TheWorld={state={cycles=1,isday=true}}
 package.preload.ai_inventory=function()return {Count=function(inst,p)return (inst.bag or {})[p] or 0 end}end
 package.preload.ai_procurement=function()${src('ai_procurement.lua')}end
 local T=(function()${src('ai_tasks.lua')}end)()
 package.preload.ai_actions=function()${src('ai_actions.lua')}end
 package.preload.ai_policy=function()${src('ai_policy.lua')}end
 local function fixture()
  return {mode='auto',inst={GUID=1,bag={},GetPosition=function()return{x=0,z=0}end},
   Stop=function()end,Event=function()end,Problem=function(c,k,d)c.problem={kind=k,detail=d}end}
 end
 ${body}`));const error=result?to_jsstring(lua.lua_tostring(L,-1)):null;lua.lua_close(L);assert.equal(result,lua.LUA_OK,error);}
test('a blocked goal can change its method without losing root goal or accepting autonomy replacement',()=>run(`
 local c=fixture();T.Accept(c,{activity='collect',prefab='log',count=30,reason='收木头'},nil,'chat','收30木头入库')
 c.plan.delivered=8;local id=c.job.id
 T.Block(c,'route_blocked',{prefab='log',reason='岸边不可达'})
 assert(c.job.status=='blocked' and c.job.approach.failure=='route_blocked')
 assert(not T.Accept(c,{activity='craft',recipe='axe',reason='换目标'},nil,'autonomy'))
 assert(c.job.id==id and c.job.goal=='收30木头入库' and c.plan.delivered==8)
 clock=131;assert(T.Ready(c));assert(c.job.approach.attempt==2 and c.plan.delivered==8)
 T.Command(c,'follow');assert(not T.Ready(c));T.Command(c,'cancel');assert(c.job.status=='cancelled')
 `));
test('eating and unrelated or old-stage successes never hide a stalled collection task',()=>run(`
 local c=fixture();T.Accept(c,{activity='collect',prefab='log',count=30,reason='木头'},nil,'chat','木头')
 clock=160;T.Progress(c,'action_success',{action='EAT'})
 assert(c.task_last_progress==100,'survival is not root-goal progress')
 T.Progress(c,'build_success',{recipe='rope'});assert(c.task_last_progress==100)
 T.Progress(c,'transfer_success',{prefab='log',count=3,take=true,taskContext={id='old',index=1,kind='objective'}})
 assert(c.task_last_progress==100,'late work from another job cannot count')
 assert(T.Progress(c,'transfer_success',{prefab='log',count=3,take=true,taskContext=T.Context(c)}))
 assert(c.task_last_progress==160)
 `));
test('survival time is excluded without erasing earlier unsuccessful active work',()=>run(`
 local c=fixture();T.Accept(c,{activity='collect',prefab='log',count=30,reason='木头'},nil,'chat','木头')
 clock=160;assert(T.Ready(c));clock=170;T.Interrupt(c,'先吃饭')
 clock=300;T.Interrupt(c,'先吃饭');clock=310;assert(T.Ready(c))
 clock=371;assert(not T.Ready(c) and c.job.status=='blocked','active waiting must accumulate across survival detours')
 `));
test('a model cannot execute an activity marked unsupported by the actual game capability catalog',()=>{
 const d={reply:'',command:null,plan:{activity:'fish',prefab:null,recipe:null,count:null,reason:'钓鱼'},tripSeconds:240,taskStatus:'ongoing',experiences:[]};
 assert.throws(()=>validateDecision(d,{source:'chat',snapshot:{actionCatalog:{activities:{fish:{supported:false}}}}}),/capability/i);
});
test('remembered blocked routes use a different safe approach and reset runtime timers after reload',()=>run(`
 Vector3=function(x,y,z)return{x=x,z=z}end
 package.preload.ai_safety=function()return{Risk=function()return 0 end}end
 local N=(function()${src('ai_navigation.lua')}end)()
 local c=fixture();c.inst.components={locomotor={pathcaps={}}}
 TheWorld.Map={IsPassableAtPoint=function()return true end}
 TheWorld.Pathfinder={IsClear=function()return true end}
 local dest={x=30,z=0};N.Failed(c,dest,'route_blocked')
 local p=N.Waypoint(c,dest);assert(p and (p.x~=30 or p.z~=0),'must try a real side route rather than the same destination')
 c.inst.GetPosition=function()return p end
 assert(N.Waypoint(c,dest)==dest)
 assert(N.Waypoint(c,dest)==dest,'after a successful side hop keep the destination until another real failure')
 local old=c.nav_memory;c.nav_memory=nil;clock=1;N.Load(c,old)
 assert(next(c.nav_memory));assert(N.Waypoint(c,dest),'saved route experience must work after GetTime restarts')
 for i=1,8 do N.Failed(c,dest,'unsafe_route')end
 local retry=c.nav_memory['30/0'].retryAt
 clock=clock+30;N.Failed(c,dest,'unsafe_route')
 assert(c.nav_memory['30/0'].retryAt==retry,'repeated checks during exhausted cooldown cannot postpone retry forever')
 clock=retry+1;assert(N.Waypoint(c,dest),'a cooled-down route can try again')
 N.Arrived(c,dest);assert(not next(c.nav_memory))
 `));
test('future construction reserves real raw materials while the current task retains priority',()=>run(`
 AllRecipes={treasurechest={name='treasurechest',ingredients={{type='boards',amount=3}}},boards={name='boards',ingredients={{type='log',amount=4}}},
  spear={name='spear',ingredients={{type='log',amount=2}}}}
 local B=(function()${src('ai_reservations.lua')}end)()
 local c=fixture();c.inst.components={builder={ingredientmod=1},inventory={}}
 c.inst.bag.log=16
 c.job={status='active',index=1,steps={{activity='craft',recipe='spear',count=1},{activity='craft',recipe='treasurechest',count=1}}};c.plan=c.job.steps[1]
 local r=B.Compute(c,'spear');assert(r.protected.log==12)
 assert(B.CanSpend(c,'log',2,'spear'));assert(not B.CanSpend(c,'log',5,'spear'))
 c.inst.bag.log=3;r=B.Compute(c,'spear');assert(r.protected.log==1,'future claims must not starve the current prerequisite')
 assert(B.CanSpend(c,'log',2,'spear'))
 c.inst.bag={boards=3,log=4};r=B.Compute(c,'spear');assert(r.protected.boards==3 and not r.protected.log,'existing boards avoid duplicate raw reservations')
 `));
test('precious stockpile protection still applies when the basic precious threshold allows crafting',()=>run(`
 AllRecipes={};package.preload.ai_reservations=function()${src('ai_reservations.lua')}end
 local R=(function()${src('ai_resources.lua')}end)()
 local c=fixture();c.inst.components={builder={},inventory={ForEachItem=function(_,fn)
  fn({prefab='greengem',components={stackable={StackSize=function()return 5 end}}})end}}
 c.inst.bag.greengem=5;c.projects={gems={kind='stockpile',prefab='greengem',count=5}}
 assert(not R.CanUse(c,'greengem',1),'future/project reserves must compose with precious minimums')
 c.projects={};assert(R.CanUse(c,'greengem',1))
 `));
test('repairing a method preserves the root goal, delivered count and save identity through its completion',()=>run(`
 local c=fixture();T.Accept(c,{activity='collect',prefab='log',count=30,reason='木头'},nil,'chat','收30木头')
 c.plan.delivered=8;local id=c.job.id
 assert(T.Repair(c,{activity='collect',prefab='twigs',count=2,reason='先补工具材料'},'缺工具，补两根树枝'))
 assert(c.job.id==id and c.job.goal=='收30木头' and c.plan.delivered==8 and c.plan.prefab=='log')
 c.inst.bag.twigs=2;assert(not T.Method(c));assert(not c.method_plan and not c.job.method)
 assert(c.job.id==id and c.plan.delivered==8)
 T.Command(c,'follow');assert(not T.Repair(c,{activity='store',reason='不能擅自恢复'},'暂停'))
 `));
