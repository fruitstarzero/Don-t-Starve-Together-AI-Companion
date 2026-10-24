import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {lua,lauxlib,lualib,to_luastring,to_jsstring} from 'fengari';
import {DecisionEngine} from '../bridge/engine.mjs';
import {anchorProject,loadState,updateProjects} from '../bridge/memory.mjs';
import luaparse from 'luaparse';
const source=f=>fs.readFileSync(new URL('../mod/scripts/'+f,import.meta.url),'utf8');
function run(code){const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);const status=lauxlib.luaL_dostring(L,to_luastring(`package.preload.ai_reservations=function()${fs.readFileSync(new URL('../mod/scripts/ai_reservations.lua',import.meta.url),'utf8')}end
 package.preload.ai_navigation=function()${fs.readFileSync(new URL('../mod/scripts/ai_navigation.lua',import.meta.url),'utf8')}end
package.preload.ai_actions=function()${fs.readFileSync(new URL('../mod/scripts/ai_actions.lua',import.meta.url),'utf8')}end
package.preload.ai_procurement=function() ${source('ai_procurement.lua')} end\npackage.preload.ai_tasks=function() ${source('ai_tasks.lua')} end\n`+code));const error=status?to_jsstring(lua.lua_tostring(L,-1)):undefined;lua.lua_close(L);assert.equal(status,lua.LUA_OK,error);}
const builderSource=fs.readFileSync(new URL('../reference/scripts/components/builder.lua',import.meta.url),'utf8');
const builderAst=luaparse.parse(builderSource,{luaVersion:'5.1',ranges:true});
const buildingMethods=['BufferBuild','MakeRecipeAtPoint'].map(name=>{
 const n=builderAst.body.find(n=>n.type==='FunctionDeclaration'&&n.identifier?.identifier?.name===name);
 return builderSource.slice(...n.range);
}).join('\n');

test('ordinary in-game questions leave a running action and mode intact',()=>run(`
 Class=function(ctor)local c={};c.__index=c;return c end
 GetTime=function()return 100 end;TheShard={GetShardId=function()return '1'end}
 for _,name in ipairs({'ai_policy','ai_social','ai_memory','ai_capabilities','ai_speechhistory','ai_resources'})do
   package.preload[name]=function()return {}end
 end
 package.loaded.ai_policy={commands={}};package.loaded.ai_memory={IsHomeDeclaration=function()return false end}
 package.preload.ai_inventory=function()return {}end
 local Manager=(function()${source('components/aicompanionmanager.lua')}end)()
 local stopped=0;local c={revision=2,mode='auto',pending={action='CHOP'},Stop=function()stopped=stopped+1 end}
 local m=setmetatable({chats={},chatsequence=0,session='s',bot={components={aicompanion=c}}},Manager)
 m.Authorized=function()return true end;m.SendStatus=function()end
 m:Command({GetPosition=function()return {x=1,z=2}end},'chat','暖石怎么做？')
 assert(stopped==0 and c.pending.action=='CHOP' and c.mode=='auto','question must not freeze ongoing work')
 assert(#m.chats==1)
 `));

test('answer-only chat preserves the previously assigned task',async t=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'dst-reliability-'));t.after(()=>fs.rmSync(root,{recursive:true,force:true}));
 const e=new DecisionEngine({root,generate:async()=>({reply:'先准备暖石。',command:null,plan:null,taskStatus:'none',tripSeconds:240,experiences:[],memories:[],diary:null})});
 const s={ready:true,session:'s',world:'w',shard:'1',owner:'o',revision:3,at:100,ownerHere:true,mode:'stay',
  companion:{inventory:[]},events:[],observed:[],chats:[{id:'q',text:'冬天怎么办？',revision:3,expires:300}]};
 fs.mkdirSync(path.dirname(e.file(s)),{recursive:true});fs.writeFileSync(e.file(s),JSON.stringify({task:{text:'收集木头',revision:2},turns:[]}));
 e.tick(s);await e.sessions.get('s').pending;
 assert.equal(JSON.parse(fs.readFileSync(e.file(s))).task?.text,'收集木头');
});

