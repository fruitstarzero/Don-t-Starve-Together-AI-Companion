export const activities = ['auto','collect','farm','transplant','fish','cook','store','sort','explore','rest','craft','visit'];
export const commands = ['come','teleport','follow','auto','stay','home','retreat','sethome','abigail_summon','abigail_recall','resume','cancel'];
const str={type:'string'};
const nullable = value => ({anyOf:[{type:'null'},value]});
const obj = properties => ({type:'object',additionalProperties:false,properties,required:Object.keys(properties)});
const planSchema=obj({activity:{type:'string',enum:activities},prefab:nullable(str),recipe:nullable(str),
  count:nullable({type:'integer'}),placeId:nullable(str),useLast:{type:'boolean'},reason:str});
export const schema=obj({
  reply:str,
  command:nullable({type:'string',enum:commands}),
  plan:nullable(planSchema),
  workflow:nullable(obj({goal:str,steps:{type:'array',minItems:1,maxItems:6,items:planSchema}})),
  method:nullable(obj({reason:str,plan:planSchema})),
  goalBoard:nullable(obj({short:{type:'array',items:str},medium:{type:'array',items:str},long:{type:'array',items:str},next:str,reason:str})),
  tripSeconds:{type:'integer'},
  learnSkill:nullable(str),
  taskStatus:{type:'string',enum:['ongoing','complete','blocked','none']},
  experiences:{type:'array',items:obj({id:str,operation:{type:'string',enum:['upsert','remove']},
    text:str,evidence:str,confidence:{type:'number'},scope:str})},
  memories:{type:'array',items:obj({id:str,operation:{type:'string',enum:['upsert','remove']},
    kind:{type:'string',enum:['fact','preference','procedure','place']},text:str,evidence:str,
    anchor:nullable({type:'string',enum:['speaker','observed']}),targetId:nullable({type:'integer'})})},
  projects:{type:'array',items:obj({id:str,operation:{type:'string',enum:['upsert','remove']},
    kind:{type:'string',enum:['garden','transplant','stockpile']},text:str,evidence:str,
    prefab:nullable(str),count:nullable({type:'integer'}),
    anchor:nullable({type:'string',enum:['speaker','observed','home']}),targetId:nullable({type:'integer'})})},
  diary:nullable(obj({title:str,mood:str,text:str,tags:{type:'array',items:str}})),
});

