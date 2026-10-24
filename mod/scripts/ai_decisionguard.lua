local D={}
function D.Stale(result,c)
    if not (result.plan or result.workflow or result.command or result.method or result.goalBoard or result.learnSkill or #(result.projectUpdates or {})>0
        or #(result.placeUpdates or {})>0) then return false end
    local guard=result.taskGuard
    if guard and (guard.id~=(c.job and c.job.id or false) or guard.index~=(c.job and c.job.index or 0)
        or guard.closed~=(c.job and (c.job.status=="complete" or c.job.status=="cancelled") or false)) then return true end
    local before=result.decisionContext
    if not before then return false end -- Legacy bridge during a controlled upgrade.
    if type(before.at)~="number" or GetTime()-before.at>45 or GetTime()<before.at then return true end
    local state=TheWorld.state
    if before.phase and before.phase~=state.phase or before.season and before.season~=state.season
        or before.raining~=nil and before.raining~=state.israining then return true end
    if before.ghost~=nil and before.ghost~=c.inst:HasTag("playerghost") then return true end
    if before.critical~=nil and before.critical~=(c.inst.components.health:GetPercent()<.3) then return true end
    return false
end
return D
