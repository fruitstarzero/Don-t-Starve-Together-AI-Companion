import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {DecisionEngine} from '../bridge/engine.mjs';
import {staleDecision} from '../bridge/decision-context.mjs';
const snapshot=()=>({ready:true,session:'fresh',world:'w',owner:'o',shard:'1',revision:0,at:100,ownerHere:true,
 mode:'stay',time:{phase:'day',season:'autumn',raining:false},companion:{inventory:[],health:100,maxHealth:100},chats:[],observed:[],events:[]});
test('a plan computed before nightfall is rejected while the owner gets an honest reply and keeps the task',async t=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'dst-fresh-'));t.after(()=>fs.rmSync(root,{recursive:true,force:true}));
 let finish;let now=10000;const engine=new DecisionEngine({root,now:()=>now,generate:()=>new Promise(r=>finish=r)});
 const s=snapshot();s.chats=[{id:'chat',text:'去探索',revision:0,expires:285}];engine.tick(s);
 now+=2000;engine.tick({...s,at:102,time:{...s.time,phase:'night'}});
 finish({reply:'我开始探索了',command:null,plan:{activity:'explore',prefab:null,recipe:null,count:null,reason:'白天探索'},tripSeconds:240,taskStatus:'ongoing',experiences:[]});
 await engine.sessions.get(s.session).pending;
 const result=engine.sessions.get(s.session).results[0];assert.equal(result.plan,null);assert.equal(result.staleAction,true);
 assert.doesNotMatch(result.reply,/我开始探索了/);
});
test('chat actions cannot replace a task that advanced while the model was thinking',()=>{
 const s={...snapshot(),taskJournalVersion:1,taskJournal:{id:'job',index:1,status:'active'}};
 assert.equal(staleDecision({plan:{activity:'explore'}},s,{...s,taskJournal:{...s.taskJournal,index:2}},100),true);
 assert.equal(staleDecision({reply:'讲解步骤'},s,{...s,taskJournal:{...s.taskJournal,index:2}},100),false);
});
test('game rejection replaces the proposed reply and never commits its memories or diary',async t=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'dst-receipt-'));t.after(()=>fs.rmSync(root,{recursive:true,force:true}));
 const diary=[];const engine=new DecisionEngine({root,diary:{context:()=>[],add:d=>diary.push(d)},generate:async()=>({
  reply:'我开始探索了',command:null,plan:{activity:'explore',prefab:null,recipe:null,count:null,reason:'探索'},tripSeconds:240,taskStatus:'ongoing',
  experiences:[{id:'route',operation:'upsert',text:'已经开始探索',evidence:'模型方案',confidence:.6,scope:'world'}],
  memories:[{id:'exploring',operation:'upsert',kind:'fact',text:'开始探索',evidence:'模型方案',anchor:null,targetId:null}],
  diary:{title:'探索',mood:'期待',text:'准备开始探索的感受',tags:['游戏']}})});
 const s=snapshot();s.chats=[{id:'chat',text:'去探索',revision:0,expires:285}];engine.tick(s);await engine.sessions.get(s.session).pending;
 const result=engine.sessions.get(s.session).results[0];let state=JSON.parse(fs.readFileSync(engine.file(s)));
 assert.doesNotMatch(state.turns.at(-1).text,/我开始探索了/);assert.equal(state.experiences.length,0);
 engine.tick({...s,at:102,chats:[],responses:[{id:result.id,source:'chat',text:'旧方案没有执行',actionAccepted:false,at:102}]});
 state=JSON.parse(fs.readFileSync(engine.file(s)));assert.equal(state.turns.at(-1).text,'旧方案没有执行');
 assert.equal(state.experiences.length,0);assert.equal(state.memories.length,0);assert.equal(diary.length,0);
});
test('accepted effects survive a bridge restart and a replayed receipt cannot add the diary twice',async t=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'dst-accept-'));t.after(()=>fs.rmSync(root,{recursive:true,force:true}));
 const entries=[];const diary={context:()=>[],add:d=>entries.push(d)};
 const engine=new DecisionEngine({root,diary,generate:async()=>({reply:'开始准备探索。',command:null,
  plan:{activity:'explore',prefab:null,recipe:null,count:null,reason:'探索'},tripSeconds:240,taskStatus:'ongoing',
  experiences:[{id:'route',operation:'upsert',text:'这条路可以先探索',evidence:'当前白天且安全',confidence:.6,scope:'world'}],
  diary:{title:'计划',mood:'期待',text:'想一起看看附近',tags:['游戏']}})});
 const s=snapshot();s.chats=[{id:'chat',text:'去探索',revision:0,expires:285}];engine.tick(s);await engine.sessions.get(s.session).pending;
 const result=engine.sessions.get(s.session).results[0];assert.equal(entries.length,0);
 const restarted=new DecisionEngine({root,diary,generate:async()=>{throw Error('no new request');}});
 const acknowledged={...s,chats:[],receipts:[{id:result.id,text:result.reply,actionAccepted:true,at:101}]};
 restarted.tick(acknowledged);restarted.tick(acknowledged);
 const state=JSON.parse(fs.readFileSync(engine.file(s)));assert.equal(state.experiences[0].id,'route');
 assert.equal(state.turns.at(-1).text,result.reply);assert.equal(entries.length,1);assert.equal(state.pendingDecisions.length,0);
});
