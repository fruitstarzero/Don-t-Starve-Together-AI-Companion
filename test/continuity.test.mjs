import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {lua,lauxlib,lualib,to_luastring,to_jsstring} from 'fengari';
import {syncTask} from '../bridge/tasks.mjs';
import {validateDecision} from '../bridge/schema.mjs';
import {DecisionEngine} from '../bridge/engine.mjs';
const source=f=>fs.readFileSync(new URL('../mod/scripts/'+f,import.meta.url),'utf8');
function run(code){
 const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);
 const status=lauxlib.luaL_dostring(L,to_luastring(`
 package.preload.ai_reservations=function()${fs.readFileSync(new URL('../mod/scripts/ai_reservations.lua',import.meta.url),'utf8')}end
 package.preload.ai_navigation=function()${fs.readFileSync(new URL('../mod/scripts/ai_navigation.lua',import.meta.url),'utf8')}end
package.preload.ai_actions=function()${fs.readFileSync(new URL('../mod/scripts/ai_actions.lua',import.meta.url),'utf8')}end
 package.preload.ai_procurement=function()${source('ai_procurement.lua')}end

 local clock=100;GetTime=function()return clock end;TheWorld={state={cycles=3,isday=true}}
 local T=(function()${source('ai_tasks.lua')}end)()
 local function fixture()
  return {inst={GUID=7,GetPosition=function()return {x=3,z=4}end},mode='auto',
    Stop=function()end,events={},Event=function(c,k,d)table.insert(c.events,{kind=k,detail=d})end,
    Problem=function(c,k,d)c.problem={kind=k,detail=d}end}
 end
 local function collect(n)return {activity='collect',prefab='log',count=n,reason='收集木材'}end
 ${code}`));
 const error=status?to_jsstring(lua.lua_tostring(L,-1)):undefined;lua.lua_close(L);assert.equal(status,lua.LUA_OK,error);
}
test('survival detours and repeated replanning preserve the exact goal and counters',()=>run(`
 local c=fixture();T.Accept(c,collect(30),nil,'chat','收30木头')
 c.plan.delivered=12;c.plan.progress=4
 T.Interrupt(c,'先照明');clock=400;T.Interrupt(c,'先照明')
 assert(c.job.interruption=='先照明' and c.plan.delivered==12)
 assert(not T.Accept(c,collect(2),nil,'autonomy','改为2块'))
 assert(T.Ready(c) and c.plan.count==30 and c.plan.delivered==12 and c.job.interruption==nil)
 `));
test('manual follow, stop, home and retreat pause until an explicit resume',()=>run(`
 for _,command in ipairs({'follow','stay','home','come','retreat','teleport'})do
  local c=fixture();T.Accept(c,collect(30),nil,'chat','旧目标');c.plan.delivered=8
  T.Command(c,command);assert(c.job.status=='paused' and not T.Ready(c))
  clock=1000;assert(not T.Ready(c),'time alone cannot override owner pause')
  T.Command(c,'resume');assert(c.mode=='auto' and T.Ready(c) and c.plan.delivered==8)
 end
 `));
test('self-chosen ongoing chores can change while user goals stay protected',()=>run(`
 local c=fixture();T.Accept(c,{activity='farm',reason='暂时农务'},nil,'autonomy','农务')
 assert(T.Accept(c,{activity='cook',reason='需要食物'},nil,'autonomy','做饭'))
 assert(not T.Accept(c,{activity='cook',reason='仍在做饭'},nil,'autonomy','做饭'))
 T.Accept(c,{activity='farm',reason='主人指定农务'},nil,'chat','照看农田')
 assert(not T.Accept(c,{activity='cook',reason='换做饭'},nil,'autonomy','做饭'))
 `));
