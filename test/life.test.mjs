import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {DecisionEngine} from '../bridge/engine.mjs';
const s=()=>({ready:true,session:'living',world:'world',owner:'owner',shard:'1',revision:0,at:100,ownerHere:true,
 mode:'auto',companion:{inventory:[]},chats:[],observed:[],events:[]});
const decision=()=>({reply:'',command:null,plan:null,tripSeconds:240,taskStatus:'none',experiences:[]});
test('completed prerequisites wake the model before keepalive and events persist once',async t=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'dst-life-'));t.after(()=>fs.rmSync(root,{recursive:true,force:true}));
 let now=100000,calls=0,observed;
 const engine=new DecisionEngine({root,now:()=>now,generate:async i=>{calls++;observed=i;return decision();}});
 const a=s();engine.tick(a);await engine.sessions.get(a.session).pending;assert.equal(calls,1);
 now+=6000;const b={...a,at:106,events:[{id:1,at:105,kind:'build_success',detail:{recipe:'boards'}}]};
 engine.tick(b);await engine.sessions.get(a.session).pending;assert.equal(calls,2);assert.equal(observed.unprocessedActions[0].id,1);
 const again=engine.tick(b);assert.equal(again.actionAck,1);
 const files=fs.readdirSync(path.join(root,'state/actions'));assert.equal(fs.readFileSync(path.join(root,'state/actions',files[0]),'utf8').trim().split('\n').length,1);
});
test('local game chat is recorded once while QQ-origin chat is left for its QQ writer',async t=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'dst-life-chat-'));t.after(()=>fs.rmSync(root,{recursive:true,force:true}));let now=100000,records=[];
 const engine=new DecisionEngine({root,now:()=>now,generate:async()=>decision(),recordConversation:(...args)=>records.push(args)});
 t.after(()=>engine.close());const a={...s(),mode:'stay',chats:[{id:'local',text:'你好',revision:0,expires:200}]};
 engine.tick(a);await engine.sessions.get(a.session).pending;assert.equal(records.length,1);assert.equal(records[0][3].epoch,1);
 now+=2000;engine.tick({...a,at:102,chats:[{id:'remote',remoteId:'qq-1',text:'你好',revision:0,expires:200}]});await engine.sessions.get(a.session).pending;
 assert.equal(records.length,1);
});
test('model failure and superseded requests preserve unhandled events for the next decision',async t=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'dst-life-cancel-'));t.after(()=>fs.rmSync(root,{recursive:true,force:true}));
 let now=100000,release;
 const engine=new DecisionEngine({root,now:()=>now,generate:()=>new Promise(resolve=>{release=resolve;})});t.after(()=>engine.close());
 const a={...s(),actionEvents:[{id:1,at:99,kind:'build_success',detail:{recipe:'boards'}}]};
 engine.tick(a);engine.tick({...a,revision:1});release(decision());await engine.sessions.get(a.session).pending;
 const read=()=>JSON.parse(fs.readFileSync(engine.file(a),'utf8'));
 assert.equal(read().actionMemory.handled,0);
 now+=30000;engine.generate=async()=>{throw Error('provider unavailable');};engine.tick({...a,revision:1,at:130});await engine.sessions.get(a.session).pending;
 assert.equal(read().actionMemory.handled,0);
 let input;engine.generate=async i=>{input=i;return decision();};now+=50000;engine.tick({...a,revision:1,at:180});await engine.sessions.get(a.session).pending;
 assert.equal(input.unprocessedActions[0].id,1);assert.equal(read().actionMemory.handled,1);
});
