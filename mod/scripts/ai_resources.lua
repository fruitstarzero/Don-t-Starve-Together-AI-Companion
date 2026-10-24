local R={}
-- Conservative companion policy, not a claim about vanilla renewability.
R.precious={mandrake={keep=3,ample=5},cookedmandrake={keep=3,ample=5},
    deerclops_eyeball={keep=1,ample=2},minotaurhorn={keep=1,ample=2},
    opalpreciousgem={keep=1,ample=2},greengem={keep=1,ample=2},yellowgem={keep=1,ample=2}}
function R.Name(prefab)
    return STRINGS and STRINGS.NAMES[string.upper(prefab)] or prefab
end
function R.Refresh(c)
    local I=require("ai_inventory")
    c.stock=c.stock or {}
    if not c.home then for _,box in pairs(c.stock) do box.current=false end;return end
    for _,box in ipairs(I.NearChests(c)) do
        local p=box:GetPosition();local key=string.format("%.1f/%.1f",p.x,p.z)
        local counts={}
        for _,item in pairs(box.components.container.slots) do
            counts[item.prefab]=(counts[item.prefab] or 0)+(item.components.stackable and item.components.stackable:StackSize() or 1)
        end
        c.stock[key]={x=p.x,z=p.z,id=box.GUID,counts=counts,at=GetTime(),current=true,
            freeSlots=box.components.container:GetNumSlots()-box.components.container:NumItems()}
    end
    -- Current means verifiable nearby now, never a remote live inventory read.
    for key,box in pairs(c.stock) do
        local e=Ents[box.id]
        if (box.x-c.home.x)^2+(box.z-c.home.z)^2>24*24 then c.stock[key]=nil
        elseif not e or not e:IsValid() then
            if box.current or c.inst:GetDistanceSqToPoint(Vector3(box.x,0,box.z))<20*20 then c.stock[key]=nil end
        elseif c.inst:GetDistanceSqToInst(e)>22*22 or not I.AllowedChest(c.inst,e) then box.current=false end
    end
end
function R.Count(c,prefab)
    local own=0
    c.inst.components.inventory:ForEachItem(function(item)
        if item.prefab==prefab then own=own+(item.components.stackable and item.components.stackable:StackSize() or 1) end
    end)
    local total=own
    for _,box in pairs(c.stock or {}) do if box.current then total=total+(box.counts[prefab] or 0) end end
    return total,own
end
function R.CanUse(c,prefab,amount,recipe)
    local policy=R.precious[prefab]
    if not policy then return require("ai_reservations").CanSpend(c,prefab,amount,recipe) end
    local total=R.Count(c,prefab)
    return total>=policy.ample and total-amount>=policy.keep
        and require("ai_reservations").CanSpend(c,prefab,amount,recipe)
end
function R.CanEat(c,item,emergency)
    local e=item.components.edible
    if not e or e:GetHealth(c.inst)<0 or e:GetHunger(c.inst)<=0 or not c.inst.components.eater:CanEat(item) then return false end
    if R.CanUse(c,item.prefab,1) then return true end
    -- A narrow life-saving exception for direct consumption only. It never
    -- opens crafting, fuel or crockpot paths, and ordinary food is tried first.
    if not emergency or not R.precious[item.prefab] then return false end
    return e and e:GetHealth(c.inst)>=0 and e:GetHunger(c.inst)>0
        and c.inst.components.eater:CanEat(item)
end
function R.CheckRecipe(c,name,report)
    local recipe=AllRecipes[name]
    if not recipe then return false end
    R.Refresh(c)
    for _,ing in ipairs(recipe.ingredients) do
        if not R.CanUse(c,ing.type,ing.amount,name) then
            if report then c:Problem("precious_resource",{recipe=name,prefab=ing.type,name=R.Name(ing.type),
                count=R.Count(c,ing.type),reason=R.precious[ing.type] and "珍贵材料存量不足，先保留储备" or "这份材料已留给后续任务或季节准备，先补足缺额"}) end
            return false
        end
    end
    return true
end
function R.Snapshot(c)
    R.Refresh(c)
    local known,confirmed,boxes,locations={}, {},0,{}
    for _,box in pairs(c.stock or {}) do
        boxes=boxes+1
        for prefab,n in pairs(box.counts) do
            known[prefab]=(known[prefab] or 0)+n
            if box.current then confirmed[prefab]=(confirmed[prefab] or 0)+n end
            locations[prefab]=locations[prefab] or {}
            locations[prefab][#locations[prefab]+1]={id=box.id,x=box.x,z=box.z,count=n,
                current=box.current,freeSlots=box.freeSlots}
        end
    end
    local items={}
    for prefab,n in pairs(known) do items[#items+1]={prefab=prefab,name=R.Name(prefab),count=n,confirmed=confirmed[prefab] or 0} end
    table.sort(items,function(a,b)return a.prefab<b.prefab end)
    return {items=items,known=known,confirmed=confirmed,locations=locations,observedBoxes=boxes,protected=R.precious,
        reservations=require("ai_reservations").Compute(c),debts=c.resource_debts,
        note="known 是访问过箱子的记录；confirmed 只包含当前近处可核对箱子，不含主人背包。"}
end
return R
