local I=require("ai_inventory")
local P={}
function P.Target(c)
    local state=TheWorld.state
    local inst=c.inst
    if not state.isday and not I.Find(inst,function(e)return e:HasTag("lighter") end) then return "torch","天黑前补好照明" end
    local remaining=state.remainingdaysinseason
    local winter=state.season=="winter" or state.season=="autumn" and remaining and remaining<=5
    if winter then
        if not I.Find(inst,function(e)return e.components.insulator and e.components.insulator:IsType(SEASONS.WINTER) and e.components.equippable end) then
            return "winterhat","为冬季准备保暖装备"
        end
        if I.Count(inst,"heatrock")==0 then return "heatrock","为冬季准备暖石" end
    end
    if state.israining and not I.Find(inst,function(e)return e.components.waterproofer and e.components.equippable end) then
        return "umbrella","为雨天准备防水装备"
    end
end
function P.Tick(c)
    if not c.home or c.inst:GetDistanceSqToPoint(c.home)>24*24 or c.threat then return false end
    local target,reason=P.Target(c)
    if not target or GetTime()<(c.next_preparation or 0) then return false end
    if not c.preparation or c.preparation.recipe~=target then
        c.preparation={recipe=target,reason=reason,started=GetTime()}
    end
    if GetTime()-c.preparation.started>45 then c.preparation=nil;c.next_preparation=GetTime()+60;return false end
    if I.TakeNeeded(c,target,1) then return true end
    local active=require("ai_crafting").Step(c,target)
    if not active then c.next_preparation=GetTime()+30;c.preparation=nil end
    return active
end
return P
