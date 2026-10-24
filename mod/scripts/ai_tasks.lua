-- World-owned task journal. Temporary actions never replace the current step.
local T={}
local finite={craft=true,collect=true,visit=true,transplant=true,store=true}
local function copy(v)
    if type(v)~="table" then return v end
    local out={};for k,x in pairs(v) do out[k]=copy(x) end;return out
end
local function active(c)
    return c.job and c.job.status~="complete" and c.job.status~="cancelled"
end
function T.Block(c,kind,detail)
    if not active(c) or c.job.status=="paused" or c.mode~="auto"
        or c.work_context=="survival" or c.work_context=="detour" or c.work_context=="combat" then return false end
    local method=c.job.approach or {attempt=1,failures={}}
    c.job.approach=method;method.failures=method.failures or {}
    local key=kind..":"..tostring(detail and (detail.prefab or detail.recipe or detail.destination) or "")
    if c.job.status~="blocked" then
        method.failures[key]=(method.failures[key] or 0)+1
        method.failure=kind;method.detail=copy(detail);method.blockedAt=GetTime()
        c.task_retry_at=GetTime()+math.min(240,30*2^math.min(3,method.failures[key]-1))
        method.retryAt=c.task_retry_at;method.evidence=c.resource_revision
        method.detourUntil=GetTime()+20
        T.Checkpoint(c,"方法受阻，保留原目标")
    end
    c.job.status="blocked"
    return true
end
function T.Checkpoint(c,reason)
    if not active(c) then return end
    c.job.steps[c.job.index]=c.plan
    c.job.checkpoint={reason=reason,day=TheWorld and TheWorld.state.cycles,
        position={x=c.inst:GetPosition().x,z=c.inst:GetPosition().z},
        built=c.plan.built or 0,delivered=c.plan.delivered or 0,progress=c.plan.progress or 0}
end
function T.Archive(c,status,reason)
    if not active(c) then return end
    T.Checkpoint(c,reason);c.job.status=status
    c.task_history=c.task_history or {};table.insert(c.task_history,copy(c.job))
    while #c.task_history>8 do table.remove(c.task_history,1) end
    c:Event("task_"..status,{taskId=c.job.id,reason=reason})
end
function T.Accept(c,plan,workflow,source,goal)
    if source=="autonomy" and active(c) then
        -- Periodic suggestions may not reset counters, skip stages or abandon a goal.
        if c.job.source~="autonomy" or finite[c.plan.activity] then return false end
        -- Self-chosen ongoing chores need to respond to changing daily needs.
        if plan and c.plan.activity==plan.activity and c.plan.recipe==plan.recipe and c.plan.prefab==plan.prefab
            and c.plan.placeId==plan.placeId and c.plan.count==plan.count then return false end
    end
    if active(c) then T.Archive(c,"cancelled",source=="chat" and "主人安排了新目标" or "自主生活需求改变") end
    c:Stop();c.problem=nil;c.craft_reserves=nil;c.storage_requested=nil;c.project_visit=nil;c.search_until=nil
    c.method_plan=nil;c.method_until=nil
    c.material_searches=nil;c.procurement=nil
    c.mode="auto";c.trip_seconds=c.trip_seconds or 240
    if not workflow and plan.activity=="auto" then c.plan=copy(plan);return true end
    c.task_sequence=(c.task_sequence or 0)+1
    local steps=workflow and copy(workflow.steps) or {copy(plan)}
    c.job={id=tostring(c.inst.GUID).."-"..c.task_sequence,goal=workflow and workflow.goal or goal or plan.reason,
        source=source,index=1,steps=steps,status="active",approach={attempt=1,failures={}}}
    c.plan=steps[1];c.task_last_progress=GetTime();c.task_retry_at=nil
    c.job.clock={work=0,last=GetTime()}
    T.Checkpoint(c,"接受目标");c:Event("task_started",{taskId=c.job.id,goal=c.job.goal,activity=c.plan.activity});return true
end
function T.Repair(c,plan,reason)
    if not active(c) or c.mode~="auto" or c.job.status=="paused" or not require("ai_policy").ValidPlan(plan)
        or not ({craft=true,collect=true,store=true,visit=true})[plan.activity] then return false end
    c:Stop();c.method_plan=copy(plan);c.method_until=GetTime()+90
    c.job.method={plan=c.method_plan,reason=reason};c.job.status="active";c.problem=nil
    c.job.clock={work=0,last=GetTime()};c.task_retry_at=nil
    c.job.approach=c.job.approach or {attempt=1,failures={}};c.job.approach.attempt=c.job.approach.attempt+1
    c.job.approach.state=reason;T.Checkpoint(c,"保留根目标，调整当前方法")
    c:Event("method_started",{taskId=c.job.id,reason=reason});return true
