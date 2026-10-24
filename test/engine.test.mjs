import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {DecisionEngine} from '../bridge/engine.mjs';
import {createServer} from '../bridge/server.mjs';
const snapshot=()=>({ready:true,session:'test-1',owner:'owner',world:'123',shard:'1',revision:0,sequence:1,
 at:30,ownerHere:true,mode:'auto',companion:{inventory:[]},observed:[],events:[],chats:[],craftable:['axe'],knownRecipes:['axe']});
const decision=()=>({reply:'',command:null,plan:{activity:'collect',prefab:'log',recipe:null,count:20,reason:'为下一项制作准备木材'},
 tripSeconds:240,taskStatus:'ongoing',experiences:[],diary:null});
function fixture(t,generate){const root=fs.mkdtempSync(path.join(os.tmpdir(),'dst-ai-test-'));t.after(()=>fs.rmSync(root,{recursive:true,force:true}));return new DecisionEngine({root,generate});}
test('ordinary tasks do not automatically become habits; replay is idempotent',async t=>{
 let n=0;const e=fixture(t,async()=>{n++;return decision();});const s=snapshot();
 s.chats=[{id:'chat-1',text:'收集木头',revision:0,expires:210}];e.tick(s);await e.sessions.get(s.session).pending;
 const r=e.tick(s);assert.equal(r.results.length,1);assert.equal(n,1);
 const saved=JSON.parse(fs.readFileSync(e.file(s)));assert.deepEqual(saved.experiences,[]);
 e.tick({...s,responses:[{id:r.results[0].id}]});assert.equal(e.sessions.get(s.session).results.length,0);
});
test('new manual mode cancels an older model answer',async t=>{
 let resolve;const e=fixture(t,()=>new Promise(r=>resolve=r));const s=snapshot();e.tick(s);
 e.tick({...s,revision:1,mode:'stay'});resolve(decision());await e.sessions.get(s.session).pending;
 assert.equal(e.sessions.get(s.session).results.length,0);
});
test('switching to follow cancels the old request without showing model failure or adding backoff',async t=>{
 const e=fixture(t,(_,signal)=>new Promise((resolve,reject)=>signal.addEventListener('abort',()=>reject(Error('Cancelled')),{once:true})));
 const s=snapshot();e.tick(s);
 const follow={...s,revision:1,mode:'follow'};e.tick(follow);await e.sessions.get(s.session).pending;
 const result=e.tick(follow);
 assert.equal(result.health,'ready','expected cancellation must not show the model-error banner');
 assert.equal(e.sessions.get(s.session).failures,0,'expected cancellation must not count as provider failure');
 assert.equal(e.sessions.get(s.session).results.length,0);
});
test('a provider failure mentioning cancellation still reports failure when our signal was not aborted',async t=>{
 const e=fixture(t,async()=>{throw Error('Cancelled by provider');});const s=snapshot();e.tick(s);
 await e.sessions.get(s.session).pending;
 assert.equal(e.tick(s).health,'model_error');assert.equal(e.sessions.get(s.session).failures,1);
 assert.match(e.sessions.get(s.session).error,/provider/);
});
test('cancelled tasks do not return when autonomy resumes; known places reach the model',async t=>{
 let observed;const e=fixture(t,async input=>{observed=input;return decision();});const s=snapshot();
 fs.mkdirSync(path.dirname(e.file(s)),{recursive:true});fs.writeFileSync(e.file(s),JSON.stringify({experiences:[],turns:[],task:{text:'旧任务',revision:1},places:[{id:20,prefab:'treasurechest',x:1,z:2}]}));
 s.revision=3;s.events=[{kind:'manual_command',detail:{revision:2,command:'cancel'}}];
 e.tick(s);await e.sessions.get(s.session).pending;
 assert.equal(observed.currentTask,null);assert.equal(observed.knownPlaces[0].id,20);
});
test('autonomous decisions cannot change follow mode or invent actions',async t=>{
 const e=fixture(t,async()=>({...decision(),command:'follow',plan:null}));const s=snapshot();e.tick(s);await e.sessions.get(s.session).pending;
 assert.match(e.sessions.get(s.session).error,/manual mode/);assert.equal(e.sessions.get(s.session).results.length,0);
});
test('experience can be revised and removed only by explicit model proposal',async t=>{
 let n=0;const e=fixture(t,async()=>({...decision(),experiences:n++===0?[{id:'base-wood',operation:'upsert',text:'此世界木材优先放木箱，出远门时另行判断',evidence:'看见两个已按木材分类的箱子',confidence:.7,scope:'world'}]:[{id:'base-wood',operation:'remove',text:'',evidence:'主人改变了分类',confidence:1,scope:'world'}]}));
 const s=snapshot();s.chats=[{id:'c1',text:'整理',revision:0,expires:210}];e.tick(s);await e.sessions.get(s.session).pending;
 let r=e.sessions.get(s.session).results[0];e.tick({...s,chats:[],receipts:[{id:r.id,text:r.reply,actionAccepted:true}]});
 assert.equal(JSON.parse(fs.readFileSync(e.file(s))).experiences.length,1);
 s.revision=1;s.chats=[{id:'c2',text:'改分类',revision:1,expires:210}];e.tick(s);await e.sessions.get(s.session).pending;
 r=e.sessions.get(s.session).results[0];e.tick({...s,chats:[],receipts:[{id:r.id,text:r.reply,actionAccepted:true}]});
 assert.equal(JSON.parse(fs.readFileSync(e.file(s))).experiences.length,0);
});
test('local HTTP rejects browser origins, missing tokens and other hosts',async t=>{
 const e=fixture(t,async()=>decision());const server=createServer({token:'test-token',engine:e,port:0});
 await new Promise(r=>server.listen(0,'127.0.0.1',r));t.after(()=>server.close());const url=`http://127.0.0.1:${server.address().port}`;
 assert.equal((await fetch(url+'/v1/tick',{method:'POST',body:JSON.stringify({token:'wrong',snapshot:snapshot()})})).status,403);
 assert.equal((await fetch(url+'/v1/tick',{method:'POST',headers:{origin:'https://example.com'},body:'{}'})).status,403);
 assert.equal((await fetch(url+'/v1/tick',{method:'POST',body:JSON.stringify({token:'test-token',snapshot:snapshot()})})).status,200);
});
