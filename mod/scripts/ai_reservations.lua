-- Allocate observed stock to the current prerequisite first, then future goals.
local B={}
local function stock(c,prefab)
    local n=require("ai_inventory").Count(c.inst,prefab)
    for _,box in pairs(c.stock or {}) do if box.current then n=n+(box.counts[prefab] or 0) end end
    return n
end
function B.Compute(c,spendingRecipe)
    local out={protected={},claims={},demand={}}
    if not AllRecipes or not c.inst.components or not c.inst.components.builder then return out end
    local Q=require("ai_procurement");local remaining={}
    local function available(p)
        if remaining[p]==nil then remaining[p]=stock(c,p) end
        return remaining[p]
    end
    local need,recipe
    need=function(prefab,n,protect,path,depth)
        if n<=0 or depth>8 then return end
        local have=math.min(n,available(prefab));remaining[prefab]=remaining[prefab]-have
        if protect and have>0 then out.protected[prefab]=(out.protected[prefab] or 0)+have end
        local missing=n-have
        if missing<=0 then return end
        local sub=Q.RecipeFor(prefab)
        if sub and not sub.placer and not path[sub.name] then recipe(sub.name,missing,protect,path,depth+1)
        elseif protect then out.demand[prefab]=(out.demand[prefab] or 0)+missing end
    end
    recipe=function(name,count,protect,path,depth)
        local r=AllRecipes[name]
        if not r or depth>8 or path[name] then return end
        local trail={};for k,v in pairs(path) do trail[k]=v end;trail[name]=true
        local batches=math.ceil(count/(r.numtogive or 1))
        for _,ing in ipairs(Q.Requirements(c,r)) do need(ing.prefab,ing.required*batches,protect,trail,depth+1) end
    end
    local current=c.plan or {}
    if current.activity=="craft" and current.recipe then
        recipe(current.recipe,math.max(0,(current.count or 1)-(current.built or 0)),false,{},0)
    elseif spendingRecipe then recipe(spendingRecipe,1,false,{},0) end
    local job=c.job
    if job and job.status~="complete" and job.status~="cancelled" then
        for i=job.index+1,#job.steps do
            local step=job.steps[i]
            if step.activity=="craft" and step.recipe then
                recipe(step.recipe,math.max(0,(step.count or 1)-(step.built or 0)),true,{},0)
                out.claims[#out.claims+1]={kind="workflow",recipe=step.recipe,stage=i}
            end
        end
    end
    local projects={};for id,p in pairs(c.projects or {}) do projects[#projects+1]={id=id,value=p} end
    table.sort(projects,function(a,b)return a.id<b.id end)
    for _,v in ipairs(projects) do local p=v.value
        if p.kind=="stockpile" and p.prefab and not (c.project_visit and c.project_visit.id==p.id) then
            need(p.prefab,p.count or 10,true,{},0);out.claims[#out.claims+1]={kind="project",id=p.id,prefab=p.prefab}
        end
    end
    local inv=c.inst.components.inventory
    if TheWorld and TheWorld.state.season and inv and inv.equipslots and inv.FindItem then
        local target=require("ai_preparation").Target(c)
        if target and target~=spendingRecipe and not (c.preparation and c.preparation.recipe==target) then
            need(target,1,true,{},0);out.claims[#out.claims+1]={kind="season",recipe=target}
        end
    end
    return out
end
function B.Emergency(c)
    local comps=c.inst.components;local hunger=comps.hunger;local health=comps.health
    return hunger and hunger.GetPercent and hunger:GetPercent()<.08
        or health and health.GetPercent and health:GetPercent()<.2
        or TheWorld and not TheWorld.state.isday and c.inst.LightWatcher and c.inst.LightWatcher:GetLightValue()<.12
end
function B.CanSpend(c,prefab,amount,recipe)
    local reserve=B.Compute(c,recipe).protected[prefab] or 0
    if reserve==0 or stock(c,prefab)-amount>=reserve then return true end
    if B.Emergency(c) then
        c.resource_debts=c.resource_debts or {}
        local old=c.resource_debts[prefab];local baseline=math.max(old and old.baseline or 0,stock(c,prefab))
        c.resource_debts[prefab]={prefab=prefab,baseline=baseline,amount=math.max(0,baseline-stock(c,prefab))+amount,
            reason="紧急生存临时借用普通储备",day=TheWorld.state.cycles}
        return true
    end
    return false
end
function B.TakeLimit(c,prefab,wanted)
    local protected=B.Compute(c).protected[prefab] or 0
    if protected==0 or B.Emergency(c) then return wanted end
    return math.min(wanted,math.max(0,stock(c,prefab)-protected-require("ai_inventory").Count(c.inst,prefab)))
end
function B.Repay(c)
    for prefab,debt in pairs(c.resource_debts or {}) do
        local missing=debt.baseline-stock(c,prefab)
        if missing<=0 then c.resource_debts[prefab]=nil
        elseif require("ai_crafting").Acquire(c,prefab,missing) then return true end
    end
    return false
end
return B
