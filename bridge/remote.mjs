import {randomUUID} from 'node:crypto';

// No offline replay. Commands are bound to a fresh, already-running game session.
export class RemoteInbox {
 constructor({now=Date.now}={}){this.now=now;this.requests=new Map();}
 enqueue(text,s,seenAt,requestId=randomUUID()){
  if(typeof text!=='string'||!text.trim()||text.length>1200)throw Error('指令为空或超过1200字');
  if(!s?.ownerHere||this.now()-seenAt>10000)throw Error('游戏未连接或状态已过期；不会离线排队执行');
  if(!/^[a-zA-Z0-9_-]{8,100}$/.test(requestId))throw Error('Invalid request id');
  const old=this.requests.get(requestId);
  if(old){if(old.text!==text||old.session!==s.session)throw Error('Conflicting request id');return old;}
  this.prune();
  if([...this.requests.values()].some(r=>['queued','processing'].includes(r.status)))throw Error('上一条饥荒消息尚在处理，请稍后再发');
  const r={id:requestId,text,session:s.session,owner:s.owner,world:s.world,shard:s.shard,
   revision:s.revision,status:'queued',createdAt:this.now(),expiresAt:this.now()+185000};
  this.requests.set(r.id,r);return r;
 }
 sync(s){
  for(const r of this.requests.values()){
   if(!['queued','processing'].includes(r.status))continue;
   if(this.now()>r.expiresAt){r.status='expired';r.error='游戏未在有效时间内确认；未自动重试';continue;}
   if(r.session!==s.session||r.owner!==s.owner||r.world!==s.world||r.shard!==s.shard)continue;
   const reply=s.responses?.find(v=>v.remoteId===r.id);
   if(reply){r.status='done';r.reply=reply.text;r.modelError=reply.modelError===true;continue;}
   const chat=s.chats.find(v=>v.remoteId===r.id);
   if(chat){r.status='processing';r.appliedRevision=chat.revision;continue;}
   if(s.revision!==(r.appliedRevision??r.revision)){
    r.status='cancelled';r.error='游戏内更新的安排已取代这条消息；未重新执行';
   }
  }
  this.prune();
 }
 commands(s){return [...this.requests.values()].filter(r=>r.status==='queued'&&r.session===s.session
  &&r.world===s.world&&r.shard===s.shard&&r.owner===s.owner&&r.revision===s.revision&&r.expiresAt>this.now())
  .map(r=>({id:r.id,text:r.text,session:s.session,revision:s.revision,expires:s.at+10}));}
 result(id){const r=this.requests.get(id);if(!r)return {status:'unknown',error:'未找到请求，服务可能已重启；不会自动重放'};
  if(['queued','processing'].includes(r.status)&&this.now()>r.expiresAt){r.status='expired';r.error='指令已过期，未自动重试';}
  return {id:r.id,status:r.status,reply:r.reply,error:r.error,modelError:r.modelError};}
 cancel(id){const r=this.requests.get(id);if(r&&['queued','processing'].includes(r.status)){r.status='cancelled';r.error='QQ请求已取消';}return {ok:true};}
 cancellations(s){return [...this.requests.values()].filter(r=>r.status==='cancelled'&&r.session===s.session
  &&s.chats.some(c=>c.remoteId===r.id)).map(r=>({id:r.id,session:s.session}));}
 prune(){for(const [id,r] of this.requests)if(this.now()-r.createdAt>600000)this.requests.delete(id);}
 retireSession(session){for(const r of this.requests.values())if(r.session===session&&['queued','processing'].includes(r.status)){
  r.status='cancelled';r.error='原世界会话已结束；不会在重进或回滚后执行旧请求';
 }}
}
