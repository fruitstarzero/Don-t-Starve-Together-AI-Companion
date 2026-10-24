-- Explicit owner-only convenience action, separate from the sign mod and from
-- normal walking/following. Never loads a shard or changes survival statistics.
local T={}
function T.ToOwner(c,owner)
    local inst=c.inst
    if not owner or not owner:IsValid() or owner.userid~=c.ownerid then
        c.status="主人不在当前分片，不能跨分片传送";return false
    end
    if inst:HasTag("playerghost") or inst.components.health:IsDead() or owner:HasTag("playerghost") then
        c.status="幽灵或死亡状态不使用此传送，请按原版机制复活";return false
    end
    if GetTime()-(c.lastteleport or -10000)<10 then c.status="传送稍作冷却后再试";return false end
    if inst:GetCurrentPlatform() or owner:GetCurrentPlatform()
        or inst.components.rider and inst.components.rider:IsRiding() then
        c.status="船上或骑乘时暂不使用地表传送";return false
    end
    if inst.sg:HasStateTag("busy") or inst.sg:HasStateTag("nointerrupt") then
        c.status="正在完成动作，请稍后再传送";return false
    end
    local p=owner:GetPosition()
    local offset=FindWalkableOffset(p,0,2,12,true,false,nil,false,false)
    if not offset then c.status="你身边没有安全可站立的位置";return false end
    local dest=p+offset
    c:Stop()
    inst.Physics:Teleport(dest.x,0,dest.z)
    local bond=inst.components.ghostlybond
    local ghost=bond and bond.summoned and bond.ghost
    if ghost and ghost:IsValid() and not ghost:IsInLimbo() then ghost.Physics:Teleport(dest.x,0,dest.z) end
    c.mode="stay";c.lastteleport=GetTime();c.status="已传送到你身边"
    c:Event("teleported_to_owner",{x=dest.x,z=dest.z,shard=TheShard:GetShardId()})
    return true
end
return T
