-- Local observations, not world-wide resource radar. Saved with the companion.
local Q={}
local rockProducts={rock1={rocks=true,flint=true,nitre=true},rock2={rocks=true,flint=true,goldnugget=true},
    rock_flintless={rocks=true},rock_ice={ice=true}}
local hints={log="树林",cutgrass="草地／稀树草原",twigs="草地／树林边缘",flint="岩石地／地面散落",
    rocks="岩石地",goldnugget="带金纹的矿石",nitre="普通硝石矿",ice="冬季冰矿",
    berries="浆果丛",cutreeds="沼泽芦苇（先避开触手）",seeds="地面落籽",
    charcoal="箱中或地面木炭；不自动放火烧林",silk="箱中或安全战斗掉落；暂不主动清蜘蛛巢"}
local terrains={rocks={"ROCKY"},flint={"ROCKY"},goldnugget={"ROCKY"},nitre={"ROCKY"},
    cutgrass={"SAVANNA","GRASS"},twigs={"GRASS","FOREST","DECIDUOUS"},
    log={"FOREST","DECIDUOUS"},berries={"GRASS","FOREST"},cutreeds={"MARSH"}}
local function xyz(p)return Vector3(p.x,0,p.z)end
function Q.Hint(prefab)return hints[prefab] or "箱中、地面或已适配的可采集来源"end
function Q.Yields(e,prefab)
    local components=e.components or {}
    if components.inventoryitem and components.inventoryitem.owner==nil
        and components.inventoryitem.canbepickedup and e.prefab==prefab then return true end
    if components.pickable and components.pickable.product==prefab and components.pickable:CanBePicked()
        and not e:HasTag("thorny") and not e:HasTag("trap") then return true end
    local work=components.workable
    if work and work:CanBeWorked() then
        if prefab=="log" and e:HasTag("tree") and not e:HasTag("burnt") then return true end
        return rockProducts[e.prefab] and rockProducts[e.prefab][prefab] or false
    end
    return false