export function validateDecision(d,{source,snapshot}) {
  if(!d || typeof d.reply!=='string' || d.reply.length>2400 || !Array.isArray(d.experiences)
    || !Number.isFinite(d.tripSeconds) || d.tripSeconds<60 || d.tripSeconds>1920) throw Error('Invalid decision');
  if(source==='social' && (d.command || d.plan || d.workflow || d.method||d.goalBoard||d.learnSkill || d.taskStatus!=='none'))throw Error('Social requests cannot change game actions');
  if(d.command && (source!=='chat' || !commands.includes(d.command))) throw Error('Autonomy cannot change manual mode');
  if([d.command,d.plan,d.workflow,d.method].filter(Boolean).length>1) throw Error('Use either a command, a plan, a method or a workflow');
  if(d.method&&(typeof d.method.reason!=='string'||d.method.reason.length>300||!snapshot.taskJournal
    ||['paused','complete','cancelled'].includes(snapshot.taskJournal.status)||snapshot.mode!=='auto'
    ||!['collect','craft','store','visit'].includes(d.method.plan?.activity)))throw Error('Invalid method repair');
  if(d.goalBoard){for(const k of ['short','medium','long'])if(!Array.isArray(d.goalBoard[k])||d.goalBoard[k].length>3
    ||d.goalBoard[k].some(x=>typeof x!=='string'||x.length>160))throw Error('Invalid goal board');
    for(const k of ['next','reason'])if(typeof d.goalBoard[k]!=='string'||d.goalBoard[k].length>300)throw Error('Invalid goal board');}
  if(d.workflow && (source!=='chat' || typeof d.workflow.goal!=='string' || !d.workflow.goal.trim()
    || d.workflow.goal.length>400 || !Array.isArray(d.workflow.steps) || !d.workflow.steps.length
    || d.workflow.steps.length>6))throw Error('Invalid executable workflow');
  for(const p of [d.plan,d.method?.plan,...(d.workflow?.steps||[])].filter(Boolean)) {
    if(snapshot.actionCatalog&&!snapshot.actionCatalog.activities?.[p.activity]?.supported)
      throw Error('Activity is not supported by the game capability catalog');
    if(d.workflow && (!['collect','craft','visit','transplant','store'].includes(p.activity)
      || ['collect','craft','transplant'].includes(p.activity)&&!Number.isInteger(p.count)))throw Error('Workflow steps need observable completion');
    if(!activities.includes(p.activity) || typeof p.reason!=='string' || p.reason.length>400
      || p.prefab!==null && (typeof p.prefab!=='string' || !/^[a-z0-9_]{1,80}$/.test(p.prefab))
      || p.recipe!==null && (typeof p.recipe!=='string' || !/^[a-z0-9_]{1,80}$/.test(p.recipe))
      || p.count!==null && (!Number.isInteger(p.count) || p.count<1 || p.count>500)) throw Error('Invalid plan');
    if(p.useLast!=null && typeof p.useLast!=='boolean')throw Error('Invalid reserve policy');
    if(p.activity==='transplant'&&!['dug_grass','dug_sapling','dug_berrybush','dug_berrybush2'].includes(p.prefab))throw Error('Unsupported transplant');
    if(p.activity==='transplant'&&p.placeId!=null
      && ![...(snapshot.projects||[]),...(d.projects||[])].some(v=>v.id===p.placeId&&v.operation!=='remove'))throw Error('Unknown transplant area');
    // Never accept an invented recipe or an unbounded material collection request.
    if(p.activity==='craft' && (!p.recipe || !snapshot.craftable?.includes(p.recipe))) {
      // Known recipes with missing ingredients may be gathered, but the engine still validates tech.
      if(!snapshot.knownRecipes?.includes(p.recipe)
        && !snapshot.recipeDetails?.some(r=>r.id===p.recipe&&r.canPrepare===true)) throw Error('Recipe not observed as available');
    }
    if(p.activity==='collect' && !p.prefab) throw Error('Collection needs a material');
    if(p.activity==='visit' && (!/^[a-z0-9_-]{1,48}$/.test(p.placeId||'')
      || !(snapshot.landmarks||[]).some(m=>m.id===p.placeId && m.position?.shard===snapshot.shard)))throw Error('Place is not known on this shard');
  }
  if(!['ongoing','complete','blocked','none'].includes(d.taskStatus))throw Error('Invalid task status');
  const projects=d.projects||[];
  if(!Array.isArray(projects)||projects.length>3||source==='social'&&projects.length)throw Error('Invalid projects');
  for(const p of projects){
    if(!/^[a-z0-9_-]{1,48}$/.test(p.id)||!['upsert','remove'].includes(p.operation)
      || !['garden','transplant','stockpile'].includes(p.kind)||typeof p.text!=='string'||p.text.length>400
      || typeof p.evidence!=='string'||p.evidence.length>400||p.operation!=='remove'&&!p.evidence.trim()
      || p.prefab!=null&&!/^[a-z0-9_]{1,80}$/.test(p.prefab)
      || p.count!=null&&(!Number.isInteger(p.count)||p.count<1||p.count>100)
      || p.anchor!=null&&!['speaker','observed','home'].includes(p.anchor)
      || p.targetId!=null&&!Number.isInteger(p.targetId))throw Error('Invalid project');
    if(p.operation!=='remove'&&p.kind==='transplant'&&!['dug_grass','dug_sapling','dug_berrybush','dug_berrybush2'].includes(p.prefab))throw Error('Unsupported transplant project');
  }
  const memories=d.memories||[];
  if(!Array.isArray(memories) || memories.length>3)throw Error('Too many important memories');
  for(const m of memories)if(!/^[a-z0-9_-]{1,48}$/.test(m.id)||!['upsert','remove'].includes(m.operation)
    || !['fact','preference','procedure','place'].includes(m.kind)||typeof m.text!=='string'||m.text.length>500
    || typeof m.evidence!=='string'||m.evidence.length>400||m.operation!=='remove'&&!m.evidence.trim()
    || m.anchor!=null&&!['speaker','observed'].includes(m.anchor)
    || m.targetId!=null&&!Number.isInteger(m.targetId)
    || m.id==='home'&&(m.kind!=='place'||source!=='chat'))throw Error('Invalid important memory');
  if(d.experiences.length>3) throw Error('Too many memory updates');
  if(d.learnSkill && !snapshot.availableSkills?.some(s=>s.id===d.learnSkill))throw Error('Skill is not available');
  for(const e of d.experiences) if(!/^[a-z0-9_-]{1,48}$/.test(e.id) || !['upsert','remove'].includes(e.operation)
    || typeof e.text!=='string' || e.text.length>350 || typeof e.evidence!=='string' || e.evidence.length>400
    || !Number.isFinite(e.confidence) || e.confidence<0 || e.confidence>1 || typeof e.scope!=='string' || e.scope.length>100) throw Error('Invalid experience');
  if(d.diary && (typeof d.diary.text!=='string' || d.diary.text.length>600 || !Array.isArray(d.diary.tags))) throw Error('Invalid diary');
  return d;
}