test('crafting resolves intermediate boards, keeps the root goal and rejects cycles',()=>run(`
 local bag={log=12};local made={};local problems={}
 package.preload.ai_inventory=function()return {Count=function(_,p)return bag[p] or 0 end,TakeNeeded=function()return false end}end
 package.preload.ai_resources=function()return {CheckRecipe=function()return true end,Name=function(p)return p end}end
 local C=(function()${source('ai_crafting.lua')}end)()
 AllRecipes={treasurechest={name='treasurechest',placer=true,ingredients={{type='boards',amount=3}}},
   boards={name='boards',ingredients={{type='log',amount=4}}},loop={name='loop',ingredients={{type='loop',amount=1}}}}
 local c={plan={activity='craft',recipe='treasurechest'},inst={components={builder={
   KnowsRecipe=function()return true end,IsBuildBuffered=function()return false end}}},
   Resources=function()return false end,Problem=function(_,kind)table.insert(problems,kind)end,
   Craft=function(_,name)
     for _,v in ipairs(AllRecipes[name].ingredients)do assert((bag[v.type] or 0)>=v.amount);bag[v.type]=bag[v.type]-v.amount end
     bag[name]=(bag[name] or 0)+1;table.insert(made,name);return true
   end}
 for i=1,4 do assert(C.Step(c,'treasurechest'))end
 assert(table.concat(made,',')=='boards,boards,boards,treasurechest')
 assert(bag.log==0 and bag.boards==0 and bag.treasurechest==1 and c.plan.recipe=='treasurechest')
 assert(not C.Step(c,'loop') and #problems>0,'cyclic recipes must not loop forever')
 `));

test('withdrawals preserve a stack sample and recheck real capacity',()=>run(`
 package.preload.ai_policy=function()return {}end
 local I=(function()${source('ai_inventory.lua')}end)()
 local size=20;local capacity=50
 local item={prefab='log',components={stackable={StackSize=function()return size end}}}
 local box={components={container={slots={item}}}}
 local c={inst={components={inventory={CanAcceptCount=function()return capacity end}}}}
 assert(I.TakeCount(c,box,item,20,true)==19)
 capacity=2;assert(I.TakeCount(c,box,item,10,true)==2)
 size=1;capacity=50;assert(I.TakeCount(c,box,item,1,true)==0)
 assert(I.TakeCount(c,box,item,1,false)==1,'explicit last-item permission must work')
 `));

test('garden care harvests only mature plants and plants existing empty soil',()=>run(`
 local planted=false;local harvested=false;local chosen
 ACTIONS={PICK='pick',PLANTSOIL='plant',INTERACT_WITH='tend'}
 GetTime=function()return 100 end;TheShard={GetShardId=function()return '1'end}
 Vector3=function(x,y,z)return {x=x,z=z}end
 local seed={components={farmplantable={}}}
 package.preload.ai_inventory=function()return {Find=function(_,fn)if fn(seed)then return seed end end,TakeNeeded=function()return false end}end
 local J=(function()${source('ai_projects.lua')}end)()
 local mature={HasTag=function(_,tag)return tag=='farm_plant'end,GetDistanceSqToPoint=function()return 0 end,
   components={pickable={CanBePicked=function()return not harvested end}}}
 local soil={prefab='farm_soil',GetDistanceSqToPoint=function()return 0 end,components={},HasTag=function()return false end}
 local wild={prefab='grass',GetDistanceSqToPoint=function()return 0 end,HasTag=function()return false end,
   components={pickable={CanBePicked=function()return true end}}}
 local c={projects={},inst={GetDistanceSqToPoint=function()return 0 end},
   Find=function(_,fn)for _,e in ipairs({wild,mature,soil})do if fn(e)then return e end end end,
   Act=function(_,action)chosen=action;return true end}
 local p=J.RememberGarden(c,{x=2,z=3},'actual planted area')
 assert(p and p.position.shard=='1')
 assert(J.Garden(c,p) and chosen=='pick')
 harvested=true;assert(J.Garden(c,p) and chosen=='plant')
 J.Apply(c,{{id=p.id,operation='remove'}});assert(next(c.projects)==nil)
 assert(J.RememberGarden(c,{x=2,z=3},'seen again')==nil,'cancelled garden must not reappear on observation')
 J.Apply(c,{{id=p.id,kind='garden',operation='upsert',position=p.position,text='恢复照料',evidence='主人重新安排'}})
 assert(c.projects[p.id] and J.RememberGarden(c,{x=2,z=3},'seen again'))
 `));

