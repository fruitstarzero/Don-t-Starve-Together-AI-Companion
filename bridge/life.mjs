import fs from 'node:fs';
import path from 'node:path';
import {tagWorld} from './timeline.mjs';
const important=new Set(['task_complete','task_stage','problem','build_success','method_complete','method_expired','action_failed','action_blocked']);
export function ingestActions(root,key,state,s){
 const old=state.actionMemory;
 const same=old?.session===s.session&&old.epoch===state.timeline?.epoch;
 const memory=same?old:{session:s.session,epoch:state.timeline?.epoch,cursor:0,handled:0,recent:old?.epoch===state.timeline?.epoch?old.recent||[]:[]};
 const rows=(s.actionEvents||s.events||[]).filter(e=>Number.isInteger(e.id)&&e.id>memory.cursor).sort((a,b)=>a.id-b.id);
 if(rows.length){
  const file=path.join(root,'state','actions',key+'-'+memory.epoch+'.jsonl');fs.mkdirSync(path.dirname(file),{recursive:true});
  if(fs.existsSync(file)&&fs.statSync(file).size>2000000)fs.renameSync(file,file+'.'+Date.now()+'.archive');
  for(const e of rows){const row=tagWorld({...e,session:s.session,taskId:e.detail?.taskContext?.id||s.taskJournal?.id||null},s,memory.epoch);
   fs.appendFileSync(file,JSON.stringify(row)+'\n');memory.recent.push(row);memory.cursor=e.id;
  }
  memory.recent=memory.recent.slice(-60);
 }
 state.actionMemory=memory;
 const unseen=memory.recent.filter(e=>e.session===s.session&&e.id>memory.handled);
 return {ack:memory.cursor,unseen,needsDecision:unseen.some(e=>important.has(e.kind))};
}
export function lifeState(s,state){
 return {goalBoard:s.goalBoard||state.goalBoard||{short:['核对眼前照明、食物与安全'],medium:['形成能重复补给的基地生活'],long:['跨季节持续生存，并按能力扩展探索'],next:'根据真实观察选择下一段行动',reason:'长期生存指南的初始目标，尚未声称完成'},
  actionState:s.actionState||{current:s.status,task:s.taskJournal?.goal,next:s.taskJournal?.approach?.state},
  recentActions:state.actionMemory?.recent?.slice(-20)||[]};
}
