local P = require("ai_policy")
local I = {}
local CHESTS = { treasurechest=true, icebox=true, dragonflychest=true, saltbox=true,
    scaledchest=true, shadowchester=false }

function I.Count(inst,prefab)
    local n=0
    inst.components.inventory:ForEachItem(function(v)
        if v.prefab==prefab then n=n+(v.components.stackable and v.components.stackable:StackSize() or 1) end
    end)
    return n
end

-- Keep a stackable sample so the existing chest remains an obvious destination.
-- Survival emergencies may use the last item; tools are not stackable samples.
function I.TakeCount(c,box,item,wanted,keepSample)
    local stack=item.components.stackable
    local size=stack and stack:StackSize() or 1
    local total=0
    for _,v in pairs(box.components.container.slots) do
        if v.prefab==item.prefab then total=total+(v.components.stackable and v.components.stackable:StackSize() or 1) end
    end
    local available=keepSample and stack and math.max(0,total-1) or total
    local capacity=c.inst.components.inventory:CanAcceptCount(item,wanted)
    return math.max(0,math.min(wanted,size,available,capacity))
end

function I.Find(inst,fn)
    local inv=inst.components.inventory
    for _,item in pairs(inv.equipslots) do if fn(item) then return item end end
    return inv:FindItem(fn)
end

function I.Describe(item, equipped)
    local edible = item.components.edible
    local food=edible and (edible.foodtype==FOODTYPE.MEAT or edible.foodtype==FOODTYPE.VEGGIE
        or edible.foodtype==FOODTYPE.GOODIES or edible.foodtype==FOODTYPE.GENERIC)
    local e = item.components.equippable
    return { id=item.GUID, prefab=item.prefab, name=item:GetDisplayName(),
        count=item.components.stackable and item.components.stackable:StackSize() or 1,
        food=food==true, calories=food and edible:GetHealth()>=0 and edible:GetSanity()>=-2 and edible:GetHunger() or 0,
        seed=item:HasTag("deployedfarmplant") or item.prefab == "seeds",
        gear=e ~= nil or item.components.tool ~= nil, equipped=equipped == true,
        personal=item.prefab == "abigail_flower" or item:HasTag("irreplaceable"),
        freshness=item.components.perishable and item.components.perishable:GetPercent() or nil,
        durability=item.components.finiteuses and item.components.finiteuses:GetPercent() or nil }
end

function I.Items(inst)
    local out = {}
    inst.components.inventory:ForEachItem(function(item)
        table.insert(out, I.Describe(item, item.components.equippable and item.components.equippable:IsEquipped()))
    end)
    -- Prefer keeping food that will spoil sooner, rather than saving it until rotten.
    table.sort(out, function(a,b) return (a.freshness or 2) < (b.freshness or 2) end)
    return out
end

function I.Needs(c)
    local inst = c.inst
    local duration = math.max(TUNING.SEG_TIME * 4, c.trip_seconds or TUNING.TOTAL_DAY_TIME * .5)
    local calories = math.max(0, duration * inst.components.hunger.hungerrate)
    local materials = {}
    -- Carry enough for one normal emergency torch when no spare light is present.
    local light = I.Find(inst,function(item) return item:HasTag("lighter") end)
    if not light then materials.cutgrass=2; materials.twigs=2 end
    local recipe = c.plan and c.plan.recipe and AllRecipes[c.plan.recipe]
    if recipe then for _, ing in ipairs(recipe.ingredients) do
        materials[ing.type] = math.max(materials[ing.type] or 0, ing.amount)
    end end
    for prefab,n in pairs(c.craft_reserves or {}) do materials[prefab]=math.max(materials[prefab] or 0,n) end
    if c.plan and c.plan.activity == "collect" and c.plan.prefab then
        -- While collecting, cargo is still cargo, not a permanent personal reserve.
        -- A later craft task supplies its own actual recipe reserve.
    end
    return { calories=calories, materials=materials }
end

function I.Reserves(c)
    return P.KeepCounts(I.Items(c.inst), I.Needs(c))
end

function I.AllowedChest(inst, box)
    local container = box and box:IsValid() and box.components.container
    return container and CHESTS[box.prefab] == true and not box:HasTag("burnt")
        and not container:IsOpenedByOthers(inst) and not container:IsRestricted(inst)
        and container:CanOpen() and not box:IsInLimbo()
end

