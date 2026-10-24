local I=require("ai_inventory")
local J={}
local transplants={dug_grass="grass",dug_sapling="sapling",dug_berrybush="berrybush",dug_berrybush2="berrybush2"}
local function point(p)return Vector3(p.x,0,p.z)end

function J.Apply(c,updates)
    c.projects=c.projects or {}
    c.ignored_gardens=c.ignored_gardens or {}
    for _,p in ipairs(updates or {}) do
        if p.operation=="remove" then
            local old=c.projects[p.id]
            if old and old.position then c.ignored_gardens[p.id]=old.position end
            c.projects[p.id]=nil
        elseif p.position and p.position.shard==TheShard:GetShardId() then
            for id,pos in pairs(c.ignored_gardens) do
                if (pos.x-p.position.x)^2+(pos.z-p.position.z)^2<=8*8 then c.ignored_gardens[id]=nil end
            end
            local old=c.projects[p.id]
            local n=0;for _ in pairs(c.projects) do n=n+1 end
            if old or n<24 then
                c.projects[p.id]={id=p.id,kind=p.kind,text=p.text,prefab=p.prefab,count=p.count,
                    position=p.position,evidence=p.evidence,nextcheck=0,origin="remembered",plants=old and old.plants}
            end
        end
    end
end

function J.RememberGarden(c,pos,evidence,plantprefab)
    c.projects=c.projects or {}
    for _,ignored in pairs(c.ignored_gardens or {}) do
        if (ignored.x-pos.x)^2+(ignored.z-pos.z)^2<=8*8 then return end
    end
    for _,p in pairs(c.projects) do
        if p.kind=="garden" and (p.position.x-pos.x)^2+(p.position.z-pos.z)^2<=8*8 then
            if plantprefab then p.plants=p.plants or {};p.plants[plantprefab]=true end
            return p
        end
    end
    local n=0;for _ in pairs(c.projects) do n=n+1 end
    if n>=24 then return end
    local id="garden-"..math.floor(pos.x).."-"..math.floor(pos.z)
    c.projects[id]={id=id,kind="garden",text="照看已观察的种植区，闲时检查收割与补种",
        position={x=pos.x,z=pos.z,shard=TheShard:GetShardId()},evidence=evidence,
        nextcheck=0,origin="observed",plants=plantprefab and {[plantprefab]=true} or nil}
    return c.projects[id]
end

function J.Observe(c)
    if GetTime()<(c.next_project_observe or 0) then return end
    c.next_project_observe=GetTime()+5;c.worksites=c.worksites or {}
    local nearby=c:Scan(24)
    for _,e in ipairs(nearby) do
        if e.components.prototyper then
            local p=e:GetPosition();local key=string.format("%.1f/%.1f",p.x,p.z)
            c.worksites[key]={kind="science",x=p.x,z=p.z,prefab=e.prefab,trees=e.components.prototyper.trees}
        end
        if c.home and e:GetDistanceSqToPoint(c.home)<24*24
            and (e.prefab=="farm_soil" or e:HasTag("farm_plant")) then
            J.RememberGarden(c,e:GetPosition(),"在基地附近实际观察到耕地或作物")
        end
    end
    for key,p in pairs(c.worksites) do
        if c.inst:GetDistanceSqToPoint(point(p))<20*20 then
            local found=false
            for _,e in ipairs(nearby) do
                if e.components.prototyper and e:GetDistanceSqToPoint(point(p))<1 then found=true;break end
            end
            if not found then c.worksites[key]=nil end
        end
    end
end

local function inArea(e,p,r)return e:GetDistanceSqToPoint(point(p.position))<=r*r end
function J.Garden(c,p)
    if c.inst:GetDistanceSqToPoint(point(p.position))>7*7 then
        return c:MoveTo(point(p.position),"去记下的种植区巡查",4)
    end
    local plant=c:Find(function(e)return inArea(e,p,7) and e:HasTag("farm_plant")
        and e.components.pickable and e.components.pickable:CanBePicked() end,15)
    if plant then return c:Act(ACTIONS.PICK,plant) end
    local tend=c:Find(function(e)return inArea(e,p,7) and e.components.farmplanttendable
        and e.components.farmplanttendable.tendable end,15)
    if tend then return c:Act(ACTIONS.INTERACT_WITH,tend) end
    local soil=c:Find(function(e)return inArea(e,p,7) and e.prefab=="farm_soil" end,15)
    if soil then
        local seed=I.Find(c.inst,function(e)return e.components.farmplantable~=nil end)
        if seed then return c:Act(ACTIONS.PLANTSOIL,soil,seed) end
        if I.TakeNeeded(c,"seeds",2) then return true end
        c:Problem("garden_supply",{prefab="seeds",reason="记下的菜地有空位，暂时缺种子，等有种子再补种"})
    end
    local plantation=c:Find(function(e)return inArea(e,p,7) and (p.plants and p.plants[e.prefab]
        or p.kind=="transplant" and transplants[p.prefab]==e.prefab)
        and e.components.pickable and e.components.pickable:CanBePicked() end,15)
    if plantation then return c:Act(ACTIONS.PICK,plantation) end
    local fertilizer=I.Find(c.inst,function(e)return e.components.fertilizer~=nil end)
    local hungry=c:Find(function(e)return inArea(e,p,7) and e.components.pickable
        and e.components.pickable:CanBeFertilized() end,15)
    if hungry and fertilizer then return c:Act(ACTIONS.FERTILIZE,hungry,fertilizer) end
    local can=I.Find(c.inst,function(e)return e:HasTag("wateringcan") and e.components.wateryprotection
        and e.components.finiteuses and e.components.finiteuses:GetUses()>0 end)
    if can then
        local dry=c:Find(function(e)
            if not inArea(e,p,7) or not e:HasTag("farm_plant") then return false end
            local x,y,z=e.Transform:GetWorldPosition()
            return TheWorld.components.farming_manager and not TheWorld.components.farming_manager:IsSoilMoistAtPoint(x,y,z)
        end,15)
        if dry then return c:Act(ACTIONS.POUR_WATER,dry,can,dry:GetPosition()) end
    end
    -- Till only an existing farming tile in this recorded area, never enlarge it.
    if soil==nil and I.Find(c.inst,function(e)return e.components.farmplantable~=nil end) then
        local hoe=I.Find(c.inst,function(e)return e.components.farmtiller~=nil end)
        if hoe then for dx=-3,3,1.5 do for dz=-3,3,1.5 do
            local pt=point(p.position)+Vector3(dx,0,dz)
            if TheWorld.Map:CanTillSoilAtPoint(pt.x,0,pt.z,false) then return c:Act(ACTIONS.TILL,nil,hoe,pt) end
        end end end
    end
    return false