test('life-saving precious food does not unlock crafting or accept non-food',()=>run(`
 local R=(function()${source('ai_resources.lua')}end)()
 local c={inst={components={inventory={ForEachItem=function()end},eater={CanEat=function()return true end}}}}
 local item={prefab='mandrake',components={edible={GetHealth=function()return 60 end,GetHunger=function()return 75 end}}}
 assert(not R.CanEat(c,item,false));assert(R.CanEat(c,item,true));assert(not R.CanUse(c,'mandrake',1))
 assert(not R.CanEat(c,{prefab='axe',components={}},true))
 `));

test('long-term project memory anchors to the original message and supports cancellation',()=>{
 const s={shard:'1',companion:{home:{x:9,z:8}},observed:[{id:4,x:2,z:3}]};
 const p=anchorProject({id:'garden',kind:'garden',operation:'upsert',anchor:'speaker'},s,{context:{shard:'1',speaker:{x:10,z:20}}});
 assert.deepEqual(p.position,{x:10,z:20,shard:'1'});
 const state=loadState();updateProjects(state,[p]);assert.equal(state.projects.length,1);
 updateProjects(state,[{id:'garden',operation:'remove'}]);assert.equal(state.projects.length,0);
 assert.throws(()=>anchorProject({id:'bad',kind:'garden',anchor:'observed',targetId:999},s));
});

test('buildings use the installed vanilla buffering and placement methods once',()=>run(`
 Class=function()local c={};c.__index=c;return c end;PI=math.pi;GetTime=function()return 100 end
 Vector3=function(x,y,z)return setmetatable({x=x,z=z},{__add=function(a,b)return {x=a.x+b.x,z=a.z+b.z}end})end
 TheWorld={Map={CanDeployRecipeAtPoint=function()return true end}}
 package.preload.ai_policy=function()return {}end;package.preload.ai_inventory=function()return {}end
 package.preload.ai_life=function()return {}end;package.preload.ai_resources=function()return {CheckRecipe=function()return true end}end
 package.preload.ai_crafting=function()${source('ai_crafting.lua')}end
 local Companion=(function()${source('components/aicompanion.lua')}end)()
 local buffered=false;local spent=0
 local recipe={name='treasurechest',placer=true,ingredients={{type='boards',amount=3}}}
 AllRecipes={treasurechest=recipe};GetValidRecipe=function()return recipe end;CanPrototypeRecipe=function()return true end
 local Builder={};${buildingMethods}
 local inst={components={},GetPosition=function()return Vector3(0,0,0)end}
 inst.components.inventory={IsOpenedBy=function()return true end,Has=function()return true,3 end}
 local b=setmetatable({inst=inst},{__index=Builder});inst.components.builder=b
 b.IsBuildBuffered=function()return buffered end;b.KnowsRecipe=function()return true end;b.CanLearn=function()return true end
 b.HasIngredients=function()return true end;b.GetIngredients=function()return {},false end
 b.CheckIngredientsForMimic=function()return false end;b.AddRecipe=function()end
 b.RemoveIngredients=function()spent=spent+1 end;b.SetBuildBuffered=function(_,name,v)buffered=v end
 b.MakeRecipe=function()inst.bufferedaction={};return true end
 inst.components.locomotor={};inst.sg={HasStateTag=function()return false end}
 local c=setmetatable({inst=inst,Problem=function()end},Companion)
 assert(c:Craft('treasurechest'),'actual vanilla MakeRecipeAtPoint requires buffering')
 assert(spent==1 and buffered)
 local key=c.pending.buildkey
 c.build_failed={[key]=200}
 assert(c:Craft('treasurechest') and spent==1,'buffered materials must never be paid twice')
 assert(c.pending.buildkey~=key,'blocked building position must rotate to another valid point')
 `));