function I.Chest(c, box, item)
    local container = box.components.container
    local prefabs, categories = {}, {}
    for _, v in pairs(container.slots) do
        prefabs[v.prefab] = true
        local cat = P.Category(I.Describe(v))
        categories[cat] = (categories[cat] or 0) + 1
    end
    local category, most = nil, 0
    for cat,n in pairs(categories) do if n > most then category=cat; most=n end end
    return { id=box.GUID, prefab=box.prefab, x=box:GetPosition().x, z=box:GetPosition().z,
        category=category, prefabs=prefabs, empty=container:IsEmpty(),
        room=item and container:CanAcceptCount(item) or (container:GetNumSlots()-container:NumItems()),
        ice=box.prefab == "icebox" or box.prefab == "saltbox",
        available=I.AllowedChest(c.inst, box) == true }
end

function I.NearChests(c)
    local p = c.inst:GetPosition()
    local out = {}
    for _, box in ipairs(TheSim:FindEntities(p.x,0,p.z,22,{"_container"},{"INLIMBO"})) do
        if I.AllowedChest(c.inst, box) and c.home and box:GetDistanceSqToPoint(c.home) <= 24*24 then
            table.insert(out,box)
        end
    end
    return out
end

function I.BestChest(c, item, boxes, exclude)
    local best, score = nil, -1000
    for _, box in ipairs(boxes) do
        if box ~= exclude then
            local n = P.ChestScore(I.Describe(item), I.Chest(c,box,item))
            if n > score then best=box; score=n end
        end
    end
    return best, score
end

-- Executed by a BufferedAction at the chest, never by a remote HTTP callback.
function I.Transfer(c, act)
    local box = act.target
    if not I.AllowedChest(c.inst,box) or c.inst:GetDistanceSqToInst(box) > 3.5*3.5 then return false end
    local inv, container = c.inst.components.inventory, box.components.container
    local item = act.invobject
    if not item or not item:IsValid() then return false end
    local take = act.options and act.options.ai_take == true
    local n = math.floor(tonumber(act.options and act.options.ai_count) or 0)
    if n < 1 then return false end
    if take then n=require("ai_reservations").TakeLimit(c,item.prefab,n);if n<1 then return false end end
    local source, dest
    if take then
        if not container:IsHolding(item) then return false end
        source=container; dest=inv
        n=I.TakeCount(c,box,item,n,act.options.ai_keep_sample)
    else
        if not inv:IsHolding(item,true) then return false end
        local keep = I.Reserves(c)
        if act.options.ai_sort_cargo and c.sortcargo and c.sortcargo.prefab==item.prefab then
            local d=I.Describe(item,item.components.equippable and item.components.equippable:IsEquipped())
            if d.gear and not d.equipped and not d.personal then
                keep[item.GUID]=math.max(0,d.count-c.sortcargo.remaining)
            end
        end
        n = math.min(n, I.Describe(item).count - (keep[item.GUID] or 0))
        if n < 1 then return false end
        n = math.min(n,container:CanAcceptCount(item))
        source=inv; dest=container
    end
    if n < 1 then return false end
    container:Open(c.inst)
    if not container:IsOpenedBy(c.inst) then return false end
    -- onopenfn may sort/stack contents; recompute after every such mod hook.
    if not source:IsHolding(item,true) then container:Close(c.inst);return false end
    if take then n=I.TakeCount(c,box,item,n,act.options.ai_keep_sample)
    else n=math.min(n,container:CanAcceptCount(item)) end
    if n<1 then container:Close(c.inst);return false end
    local moved
    if item.components.stackable and n < item.components.stackable:StackSize() then
        moved=item.components.stackable:Get(n)
    else moved=source:RemoveItem(item,true) end
    if moved == nil then container:Close(c.inst); return false end
    -- An intentional chest transfer must not trigger vanilla GiveItem's
    -- "return to previous open container" shortcut for whole stacks/tools.
    moved.prevcontainer=nil;moved.prevslot=nil
    local movedId=moved.GUID
    local ok = dest:GiveItem(moved,nil,c.inst:GetPosition(),false)
    if not ok and moved:IsValid() and moved.components.inventoryitem.owner == nil then
        source:GiveItem(moved,nil,c.inst:GetPosition(),true)
    end
    container:Close(c.inst)
    if ok and take and act.options.ai_sort_to then
        local destination=Ents[act.options.ai_sort_to]
        local dp=destination and destination:GetPosition()
        local sp=box:GetPosition()
        c.sortcargo={prefab=item.prefab,itemid=movedId,remaining=n,destination=act.options.ai_sort_to,source=box.GUID,
            destination_pos=dp and {x=dp.x,z=dp.z},source_pos={x=sp.x,z=sp.z}}
    elseif ok and not take and act.options.ai_sort_cargo and c.sortcargo then
        c.sortcargo.remaining=c.sortcargo.remaining-n
        if c.sortcargo.remaining<=0 then c.sortcargo=nil end
    end
    c:Event(ok and "transfer_success" or "transfer_failed", {prefab=item.prefab, count=n, take=take, box=box.GUID,taskContext=act.ai_task_context})
    return not not ok
