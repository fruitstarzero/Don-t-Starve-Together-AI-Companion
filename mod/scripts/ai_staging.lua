-- A bounded, recoverable use of ordinary DROP/PICKUP when both bags and chests
-- are full. Never discard food, equipment, precious resources or unknown mod items.
local I=require("ai_inventory")
local S={}
local ordinary={rocks=true,flint=true,goldnugget=true,nitre=true,charcoal=true,ash=true,
    cutstone=true,cutreeds=true,rope=true,poop=true,guano=true,beardhair=true,pigskin=true,
    spidergland=true,silk=true,stinger=true}
function S.MakeRoom(c)
    local inv=c.inst.components.inventory
    if inv:GetNumSlots()-inv:NumItems()>=2 or inv:Has("boards",3) then return false end
    c.staged_cargo=c.staged_cargo or {}
    if #c.staged_cargo>=2 then return false end
    if not c.home or c.inst:GetDistanceSqToPoint(c.home)>6*6
        or require("ai_safety").Risk(c,c.inst:GetPosition())>0 or TheWorld.state.isnight then return false end
    for _,e in ipairs(c:Scan(12)) do
        if e.prefab=="mole" or e.prefab=="catcoon" or e.prefab=="slurtle" or e.prefab=="snurtle"
            or e.components.burnable and e.components.burnable:IsBurning() and c.inst:GetDistanceSqToInst(e)<6*6 then return false end
    end
    local keep=I.Reserves(c)
    for _,d in ipairs(I.Items(c.inst)) do
        if ordinary[d.prefab] and not d.food and not d.gear and not d.personal and (keep[d.id] or 0)==0 then
            local item=Ents[d.id]
            if item and inv:IsHolding(item,true) and not item.components.inventoryitem.islockedinslot then
                return c:Act(ACTIONS.DROP,nil,item,c.inst:GetPosition(),{wholestack=true,ai_stage=true})
            end
        end
    end
    return false
end
function S.Record(c,item,pos)
    c.staged_cargo=c.staged_cargo or {}
    if #c.staged_cargo>=2 then return end
    c.staged_cargo[#c.staged_cargo+1]={id=item.GUID,prefab=item.prefab,x=pos.x,z=pos.z,
        count=item.count}
end
function S.Recover(c)
    local entry=c.staged_cargo and c.staged_cargo[1]
    if not entry or c.storage_requested then return false end
    local point=Vector3(entry.x,0,entry.z)
    if c.inst:GetDistanceSqToPoint(point)>22*22 then return c:MoveTo(point,"回去取临时腾位的普通物资",2) end
    local item=Ents[entry.id]
    if item and item:IsValid() and c.inst.components.inventory:IsHolding(item,true) then S.Recovered(c,entry.id);return false end
    if not item or not item:IsValid() or item.prefab~=entry.prefab
        or item.components.inventoryitem.owner~=nil then
        item=c:Find(function(e)return e.prefab==entry.prefab and e.components.inventoryitem
            and e.components.inventoryitem.owner==nil and e:GetDistanceSqToPoint(point)<4*4 end,24)
    end
    if not item then c:Problem("storage_recovery",{prefab=entry.prefab,reason="临时腾位的物资不在原处，需要检查或帮忙取回"});return false end
    local n=item.components.stackable and item.components.stackable:StackSize() or 1
    if c.inst.components.inventory:CanAcceptCount(item,n)<n then return false end
    return c:Act(ACTIONS.PICKUP,item,nil,nil,{ai_recover=entry.id})
end
function S.Recovered(c,id)
    for i=#(c.staged_cargo or {}),1,-1 do if c.staged_cargo[i].id==id then table.remove(c.staged_cargo,i) end end
end
return S