end
function T.Method(c)
    local p=c.method_plan;if not p then return false end
    local done=false;local I=require("ai_inventory")
    if GetTime()>=(c.method_until or 0) then done=true
    elseif p.activity=="collect" then
        if I.Count(c.inst,p.prefab)>=(p.count or 1) then done=true
        elseif require("ai_crafting").Acquire(c,p.prefab,math.max(1,(p.count or 1)-I.Count(c.inst,p.prefab))) then return true end
    elseif p.activity=="craft" then
        if (p.built or 0)>=(p.count or 1) then done=true
        elseif require("ai_crafting").Step(c,p.recipe) then return true end
    elseif p.activity=="store" then
        if c.home and c:MoveTo(c.home,"先存本批物资，再继续根目标",4) then return true end
        if I.Store(c,false) or require("ai_crafting").Storage(c) then return true end
        done=not c.storage_full and not c.sortcargo and #(c.staged_cargo or {})==0
    elseif p.activity=="visit" then
        local place=c.landmarks and c.landmarks[p.placeId]
        if place and place.position then
            local dest=Vector3(place.position.x,0,place.position.z)
            if c.inst:GetDistanceSqToPoint(dest)<=4 then done=true
            elseif c:MoveTo(dest,"按新方法前往已知地点",2) then return true end
        end
    end
    if done then
        local expired=GetTime()>=(c.method_until or 0)
        c.method_plan=nil;c.method_until=nil;if c.job then c.job.method=nil end
        c:Event(expired and "method_expired" or "method_complete",{activity=p.activity,reason=p.reason})
        return false
    end
    c.status="当前方法缺少条件，保留根目标等待下一次判断";return true
end
function T.Command(c,command)
    if command=="cancel" then
        c.method_plan=nil;c.method_until=nil
        T.Archive(c,"cancelled","主人明确取消")
        c.plan={activity="auto",reason="已取消旧目标"};c.mode="auto";return
    end
    if command=="auto" or command=="resume" then
        c.mode="auto"
        if active(c) then
            c.job.status="active";c.job.interruption=nil;c.plan=c.job.steps[c.job.index]
            c.job.materialSearch=nil;c.search_until=nil
            c.material_searches=nil
            c.task_last_progress=GetTime();c.task_retry_at=nil
            c.job.clock={work=0,last=GetTime()}
            T.Checkpoint(c,"主人恢复原任务")
            if c.job.pendingEvidence then
                local evidence=c.job.pendingEvidence;c.job.pendingEvidence=nil;T.Complete(c,evidence)
            end
        else c.plan={activity="auto",reason="自主判断生活需要"} end
    elseif command=="follow" or command=="stay" or command=="come" or command=="home" or command=="retreat" or command=="teleport" then
        if active(c) then c.job.status="paused";c.job.interruption="主人指令："..command;T.Checkpoint(c,c.job.interruption) end
    end
end
function T.Interrupt(c,reason)
    if not active(c) or c.job.status=="paused" then return end
    if c.job.interruption~=reason then T.Checkpoint(c,reason) end
    c.job.interruption=reason
    -- Exclude interruption time, but retain unsuccessful work accumulated earlier.
    c.job.clock=c.job.clock or {work=0,last=GetTime()}
    c.job.clock.last=GetTime()
end
function T.Ready(c)
    if not active(c) then return true end
    if c.job.status=="paused" then return false end
    local interrupted=c.job.interruption~=nil
    c.job.interruption=nil
    local clock=c.job.clock or {work=0,last=GetTime()};c.job.clock=clock
    if interrupted then clock.last=GetTime() end
    if c.job.status=="blocked" then
        local evidence=c.job.approach and c.job.approach.evidence
        local changed=evidence and c.resource_revision and evidence~=c.resource_revision
        if not changed and GetTime()<(c.task_retry_at or 0) then
            c.status="原任务受阻，保留进度等待条件改善"
            if c.problem then c.problem.updated=GetTime() end
            return false
        end
        c.job.status="active";c.task_last_progress=GetTime()
        clock.work=0;clock.last=GetTime()
        if changed then c.material_searches=nil end
        c.job.approach=c.job.approach or {attempt=1,failures={}}
        c.job.approach.attempt=c.job.approach.attempt+1
        c.job.approach.state="重新核对库存并尝试其它可达来源"
    end
    clock.work=clock.work+math.max(0,GetTime()-clock.last);clock.last=GetTime()
    if finite[c.plan.activity] and clock.work>120 then
        c.job.status="blocked";c.job.stalls=(c.job.stalls or 0)+1
        c.task_retry_at=GetTime()+math.min(240,30*2^(c.job.stalls-1))
        c.job.approach=c.job.approach or {attempt=1,failures={}}
        c.job.approach.failure="task_stalled";c.job.approach.retryAt=c.task_retry_at
        c.job.approach.detourUntil=GetTime()+20
        T.Checkpoint(c,"持续没有实质进展")
        c:Problem("task_stalled",{reason="原任务一段时间没有进展，先保留目标；需要检查材料、路线或给我新的安排",taskId=c.job.id,
            activity=c.plan.activity,recipe=c.plan.recipe,prefab=c.plan.prefab})
        return false
    end
    return true