test('workflow completion advances one actual step and survives a save/reload',()=>run(`
 local c=fixture();T.Accept(c,nil,{goal='做箱子再收木头',steps={
  {activity='craft',recipe='treasurechest',count=2,reason='做两个箱子'},collect(10),{activity='store',reason='存余货'}}},'chat')
 c.plan.built=1;T.Interrupt(c,'吃饭')
 local d=fixture();T.Load(d,{job=c.job,task_history=c.task_history,task_sequence=c.task_sequence})
 assert(d.plan.built==1 and d.job.index==1 and d.plan.recipe=='treasurechest')
 d.plan.built=2;T.Complete(d,{built=2});assert(d.job.index==2 and d.plan.prefab=='log')
 d.plan.delivered=10;T.Complete(d,{count=10});assert(d.job.index==3 and d.plan.activity=='store')
 T.Complete(d,{surplus=false});assert(d.job.status=='complete' and d.plan.activity=='auto')
 T.Command(d,'auto');assert(d.plan.activity=='auto' and #d.task_history==1)
 `));
test('cancelled goals never return and replacement keeps a terminal record',()=>run(`
 local c=fixture();T.Accept(c,collect(30),nil,'chat','旧目标');c.plan.delivered=9
 T.Command(c,'cancel');T.Command(c,'auto');assert(c.job.status=='cancelled' and c.plan.activity=='auto')
 T.Accept(c,collect(5),nil,'chat','新目标');assert(c.plan.delivered==nil and c.job.goal=='新目标')
 T.Accept(c,{activity='craft',recipe='axe',reason='斧头'},nil,'chat','斧头')
 assert(#c.task_history==2 and c.task_history[1].steps[1].delivered==9)
 `));
test('stalled work waits before retry and movement is not fabricated progress',()=>run(`
 local c=fixture();T.Accept(c,collect(30),nil,'chat','收集');clock=221
 assert(not T.Ready(c) and c.job.status=='blocked' and c.problem.kind=='task_stalled')
 clock=240;assert(not T.Ready(c));clock=252;assert(T.Ready(c))
 T.Progress(c,'action_success',{action='CHOP',product='log'});assert(c.job.checkpoint.reason=='action_success')
 clock=374;assert(not T.Ready(c));T.Command(c,'resume');assert(T.Ready(c))
 `));
test('legacy saves migrate with counters and preserve manual mode',()=>run(`
 local c=fixture();c.plan=collect(30);c.plan.delivered=11
 T.Load(c,{mode='follow'});assert(c.mode=='follow' and c.job.status=='paused' and c.plan.delivered==11)
 T.Command(c,'resume');assert(c.plan.delivered==11)
 `));
