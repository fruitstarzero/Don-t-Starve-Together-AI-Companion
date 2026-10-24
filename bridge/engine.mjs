import fs from 'node:fs';
import path from 'node:path';
import {randomUUID} from 'node:crypto';
import {validateDecision} from './schema.mjs';
import {loadState,anchorMemory,updateMemories,syncHome,anchorProject,updateProjects} from './memory.mjs';
import {gameKnowledge} from './knowledge.mjs';
import {syncTask} from './tasks.mjs';
import {RemoteInbox} from './remote.mjs';
import {writeGameJournal} from './journal.mjs';
import {decisionContext,staleDecision,hasActions} from './decision-context.mjs';
import {reconcileTimeline,tagWorld} from './timeline.mjs';
import {ingestActions,lifeState} from './life.mjs';

const read=(file,fallback)=>{try{return JSON.parse(fs.readFileSync(file,'utf8'));}catch{return fallback;}};
const atomic=(file,value)=>{fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file+'.tmp',JSON.stringify(value,null,2));fs.renameSync(file+'.tmp',file);};
const readGuide=root=>{try{return fs.readFileSync(path.join(root,'bridge/survival-guide.md'),'utf8').slice(0,16000);}catch{return '先维持生存与安全返程，再完善基地、可重复补给和四季准备；按真实能力行动。';}};

export function validSnapshot(s) {
  return s && s.ready===true && typeof s.session==='string' && /^[\w-]{1,80}$/.test(s.session)
    && typeof s.world==='string' && s.world.length<100 && typeof s.owner==='string' && s.owner.length<100
    && typeof s.shard==='string' && s.shard.length<40 && Number.isInteger(s.revision) && s.revision>=0
    && Number.isFinite(s.at) && s.at>=0 && s.companion && Array.isArray(s.companion.inventory)
    && Array.isArray(s.observed) && Array.isArray(s.events) && Array.isArray(s.chats) && s.chats.length<=4;
}

