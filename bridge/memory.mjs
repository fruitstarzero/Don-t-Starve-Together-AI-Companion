export function loadState(value={}){
 return {task:null,...value,experiences:value.experiences||[],turns:value.turns||[],places:value.places||[],memories:value.memories||[],socialTurns:value.socialTurns||[],projects:value.projects||[]};
}
const point=(p,shard)=>p && Number.isFinite(p.x) && Number.isFinite(p.z)
 && Math.abs(p.x)<100000 && Math.abs(p.z)<100000?{x:p.x,z:p.z,shard}:null;
export function anchorMemory(m,s,chat){
 const memory={...m};
 if(m.kind==='place' && m.operation!=='remove'){
  if(m.anchor==='speaker' && chat){
   if(chat.context?.shard && chat.context.shard!==s.shard)throw Error('Speaker is on a different shard');
   memory.position=point(chat.context?.speaker||s.player,s.shard);
  }else if(m.anchor==='observed' && m.id!=='home'){
   memory.position=point(s.observed.find(e=>e.id===m.targetId),s.shard);
  }
  if(!memory.position)throw Error('Place requires an observed or original speaker anchor');
 }
 return memory;
}
export function updateMemories(state,updates){
 for(const m of updates){state.memories=state.memories.filter(old=>old.id!==m.id);
  if(m.operation!=='remove')state.memories.push(m);
 }
 state.memories=state.memories.slice(-64);
}
export function anchorProject(p,s,chat){
 if(p.operation==='remove')return p;
 let position;
 if(p.anchor==='home')position=point(s.companion.homeMemory?.position||s.companion.home,s.shard);
 else position=anchorMemory({...p,kind:'place'},s,chat).position;
 if(!position)throw Error('Project requires a known place');
 return {...p,position};
}
export function updateProjects(state,updates){
 for(const p of updates){state.projects=state.projects.filter(old=>old.id!==p.id);
  if(p.operation!=='remove')state.projects.push(p);
 }
 state.projects=state.projects.slice(-24);
}
export function syncHome(state,s){
 const m=s.companion.homeMemory;
 if(m?.id==='home' && m.position?.shard===s.shard && point(m.position,s.shard)){
  const saved=state.memories.find(v=>v.id==='home');
  if(JSON.stringify(saved?.position)!==JSON.stringify(m.position)){
   updateMemories(state,[{...m,operation:'upsert'}]);return true;
  }
 }
 return false;
}
