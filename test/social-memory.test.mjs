import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {lua,lauxlib,lualib,to_luastring,to_jsstring} from 'fengari';
import {DecisionEngine} from '../bridge/engine.mjs';
import {anchorMemory} from '../bridge/memory.mjs';
import {gameKnowledge} from '../bridge/knowledge.mjs';

const s=()=>({ready:true,session:'social-test',owner:'owner',world:'world',shard:'1',revision:0,
 at:100,ownerHere:true,mode:'follow',player:{x:10,z:20},companion:{inventory:[]},
 observed:[],events:[],chats:[],craftable:[],knownRecipes:[],
 social:{candidate:{id:'notice-1',kind:'idle',at:100,expires:280},canSpeak:true}});
const d=()=>({reply:'今天一起慢慢逛吧。',command:null,plan:null,tripSeconds:240,
 taskStatus:'none',learnSkill:null,experiences:[],memories:[],diary:null});
function fixture(t,generate){const root=fs.mkdtempSync(path.join(os.tmpdir(),'dst-social-'));t.after(()=>fs.rmSync(root,{recursive:true,force:true}));return new DecisionEngine({root,generate});}
function runLua(file,body){const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);
 const code=`local M=(function() ${fs.readFileSync(new URL(file,import.meta.url),'utf8')} end)()\n${body}`;
 const status=lauxlib.luaL_dostring(L,to_luastring(code));const error=status?to_jsstring(lua.lua_tostring(L,-1)):undefined;lua.lua_close(L);assert.equal(status,lua.LUA_OK,error);}

test('social trigger speaks in follow mode once and never clears the current task',async t=>{
 let calls=0;const e=fixture(t,async input=>{calls++;assert.equal(input.source,'social');return d();});const snap=s();
 fs.mkdirSync(path.dirname(e.file(snap)),{recursive:true});fs.writeFileSync(e.file(snap),JSON.stringify({experiences:[],turns:[],task:{text:'收集木头',revision:0},places:[]}));
 e.tick(snap);await e.sessions.get(snap.session).pending;
 assert.equal(calls,1);const r=e.tick(snap);assert.equal(r.results[0].source,'social');assert.equal(r.results[0].speechId,'notice-1');
 assert.equal(JSON.parse(fs.readFileSync(e.file(snap))).task.text,'收集木头');
 e.tick(snap);assert.equal(calls,1);
});
test('social model cannot change actions or learn skills',async t=>{
 const e=fixture(t,async()=>({...d(),plan:{activity:'collect',prefab:'log',recipe:null,count:1,reason:'越权'}}));const snap=s();
 e.tick(snap);await e.sessions.get(snap.session).pending;assert.match(e.sessions.get(snap.session).error,/social/i);assert.equal(e.sessions.get(snap.session).results.length,0);
});
test('important location anchors use the original message, survive reload, and reject invented positions',async t=>{
 const e=fixture(t,async()=>({...d(),reply:'记下了。',memories:[{id:'home',operation:'upsert',kind:'place',text:'我们的家',evidence:'主人明确说家在这里',anchor:'speaker',targetId:null}]}));
 const snap=s();snap.social=null;snap.chats=[{id:'home-chat',text:'家在这里',revision:0,expires:280,context:{speaker:{x:7,z:9},shard:'1'}}];
 e.tick(snap);await e.sessions.get(snap.session).pending;
 const accepted=e.sessions.get(snap.session).results[0];
 const result=e.tick({...snap,chats:[],receipts:[{id:accepted.id,text:accepted.reply,actionAccepted:true}]}).results[0]||accepted;
 const saved=JSON.parse(fs.readFileSync(e.file(snap)));assert.deepEqual(saved.memories[0].position,{x:7,z:9,shard:'1'});
 assert.deepEqual(result.speakerPosition,{x:7,z:9});
 let seen;const reloaded=new DecisionEngine({root:e.root,generate:async input=>{seen=input;return {...d(),reply:''};}});
 const later=s();later.social.candidate.id='notice-2';reloaded.tick(later);await reloaded.sessions.get(later.session).pending;
 assert.equal(seen.importantMemories[0].id,'home');
});
test('Lua speech gate limits repeats and lets the model remain silent',()=>runLua('../mod/scripts/ai_social.lua',`
 local state=M.New(0)
 local facts={near=true,safe=true,hunger=1,health=1,phase='day',events={}}
 assert(M.Observe(state,facts,10).candidate==nil)
 local notice=M.Observe(state,facts,400).candidate;assert(notice and notice.kind=='idle')
 assert(M.Accept(state,notice.id,'在你旁边看看风景。',400))
 assert(not M.Accept(state,notice.id,'重复',401))
 assert(M.Observe(state,facts,450).candidate==nil)
 facts.health=.2
 local urgent=M.Observe(state,facts,451).candidate;assert(urgent and urgent.urgent)
 assert(M.Accept(state,urgent.id,'我先撤一下，需要疗伤。',451))
 facts.health=1
 assert(M.Observe(state,facts,500).candidate==nil)
 facts.health=.2
 assert((M.Observe(state,facts,600).candidate or {}).kind~='health','same urgent topic cannot repeat within its cooldown')
 `));
test('home declarations exclude questions, negation and examples',()=>runLua('../mod/scripts/ai_memory.lua',`
 assert(M.IsHomeDeclaration('家在这里'))
 assert(M.IsHomeDeclaration('记住，这里是我们的家。'))
 assert(not M.IsHomeDeclaration('假设我说家在这里'))
 assert(not M.IsHomeDeclaration('家在这里吗？'))
 assert(not M.IsHomeDeclaration('家不在这里'))
 `));
test('location memory rejects invented, nonvisible and cross-shard anchors',()=>{
 const snap=s(),m={id:'mine',kind:'place',operation:'upsert',anchor:'observed',targetId:999};
 assert.throws(()=>anchorMemory(m,snap,null),/anchor/);
 assert.throws(()=>anchorMemory({...m,anchor:'speaker'},snap,null),/anchor/);
 assert.throws(()=>anchorMemory({...m,anchor:'speaker'},snap,{context:{speaker:{x:1,z:2},shard:'2'}}),/shard/);
 snap.observed=[{id:999,x:3,z:4}];assert.deepEqual(anchorMemory(m,snap,null).position,{x:3,z:4,shard:'1'});
});
test('game-confirmed home memory persists even while the model is idle',t=>{
 const e=fixture(t,async()=>{throw Error('Should not call the model');}),snap=s();snap.social=null;
 snap.companion.homeMemory={id:'home',kind:'place',text:'家',position:{x:9,z:11,shard:'1'}};
 e.tick(snap);assert.equal(JSON.parse(fs.readFileSync(e.file(snap))).memories[0].position.x,9);
});
test('mod guidance distinguishes real component support from unsupported custom UI',()=>{
 const knowledge=gameKnowledge({enabledMods:[{id:'workshop-3223103565',name:'sorting'},{id:'workshop-2119742489',name:'travel'},{id:'workshop-unknown',name:'new mod'}]});
 assert.deepEqual(knowledge.mods.map(m=>m.support),['standard','limited','unknown']);
});