export class DecisionEngine {
  constructor({root,generate,diary,recordConversation,now=Date.now}) {
    this.root=root;this.generate=generate;this.diary=diary;this.now=now;this.sessions=new Map();this.modelBusy=false;
    this.remote=new RemoteInbox({now});
    this.worldEpochs=new Map();
    this.recordConversation=recordConversation;
  }
  key(s){return Buffer.from(`${s.owner}/${s.world}/${s.shard}`).toString('hex');}
  file(s){return path.join(this.root,'state','worlds',this.key(s)+'.json');}
  commitEffects(state,p,s){
    for(const proposal of p.experiences||[]) {
      state.experiences=state.experiences.filter(e=>e.id!==proposal.id);
      if(proposal.operation==='upsert'&&proposal.text.trim()&&proposal.evidence.trim())
        state.experiences.push(tagWorld({...proposal,at:new Date(this.now()).toISOString()},s,state.timeline?.epoch));
    }
    state.experiences=state.experiences.slice(-24);
    updateMemories(state,(p.memories||[]).map(m=>tagWorld(m,s,state.timeline?.epoch)));
    updateProjects(state,p.projects||[]);
    if(p.legacyTask)state.task=p.legacyTask;
    if(p.diary)this.diary?.add(p.diary);
  }
  reconcileResponses(state,s){
    let changed=false;const pending=[];
    for(const p of state.pendingDecisions||[]){
      const valid=p.session===s.session&&p.epoch===state.timeline?.epoch;
      const receipt=valid&&[...(s.receipts||[]),...(s.responses||[])].find(r=>r.id===p.id);
      const turn=state.turns.find(t=>t.resultId===p.id);
      if(receipt){
        if(receipt.actionAccepted===true)this.commitEffects(state,p,s);
        if(p.userText&&!p.remoteId)this.recordConversation?.(s,p.userText,receipt.text||'游戏已处理这份方案。',state.timeline);
        if(turn){turn.text=receipt.text||'游戏已确认处理这份方案。';delete turn.awaitingGame;}
        changed=true;
      }else if(valid&&p.revision===s.revision&&p.expires>s.at)pending.push(p);
      else {if(turn){turn.text='这份方案未收到游戏确认，不能视为已执行。';delete turn.awaitingGame;}changed=true;}
    }
    state.pendingDecisions=pending;return changed;
  }
  tick(s) {
    if(!validSnapshot(s)) throw Error('Invalid game snapshot');
    let live=this.sessions.get(s.session);
    if(live?.snapshot && (s.owner!==live.snapshot.owner || s.world!==live.snapshot.world || s.shard!==live.snapshot.shard || s.at<live.snapshot.at)) throw Error('Session identity changed');
    const state=loadState(read(this.file(s),{}));
    const timeline=reconcileTimeline(state,s,this.now());
    this.worldEpochs.set(this.key(s),state.timeline.epoch);
    if(timeline.archive)atomic(path.join(this.root,'state','timeline-archives',this.key(s)+'-'+this.now()+'-'+randomUUID()+'.json'),timeline.archive);
    if(timeline.swapped){
      this.remote.retireSession(timeline.previousSession);
      for(const old of this.sessions.values())if(old.snapshot&&this.key(old.snapshot)===this.key(s)&&old.snapshot.session!==s.session)old.controller?.abort();
    }
    if(!live){live={results:[],seen:new Set(),seenSocial:new Set(),lastSocial:0,lastPlan:0,failures:0,receivedAt:this.now()};this.sessions.set(s.session,live);}
    if(live.snapshot && (s.owner!==live.snapshot.owner || s.world!==live.snapshot.world || s.shard!==live.snapshot.shard || s.at<live.snapshot.at)) throw Error('Session identity changed');
    if(live.snapshot && s.revision!==live.snapshot.revision) live.controller?.abort();
    live.snapshot=structuredClone(s);live.receivedAt=this.now();
    this.remote.sync(s);
    const actions=ingestActions(this.root,this.key(s),state,s);
    if(s.goalBoard)state.goalBoard=structuredClone(s.goalBoard);
    state.life=lifeState(s,state);
    let changed=this.reconcileResponses(state,s)||timeline.rollback||timeline.swapped;
    changed=syncHome(state,s)||changed;
    changed=syncTask(state,s)||changed;
    if(Array.isArray(s.projects)&&JSON.stringify(state.projects)!==JSON.stringify(s.projects)){
      state.projects=structuredClone(s.projects).slice(-24);changed=true;
    }
    for(const r of (s.responses||[]).filter(r=>r.source==='social'||r.source==='autonomy')){
      if(!state.socialTurns.some(old=>old.id===r.id)){
        state.socialTurns.push(tagWorld({id:r.id,text:r.text,at:r.at},s,state.timeline.epoch));state.socialTurns=state.socialTurns.slice(-10);changed=true;
      }
    }
    atomic(this.file(s),state); // Also persist the timeline high-water mark.
    if(changed||!live.lastJournal||this.now()-live.lastJournal>=5000){
      writeGameJournal(this.root,s,state,this.now());live.lastJournal=this.now();
    }
    const results=live.results.filter(r=>r.expires>s.at && r.revision===s.revision);
    // Keep delivery until a later snapshot acknowledges an applied result. Ids are idempotent in Lua.
    const acknowledged=new Set([...(s.receipts||[]),...(s.responses||[])].map(r=>r.id));
    live.results=live.results.filter(r=>!acknowledged.has(r.id) && r.expires>s.at && r.revision===s.revision);
    const chat=s.chats.find(c=>typeof c.id==='string' && typeof c.text==='string' && c.text.length<=1200
      && c.revision===s.revision && c.expires>s.at && !live.seen.has(c.id));
    const delay=Math.min(300000,20000*2**live.failures);
    const notice=s.social?.candidate;
    const social=notice && s.social.canSpeak===true && notice.expires>s.at
      && !live.seenSocial.has(notice.id) && this.now()-live.lastSocial>delay;
    const plan=s.mode==='auto' && (this.now()-live.lastPlan>delay
      ||live.failures===0&&actions.needsDecision&&this.now()-live.lastPlan>=5000);
    if(s.ownerHere && !live.busy && !this.modelBusy && (chat || !this.remote.commands(s).length&&(social || plan))) {
      const source=chat?'chat':plan?'autonomy':'social';
      live.busy=true;this.modelBusy=true;
      if(source!=='social')live.lastPlan=this.now();
      if(social){live.seenSocial.add(notice.id);live.lastSocial=this.now();
        if(live.seenSocial.size>128)live.seenSocial.delete(live.seenSocial.values().next().value);}
      const controller=new AbortController();live.controller=controller;
      if(chat)live.seen.add(chat.id);
      const promise=this.decide(live,chat,source).catch(error=>{
        // A newer instruction/session intentionally supersedes this request.
        // Only our own abort signal establishes that; provider errors whose
        // message happens to say "Cancelled" must still be diagnosed.
        if(controller.signal.aborted)return;
        live.failures=Math.min(3,live.failures+1);live.error=error.message.slice(0,350);
        if(chat && live.snapshot.revision===s.revision) live.results.push({
          id:randomUUID(),session:s.session,revision:s.revision,source:'chat',chatid:chat.id,
          expires:live.snapshot.at+15,remoteId:chat.remoteId||null,reply:'这次 AI 连接没有完成，先用快捷按钮控制；稍后可以重发。',plan:null,modelError:true});
      }).finally(()=>{live.busy=false;this.modelBusy=false;});
      live.pending=promise;
    }
    for(const [key,session] of this.sessions) if(this.now()-session.receivedAt>600000 && !session.busy)this.sessions.delete(key);
    const cancelled=this.remote.cancellations(s);
    return {health:live.error?'model_error':'ready',busy:live.busy,actionAck:actions.ack,commands:this.remote.commands(s),cancellations:cancelled,
      results:results.filter(r=>!acknowledged.has(r.id)&&!cancelled.some(c=>c.id===r.remoteId))};
  }
  async decide(live,chat,source=chat?'chat':'autonomy') {
    const s=structuredClone(live.snapshot);
    const startedAt=this.now();
    const state=loadState(read(this.file(s),{}));
    syncTask(state,s);
    const input={source,time:new Date(this.now()).toLocaleString('zh-CN',{timeZone:'Asia/Shanghai'}),
      currentMessage:chat?.text||'',supersededMessages:s.supersededChats||[],currentTask:state.task,recentConversation:state.turns.slice(-20),
      importantMemories:state.memories,longTermProjects:state.projects,recentSpeech:state.socialTurns,gameKnowledge:gameKnowledge(s),
      worldTimeline:state.timeline,memoryReconciliation:state.reconciliation||null,
      experiences:state.experiences,knownPlaces:state.places,diaries:this.diary?.context(chat?.text||'饥荒 AI伙伴')||[],
      life:lifeState(s,state),actionGap:s.actionGap||null,unprocessedActions:(state.actionMemory?.recent||[]).filter(e=>e.session===s.session&&e.id>(state.actionMemory?.handled||0)),
      survivalGuide:readGuide(this.root),snapshot:s};
    const decision=validateDecision(await this.generate(input,live.controller.signal),{source,snapshot:s});
    if(live.controller.signal.aborted || live.snapshot.revision!==s.revision || this.now()-live.receivedAt>10000
      || this.worldEpochs.get(this.key(s))!==state.timeline?.epoch) return;
    const stale=staleDecision(decision,s,live.snapshot,this.now()-startedAt);
    const memories=(stale?[]:decision.memories||[]).map(m=>anchorMemory(m,s,chat));
    const projects=(stale?[]:decision.projects||[]).map(p=>anchorProject(p,s,chat));
    const speaker=chat?.context?.speaker||s.player;
    const reply=stale?(source==='chat'?'刚才判断期间环境变了，旧方案没有执行；原有任务和进度保留。请按当前情况重新安排，或让我继续自主判断。':''):
      source==='chat'?decision.reply:s.social?.canSpeak?decision.reply.slice(0,180):'';
    const result={id:randomUUID(),session:s.session,revision:s.revision,source,chatid:chat?.id||null,
      expires:live.snapshot.at+30,command:stale?null:decision.command,plan:stale?null:decision.plan,tripSeconds:decision.tripSeconds,
      staleAction:stale,decisionContext:decisionContext(s),
      goalBoard:stale?null:decision.goalBoard||null,method:stale?null:decision.method||null,
      remoteId:chat?.remoteId||null,
      userText:chat?.text||null,
      learnSkill:stale?null:decision.learnSkill||null,taskStatus:stale?'none':decision.taskStatus,reply,
      workflow:stale?null:decision.workflow||null,taskGoal:chat?.text||decision.plan?.reason,
      taskGuard:s.taskJournalVersion===1?{id:s.taskJournal?.id||false,index:s.taskJournal?.index||0,
        closed:['complete','cancelled'].includes(s.taskJournal?.status)}:null,
      speechId:source!=='chat'?s.social?.candidate?.id:null,
      speakerPosition:source==='chat'&&speaker?{x:speaker.x,z:speaker.z}:null,
      placeUpdates:memories.filter(m=>m.kind==='place'),projectUpdates:projects};
    live.results.push(result);live.failures=0;live.error=null;
    if(stale)live.lastPlan=0;
    // Reload after model latency so confirmed game facts arriving during this
    // request are not lost to an older snapshot of the state file.
    const current=loadState(read(this.file(s),{}));
    if(!stale&&current.actionMemory?.session===s.session)current.actionMemory.handled=Math.max(current.actionMemory.handled||0,state.actionMemory?.cursor||0);
    const pending=!stale&&(hasActions(decision)||result.placeUpdates.length>0);
    const effects={experiences:stale?[]:decision.experiences,memories,projects,diary:stale?null:decision.diary,userText:chat?.text,remoteId:chat?.remoteId,
      legacyTask:s.taskJournalVersion!==1&&chat&&result.plan?{text:chat.text,status:'accepted',plan:result.plan,
        revision:s.revision,at:new Date(this.now()).toISOString()}:null};
    if(pending){
      current.pendingDecisions=[...(current.pendingDecisions||[]),{...effects,id:result.id,session:s.session,
        epoch:current.timeline?.epoch,revision:s.revision,expires:result.expires}].slice(-8);
    }else {this.commitEffects(current,effects,s);if(chat&&!chat.remoteId)this.recordConversation?.(s,chat.text,reply,current.timeline);}
    if(chat){current.turns.push(tagWorld({role:'user',text:chat.text},s,current.timeline?.epoch),
      tagWorld({role:'assistant',text:pending?'方案等待游戏确认，尚不能视为已执行。':reply,resultId:result.id,awaitingGame:pending},s,current.timeline?.epoch));current.turns=current.turns.slice(-20);}
    if(s.taskJournalVersion===1)syncTask(current,live.snapshot);
    // complete/none describe the model answer; they are never game completion evidence.
    // These observations came from actual local perception, never a global entity scan.
    for(const e of s.observed.filter(e=>e.chest || e.science)) {
      current.places=current.places.filter(p=>p.id!==e.id);
      current.places.push({id:e.id,prefab:e.prefab,x:e.x,z:e.z,day:s.time?.day});
    }
    current.places=current.places.slice(-100);current.lastDecision={at:new Date(this.now()).toISOString(),result};
    atomic(this.file(s),current);
    writeGameJournal(this.root,live.snapshot,current,this.now());
  }
  status(){return [...this.sessions.values()].map(l=>({session:l.snapshot?.session,world:l.snapshot?.world,
    mode:l.snapshot?.mode,status:l.snapshot?.status,busy:l.busy,error:l.error||null,
    seenAt:new Date(l.receivedAt).toISOString(),state:l.snapshot}));}
  close(){for(const l of this.sessions.values())l.controller?.abort();}
  remoteChat(text,id,expected){
    const live=[...this.sessions.values()].filter(l=>l.snapshot?.ownerHere&&this.now()-l.receivedAt<=10000);
    if(live.length!==1)throw Error(live.length?'多个世界在线，不能猜测目标世界':'饥荒世界未连接；不会离线执行');
    const s=live[0].snapshot;
    if(!expected||expected.session!==s.session||expected.world!==s.world||expected.shard!==s.shard)
      throw Error('饥荒世界已变化；请在当前世界重新下达，不会跨存档执行旧消息');
    return this.remote.enqueue(text,live[0].snapshot,live[0].receivedAt,id);
  }
}
