import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {DecisionEngine} from '../bridge/engine.mjs';
const snap=(session,day,fraction=.5)=>({ready:true,session,world:'same-world',owner:'owner',shard:'1',revision:0,at:10,ownerHere:true,
 mode:'stay',time:{day,dayFraction:fraction,phase:'day',season:'autumn'},saveSerial:3,
 companion:{inventory:[]},chats:[],observed:[],events:[],responses:[],taskJournalVersion:1,taskJournal:null,projects:[]});
function fixture(t){const root=fs.mkdtempSync(path.join(os.tmpdir(),'dst-timeline-'));t.after(()=>fs.rmSync(root,{recursive:true,force:true}));return{root,engine:new DecisionEngine({root,generate:async()=>{throw Error('No model expected');}})};}
test('rollback archives future world memories and trusts only the loaded game task',t=>{
 const {root,engine}=fixture(t);const s=snap('old-run',10);engine.tick(s);
 const file=engine.file(s),state=JSON.parse(fs.readFileSync(file));state.memories=[{id:'future',text:'第十天造好了冰箱'}];state.turns=[{role:'assistant',text:'冰箱已完成'}];fs.writeFileSync(file,JSON.stringify(state));
 const loaded=snap('new-run',9);new DecisionEngine({root,generate:async()=>{}}).tick(loaded);
 const now=JSON.parse(fs.readFileSync(file));assert.deepEqual(now.memories,[]);assert.deepEqual(now.turns,[]);assert.equal(now.task,null);
 assert.equal(now.timeline.epoch,2);assert.equal(fs.readdirSync(path.join(root,'state/timeline-archives')).length,1);
});
test('normal reload or service restart preserves valid memory and rejects retired session packets',t=>{
 const {root,engine}=fixture(t);const first=snap('first-run',3);engine.tick(first);
 const file=engine.file(first),state=JSON.parse(fs.readFileSync(file));state.memories=[{id:'home-fact',text:'记得种植区'}];fs.writeFileSync(file,JSON.stringify(state));
 const next=new DecisionEngine({root,generate:async()=>{}});next.tick(snap('second-run',3,.51));
 assert.equal(JSON.parse(fs.readFileSync(file)).memories[0].id,'home-fact');
 assert.throws(()=>next.tick({...first,at:11}),/retired/i);
 assert.equal(JSON.parse(fs.readFileSync(file)).timeline.epoch,1);
});
