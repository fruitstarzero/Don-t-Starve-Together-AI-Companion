export function worldAge(s){
 const day=s.time?.day,fraction=s.time?.dayFraction;
 return Number.isFinite(day)&&day>=0?day+(Number.isFinite(fraction)&&fraction>=0&&fraction<=1?fraction:0):null;
}
export function tagWorld(value,s,epoch){return {...value,worldAge:worldAge(s),timelineEpoch:epoch};}
export function reconcileTimeline(state,s,now){
 const age=worldAge(s),old=state.timeline;
 if(old?.retiredSessions?.includes(s.session))throw Error('Retired game session cannot update this world');
 const swapped=old?.session&&old.session!==s.session;
 const backwards=age!==null&&Number.isFinite(old?.worldAge)&&age<old.worldAge-3/480;
 const serialBack=Number.isInteger(s.saveSerial)&&Number.isInteger(old?.saveSerial)&&s.saveSerial<old.saveSerial;
 const rollback=Boolean(old&&(backwards||serialBack));
 const archive=rollback?structuredClone({timeline:old,memories:state.memories,experiences:state.experiences,
  turns:state.turns,places:state.places,projects:state.projects,socialTurns:state.socialTurns,task:state.task,taskHistory:state.taskHistory}):null;
 if(rollback){
  const keep=x=>age!==null&&Number.isFinite(x.worldAge)&&x.worldAge<=age;
  for(const key of ['memories','experiences','turns','socialTurns'])state[key]=(state[key]||[]).filter(keep);
  state.places=[];state.projects=[];state.task=null;state.taskHistory=[];state.goalBoard=null;state.life=null;state.actionMemory=null;
  state.reconciliation={at:new Date(now).toISOString(),reason:serialBack?'存档序号倒退':'游戏日期或日内时间倒退',
   warning:'已回滚世界。旧时间线日记和QQ对话可作为经历阅读，不能据此认定当前建筑、库存或任务已完成。当前游戏存档优先。'};
 }
 state.timeline={epoch:(old?.epoch||1)+(rollback?1:0),session:s.session,worldAge:age,
  saveSerial:Number.isInteger(s.saveSerial)?s.saveSerial:old?.saveSerial,
  retiredSessions:[...(old?.retiredSessions||[]),...(swapped?[old.session]:[])].slice(-32)};
 return {archive,swapped,rollback,previousSession:old?.session};
}
