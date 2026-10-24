import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {LocalDiary} from '../bridge/diary.mjs';
import {validateConfig,instanceId} from '../bridge/config.mjs';
import {install} from '../tools/setup.mjs';
import {generate,resolveCodex} from '../bridge/model.mjs';
import {startServer} from '../bridge/server.mjs';
import net from 'node:net';
import {once} from 'node:events';
const source=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
test('fresh standalone bridge boots with its own config and exposes the correct installation identity',async t=>{
 const root=fixture(t);fs.mkdirSync(path.join(root,'bridge'),{recursive:true});
 const portFinder=net.createServer();portFinder.listen(0,'127.0.0.1');await once(portFinder,'listening');const port=portFinder.address().port;
 await new Promise(resolve=>portFinder.close(resolve));const token='c'.repeat(64);
 fs.writeFileSync(path.join(root,'bridge/config.json'),JSON.stringify({port,token,codexPath:'',model:''}));
 const server=startServer(root);await once(server,'listening');t.after(()=>new Promise(resolve=>server.close(resolve)));
 const health=await(await fetch(`http://127.0.0.1:${port}/health`)).json();assert.equal(health.version,'0.8.0');assert.equal(health.instanceId,instanceId(token));
 assert.equal(fs.existsSync(path.join(root,'chat-routing.json')),false);
});
function fixture(t){const dir=fs.mkdtempSync(path.join(os.tmpdir(),'companion-share-'));t.after(()=>fs.rmSync(dir,{recursive:true,force:true}));return dir;}
test('local diaries are isolated and voluntary without a daily write limit',t=>{
 const root=fixture(t);const a=new LocalDiary(path.join(root,'a')),b=new LocalDiary(path.join(root,'b'));
 for(let i=0;i<5;i++)assert(a.add({title:'基地记录',text:'今天种植记录'+i,tags:['基地']}));
 assert.equal(a.read().length,5);assert.deepEqual(b.read(),[]);assert.equal(a.context('基地').length,5);
 assert(!a.add({text:''}));assert(!a.add({text:'今天种植记录4'}));
});
test('configuration rejects default or malformed secrets and invalid ports',()=>{
 const good={token:'a'.repeat(64),port:3131};assert.equal(validateConfig(good),good);
 for(const config of [{...good,token:'GENERATED_LOCALLY_BY_SETUP'},{...good,port:80},{...good,model:2}])assert.throws(()=>validateConfig(config));
 assert.notEqual(instanceId(good.token),instanceId('b'.repeat(64)));
});
test('installer creates private local credentials, preserves them on upgrade and backs up the mod',t=>{
 const base=fixture(t),root=path.join(base,'project'),game=path.join(base,'game');
 fs.mkdirSync(path.join(root,'bridge'),{recursive:true});fs.cpSync(path.join(source,'mod'),path.join(root,'mod'),{recursive:true});
 fs.copyFileSync(path.join(source,'role.example.md'),path.join(root,'role.example.md'));
 fs.mkdirSync(path.join(game,'data'),{recursive:true});fs.mkdirSync(path.join(game,'bin64'),{recursive:true});
 fs.writeFileSync(path.join(game,'bin64/dontstarve_steam_x64.exe'),'test fixture; not executable');
 const first=install({root,gamePath:game,checkRunning:()=>{}});
 assert.match(first.config.token,/^[a-f0-9]{64}$/);assert(fs.readFileSync(path.join(first.destination,'scripts/ai_private.lua'),'utf8').includes(first.config.token));
 assert(!fs.existsSync(path.join(source,'mod/scripts/ai_private.lua')),'install must not put secret in source mod');
 fs.writeFileSync(path.join(first.destination,'local-marker.txt'),'original');
 fs.writeFileSync(path.join(root,'role.md'),'local custom role');
 const second=install({root,gamePath:game,port:3132,checkRunning:()=>{}});
 assert.equal(second.config.token,first.config.token);assert.equal(second.config.port,3132);
 assert.equal(fs.readFileSync(path.join(second.backup,'local-marker.txt'),'utf8'),'original');
 assert.equal(fs.readFileSync(path.join(root,'role.md'),'utf8'),'local custom role');
 assert(fs.readFileSync(path.join(second.destination,'scripts/ai_private.lua'),'utf8').includes('127.0.0.1:3132'));
});
test('running-game checks stop installation before writing credentials or game files',t=>{
 const root=fixture(t);const game=path.join(root,'game');fs.mkdirSync(path.join(game,'data'),{recursive:true});fs.mkdirSync(path.join(game,'bin64'),{recursive:true});fs.writeFileSync(path.join(game,'bin64/dontstarve_steam_x64.exe'),'fixture');
 assert.throws(()=>install({root,gamePath:game,checkRunning:()=>{throw Error('game running');}}),/game running/);
 assert(!fs.existsSync(path.join(root,'bridge/config.json')));assert(!fs.existsSync(path.join(game,'mods')));
});
test('standalone model invocation works with only local role and configured CLI, without QQ',async t=>{
 const root=fixture(t);fs.mkdirSync(path.join(root,'bridge'),{recursive:true});
 fs.copyFileSync(path.join(source,'bridge/instructions.txt'),path.join(root,'bridge/instructions.txt'));
 fs.writeFileSync(path.join(root,'role.example.md'),'generic role');
 const fake=path.join(root,'fake-codex.mjs');
 fs.writeFileSync(fake,`let input='';process.stdin.on('data',v=>input+=v);process.stdin.on('end',()=>{
  if(!process.argv.includes('read-only')||!process.argv.includes('--output-schema'))process.exit(2);
  const data=JSON.parse(input);console.log(JSON.stringify({type:'item.completed',item:{type:'agent_message',text:JSON.stringify({reply:data.currentMessage})}}));
  console.log(JSON.stringify({type:'turn.completed'}));});`);
 assert.equal(resolveCodex({codexPath:fake}).command,process.execPath);
 const value=await generate(root,{codexPath:fake},{currentMessage:'你好'},new AbortController().signal);
 assert.equal(value.reply,'你好');assert(!fs.existsSync(path.join(root,'state/conversation.json')));
});
test('structured model parser rejects tool execution and an abort leaves no pending timeout',async t=>{
 const root=fixture(t);fs.mkdirSync(path.join(root,'bridge'),{recursive:true});fs.writeFileSync(path.join(root,'bridge/instructions.txt'),'game only');fs.writeFileSync(path.join(root,'role.example.md'),'generic role');
 const fake=path.join(root,'fake.mjs');fs.writeFileSync(fake,`console.log(JSON.stringify({type:'item.completed',item:{type:'command_execution'}}));console.log(JSON.stringify({type:'turn.completed'}));`);
 await assert.rejects(generate(root,{codexPath:fake},{},new AbortController().signal),/Codex failed/);
 fs.writeFileSync(fake,'setInterval(()=>{},1000);');const controller=new AbortController();
 const pending=generate(root,{codexPath:fake},{},controller.signal);controller.abort();await assert.rejects(pending,/Cancelled/);
});
