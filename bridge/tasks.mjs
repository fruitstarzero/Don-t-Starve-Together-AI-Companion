// The saved game journal, rather than a model assertion, owns task progress.
export function syncTask(state,snapshot){
  const before=JSON.stringify([state.task,state.taskHistory]);
  if(snapshot.taskJournalVersion===1){
    const job=snapshot.taskJournal;
    state.task=job && !['complete','cancelled'].includes(job.status)?{
      ...structuredClone(job),text:job.goal,plan:structuredClone(snapshot.plan),revision:snapshot.revision}:null;
    state.taskHistory=structuredClone(snapshot.taskHistory||[]);
  }else if(state.task){
    // Compatibility with a 0.4 snapshot while its world has not reloaded yet.
    const commands=(snapshot.events||[]).filter(e=>e.kind==='manual_command'
      && e.detail?.revision>(state.task.commandRevision??state.task.revision??-1));
    for(const e of commands){
      if(e.detail.command==='cancel'){state.task=null;break;}
      if(['follow','stay','come','home','retreat'].includes(e.detail.command))state.task.status='paused';
      if(['auto','resume'].includes(e.detail.command))state.task.status='ongoing';
      state.task.commandRevision=e.detail.revision;
    }
  }
  return before!==JSON.stringify([state.task,state.taskHistory]);
}