end
function T.Context(c)
    return active(c) and {id=c.job.id,index=c.job.index,kind=c.work_context or "objective"} or nil
end
function T.Progress(c,kind,detail)
    if not active(c) or c.job.status=="paused" then return false end
    detail=detail or {}
    local context=detail.taskContext
    if context and (context.id~=c.job.id or context.index~=c.job.index
        or context.kind~="objective") then return false end
    local p=c.plan;local material=p.activity=="collect" and p.prefab or nil
    local function needed(prefab)return prefab and (prefab==material or (c.craft_reserves or {})[prefab]~=nil) end
    local relevant=false
    if kind=="build_success" then
        relevant=p.activity=="craft" and detail.recipe==p.recipe
        for _,name in ipairs(c.procurement and c.procurement.chain or {}) do
            if name==detail.recipe then relevant=true end
        end
    elseif kind=="transfer_success" then
        relevant=(detail.count or 0)>0 and (detail.take and needed(detail.prefab)
            or detail.take==false and (p.activity=="store" or p.activity=="sort" or material==detail.prefab))
    elseif kind=="action_success" then
        relevant=needed(detail.product or (detail.action=="PICKUP" and detail.prefab))
            and (detail.action=="CHOP" or detail.action=="MINE" or detail.action=="PICK" or detail.action=="PICKUP")
        if p.activity=="transplant" and (detail.action=="DIG" or detail.action=="DEPLOY") then relevant=true end
    end
    if relevant then
        c.job.stalls=0
        if c.job.status=="blocked" then c.job.status="active";c.task_retry_at=nil end
        c.task_last_progress=GetTime();c.job.clock={work=0,last=GetTime()};T.Checkpoint(c,kind)
        return true
    end
    return false
end
function T.Complete(c,evidence)
    if not active(c) then c.plan={activity="auto",reason="本地目标已完成"};return end
    if c.job.status=="paused" then c.job.pendingEvidence=copy(evidence);T.Checkpoint(c,"暂停期间原动作已完成，等主人恢复");return end
    c.method_plan=nil;c.method_until=nil;c.job.method=nil
    T.Checkpoint(c,"实际完成当前步骤")
    c.job.steps[c.job.index].evidence=copy(evidence)
    if c.job.index<#c.job.steps then
        c.job.index=c.job.index+1;c.plan=c.job.steps[c.job.index];c.job.materialSearch=nil;c.search_until=nil
        c.material_searches=nil;c.procurement=nil
        c.job.status="active";c.task_last_progress=GetTime();c.problem=nil;c.craft_reserves=nil
        c.job.clock={work=0,last=GetTime()};c.job.approach={attempt=1,failures={}}
        c:Event("task_stage",{taskId=c.job.id,index=c.job.index,activity=c.plan.activity})
    else
        T.Archive(c,"complete","游戏实际完成所有步骤")
        c.plan={activity="auto",reason="目标已实际完成，继续自主生活"}
    end
end
function T.Load(c,data)
    c.job=data.job;c.task_history=data.task_history or {};c.task_sequence=data.task_sequence or 0
    if active(c) then
        c.method_plan=c.job.method and c.job.method.plan;c.method_until=c.method_plan and GetTime()+90
        c.plan=c.job.steps[c.job.index]
        c.task_last_progress=GetTime();c.task_retry_at=GetTime()+10
        c.job.clock={work=0,last=GetTime()}
        if c.job.approach then c.job.approach.retryAt=c.task_retry_at;c.job.approach.detourUntil=GetTime()+10 end
    elseif c.plan and c.plan.activity~="auto" then
        -- Migrate a saved 0.4 task without discarding its accumulated counters.
        local plan=c.plan;T.Accept(c,plan,nil,"legacy",plan.reason)
        c.mode=data.mode or "auto"
        if c.mode~="auto" then c.job.status="paused";c.job.interruption="载入先前手动模式" end
    end
end
return T