end
function Q.Observe(c)
    if not c.Scan or GetTime()<(c.next_resource_observe or 0) then return end
    c.next_resource_observe=GetTime()+5
    c.resource_memory=c.resource_memory or {};c.terrain_memory=c.terrain_memory or {}
    local here=c.inst:GetPosition();local day=TheWorld.state.cycles or 0
    local near=c:Scan(24);local seen={}
    for _,e in ipairs(near) do
        local products={}
        for prefab in pairs(hints) do if Q.Yields(e,prefab) then products[prefab]=true end end
        -- Standard mod pickables also become usable after actually seeing them.
        local pick=e.components.pickable
        if pick and pick.product and pick:CanBePicked() and not e:HasTag("thorny") then products[pick.product]=true end
        if next(products) then
            local p=e:GetPosition();local key=e.prefab..":"..string.format("%.1f/%.1f",p.x,p.z)
            seen[key]=true
            c.resource_memory[key]={prefab=e.prefab,x=p.x,z=p.z,products=products,day=day}
        end
    end
    for key,p in pairs(c.resource_memory) do
        -- Revisit invalidates exhausted nodes; old distant observations are only leads.
        if (p.x-here.x)^2+(p.z-here.z)^2<20*20 and not seen[key] then c.resource_memory[key]=nil end
    end
    local map=TheWorld.Map
    if map and map.GetTileAtPoint then
        local key=math.floor(here.x/16).."/"..math.floor(here.z/16)
        c.terrain_memory[key]={x=here.x,z=here.z,tile=map:GetTileAtPoint(here.x,0,here.z),day=day}
    end
    local function trim(list,max)
        local entries={};for key,v in pairs(list) do entries[#entries+1]={key=key,day=v.day or 0} end
        table.sort(entries,function(a,b)return a.day<b.day or a.day==b.day and a.key<b.key end)
        for i=1,#entries-max do list[entries[i].key]=nil end
    end
    trim(c.resource_memory,180);trim(c.terrain_memory,160)
    local keys={};for k in pairs(c.resource_memory) do keys[#keys+1]=k end;table.sort(keys)
    local signature=table.concat(keys,"|")
    if c.resource_signature~=signature then
        c.resource_signature=signature;c.resource_revision=(c.resource_revision or 0)+1
    end
end
local function key(p)return string.format("%.0f/%.0f",p.x,p.z)end
local function selectLead(c,prefab,search)
    local best,score
    local function candidate(p,penalty)
        local k=key(p);local dist=c.inst:GetDistanceSqToPoint(xyz(p))
        if not search.tried[k] and dist>12*12 and dist<180*180
            and not ((c.route_failed or {})[k] and c.route_failed[k]>GetTime()) then
            local n=math.sqrt(dist)+penalty
            if not score or n<score then best=p;score=n end
        end
    end
    for _,p in pairs(c.resource_memory or {}) do
        if p.products and p.products[prefab] then candidate(p,0) end
    end
    if not best and WORLD_TILES then
        for _,p in pairs(c.terrain_memory or {}) do
            for _,tile in ipairs(terrains[prefab] or {}) do
                if WORLD_TILES[tile] and p.tile==WORLD_TILES[tile] then candidate(p,60);break end
            end
        end
    end
    return best
end
function Q.Search(c,prefab)
    if not TheWorld or not TheWorld.state or not TheWorld.state.isday or not c.inst.GetPosition then return false end
    if not hints[prefab] and not next(c.resource_memory or {}) then return false end
    c.material_searches=c.material_searches or {}
    local day=TheWorld.state.cycles or 0
    local search=c.material_searches[prefab]
    if not search or search.day~=day then
        local p=c.inst:GetPosition();search={x=p.x,z=p.z,index=1,tried={},day=day};c.material_searches[prefab]=search
    end
    local lead=search.target or selectLead(c,prefab,search)
    if lead then
        search.target=lead;search.untiltime=search.untiltime or GetTime()+70
        if c.inst:GetDistanceSqToPoint(xyz(lead))<=8*8 or GetTime()>search.untiltime then
            search.tried[key(lead)]=true;search.target=nil;search.untiltime=nil
            return Q.Search(c,prefab)
        end
        if c:MoveTo(xyz(lead),"去已见过的来源核对 "..prefab.."（"..Q.Hint(prefab).."）",6) then return true end
        search.tried[key(lead)]=true;search.target=nil;search.untiltime=nil
        return false
    end
    if prefab=="charcoal" or prefab=="silk" then return false end
    -- One bounded widening sweep per material/day. Actual routing and survival still apply.
    if search.index>8 then return false end
    local angle=search.index*math.pi/2;local radius=search.index<=4 and 22 or 44
    local pos=Vector3(search.x+math.cos(angle)*radius,0,search.z+math.sin(angle)*radius)
    search.untiltime=search.untiltime or GetTime()+20
    if c.inst:GetDistanceSqToPoint(pos)<4*4 or GetTime()>search.untiltime then
        search.index=search.index+1;search.untiltime=nil;return Q.Search(c,prefab)
    end
    if c:MoveTo(pos,"保留原目标，寻找 "..prefab.."（"..Q.Hint(prefab).."）",3) then return true end
    search.index=search.index+1;search.untiltime=nil;return false
end
function Q.RecipeFor(prefab)
    local r=AllRecipes[prefab]
    if r and (r.product or r.name)==prefab then return r end
    -- A mod may give an ordinary refinement a recipe id different from its product.
    local best
    for _,recipe in pairs(AllRecipes) do
        if recipe.product==prefab and not recipe.placer and not recipe.builder_tag
            and not next(recipe.character_ingredients or {}) and (not best or recipe.name<best.name) then best=recipe end
    end
    return best
end
function Q.Requirements(c,recipe)
    local out={};local b=c.inst.components.builder
    for _,ing in ipairs(recipe.ingredients or {}) do
        local raw=ing.amount*(b.ingredientmod or 1)
        local amount=math.max(1,RoundBiasedUp and RoundBiasedUp(raw) or math.floor(raw+.5))
        out[#out+1]={prefab=ing.type,required=amount}
    end
    return out
end
return Q