end

function I.Store(c, sorting)
    c.storage_full=false
    local boxes = I.NearChests(c)
    if c.sortcargo then
        local cargo=c.sortcargo
        local item=Ents[cargo.itemid]
        if not item or not c.inst.components.inventory:IsHolding(item,true) then
            item=I.Find(c.inst,function(v)return v.prefab==cargo.prefab and not (v.components.equippable and v.components.equippable:IsEquipped()) end)
        end
        if not item then c.sortcargo=nil
        else
            local function resolve(id,pos)
                local box=Ents[id]
                if I.AllowedChest(c.inst,box) then return box end
                if pos then for _,v in ipairs(boxes) do
                    if v:GetDistanceSqToPoint(Vector3(pos.x,0,pos.z))<.5 then return v end
                end end
            end
            local box=resolve(cargo.destination,cargo.destination_pos) or resolve(cargo.source,cargo.source_pos)
            if box and I.AllowedChest(c.inst,box) then return c:TransferAction(box,item,cargo.remaining,false) end
            c.status="整理货物仍在背包，目标箱暂不可用；先不取新的物品"
            return false
        end
    end
    local keep = I.Reserves(c)
    local surplus=false
    for _, d in ipairs(I.Items(c.inst)) do
        local item = Ents[d.id]
        if d.count > (keep[d.id] or 0) and item and not d.equipped then
            surplus=true
            local box = I.BestChest(c,item,boxes)
            if box then return c:TransferAction(box,item,d.count-(keep[d.id] or 0),false) end
        end
    end
    if sorting and not c.inst.components.inventory:IsFull() then
        for _, source in ipairs(boxes) do
            for _, item in pairs(source.components.container.slots) do
                local dest, score = I.BestChest(c,item,boxes,source)
                local current = P.ChestScore(I.Describe(item),I.Chest(c,source,item))
                if dest and score >= current+4 then
                    -- Transfer through her own inventory and walk to the destination next tick.
                    return c:TransferAction(source,item,I.Describe(item).count,true,dest.GUID)
                end
            end
        end
    end
    if not surplus and not c.storage_requested and require("ai_staging").Recover(c) then return true end
    c.storage_full=surplus or c.storage_requested and #(c.staged_cargo or {})>0
    return false
end

function I.TakeNeeded(c, prefab, amount)
    require("ai_resources").Refresh(c)
    local h=c.inst.components.hunger;local hp=c.inst.components.health
    local starving=h and (h:GetPercent()<.08 or hp and hp:GetPercent()<.2 and h:GetPercent()<.25)
    local dark=TheWorld and not TheWorld.state.isday and c.inst.LightWatcher and c.inst.LightWatcher:GetLightValue()<.12
    local keepSample=not (starving or dark or c.plan and c.plan.useLast)
    for _, box in ipairs(I.NearChests(c)) do
        for _, item in pairs(box.components.container.slots) do
            if item.prefab == prefab then
                local n=I.TakeCount(c,box,item,require("ai_reservations").TakeLimit(c,prefab,amount),keepSample)
                if n>0 then return c:TransferAction(box,item,n,true,nil,keepSample) end
            end
        end
    end
    local best,dist
    for _,box in pairs(c.stock or {}) do
        local n=(box.counts[prefab] or 0)-(keepSample and 1 or 0)
        local d=c.inst:GetDistanceSqToPoint(Vector3(box.x,0,box.z))
        if n>0 and d>22*22 and (not dist or d<dist) then best=box;dist=d end
    end
    if best then return c:MoveTo(Vector3(best.x,0,best.z),"回记下的箱子核对并取用 "..prefab,2) end
    return false
end
return I