end

function J.Transplant(c,prefab,count,p)
    c.transplant_done=false
    prefab=prefab or "dug_berrybush"
    local grown=transplants[prefab]
    if not grown then c:Problem("unsupported_action",{prefab=prefab,reason="这类移植还未适配，先不挖走植物"});return false end
    local dest=p and point(p.position) or c.home
    if not dest then return false end
    local planted=0
    for _,e in ipairs(c:Scan(28)) do
        if e.prefab==grown and e:GetDistanceSqToPoint(dest)<7*7 then planted=planted+1 end
    end
    if c.inst:GetDistanceSqToPoint(dest)<20*20 and planted>=(count or 4) then c.transplant_done=true;return false end
    local item=I.Find(c.inst,function(e)return e.prefab==prefab end)
    if item then
        if c:MoveTo(dest,"把移植苗带回种植区",6) then return true end
        for r=3,6,1.5 do for i=1,12 do
            local pt=dest+Vector3(math.cos(i*PI/6)*r,0,math.sin(i*PI/6)*r)
            if item.components.deployable and item.components.deployable:CanDeploy(pt,nil,c.inst) then
                return c:Act(ACTIONS.DEPLOY,nil,item,pt)
            end
        end end
        c:Problem("plant_space",{prefab=prefab,reason="记下的移植区没有合适空位，需要换个位置"});return false
    end
    if I.TakeNeeded(c,prefab,1) then return true end
    if c:Resources(prefab,nil,24) then return true end
    local target=c:Find(function(e)return e.prefab==grown and e.components.workable
        and e.components.workable:GetWorkAction()==ACTIONS.DIG and e.components.workable:CanBeWorked()
        and (not c.home or e:GetDistanceSqToPoint(c.home)>26*26) end,24)
    if target then
        local shovel=c:EquipTool(ACTIONS.DIG,"shovel")
        if shovel then return c:Act(ACTIONS.DIG,target,shovel) end
        return c.pending~=nil
    end
    if not TheWorld.state.isnight and c.inst:GetDistanceSqToPoint(dest)<55*55 then
        if not c.transplant_search or GetTime()>c.transplant_search.untiltime
            or c.inst:GetDistanceSqToPoint(point(c.transplant_search))<3*3 then
            local angle=math.random()*2*PI
            c.transplant_search={x=dest.x+math.cos(angle)*34,z=dest.z+math.sin(angle)*34,untiltime=GetTime()+16}
        end
        if c:MoveTo(point(c.transplant_search),"在基地外围寻找普通可移植苗",3) then return true end
    end
    c:Problem("transplant_supply",{prefab=prefab,reason="附近没找到可移植苗，保留基地现有植物，等探索后再补"})
    return false
end

function J.Tick(c)
    if TheWorld.state.isnight then return false end
    local nearest,dist
    for _,p in pairs(c.projects or {}) do
        if p.position.shard==TheShard:GetShardId() and GetTime()>=(p.nextcheck or 0) then
            local d=c.inst:GetDistanceSqToPoint(point(p.position))
            if not dist or d<dist then nearest=p;dist=d end
        end
    end
    if not nearest then return false end
    local p=nearest
    if not c.project_visit or c.project_visit.id~=p.id then c.project_visit={id=p.id,since=GetTime()} end
    local active
    if GetTime()-c.project_visit.since<60 then
        if p.kind=="garden" then active=J.Garden(c,p)
        elseif p.kind=="transplant" then active=J.Transplant(c,p.prefab,p.count,p)
            if not active then active=J.Garden(c,p) end
        elseif p.kind=="stockpile" and p.prefab then
            local total=require("ai_resources").Count(c,p.prefab)
            if total<(p.count or 10) then active=c:Resources(p.prefab,nil,24) end
        end
    end
    if active then return true end
    p.lastcheck=GetTime();p.nextcheck=GetTime()+90;c.project_visit=nil
    return false
end

function J.Snapshot(c)
    J.Observe(c)
    local list={};for _,p in pairs(c.projects or {}) do list[#list+1]=p end
    table.sort(list,function(a,b)return a.id<b.id end)
    return list
end
return J
