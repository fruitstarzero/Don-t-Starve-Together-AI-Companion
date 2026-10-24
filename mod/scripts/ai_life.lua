local I=require("ai_inventory")
local cooking=require("cooking")
local R=require("ai_resources")
local L={}

-- Evaluate combinations using this installed version's recipes. Do not use a
-- cookbook copied from an older version or consume someone else's pot contents.
function L.CrockPot(c)
    if c.cookingjob then
        local job=c.cookingjob
        local old=c:Find(function(v)return v.prefab=="cookpot" and v:GetDistanceSqToPoint(Vector3(job.x,0,job.z))<.5 end,22)
        if old then c.cookingpot=old.GUID;c.cookingredients=job.ingredients or {};c.cookingjob=nil end
    end
    local pot=c:Find(function(v)
        return v.prefab=="cookpot" and v.components.stewer and not v.components.stewer:IsCooking()
            and not v.components.stewer:IsDone() and not v.components.container:IsOpenedByOthers(c.inst)
    end,18)
    if not pot then return false end
    local container=pot.components.container
    if not container:IsEmpty() and c.cookingpot~=pot.GUID then return false end
    if container:IsFull() then
        return c:Act(ACTIONS.COOK,pot,nil,nil,{ai_cook_finish=true})
    end
    if c.cookingpot==pot.GUID and c.cookingredients then
        local prefab=c.cookingredients[1]
        if prefab then
            local item=I.Find(c.inst,function(v)return v.prefab==prefab end)
            if item then return c:Act(ACTIONS.AI_COOKSTORE,pot,item) end
        end
        c.status="锅料缺失，保留半锅材料等待补给"
        return false
    end
    local list={}
    local allocated={}
    for _,d in ipairs(I.Items(c.inst)) do
        if cooking.ingredients[d.prefab] and #list<10 and not d.equipped and not d.personal then
            local total=R.Count(c,d.prefab)
            local policy=R.precious[d.prefab]
            local usable=policy and (total>=policy.ample and math.max(0,total-policy.keep) or 0) or d.count
            local amount=policy and math.min(d.count,math.max(0,usable-(allocated[d.prefab] or 0))) or d.count
            if amount>0 then list[#list+1]={prefab=d.prefab,count=amount};allocated[d.prefab]=(allocated[d.prefab] or 0)+amount end
        end
    end
    local best,bestscore=nil,-math.huge
    local combination,used={},{}
    local tries=0
    local hp=c.inst.components.health:GetPercent()
    local function choose(depth,start)
        if tries>600 then return end
        if depth==5 then
            tries=tries+1
            local name=cooking.CalculateRecipe("cookpot",combination)
            local recipe=name and cooking.recipes.cookpot[name]
            local edible=recipe and (recipe.foodtype==FOODTYPE.MEAT or recipe.foodtype==FOODTYPE.VEGGIE
                or recipe.foodtype==FOODTYPE.GOODIES or recipe.foodtype==FOODTYPE.GENERIC)
            if edible and (recipe.health or 0)>=0 and (recipe.sanity or 0)>=0 then
                local score=(recipe.hunger or 0)+(hp<.7 and 3 or .3)*(recipe.health or 0)+(recipe.sanity or 0)
                if score>bestscore then bestscore=score;best={unpack(combination)} end
            end
            return
        end
        for i=start,#list do
            if (used[i] or 0)<list[i].count then
                used[i]=(used[i] or 0)+1;combination[depth]=list[i].prefab
                choose(depth+1,i);used[i]=used[i]-1
            end
        end
    end
    choose(1,1)
    if not best or bestscore<20 then return false end
    c.cookingpot=pot.GUID;c.cookingredients=best
    return L.CrockPot(c)
end

function L.CookStore(c,act)
    local pot,item=act.target,act.invobject
    if not pot or not item or not pot:IsValid() or not item:IsValid() or pot.GUID~=c.cookingpot
        or not pot.components.stewer or pot.components.stewer:IsCooking()
        or pot.components.container:IsOpenedByOthers(c.inst) or c.inst:GetDistanceSqToInst(pot)>12.25
        or not c.inst.components.inventory:IsHolding(item,true) then return false end
    local container=pot.components.container
    R.Refresh(c)
    if not R.CanUse(c,item.prefab,1) then c:Problem("precious_resource",{prefab=item.prefab,reason="这份珍贵材料先留着"});return false end
    if container:IsFull() or not container:CanTakeItemInSlot(item) then return false end
    local one=c.inst.components.inventory:RemoveItem(item,false)
    if not one then return false end
    container:Open(c.inst)
    local ok=container:GiveItem(one,nil,c.inst:GetPosition(),false)
    if not ok and one:IsValid() and one.components.inventoryitem.owner==nil then c.inst.components.inventory:GiveItem(one) end
    container:Close(c.inst)
    if ok and c.cookingredients and c.cookingredients[1]==item.prefab then table.remove(c.cookingredients,1) end
    return not not ok
end

function L.MaintainFire(c)
    local fire=c:Find(function(v)
        return (v.prefab=="firepit" or v.prefab=="campfire" or v.prefab=="coldfirepit")
            and v.components.fueled and v.components.fueled:GetPercent()<.25
    end,12)
    if fire and not TheWorld.state.isday then
        local fuel=I.Find(c.inst,function(v)return v.components.fuel and (v.prefab=="log" or v.prefab=="charcoal") end)
        if fuel then return c:Act(ACTIONS.ADDFUEL,fire,fuel) end
    end
    return false
end

function L.FarmExtras(c,radius)
    local inst=c.inst
    local seed=I.Find(inst,function(v)return v.components.farmplantable~=nil end)
    local hoe=I.Find(inst,function(v)return v.components.farmtiller~=nil end)
    if seed and hoe then
        local p=inst:GetPosition()
        for dx=-4,4,1.5 do for dz=-4,4,1.5 do
            local pt=Vector3(p.x+dx,0,p.z+dz)
            if TheWorld.Map:CanTillSoilAtPoint(pt.x,0,pt.z,false) then
                return c:Act(ACTIONS.TILL,nil,hoe,pt)
            end
        end end
    end
    local fertilizer=I.Find(inst,function(v)return v.components.fertilizer~=nil end)
    local pickable=c:Find(function(v)return v.components.pickable and v.components.pickable:CanBeFertilized() end,radius)
    if fertilizer and pickable then return c:Act(ACTIONS.FERTILIZE,pickable,fertilizer) end
    return false
end
return L
