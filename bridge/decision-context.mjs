export const hasActions=d=>Boolean(d.command||d.plan||d.workflow||d.learnSkill||d.method||d.goalBoard||d.projects?.length||d.memories?.some(m=>m.kind==='place'));
export function decisionContext(s){return {at:s.at,phase:s.time?.phase,season:s.time?.season,raining:s.time?.raining,
 ghost:s.companion.ghost===true,critical:s.companion.maxHealth>0&&s.companion.health/s.companion.maxHealth<.3};}
export function staleDecision(d,start,current,elapsedMs){
 if(!hasActions(d))return false;
 const before=decisionContext(start),after=decisionContext(current);
 return elapsedMs>90000||current.at-start.at>45||current.ownerHere!==true
  ||start.taskJournalVersion===1&&(start.taskJournal?.id!==current.taskJournal?.id
    ||(start.taskJournal?.index||0)!==(current.taskJournal?.index||0)
    ||['complete','cancelled'].includes(start.taskJournal?.status)!==['complete','cancelled'].includes(current.taskJournal?.status))
  ||['phase','season','raining','ghost','critical'].some(k=>before[k]!=null&&after[k]!=null&&before[k]!==after[k]);
}