test('finite workflow validates all stages and rejects unsupported guide actions',()=>{
 const step={activity:'craft',recipe:'axe',prefab:null,count:1,placeId:null,useLast:false,reason:'做斧头'};
 const decision={reply:'开始准备',plan:null,command:null,workflow:{goal:'准备斧头再收木材',steps:[step]},tripSeconds:240,taskStatus:'ongoing',experiences:[]};
 const context={source:'chat',snapshot:{knownRecipes:['axe']}};
 assert.equal(validateDecision(decision,context),decision);
 for(const steps of [[{...step,recipe:'invented'}],[{...step,activity:'fish'}],Array(7).fill(step),[{...step,count:null}]])
  assert.throws(()=>validateDecision({...decision,workflow:{...decision.workflow,steps}},context));
 assert.throws(()=>validateDecision(decision,{...context,source:'autonomy'}));
 assert.throws(()=>validateDecision({...decision,plan:step},context));
});
test('bridge mirrors only game-confirmed stages and explicit terminal state',()=>{
 const state={task:{text:'旧后台任务'}};
 const snapshot={taskJournalVersion:1,taskJournal:{id:'t',goal:'收木材入库',status:'paused',index:2,steps:[{},{}]},plan:{activity:'store'},revision:4};
 syncTask(state,snapshot);assert.equal(state.task.text,'收木材入库');assert.equal(state.task.index,2);assert.equal(state.task.status,'paused');
 syncTask(state,{...snapshot,taskJournal:{...snapshot.taskJournal,status:'complete'}});assert.equal(state.task,null);
 const old={task:{text:'旧版任务',revision:1}};
 syncTask(old,{events:[{kind:'manual_command',detail:{revision:2,command:'stay'}}]});assert.equal(old.task.status,'paused');
 syncTask(old,{events:[{kind:'manual_command',detail:{revision:3,command:'cancel'}}]});assert.equal(old.task,null);
});
test('model complete cannot erase a real task, and late stage results carry a guard',async t=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'dst-continuity-'));t.after(()=>fs.rmSync(root,{force:true,recursive:true}));
 let resolve;
 const engine=new DecisionEngine({root,generate:()=>new Promise(r=>resolve=r)});
 const s={ready:true,session:'s',world:'w',shard:'1',owner:'o',revision:2,at:100,mode:'auto',ownerHere:true,
  companion:{inventory:[]},events:[],chats:[],observed:[],taskJournalVersion:1,
  taskJournal:{id:'task-1',goal:'两步目标',status:'active',index:1,steps:[{},{}]},plan:{activity:'collect'}};
 engine.tick(s);
 engine.tick({...s,at:101,taskJournal:{...s.taskJournal,index:2},plan:{activity:'store'}});
 resolve({reply:'',command:null,plan:null,workflow:null,taskStatus:'complete',tripSeconds:240,experiences:[]});
 await engine.sessions.get('s').pending;
 const saved=JSON.parse(fs.readFileSync(engine.file(s)));assert.equal(saved.task.index,2);
 assert.equal(engine.sessions.get('s').results[0].taskGuard.index,1);
});
test('missing common crafting materials trigger only a bounded daylight local search',()=>run(`
 local angle;PI=math.pi;Vector3=function(x,y,z)return {x=x,z=z}end
 package.preload.ai_inventory=function()return {}end
 package.preload.ai_resources=function()return {Name=function(v)return v end}end
 local C=(function()${source('ai_crafting.lua')}end)()
 local c=fixture();T.Accept(c,{activity='craft',recipe='axe',reason='斧头'},nil,'chat','斧头')
 c.inst.GetDistanceSqToPoint=function()return 100 end;c.MoveTo=function()return true end
 assert(C.Search(c,'flint'));for i=1,9 do clock=clock+21;C.Search(c,'flint')end
 assert(not C.Search(c,'flint') and c.material_searches.flint.index>8)
 T.Command(c,'resume');assert(C.Search(c,'flint'))
 assert(not C.Search(c,'mandrake'));TheWorld.state.isday=false;assert(not C.Search(c,'log'))
 `));
test('a paused build completion waits for the owner before advancing the queue',()=>run(`
 local c=fixture();T.Accept(c,nil,{goal='造箱再存货',steps={
 {activity='craft',recipe='treasurechest',count=1,reason='造箱'},{activity='store',reason='存货'}}},'chat')
 T.Command(c,'stay');c.plan.built=1;T.Complete(c,{built=1})
 assert(c.job.index==1 and c.job.status=='paused')
 T.Command(c,'resume');assert(c.job.index==2 and c.plan.activity=='store' and c.job.status=='active')
 `));
const managerSetup=`
 Class=function()local c={};c.__index=c;return c end
 package.preload.ai_policy=function()${source('ai_policy.lua')}end
 package.preload.ai_tasks=function()${source('ai_tasks.lua')}end
 package.preload.ai_memory=function()return {ApplyPlaces=function()end}end
 package.preload.ai_decisionguard=function()${source('ai_decisionguard.lua')}end
 package.preload.ai_social=function()${source('ai_social.lua')}end
 package.preload.ai_speechhistory=function()${source('ai_speechhistory.lua')}end
 for _,n in ipairs({'ai_capabilities','ai_inventory','ai_resources'})do package.preload[n]=function()return {}end end
 local Manager=(function()${source('components/aicompanionmanager.lua')}end)()
 local c=fixture();c.plan={activity='auto'};c.revision=2
 package.loaded.ai_social=nil;package.loaded.ai_speechhistory=nil
 local m=setmetatable({session='s',seen_results={},responses={},social=require('ai_social').New(0),bot={components={aicompanion=c}}},Manager)
 local function result(id,source)return {id=id,session='s',revision=2,source=source,expires=200,reply=''}end
 `;
test('actual Apply accepts a workflow but cannot complete it from a model assertion',()=>run(managerSetup+`
 local r=result('assign','chat');r.workflow={goal='先木材后存放',steps={collect(12),{activity='store',reason='入库'}}}
 r.tripSeconds=240;m:Apply(r)
 assert(c.job.index==1 and c.plan.count==12)
 local complete=result('fake-complete','autonomy');complete.taskStatus='complete';m:Apply(complete)
 assert(c.job.status=='active' and c.plan.count==12,'model complete is not local evidence')
 c.plan.delivered=12;T.Complete(c,{count=12});assert(c.plan.activity=='store')
 `));
