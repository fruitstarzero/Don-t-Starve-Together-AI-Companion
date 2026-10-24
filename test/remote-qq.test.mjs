import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {lua,lauxlib,lualib,to_luastring,to_jsstring} from 'fengari';
import {RemoteInbox} from '../bridge/remote.mjs';
import {DecisionEngine} from '../bridge/engine.mjs';
import {createServer} from '../bridge/server.mjs';
const s=()=>({ready:true,session:'session',world:'world',shard:'1',owner:'owner',ownerHere:true,revision:0,at:100,
 mode:'stay',companion:{inventory:[]},observed:[],events:[],chats:[],responses:[],projects:[],taskJournalVersion:1});
test('remote delivery binds world/session/revision, waits for real game reply and rejects offline replay',()=>{
 let now=10000;const inbox=new RemoteInbox({now:()=>now});const snap=s();
 const r=inbox.enqueue('收20个木头',snap,now,'request-0001');
 assert.equal(inbox.enqueue(r.text,snap,now,r.id),r);
 assert.throws(()=>inbox.enqueue('另一条',snap,now,'request-0002'));
 assert.equal(inbox.commands({...snap,world:'other'}).length,0);
 snap.revision=1;snap.chats=[{remoteId:r.id,revision:1}];inbox.sync(snap);
 assert.equal(inbox.result(r.id).status,'processing');assert.equal(inbox.commands(snap).length,0);
 snap.chats=[];snap.responses=[{remoteId:r.id,text:'游戏已接受目标'}];inbox.sync(snap);
 assert.equal(inbox.result(r.id).reply,'游戏已接受目标');
 now+=11000;assert.throws(()=>inbox.enqueue('停下',snap,10000,'request-0003'));
});
test('manual revision and explicit cancellation invalidate late requests',()=>{
 const snap=s();const inbox=new RemoteInbox({now:()=>10000});
 const r=inbox.enqueue('做箱子',snap,10000,'request-0004');inbox.sync({...snap,revision:1});
 assert.equal(inbox.result(r.id).status,'cancelled');
 const next=inbox.enqueue('采集',snap,10000,'request-0005');inbox.cancel(next.id);
 assert.equal(inbox.commands(snap).length,0);
 assert.equal(inbox.cancellations({...snap,chats:[{remoteId:next.id}]}).length,1);
});
test('HTTP remote channel is authenticated and succeeds only after an applied game response',async t=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'dst-remote-'));t.after(()=>fs.rmSync(root,{recursive:true,force:true}));
 const engine=new DecisionEngine({root,generate:async()=>({reply:'准备收集木头。',plan:null,command:null,taskStatus:'none',tripSeconds:240,experiences:[]})});
 const server=createServer({token:'test-only',engine});await new Promise(r=>server.listen(0,'127.0.0.1',r));t.after(()=>server.close());
 const api=async(route,data,token='test-only')=>fetch(`http://127.0.0.1:${server.address().port}`+route,{method:'POST',body:JSON.stringify({token,...data})});
 const snap=s();engine.tick(snap);
 assert.equal((await api('/v1/qq/chat',{text:'收木头',id:'request-0006',expected:{session:'session',world:'world',shard:'1'}},'bad')).status,403);
 assert.equal((await api('/v1/qq/chat',{text:'收木头',id:'request-0006'})).status,409);
 assert.equal((await api('/v1/qq/chat',{text:'收木头',id:'request-0006',expected:{session:'old-session',world:'world',shard:'1'}})).status,409);
 assert.equal((await api('/v1/qq/chat',{text:'收木头',id:'request-0006',expected:{session:'session',world:'world',shard:'1'}})).status,200);
 const frame=engine.tick(snap);assert.equal(frame.commands.length,1);
 snap.revision++;snap.chats=[{id:'gamechat',remoteId:'request-0006',text:'收木头',revision:1,expires:280}];
 engine.tick(snap);await engine.sessions.get(snap.session).pending;
 const reply=engine.tick(snap).results[0];assert.equal(reply.remoteId,'request-0006');
 assert.equal((await (await api('/v1/qq/result',{id:'request-0006'})).json()).status,'processing');
 snap.chats=[];snap.responses=[{id:reply.id,remoteId:reply.remoteId,text:reply.reply}];engine.tick(snap);
 assert.equal((await (await api('/v1/qq/result',{id:'request-0006'})).json()).status,'done');
 const mirror=JSON.parse(fs.readFileSync(path.join(root,'state/shared-game.json')));
 assert.equal(mirror.recentConversation.at(-1).text,'准备收集木头。');
 assert.equal(fs.readdirSync(path.join(root,'state/journals')).length,1);
});
test('actual game manager deduplicates remote commands and keeps their response correlation',()=>{
 const read=f=>fs.readFileSync(new URL('../mod/scripts/'+f,import.meta.url),'utf8');
 const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);
 const status=lauxlib.luaL_dostring(L,to_luastring(`
 package.preload.ai_actions=function()${fs.readFileSync(new URL('../mod/scripts/ai_actions.lua',import.meta.url),'utf8')}end
 Class=function()local c={};c.__index=c;return c end;GetTime=function()return 100 end
 for _,n in ipairs({'ai_policy','ai_inventory','ai_social','ai_memory','ai_capabilities','ai_resources'})do package.preload[n]=function()return {}end end
 package.preload.ai_speechhistory=function()${read('ai_speechhistory.lua')}end
 local Manager=(function()${read('components/aicompanionmanager.lua')}end)()
 local c={revision=2};local m=setmetatable({session='s',chats={},responses={},bot={components={aicompanion=c}}},Manager)
 m.Authorized=function()return true end
 local count=0;m.Command=function(_,owner,command,text,id)count=count+1;c.revision=c.revision+1;m:RecordReply('reply',text,'chat','command',false,false,id,text)end
 local r={id='remote',text='跟着我',session='s',revision=2,expires=110}
 assert(m:RemoteCommand({},r));assert(not m:RemoteCommand({},r));assert(count==1)
 assert(m.responses[1].remoteId=='remote' and m.responses[1].userText=='跟着我')
 m.chats={{remoteId='cancel'}};m:CancelRemote({session='s',id='cancel'});assert(#m.chats==0 and c.revision==4)
 `));const error=status?to_jsstring(lua.lua_tostring(L,-1)):null;lua.lua_close(L);assert.equal(status,lua.LUA_OK,error);
});
