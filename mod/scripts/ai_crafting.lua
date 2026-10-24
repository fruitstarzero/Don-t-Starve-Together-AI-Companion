local I=require("ai_inventory")
local R=require("ai_resources")
local Q=require("ai_procurement")
local C={}
function C.Search(c,prefab)
    return Q.Search(c,prefab)
end

local function available(c,recipe)
    local b=c.inst.components.builder
    return b:KnowsRecipe(recipe) or b:CanLearn(recipe.name)
        and CanPrototypeRecipe(recipe.level,b.accessible_tech_trees)
end

local function recipeFor(prefab)
    return Q.RecipeFor(prefab)
end

function C.Acquire(c,prefab,amount,path,depth)
    c.procurement=c.procurement or {}
    c.procurement.missing={prefab=prefab,count=amount,source=Q.Hint(prefab)}
    c.procurement.phase="取箱、补料或加工中间材料"
    if I.TakeNeeded(c,prefab,amount) then return true end
    local inv=c.inst.components.inventory
    if inv and inv.IsFull and inv:IsFull()
        and I.Count(c.inst,prefab)==0 and not recipeFor(prefab) then
        c:Problem("storage_space",{prefab=prefab,reason="背包没有位置取下一份材料，需要先腾位"});return false
    end
    if c:Resources(prefab,nil,24) or c.pending then return true end
    local recipe=recipeFor(prefab)
    if recipe and not recipe.placer then
        local before=c.problem
        if C.Step(c,recipe.name,nil,path,depth) then return true end
        if c.problem and (c.problem~=before or c.problem.updated==GetTime()) then return false end
    end
    if C.Search(c,prefab) then return true end
    c.procurement.phase="已尝试本地来源，等待新线索"
    c:Problem("missing_materials",{prefab=prefab,name=R.Name(prefab),count=amount,
        source=Q.Hint(prefab),reason="缺 "..R.Name(prefab).." ×"..amount.."；"..Q.Hint(prefab).."，已检查箱子和可达线索，保留目标等待补给或新路线"})
    return false
end

function C.OutputFits(c,recipe)
    local inv=c.inst.components.inventory
    if recipe.placer or not inv:IsFull() then return true end
    local product=recipe.product or recipe.name
    local existing=I.Find(c.inst,function(v)return v.prefab==product end)
    if existing and inv:CanAcceptCount(existing,recipe.numtogive or 1)>=(recipe.numtogive or 1) then return true end
    -- Use the builder's actual chosen materials, including discounts: only rely
    -- on a slot being freed when that precise stack is going to be consumed.
    local materials=c.inst.components.builder:GetIngredients(recipe.name)
    for _,items in pairs(materials) do for item,n in pairs(items) do
        local size=item.components.stackable and item.components.stackable:StackSize() or 1
        if n>=size and inv:GetItemSlot(item) then return true end
    end end
    return false
end

local function reachTechnology(c,recipe,path,depth)
    local b=c.inst.components.builder
    local station=c:Find(function(v)return v.components.prototyper and
        CanPrototypeRecipe(recipe.level,v.components.prototyper.trees) end,28)
    if station and c.inst:GetDistanceSqToInst(station)>3*3 then
        return c:MoveTo(station:GetPosition(),"靠近可用科技设施",2)
    end
    for _,p in pairs(c.worksites or {}) do
        if p.kind=="science" and p.trees and CanPrototypeRecipe(recipe.level,p.trees)
            and c.inst:GetDistanceSqToPoint(Vector3(p.x,0,p.z))>22*22 then
            return c:MoveTo(Vector3(p.x,0,p.z),"返回记下的科技设施核对",2)
        end
    end
    -- Only construct basic science facilities, not arbitrary unlock/character stations.
    local level=recipe.level or {}
    local ordinary=true
    for kind,n in pairs(level) do if kind~="SCIENCE" and n>0 then ordinary=false end end
    local science=level.SCIENCE or 0
    local target=ordinary and science>0 and science<=2 and (science==1 and "researchlab" or "researchlab2")
    if target and not path[target] and AllRecipes[target] then
        local existing=c:Find(function(v)return v.prefab==target end,28)
        if not existing and C.Step(c,target,nil,path,depth+1) then return true end
    end
    if c.problem and c.problem.updated==GetTime() then return false end
    c:Problem("technology",{recipe=recipe.name,reason="缺少可用科技或专属解锁，暂时无法制作 "..R.Name(recipe.product or recipe.name)})
    return false
end

local function step(c,name,pos,path,depth)
    path=path or {};depth=depth or 0
    local recipe=AllRecipes[name]
    if not recipe or depth>8 or path[name] then
        c:Problem("recipe_chain",{recipe=name,reason="配方依赖不可执行或循环，需要重新安排"});return false
    end
    local trail={};for k,v in pairs(path) do trail[k]=v end;trail[name]=true
    if depth==0 then
        c.craft_reserves={}
        c.procurement={goal=name,phase="分析实际配方与科技",chain={},requirements=Q.Requirements(c,recipe)}
    end
    c.procurement=c.procurement or {goal=name,chain={}}
    c.procurement.chain=c.procurement.chain or {};c.procurement.chain[#c.procurement.chain+1]=name
    c.procurement.current=name
    local b=c.inst.components.builder
    if b:IsBuildBuffered(name) then return c:Craft(name,pos) end
    if not R.CheckRecipe(c,name,true) then return false end
    if not available(c,recipe) then return reachTechnology(c,recipe,trail,depth) end
    c.craft_reserves=c.craft_reserves or {}
    local requirements=Q.Requirements(c,recipe)
    for _,ing in ipairs(requirements) do
        c.craft_reserves[ing.prefab]=math.max(c.craft_reserves[ing.prefab] or 0,ing.required)
    end
    for _,ing in ipairs(requirements) do
        local missing=math.max(0,ing.required-I.Count(c.inst,ing.prefab))
        if missing>0 then return C.Acquire(c,ing.prefab,missing,trail,depth+1) end
    end
    c.procurement.phase="材料齐全，执行实际制作";c.procurement.missing=nil
    return c:Craft(name,pos)
end

function C.Step(c,name,pos,path,depth)
    -- Resource gathering may itself request a tool. Retain a guard across that
    -- callback boundary as well as across ordinary ingredient dependencies.
    c.crafting_calls=c.crafting_calls or {}
    if c.crafting_calls[name] then
        c:Problem("recipe_chain",{recipe=name,reason="缺少启动工具的材料，先找地面材料或求助"});return false
    end
    c.crafting_calls[name]=true
    local active=step(c,name,pos,path,depth)
    c.crafting_calls[name]=nil
    return active
end

function C.Storage(c)
    if not c.storage_full or not c.home then return false end
    if GetTime()-(c.last_storage_build or -10000)<60 then
        c:Problem("storage_full",{reason="刚补的箱子也暂时放不下，先等空间或重新分类"});return false
    end
    if c:MoveTo(c.home,"回基地补一只储物箱",5) then return true end
    c.storage_requested=true
    if require("ai_staging").MakeRoom(c) then return true end
    local active=C.Step(c,"treasurechest")
    if not active and c.inst.components.inventory:IsFull() then
        c:Problem("storage_space",{reason="背包和仓库都满了，暂时没有安全腾位方式，需要帮忙空出一两格"});return false
    end
    return active
end
return C