test('actual Apply rejects a late autonomous plan after the final stage completes',()=>run(managerSetup+`
 T.Accept(c,collect(5),nil,'chat','收5木头')
 local late=result('late','autonomy');late.plan=collect(5)
 late.taskGuard={id=c.job.id,index=1,closed=false}
 c.plan.delivered=5;T.Complete(c,{count=5});m:Apply(late)
 assert(c.job.status=='complete' and c.plan.activity=='auto')
 `));
test('actual Apply rejects a chat plan from an earlier stage and emits a negative receipt',()=>run(managerSetup+`
 T.Accept(c,nil,{goal='收集再存放',steps={collect(5),{activity='store',reason='入库'}}},'chat')
 local late=result('late-chat','chat');late.plan=collect(5)
 late.taskGuard={id=c.job.id,index=1,closed=false}
 c.plan.delivered=5;T.Complete(c,{count=5});m:Apply(late)
 assert(c.job.index==2 and c.plan.activity=='store')
 assert(m.receipts[1].actionAccepted==false and m.responses[1].text:find('没有执行'))
 `));
test('a place-only update is also rejected if the task advanced before game application',()=>run(managerSetup+`
 T.Accept(c,nil,{goal='收集再存放',steps={collect(5),{activity='store',reason='入库'}}},'chat')
 local late=result('late-place','chat');late.placeUpdates={{id='mine',kind='place'}}
 late.taskGuard={id=c.job.id,index=1,closed=false}
 c.plan.delivered=5;T.Complete(c,{count=5});m:Apply(late)
 assert(m.receipts[1].actionAccepted==false and #late.placeUpdates==0)
 `));
test('a rejected original-game skill activation cannot be acknowledged as learned',()=>run(managerSetup+`
 package.preload.ai_skills=function()return {Learn=function()return false end}end
 T.Accept(c,collect(5),nil,'chat','保留旧工作');local old=c.job.id
 local r=result('unlearnable','chat');r.learnSkill='locked-node';r.plan=collect(20);r.reply='我学会了'
 m:Apply(r)
 assert(c.job.id==old and c.plan.count==5)
 assert(m.receipts[1].actionAccepted==false and m.responses[1].text:find('没有成功'))
 `));
test('actual component build events advance steps and its save hooks restore them',()=>run(`
 Class=function(ctor)local c={};c.__index=c;setmetatable(c,{__call=function(_,inst)local v=setmetatable({},c);ctor(v,inst);return v end});return c end
 package.preload.ai_tasks=function()${source('ai_tasks.lua')}end
 for _,n in ipairs({'ai_policy','ai_inventory','ai_life','ai_resources'})do package.preload[n]=function()return {}end end
 local Companion=(function()${source('components/aicompanion.lua')}end)()
 local function inst()
  local i={GUID=42,listeners={},GetPosition=function()return {x=3,z=4}end,
   components={skilltreeupdater={GetSkillXP=function()return 0 end,GetActivatedSkills=function()return {}end}}}
  i.ListenForEvent=function(_,name,fn)i.listeners[name]=fn end;return i
 end
 local i=inst();local c=Companion(i);c.ownerid='owner';c.Stop=function()end
 T.Accept(c,nil,{goal='两把斧头和木材',steps={
 {activity='craft',recipe='axe',count=2,reason='做斧头'},collect(10)}},'chat')
 i.listeners.builditem(nil,{recipe={name='axe',numtogive=1}});assert(c.plan.built==1 and c.job.index==1)
 local saved=c:OnSave();local i2=inst();local d=Companion(i2);d:OnLoad(saved)
 assert(d.plan==d.job.steps[1] and d.plan.built==1 and d.ownerid=='owner')
 i2.listeners.builditem(nil,{recipe={name='axe',numtogive=1}})
 assert(d.job.index==2 and d.plan.prefab=='log' and d.job.steps[1].built==2)
 `));
