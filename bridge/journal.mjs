import fs from 'node:fs';
import path from 'node:path';
const atomic=(file,value)=>{fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file+'.tmp',JSON.stringify(value,null,2));fs.renameSync(file+'.tmp',file);};
export function writeGameJournal(root,s,state,now){
 if(s.owner==='AI_TEST_OWNER')return; // Disposable engine tests must not replace the player's QQ memory.
 const data={version:1,syncedAt:new Date(now).toISOString(),session:s.session,world:s.world,shard:s.shard,owner:s.owner,
  ownerHere:s.ownerHere,mode:s.mode,status:s.status,time:s.time,task:s.taskJournal,taskHistory:s.taskHistory||[],
  timeline:state.timeline,reconciliation:state.reconciliation,
  projects:s.projects||[],memories:state.memories||[],experiences:state.experiences||[],
  recentConversation:(state.turns||[]).slice(-20),recentSpeech:(s.responses||[]).slice(-20),
  home:s.companion.homeMemory||s.companion.home,procurement:s.procurement,
  resources:s.baseResources,resourceMemory:s.resourceMemory,terrainMemory:s.terrainMemory,
  goalBoard:state.life?.goalBoard,actionState:state.life?.actionState,recentActions:state.life?.recentActions,
  events:(s.events||[]).slice(-30)};
 const key=Buffer.from(`${s.owner}/${s.world}/${s.shard}`).toString('hex');
 atomic(path.join(root,'state','journals',key+'.json'),data);
 // The QQ side only reads this mirror; it never writes game-owned task files.
 atomic(path.join(root,'state','shared-game.json'),data);
}
