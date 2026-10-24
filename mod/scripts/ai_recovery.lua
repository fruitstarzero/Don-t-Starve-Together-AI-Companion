-- Useful bounded detours never install a new plan over the root task.
local X={}
function X.Tick(c)
    local job=c.job;local a=job and job.approach
    if c.mode~="auto" or not job or job.status~="blocked" or not a
        or GetTime()>(a.detourUntil or 0) then return false end
    c.work_context="detour"
    local I=require("ai_inventory")
    local near=c.home and c.inst:GetDistanceSqToPoint(c.home)<=20*20
    if near and I.Store(c,false) then return true end
    if near and require("ai_projects").Tick(c) then return true end
    if near and c:Cook() then return true end
    c.status="保留原目标，等待新材料或安全路线；稍后重试"
    return false
end
return X