test('technology routing ignores inadequate remembered stations',()=>run(`
 Vector3=function(x,y,z)return {x=x,z=z}end
 CanPrototypeRecipe=function(level,trees)return (trees.SCIENCE or 0)>=(level.SCIENCE or 0) end
 package.preload.ai_inventory=function()return {Count=function()return 0 end,TakeNeeded=function()return false end}end
 package.preload.ai_resources=function()return {CheckRecipe=function()return true end,Name=function(p)return p end}end
 AllRecipes={heatrock={name='heatrock',level={SCIENCE=2},ingredients={}},
  researchlab2={name='researchlab2',level={SCIENCE=1},ingredients={},placer=true}}
 local built,moved=0,0
 local c={worksites={a={kind='science',x=100,z=0,trees={SCIENCE=1}},b={kind='science',x=-100,z=0,trees={SCIENCE=1}}},
  inst={GetDistanceSqToPoint=function()return 10000 end,components={builder={IsBuildBuffered=function()return false end,
   KnowsRecipe=function(_,r)return r.name=='researchlab2'end,CanLearn=function()return true end,accessible_tech_trees={SCIENCE=0}}}},
  Find=function()end,Resources=function()return false end,MoveTo=function()moved=moved+1;return true end,
  Problem=function()end,Craft=function(_,name)assert(name=='researchlab2');built=built+1;return true end}
 local C=(function()${source('ai_crafting.lua')}end)()
 assert(C.Step(c,'heatrock') and built==1 and moved==0)
 `));

test('resource-tool dependency cycles terminate across callbacks',()=>run(`
 package.preload.ai_inventory=function()return {Count=function()return 0 end,TakeNeeded=function()return false end}end
 package.preload.ai_resources=function()return {CheckRecipe=function()return true end,Name=function(p)return p end}end
 AllRecipes={pickaxe={name='pickaxe',ingredients={{type='flint',amount=2}}}}
 local calls=0;local C=(function()${source('ai_crafting.lua')}end)()
 local c={inst={components={builder={KnowsRecipe=function()return true end,IsBuildBuffered=function()return false end}}},
  Problem=function()end,Resources=function(self)calls=calls+1;return C.Step(self,'pickaxe')end}
 assert(not C.Step(c,'pickaxe') and calls==1)
 `));

test('temporary cargo uses bounded normal drops and excludes survival gear',()=>run(`
 local bag={{id=1,prefab='axe',gear=true},{id=2,prefab='berries',food=true},{id=3,prefab='nitre',count=1}}
 package.preload.ai_inventory=function()return {Items=function()return bag end,Reserves=function()return {}end}end
 package.preload.ai_safety=function()return {Risk=function()return 0 end}end
 TheWorld={state={isnight=false}};ACTIONS={DROP='drop'};Ents={[3]={components={inventoryitem={}}}}
 local calls=0;local inv={GetNumSlots=function()return 16 end,NumItems=function()return 16 end,
   Has=function()return false end,IsHolding=function()return true end}
 local c={home={},inst={GetDistanceSqToPoint=function()return 0 end,GetPosition=function()return {}end,components={inventory=inv}},
  Scan=function()return {}end,
  Act=function(_,action,_,item,_,options)assert(action=='drop' and item==Ents[3] and options.wholestack);calls=calls+1;return true end}
 local S=(function()${source('ai_staging.lua')}end)()
 assert(S.MakeRoom(c) and calls==1)
 S.Record(c,{GUID=1,prefab='nitre',count=1},{x=0,z=0});S.Record(c,{GUID=2,prefab='nitre',count=1},{x=0,z=0})
 assert(not S.MakeRoom(c) and #c.staged_cargo==2)
 c.staged_cargo={};c.Scan=function()return {{prefab='mole'}}end
 assert(not S.MakeRoom(c),'do not put bait on the floor beside a scavenger')
 `));

