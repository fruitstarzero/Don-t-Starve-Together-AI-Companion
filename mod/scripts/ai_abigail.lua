local A={}
function A.Tick(c)
    local inst=c.inst
    local bond=inst.components.ghostlybond;local ghost=bond and bond.ghost
    if not ghost or not ghost:IsValid() then return false end
    local hp=ghost.components.health:GetPercent()
    local urgent=bond.summoned and (hp<.2 or inst.components.health:GetPercent()<.2)
    if not urgent and (GetTime()<(c.abigail_manual_until or 0) or GetTime()<(c.abigail_next or 0)) then return false end
    local flower=inst.components.inventory:FindItem(function(v)return v.prefab=="abigail_flower" end)
    if not flower then return false end
    local owner=c:Owner();local enemy=c.threat
    if not enemy and c.mode=="follow" and owner and inst:GetDistanceSqToInst(owner)<12*12 then enemy=owner.components.combat.target end
    local danger=enemy and enemy:IsValid() and not enemy:HasTag("player") and not enemy:HasTag("companion")
        and enemy.components.health and not enemy.components.health:IsDead() and inst:GetDistanceSqToInst(enemy)<12*12
    local withdraw=hp<.3 or inst.components.health:GetPercent()<.3 or c.mode=="retreat"
    local action
    if bond.summoned and withdraw then action=ACTIONS.CASTUNSUMMON
    elseif bond.notsummoned and danger and not withdraw and hp>.5 then action=ACTIONS.CASTSUMMON
    elseif bond.summoned and ghost.is_defensive~=nil then
        local aggressive=danger and not withdraw and not enemy:HasTag("epic")
        if ghost.is_defensive==aggressive then action=ACTIONS.COMMUNEWITHSUMMONED end
    end
    if action then c.abigail_next=GetTime()+5;return c:Act(action,nil,flower) end
    return false
end
return A