test('actual material lookup can use the last sample in a survival emergency',()=>run(`
 local hunger=.5;TheWorld={state={isday=true}}
 package.preload.ai_policy=function()return {}end;package.preload.ai_resources=function()return {Refresh=function()end}end
 local item={prefab='berries',components={stackable={StackSize=function()return 1 end}}}
 local box={components={container={slots={item}}}}
 local inv={CanAcceptCount=function()return 1 end}
 local c={inst={components={inventory=inv,hunger={GetPercent=function()return hunger end},health={GetPercent=function()return 1 end}}},
   TransferAction=function(_,_,_,count,take,_,keep)assert(count==1 and take and not keep);return true end}
 local I=(function()${source('ai_inventory.lua')}end)();I.NearChests=function()return {box}end
 assert(not I.TakeNeeded(c,'berries',1))
 hunger=.04;assert(I.TakeNeeded(c,'berries',1))
 `));

test('full bags can refine into an existing stack or a slot actually freed by ingredients',()=>run(`
 local hasOutput=false;local size=4
 local input={components={stackable={StackSize=function()return size end}}}
 package.preload.ai_inventory=function()return {Find=function()if hasOutput then return {}end end}end
 package.preload.ai_resources=function()return {}end
 local c={inst={components={inventory={IsFull=function()return true end,CanAcceptCount=function()return 1 end,
   GetItemSlot=function()return 1 end},builder={GetIngredients=function()return {log={[input]=4}}end}}}}
 local C=(function()${source('ai_crafting.lua')}end)()
 local recipe={name='boards'}
 assert(C.OutputFits(c,recipe),'consuming the last four logs frees a slot')
 size=8;assert(not C.OutputFits(c,recipe),'do not drop new boards when the log stack remains')
 hasOutput=true;assert(C.OutputFits(c,recipe),'existing boards accept the next board even with all slots occupied')
 `));

test('failed model requests are explicitly marked and preserve the old task',async t=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'dst-reliability-'));t.after(()=>fs.rmSync(root,{recursive:true,force:true}));
 const e=new DecisionEngine({root,generate:async()=>{throw Error('usage limit');}});
 const s={ready:true,session:'s',world:'w',shard:'1',owner:'o',revision:1,at:100,ownerHere:true,mode:'stay',
  companion:{inventory:[]},events:[],observed:[],chats:[{id:'q',text:'你好',revision:1,expires:300}]};
 e.tick(s);await e.sessions.get('s').pending;
 assert.equal(e.sessions.get('s').results[0].modelError,true);
 assert.match(e.sessions.get('s').error,/usage limit/);
});

test('collection credits actual deposits only toward the same ongoing goal',()=>run(`
 Class=function()local c={};c.__index=c;return c end;GetTime=function()return 100 end
 for _,name in ipairs({'ai_policy','ai_inventory','ai_life','ai_resources'})do package.preload[name]=function()return {}end end
 local Companion=(function()${source('components/aicompanion.lua')}end)()
 local c=setmetatable({plan={activity='collect',prefab='log',count=30},events={}},Companion)
 c:Event('transfer_success',{prefab='log',take=false,count=10});assert(c.plan.delivered==10)
 c:Event('transfer_success',{prefab='log',take=true,count=3});assert(c.plan.delivered==10)
 c:Event('transfer_success',{prefab='rocks',take=false,count=5});assert(c.plan.delivered==10)
 `));
