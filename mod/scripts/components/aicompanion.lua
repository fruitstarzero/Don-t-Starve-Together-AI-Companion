local P = require("ai_policy")
local I = require("ai_inventory")
local L = require("ai_life")
local R = require("ai_resources")
local T = require("ai_tasks")
local Companion = Class(function(self, inst)
    self.inst=inst
    self.mode="auto"
    self.revision=0
    self.status="观察周围环境"
    self.events={}
    self.action_events={}
    self.failed={}
    self.plan={activity="auto",reason="先保证生存，再根据实际需要做事"}
    self.nextthink=0
    self.lastmove=0
    self.inst:ListenForEvent("attacked",function(_,data)
        if data and data.attacker then self.threat=data.attacker end
    end)
    self.inst:ListenForEvent("fishingnibble",function() self.reel_at=GetTime()+.35 end)
    self.inst:ListenForEvent("fishingstrain",function() self.reel_at=GetTime()+.35 end)
    self.inst:ListenForEvent("actionfailed",function(_,data)
        if self.pending and data and data.action then
            if data.action.target then self.failed[data.action.target.GUID]=GetTime()+12 end
            self.pending=nil
        end
    end)
    local function built(_,data)
        local context=self.build_context
        self.pending=nil
        self:Event("build_success",{recipe=data and data.recipe and data.recipe.name,taskContext=context})
        if self.method_plan and data and data.recipe and self.method_plan.recipe==data.recipe.name then
            self.method_plan.built=(self.method_plan.built or 0)+(data.recipe.numtogive or 1)
        end
        if self.problem and data and data.recipe and self.problem.detail.recipe==data.recipe.name then self.problem=nil end
        if self.storage_requested and data and data.recipe and data.recipe.name=="treasurechest" then
            self.last_storage_build=GetTime();self.storage_requested=nil;self.storage_full=false
        end
        if self.plan and self.plan.activity=="craft" and data and data.recipe and data.recipe.name==self.plan.recipe
            and (not context or self.job and context.id==self.job.id and context.index==self.job.index and context.kind=="objective") then
            self.plan.built=(self.plan.built or 0)+(data.recipe.numtogive or 1)
            if self.plan.built>=(self.plan.count or 1) then
                self:Event("task_complete",{activity="craft",recipe=self.plan.recipe})
                T.Complete(self,{activity="craft",recipe=data.recipe.name,built=self.plan.built})
            end
        end
    end
    self.inst:ListenForEvent("builditem",built)
    self.inst:ListenForEvent("buildstructure",built)
end)

function Companion:Start()
    require("ai_skills").Start(self)
    if not self.task then self.task=self.inst:DoPeriodicTask(.25,function() self:Tick() end) end
end

function Companion:Event(kind, detail)
    if kind=="task_complete" then self.craft_reserves=nil end
    if kind=="transfer_success" and detail.take==false and self.plan and self.plan.activity=="collect"
        and detail.prefab==self.plan.prefab then
        self.plan.delivered=(self.plan.delivered or 0)+detail.count
    end
    if kind=="task_complete" or kind=="action_success" and self.problem
        and self.problem.detail.action==detail.action then self.problem=nil end
    T.Progress(self,kind,detail)
    self.eventsequence=(self.eventsequence or 0)+1
    local row={id=self.eventsequence,at=GetTime(),kind=kind,detail=detail}
    table.insert(self.events,row)
    self.action_events=self.action_events or {};table.insert(self.action_events,row)
    if #self.action_events>256 then table.remove(self.action_events,1);self.action_gap=(self.action_gap or 0)+1 end
    if #self.events>30 then table.remove(self.events,1) end
end

function Companion:Problem(kind,detail)
    local key=kind..":"..tostring(detail.recipe or detail.prefab or detail.action or "")
    if not self.problem or self.problem.key~=key then
        self.problem={key=key,kind=kind,detail=detail,since=GetTime(),updated=GetTime()}
    else self.problem.updated=GetTime();self.problem.detail=detail end
    self.status=detail.reason or "遇到问题，正在找替代方法"
    local recoverable={missing_materials=true,technology=true,recipe_chain=true,route_blocked=true,
        unsafe_route=true,storage_space=true,unknown_place=true,unknown_home=true,transplant_supply=true,plant_space=true}
    if recoverable[kind] then T.Block(self,kind,detail) end
    if GetTime()-(self.problem.reported or -10000)>30 then
        self:Event("problem",self.problem);self.problem.reported=GetTime()
    end
end

function Companion:Owner()
    for _, p in ipairs(AllPlayers) do
        if p ~= self.inst and p.userid == self.ownerid and not p:HasTag("ai_companion") then return p end
    end
end

function Companion:Stop()
    self.pending=nil
    self.inst:ClearBufferedAction()
    self.inst.components.locomotor:Clear()
    self.inst.components.locomotor:Stop()
    local target=self.inst.components.combat.target
    if target then self.inst.components.combat:SetTarget(nil) end
    local hand=self.inst.components.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
    if hand and hand.components.fishingrod then hand.components.fishingrod:StopFishing() end
end

function Companion:Command(command,position)
    self.revision=self.revision+1
    self.awaiting_chat=nil
    self.problem=nil
    self.craft_reserves=nil
    self.storage_requested=nil
    self.project_visit=nil
    self:Stop()
    T.Command(self,command)
    if command=="teleport" then
        require("ai_travel").ToOwner(self,self:Owner())
    elseif command=="sethome" then
        require("ai_memory").SetHome(self,position or (self:Owner() and self:Owner():GetPosition() or self.inst:GetPosition()))
    elseif command=="abigail_summon" or command=="abigail_recall" then
        self.abigail_manual_until=GetTime()+30
        local flower=self.inst.components.inventory:FindItem(function(v) return v.prefab=="abigail_flower" end)
        local action=command=="abigail_summon" and ACTIONS.CASTSUMMON
            or ACTIONS.CASTUNSUMMON
        if flower and not self.inst:HasTag("playerghost") then self:Act(action,nil,flower)
        else self.status="需要自己的花朵且温蒂必须存活" end
    else
        local modes={follow="follow",stay="stay",come="come",auto="auto",home="home",retreat="retreat"}
        self.mode=modes[command] or self.mode
        if self.mode=="retreat" then self:RecallGhost() end
        self.status="已接受指令："..command
    end
    self:Event("manual_command",{command=command,revision=self.revision})
end

function Companion:Act(action,target,item,pos,options)
    if not action then return false end
    if item and R.precious[item.prefab] and action~=ACTIONS.PICKUP and action~=ACTIONS.AI_TRANSFER then
        R.Refresh(self)
        if not (action==ACTIONS.EAT and options and options.ai_emergency and R.CanEat(self,item,true))
            and not R.CanUse(self,item.prefab,1) then
            self:Problem("precious_resource",{prefab=item.prefab,name=R.Name(item.prefab),reason="先不消耗珍贵材料"});return false
        end
    end
    if target and self.failed[target.GUID] and self.failed[target.GUID]>GetTime() then return false end
    local act=BufferedAction(self.inst,target,action,item,pos)
    local workplan=self.plan
    local context=T.Context(self)
    act.ai_task_context=context
    local product=target and target.components.pickable and target.components.pickable.product
        or target and action==ACTIONS.PICKUP and target.prefab
    if action==ACTIONS.CHOP then product="log"
    elseif action==ACTIONS.MINE then
        local wanted=self.procurement and self.procurement.missing and self.procurement.missing.prefab or workplan and workplan.prefab
        if target and wanted and require("ai_procurement").Yields(target,wanted) then product=wanted end
    end
    act.validfn=function()return self.plan==workplan end
    local workpos=pos or target and target:GetPosition()
    local staged=options and options.ai_stage and item and {GUID=item.GUID,prefab=item.prefab,
        count=item.components.stackable and item.components.stackable:StackSize() or 1}
    if item and R.precious[item.prefab] and action~=ACTIONS.AI_TRANSFER then
        act.validfn=function()
            if self.plan~=workplan then return false end
            R.Refresh(self)
            local h=self.inst.components.hunger
            local hp=self.inst.components.health:GetPercent()
            local emergency=action==ACTIONS.EAT and options and options.ai_emergency
                and (h:GetPercent()<.08 or hp<.2 and h:GetPercent()<.25)
            return R.CanUse(self,item.prefab,1) or emergency and R.CanEat(self,item,true)
        end
    end
    if options then for k,v in pairs(options) do act.options[k]=v end end
    local id=target and target.GUID or (item and item.GUID) or 0
    self.pending={id=id,action=action.id,since=GetTime(),revision=self.revision}
    local pending=self.pending
    act:AddSuccessAction(function()
        if options and options.ai_cook_finish then self.cookingpot=nil;self.cookingredients=nil end
        if staged and workpos then require("ai_staging").Record(self,staged,workpos) end
        if options and options.ai_recover then require("ai_staging").Recovered(self,options.ai_recover) end
        self:Event("action_success",{action=action.id,target=id,prefab=target and target.prefab,product=product,taskContext=context})
        if workpos and (action==ACTIONS.PLANTSOIL or action==ACTIONS.TILL or action==ACTIONS.DEPLOY
            and item and item.prefab and item.prefab:find("dug_",1,true)==1) then
            require("ai_projects").RememberGarden(self,workpos,"自己实际完成的种植动作",
                action==ACTIONS.DEPLOY and item.prefab:gsub("^dug_","") or nil)
        end
        if self.pending==pending then self.pending=nil end
        if self.plan==workplan and self.plan and self.plan.activity=="collect" and self.plan.count
            and (action==ACTIONS.PICKUP or action==ACTIONS.PICK or action==ACTIONS.CHOP or action==ACTIONS.MINE) then
            self.plan.progress=(self.plan.progress or 0)+1
        end
    end)
    act:AddFailAction(function()
        self.failed[id]=GetTime()+12
        if self.pending==pending then self.pending=nil end
        self:Event("action_failed",{action=action.id,target=id})
        self:Problem("action_failed",{action=action.id,reason="这个动作暂时没成功，我再想想办法"})
    end)
    self.status=action.id..(target and " · "..target:GetDisplayName() or "")
    self.inst.components.locomotor:PushAction(act,true)
    return true
end

function Companion:TransferAction(box,item,count,take,sortTo,keepSample)
    return self:Act(ACTIONS.AI_TRANSFER,box,item,nil,{ai_count=count,ai_take=take,ai_sort_to=sortTo,ai_keep_sample=keepSample,
        ai_sort_cargo=not take and self.sortcargo and self.sortcargo.prefab==item.prefab or false})
end
function Companion:Transfer(act) return I.Transfer(self,act) end

function Companion:MoveTo(pos,label,stopdistance)
    if not pos then return false end
    local distance=self.inst:GetDistanceSqToPoint(pos)
    if distance<(stopdistance or 2)^2 then self.route=nil;require("ai_navigation").Arrived(self,pos);return false end
    local key=string.format("%.0f/%.0f",pos.x,pos.z)
    self.route_failed=self.route_failed or {}
    local navigation=require("ai_navigation")
    if (self.route_failed[key] or 0)>GetTime() and not (self.nav_memory and self.nav_memory[key]) then return false end
    if not self.route or self.route.key~=key then self.route={key=key,distance=distance,progress=GetTime()} end
    if distance<self.route.distance-1 then self.route.distance=distance;self.route.progress=GetTime()
    elseif GetTime()-self.route.progress>14 then
        self.route_failed[key]=GetTime()+60;self.route=nil
        navigation.Failed(self,pos,"route_blocked")
        self:Problem("route_blocked",{destination=key,reason="前往目标时持续无法靠近，暂时换条路线或等待帮助"});return false
    end
    if GetTime()-self.lastmove<1 then return true end
    if not TheWorld.Map:IsPassableAtPoint(pos.x,0,pos.z) then
        navigation.Failed(self,pos,"impassable");self:Problem("route_blocked",{destination=key,reason="目标落点不可通行，需要其它落点或路线"});return false
    end
    local waypoint=navigation.Waypoint(self,pos)
    local safe=waypoint and require("ai_safety").Route(self,waypoint)
    if not safe then navigation.Failed(self,pos,"unsafe_route");self:Problem("unsafe_route",{destination=key,reason="前方可见危险或旁路不通，保留目的地等待安全路线"});return false end
    self.lastmove=GetTime()
    self.status=label or "赶路"
    self.inst.components.locomotor:GoToPoint(safe,nil,true)
    return true
end

function Companion:Scan(radius)
    local p=self.inst:GetPosition()
    return TheSim:FindEntities(p.x,0,p.z,radius or 24,nil,{"INLIMBO","NOCLICK","FX","DECOR"})
end

function Companion:Find(fn,radius)
    local best,dist=nil,math.huge
    for _,v in ipairs(self:Scan(radius)) do
        local d=self.inst:GetDistanceSqToInst(v)
        if v~=self.inst and fn(v) and not (self.failed[v.GUID] and self.failed[v.GUID]>GetTime()) and d<dist then
            best=v; dist=d
        end
    end
    return best
end

function Companion:EquipTool(action,recipe)
    local inv=self.inst.components.inventory
    local tool=I.Find(self.inst,function(item)
        return item.components.tool and item.components.tool:CanDoAction(action)
            and not (item.components.finiteuses and item.components.finiteuses:GetPercent()<=0)
    end)
    if tool then
        if inv:GetEquippedItem(EQUIPSLOTS.HANDS)~=tool then inv:Equip(tool) end
        return tool
    end
    if recipe then require("ai_crafting").Step(self,recipe) end
end

function Companion:Craft(name,pos)
    self.build_context=T.Context(self)
    local recipe=AllRecipes[name]
    local b=self.inst.components.builder
    if recipe and not b:IsBuildBuffered(name) then
        if not R.CheckRecipe(self,name,true) then return false end
        local missing={}
        for _,ing in ipairs(recipe.ingredients) do
            local has,count=self.inst.components.inventory:Has(ing.type,ing.amount,true)
            if not has then missing[#missing+1]={prefab=ing.type,name=R.Name(ing.type),count=ing.amount-(count or 0)} end
        end
        if #missing>0 then self:Problem("missing_materials",{recipe=name,missing=missing,reason="想制作的东西还缺点材料"});return false end
        if not require("ai_crafting").OutputFits(self,recipe) then
            self:Problem("storage_space",{recipe=name,reason="制作结果没有位置，先腾位再加工，避免成品掉在地上"});return false
        end
    end
    if recipe and recipe.placer and not pos then
        local anchor=self.home or self.inst:GetPosition()
        for i=1,8 do
            local angle=i*PI/4
            local pt=anchor+Vector3(math.cos(angle)*5,0,math.sin(angle)*5)
            local key=string.format("%s/%.1f/%.1f",name,pt.x,pt.z)
            if (not self.build_failed or (self.build_failed[key] or 0)<GetTime())
                and TheWorld.Map:CanDeployRecipeAtPoint(pt,recipe,0,self.inst) then
                if not b:IsBuildBuffered(name) then b:BufferBuild(name) end
                b:MakeRecipeAtPoint(recipe,pt,0)
                if self.inst.bufferedaction or self.inst.components.locomotor.bufferedaction then
                    self.pending={action="BUILD",recipe=name,position=pt,buildkey=key,since=GetTime()};self.status="按配方建造 "..name;return true
                end
            end
        end
        self:Problem("technology",{recipe=name,reason="科技或建造位置还不满足，暂时无法建造"})
        return false
    end
    if recipe and (b:IsBuildBuffered(name) or b:HasIngredients(recipe)) then
        if pos then
            if not b:KnowsRecipe(recipe) or not TheWorld.Map:CanDeployRecipeAtPoint(pos,recipe,0,self.inst) then return false end
            if recipe.placer and not b:IsBuildBuffered(name) then b:BufferBuild(name) end
            local ok=b:MakeRecipe(recipe,pos)
            if ok then self.pending={action="BUILD",recipe=name,since=GetTime()}; self.status="制作 "..name end
            if not ok then self:Problem("technology",{recipe=name,reason="当前科技或放置条件还不满足"}) end
            return ok==true
        end
        local before=self.inst.bufferedaction
        b:MakeRecipeFromMenu(recipe)
        if self.inst.bufferedaction~=before or self.inst.sg:HasStateTag("doing") then
            self.pending={action="BUILD",recipe=name,since=GetTime()}; self.status="制作 "..name
            return true
        end
        self:Problem("technology",{recipe=name,reason="当前科技或制作条件还不满足"})
    end
    return false
end

function Companion:RecallGhost()
    local bond=self.inst.components.ghostlybond
    local flower=self.inst.components.inventory:FindItem(function(v) return v.prefab=="abigail_flower" end)
    if bond and bond.summoned and flower then return self:Act(ACTIONS.CASTUNSUMMON,nil,flower) end
    return false
end

function Companion:Retreat(threat,dodge)
    if not dodge and self:RecallGhost() then return true end
    self.inst.components.combat:SetTarget(nil)
    local owner=self:Owner()
    local p=self.inst:GetPosition()
    if threat and threat:IsValid() then
        local dest=require("ai_safety").RetreatPoint(self,threat)
        if self:MoveTo(dest,"避开危险",1) then return true end
    end
    return self:MoveTo(owner and owner:GetPosition() or self.home,"撤回安全区域",3)
end

function Companion:Survive()
    local inst=self.inst
    local inv=inst.components.inventory
    local hp=inst.components.health:GetPercent()
    local hunger=inst.components.hunger:GetPercent()
    local sanity=inst.components.sanity:GetPercent()
    local combat=inst.components.combat
    if L.MaintainFire(self) then return true end
    local attacker=self.threat
    if attacker and (not attacker:IsValid() or attacker.components.health and attacker.components.health:IsDead()
        or inst:GetDistanceSqToInst(attacker)>18*18) then self.threat=nil; attacker=nil end
    if hp<.4 and attacker then return self:Retreat(attacker) end
    if inst.components.burnable and inst.components.burnable:IsBurning() then
        return self:Retreat(attacker)
    end
    if hunger<.62 or hp<.6 or sanity<.35 then
        R.Refresh(self)
        local food=inv:FindItem(function(item)
            local e=item.components.edible
            return e and R.CanUse(self,item.prefab,1) and inst.components.eater and inst.components.eater:CanEat(item)
                and e:GetHealth(inst)>=0 and e:GetSanity(inst)>=-2 and e:GetHunger(inst)>0
                and (hunger<.62 or hp<.6 and e:GetHealth(inst)>0 or sanity<.35 and e:GetSanity(inst)>0)
        end)
        if food then return self:Act(ACTIONS.EAT,nil,food) end
        local emergency=hunger<.08 or hp<.2 and hunger<.25
        if emergency then
            food=inv:FindItem(function(item)return R.CanEat(self,item,true) end)
            if food then
                self:Event("emergency_food",{prefab=food.prefab,reason="没有合适普通食物，直接食用以保命"})
                return self:Act(ACTIONS.EAT,nil,food,nil,{ai_emergency=true})
            end
        end
    end
    if hp<.65 then
        local medicine=inv:FindItem(function(v) return v.components.healer~=nil end)
        if medicine then return self:Act(ACTIONS.HEAL,inst,medicine) end
    end
    if not attacker then
        local cold=inst:GetTemperature()<15
        local hot=inst:GetTemperature()>60
        local clothing=I.Find(inst,function(v)return v.components.equippable and v.components.insulator
            and v.components.insulator:IsType(cold and SEASONS.WINTER or SEASONS.SUMMER)
            and (cold or hot) end)
        if not clothing and TheWorld.state.israining then
            clothing=I.Find(inst,function(v)return v.components.equippable and v.components.waterproofer end)
        end
        if clothing and not clothing.components.equippable:IsEquipped() then
            inv:Equip(clothing);self.status="穿戴适合当前天气的装备";return true
        end
    end
    if inst.LightWatcher:GetLightValue()<.18 and not TheWorld.state.isday then
        local light=I.Find(inst,function(v) return v:HasTag("lighter") and v.components.equippable~=nil end)
        if light then
            if not light.components.equippable:IsEquipped() then inv:Equip(light); self.status="准备照明"; return true end
        elseif require("ai_crafting").Step(self,"torch") then return true
        else
            local fire=self:Find(function(v) return v.components.burnable and v.components.burnable:IsBurning() end,22)
            if fire and self:MoveTo(fire:GetPosition(),"寻找光源",2) then return true end
            self:Problem("missing_supply",{prefab="torch",reason="缺少照明材料，需要草和树枝或附近光源"})
        end
    end
    if (inst.IsFreezing and inst:IsFreezing()) or inst:GetTemperature()<8 then
        local fire=self:Find(function(v) return v.components.burnable and v.components.burnable:IsBurning() end,25)
        if fire and self:MoveTo(fire:GetPosition(),"靠近火源取暖",2) then return true end
        if fire and inst:GetTemperature()<12 then self.status="在火边回温，暖和后继续原任务";return true end
        if not fire and self.home then
            self:Problem("cold_supply",{reason="体温正在变低，需要火源或保暖物资"})
            if self:MoveTo(self.home,"先回基地准备回温",3) then return true end
        end
    end
    if inst.IsOverheating and inst:IsOverheating() or inst:GetTemperature()>60 then
        local ice=inv:FindItem(function(v) return v.prefab=="ice" end)
        if ice then return self:Act(ACTIONS.EAT,nil,ice) end
    end
    if hunger<.3 and I.TakeNeeded(self,"berries",3) then return true end
    return false
end

function Companion:Fight(owner)
    local inst=self.inst
    local combat=inst.components.combat
    local enemy=self.threat
    if not enemy and self.mode=="follow" and owner and owner.components.combat then
        enemy=owner.components.combat.target
    end
    if not enemy or not enemy:IsValid() or enemy:HasTag("player") or enemy:HasTag("companion")
        or enemy.components.health==nil or enemy.components.health:IsDead() then return false end
    if inst:GetDistanceSqToInst(enemy)>12*12 then return false end
    local inv=inst.components.inventory
    local armor=I.Find(inst,function(v) return v.components.armor and v.components.equippable end)
    if armor and not armor.components.equippable:IsEquipped() then inv:Equip(armor) end
    local weapon=I.Find(inst,function(v) return v.components.weapon and v.components.equippable and type(v.components.weapon.damage)=="number" and v.components.weapon.damage>20 end)
    if weapon and not weapon.components.equippable:IsEquipped() then inv:Equip(weapon) end
    if require("ai_safety").RetreatNeeded(self,enemy,weapon~=nil,armor~=nil) then return self:Retreat(enemy) end
    if enemy.sg and enemy.sg:HasStateTag("attack") and inst:GetDistanceSqToInst(enemy)<4*4 then
        return self:Retreat(enemy,true)
    end
    combat:SetTarget(enemy)
    if not combat:InCooldown() then return self:Act(ACTIONS.ATTACK,enemy,weapon) end
    return false
end

function Companion:Resources(prefab,owner,radius)
    local inst=self.inst
    local occupied=owner and owner:GetBufferedAction()
    local function free(v) return not occupied or occupied.target~=v end
    local target=self:Find(function(v)
        return free(v) and v.components.inventoryitem and v.components.inventoryitem.canbepickedup
            and v.components.inventoryitem.owner==nil and not v:HasTag("trap")
            and (not prefab or v.prefab==prefab)
            and not v:HasTag("irreplaceable") and v.prefab~="abigail_flower"
    end,radius)
    if target and not inst.components.inventory:IsFull() then return self:Act(ACTIONS.PICKUP,target) end
    local products={log=ACTIONS.CHOP,rocks=ACTIONS.MINE,flint=ACTIONS.MINE,goldnugget=ACTIONS.MINE,
        nitre=ACTIONS.MINE,ice=ACTIONS.MINE,cutgrass=ACTIONS.PICK,twigs=ACTIONS.PICK,berries=ACTIONS.PICK,cutreeds=ACTIONS.PICK}
    local work=products[prefab]
    target=self:Find(function(v)
        if not free(v) or v:HasTag("burnt") then return false end
        if v.components.pickable and v.components.pickable:CanBePicked()
            and not v:HasTag("thorny") and not v:HasTag("trap") then
            return not prefab or v.components.pickable.product==prefab
        end
        local w=v.components.workable
        local toolname=work==ACTIONS.CHOP and "axe" or "pickaxe"
        if self.crafting_calls and self.crafting_calls[toolname] then return false end
        return w and w:CanBeWorked() and (work==ACTIONS.CHOP and v:HasTag("tree") or work==ACTIONS.MINE
            and require("ai_procurement").Yields(v,prefab))
            and w:GetWorkAction()==work
    end,radius)
    if not target then return false end
    if target.components.pickable then return self:Act(ACTIONS.PICK,target) end
    local action=target.components.workable:GetWorkAction()
    local tool=self:EquipTool(action,action==ACTIONS.CHOP and "axe" or "pickaxe")
    return tool and self:Act(action,target,tool) or self.pending~=nil
end

function Companion:Farm(owner,radius)
    local occupied=owner and owner:GetBufferedAction()
    local plant=self:Find(function(v) return v.components.farmplanttendable and v.components.farmplanttendable.tendable
        and (not occupied or occupied.target~=v) end,radius)
    if plant then return self:Act(ACTIONS.INTERACT_WITH,plant) end
    local soil=self:Find(function(v) return v.prefab=="farm_soil" end,radius)
    if soil then
        local seed=self.inst.components.inventory:FindItem(function(v) return v:HasTag("deployedfarmplant") end)
        if seed then return self:Act(ACTIONS.PLANTSOIL,soil,seed) end
        if I.TakeNeeded(self,"seeds",1) then return true end
    end
    local can=I.Find(self.inst,function(v) return v.components.wateryprotection and v:HasTag("wateringcan") end)
    if can and can.components.finiteuses and can.components.finiteuses:GetUses()>0 then
        local dry=self:Find(function(v)
            if not v:HasTag("farm_plant") then return false end
            local x,y,z=v.Transform:GetWorldPosition()
            return TheWorld.components.farming_manager and not TheWorld.components.farming_manager:IsSoilMoistAtPoint(x,y,z)
        end,radius)
        if dry then return self:Act(ACTIONS.POUR_WATER,dry,can,dry:GetPosition()) end
    end
    if L.FarmExtras(self,radius) then return true end
    return self:Resources(nil,owner,radius)
end

function Companion:Fish(owner,radius)
    local inv=self.inst.components.inventory
    local rod=I.Find(self.inst,function(v) return v.components.fishingrod~=nil end)
    if not rod then return self:Craft("fishingrod") end
    if not rod.components.equippable:IsEquipped() then inv:Equip(rod) end
    if rod.components.fishingrod:IsFishing() then
        if self.reel_at and GetTime()>=self.reel_at then self.reel_at=nil; return self:Act(ACTIONS.REEL,nil,rod) end
        return true
    end
    local pond=self:Find(function(v) return v.components.fishable and v.components.fishable:GetFishPercent()>0 end,radius or 20)
    if pond then return self:Act(ACTIONS.FISH,pond,rod) end
    self.status="附近没有可用池塘；海钓另需海钓竿和海钓流程"
    return false
end

function Companion:Cook()
    local ready=self:Find(function(v) return v.components.stewer and v.components.stewer:IsDone() end,20)
    if ready then return self:Act(ACTIONS.HARVEST,ready) end
    if L.CrockPot(self) then return true end
    local raw=self.inst.components.inventory:FindItem(function(v) return v.components.cookable~=nil and R.CanUse(self,v.prefab,1) end)
    local fire=self:Find(function(v) return v.components.cooker and v.components.burnable and v.components.burnable:IsBurning() end,20)
    if raw and fire then return self:Act(ACTIONS.COOK,fire,raw) end
    return false
end

function Companion:Assist(owner)
    local a=owner:GetBufferedAction()
    if a then self.last_owner_action={id=a.action.id,at=GetTime()} end
    local id=self.last_owner_action and GetTime()-self.last_owner_action.at<12 and self.last_owner_action.id
    if id=="CHOP" then return self:Resources("log",owner,10)
    elseif id=="MINE" then return self:Resources("rocks",owner,10)
    elseif id=="FISH" or id=="REEL" then return self:Fish(owner,10)
    elseif id=="PLANTSOIL" or id=="POUR_WATER" or id=="INTERACT_WITH" or id=="FERTILIZE" then return self:Farm(owner,10)
    elseif id=="COOK" then return self:Cook()
    elseif id=="PICK" or id=="PICKUP" then return self:Resources(nil,owner,8) end
    return false
end

function Companion:Tick()
    local inst=self.inst
    if not self.ownerid or not inst:IsValid() then return end
    local owner=self:Owner()
    if not owner then
        T.Interrupt(self,"主人不在当前分片")
        if not self.owner_absent then self:Stop(); self.owner_absent=true end
        self.status="主人不在此分片，停止任务；基础生存仍按原版运行"
        if not self.pending and not inst.sg:HasStateTag("busy") and not inst:HasTag("playerghost") then self:Survive() end
        return
    end
    self.owner_absent=false
    require("ai_projects").Observe(self)
    require("ai_procurement").Observe(self)
    if self.observed_owner~=owner then
        self.observed_owner=owner
        inst:ListenForEvent("performaction",function(_,data)
            if data and data.action and data.action.action then
                local a=data.action
                self.last_owner_action={id=a.action.id,at=GetTime()}
                if inst:GetDistanceSqToInst(owner)<=20*20 and not a.ai_observed then
                    a.ai_observed=true
                    local detail={action=a.action.id,target=a.target and a.target.prefab,
                        item=a.invobject and a.invobject.prefab,
                        recipe=type(a.recipe)=="table" and a.recipe.name or type(a.recipe)=="string" and a.recipe or nil}
                    a:AddSuccessAction(function() if inst:IsValid() then self:Event("owner_action_success",detail) end end)
                    a:AddFailAction(function() if inst:IsValid() then self:Event("owner_action_failed",detail) end end)
                end
            end
        end,owner)
    end
    if inst:HasTag("playerghost") or inst.components.health:IsDead() then T.Interrupt(self,"等待原版复活");self.status="已成为幽灵，需要按原版方式复活"; return end
    if self.pending and GetTime()-self.pending.since>(self.pending.action=="BUILD" and 8 or 18) then
        if self.pending.id then self.failed[self.pending.id]=GetTime()+20 end
        if self.pending.buildkey then self.build_failed=self.build_failed or {};self.build_failed[self.pending.buildkey]=GetTime()+120 end
        local blocked=self.pending.action
        self:Stop();self:Problem("action_blocked",{action=blocked,reason="动作受阻，正在重新判断路线和条件"})
    end
    -- Interrupt a current job for immediate danger, without bypassing stun/death animations.
    if self.pending and not inst.sg:HasStateTag("nointerrupt") then
        local bond=inst.components.ghostlybond
        local urgentGhost=bond and bond.summoned and bond.ghost and bond.ghost.components.health:GetPercent()<.2
        local dark=not TheWorld.state.isday and inst.LightWatcher:GetLightValue()<.12
        local starving=inst.components.hunger:GetPercent()<.06
        local emergency=urgentGhost or dark or starving or inst.components.health:GetPercent()<.3 and self.threat
        local protective=self.pending.action=="CASTUNSUMMON" or self.pending.action=="EAT"
            or self.pending.action=="HEAL" or self.pending.recipe=="torch"
        if emergency and not protective then T.Interrupt(self,"处理紧急生存");self:Stop() end
    end
    if self.pending and self.mode=="follow" and inst:GetDistanceSqToInst(owner)>12*12 then self:Stop() end
    local hand=inst.components.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
    if hand and hand.components.fishingrod and hand.components.fishingrod:IsFishing()
        and self.reel_at and GetTime()>=self.reel_at then
        self.reel_at=nil; self:Act(ACTIONS.REEL,nil,hand); return
    end
    if self.pending or inst.sg:HasStateTag("busy") then return end
    self.work_context="survival"
    if self:Survive() then T.Interrupt(self,"处理生存补给或危险");return end
    self.work_context="manual"
    if self.awaiting_chat and GetTime()<self.awaiting_chat then self.status="等待对话判断，保留基本生存"; return end
    self.awaiting_chat=nil
    if self.mode=="retreat" then self:Retreat(self.threat); return end
    if require("ai_abigail").Tick(self) then return end
    self.work_context="combat"
    if self:Fight(owner) then T.Interrupt(self,"处理附近战斗");return end
    self.work_context="manual"
    if self.mode=="come" or self.mode=="follow" then
        local dist=inst:GetDistanceSqToInst(owner)
        if dist>5*5 then self:MoveTo(owner:GetPosition(),"跟上主人",3); return end
        if self.mode=="come" then self:Stop(); self.mode="stay"; self.status="已到身边，等你安排"; return end
        if dist<9*9 and not self:Assist(owner) then self.status="跟随，留意你正在做的事" end
        return
    elseif self.mode=="stay" then self.status="待命，留意生存状态"; return
    elseif self.mode=="home" then
        if not self.home then self.mode="stay";self.status="尚未记录基地位置"
        elseif inst:GetDistanceSqToPoint(self.home)<=3*3 then self.mode="stay"; self.status="已返回基地"
        else self:MoveTo(self.home,"返回基地",3) end
        return
    end
    self.work_context="objective"
    if not T.Ready(self) then require("ai_recovery").Tick(self);return end
    if GetTime()<self.nextthink then return end
    self.nextthink=GetTime()+.75
    if T.Method(self) then return end
    local plan=self.plan or {activity="auto"}
    local activity=plan.activity
    if inst.components.inventory:IsFull() and (activity=="collect" or activity=="farm" or activity=="fish"
        or activity=="explore" or activity=="transplant" or activity=="cook") then
        T.Interrupt(self,"先存放本批物资再继续")
        if self.home and self:MoveTo(self.home,"先存放这一批物资，再继续原任务",4) then return end
        if I.Store(self,false) or require("ai_crafting").Storage(self) then return end
        if self.storage_full then self:Problem("storage_space",{reason="这批物资暂时放不下，保留原任务等待空间"});return end
    end
    if activity=="visit" then
        local place=self.landmarks and self.landmarks[plan.placeId]
        if place and place.position and place.position.shard==TheShard:GetShardId() then
            local dest=Vector3(place.position.x,0,place.position.z)
            if inst:GetDistanceSqToPoint(dest)<=2*2 then
                self:Event("task_complete",{activity="visit",place=plan.placeId});T.Complete(self,{activity="visit",place=plan.placeId})
            else self:MoveTo(dest,"前往记下的地点",2) end
        else self:Problem("unknown_place",{reason="没有记下此分片的这个地点",placeId=plan.placeId}) end
        return
    elseif activity=="craft" and plan.recipe then
        if require("ai_crafting").Step(self,plan.recipe) then return end
    elseif activity=="store" or activity=="sort" then
        if not self.home then self:Problem("unknown_home",{reason="先告诉我基地在哪，再把这批物资带回"});return end
        if self.home and inst:GetDistanceSqToPoint(self.home)>20*20 then self:MoveTo(self.home,"带物资回基地",3); return end
        if I.Store(self,activity=="sort") then return end
        if require("ai_crafting").Storage(self) then return end
        if activity=="store" and not self.storage_full and not self.sortcargo and #(self.staged_cargo or {})==0 then
            self:Event("task_complete",{activity="store"});T.Complete(self,{activity="store",surplus=false});return
        end
    elseif activity=="collect" then
        if plan.count and I.Count(inst,plan.prefab)+(plan.delivered or 0)>=plan.count then
            self.status="已收集到目标数量，判断下一步"
            self:Event("task_complete",{activity="collect",prefab=plan.prefab,count=plan.count})
            T.Complete(self,{activity="collect",prefab=plan.prefab,count=plan.count,delivered=plan.delivered})
            return
        elseif require("ai_crafting").Acquire(self,plan.prefab,math.max(1,(plan.count or 10)-I.Count(inst,plan.prefab)-(plan.delivered or 0))) then return end
        return
    elseif activity=="farm" then if self:Farm(nil,22) then return end
    elseif activity=="transplant" then
        local project=plan.placeId and self.projects and self.projects[plan.placeId]
        if require("ai_projects").Transplant(self,plan.prefab,plan.count,project) then return end
        if self.transplant_done then
            self:Event("task_complete",{activity="transplant",prefab=plan.prefab,count=plan.count})
            T.Complete(self,{activity="transplant",prefab=plan.prefab,count=plan.count});return
        end
    elseif activity=="fish" then if self:Fish(nil,22) then return end
    elseif activity=="cook" then if self:Cook() then return end
    elseif activity=="rest" then
        if self:MoveTo(self.home,"回基地休整",3) then return end
        self.status="在基地休整，保留生存物资"; return
    end
    if self.goal_board and activity=="auto" then self.status="等待下一段自主判断，保持安全与基本生存";return end
    if inst.components.hunger:GetPercent()<.7 and self:Resources("berries",nil,24) then return end
    if activity=="auto" then
        if #(self.staged_cargo or {})>0 and not self.storage_requested then
            if I.Store(self,false) or require("ai_staging").Recover(self) then return end
        end
        if inst.components.inventory:IsFull() then
            if self.home and self:MoveTo(self.home,"背包满了，回基地评估物资",4) then return end
            if I.Store(self,false) then return end
            if require("ai_crafting").Storage(self) then return end
        end
        local needs=I.Needs(self)
        for prefab,n in pairs(needs.materials) do
            if not inst.components.inventory:Has(prefab,n,true) and self:Resources(prefab,nil,20) then return end
        end
        if require("ai_reservations").Repay(self) or require("ai_preparation").Tick(self) or require("ai_projects").Tick(self) or self:Cook() then return end
    end
    if activity=="explore" or activity=="auto" then
        if not self.wander or inst:GetDistanceSqToPoint(self.wander)<2*2 or GetTime()>(self.wander_until or 0) then
            local anchor=activity=="explore" and inst:GetPosition() or self.home or owner:GetPosition()
            local theta=math.random()*2*PI
            local r=activity=="explore" and 12 or 18
            self.wander=anchor+Vector3(math.cos(theta)*r,0,math.sin(theta)*r)
            self.wander_until=GetTime()+12
        end
        self:MoveTo(self.wander,"观察附近可达区域",2)
    else self.status="暂时缺少条件，等待重新判断" end
end

function Companion:OnSave()
    if not self.ownerid then return end
    return {ownerid=self.ownerid,mode=self.mode,revision=self.revision,plan=self.plan,
        home=self.home and {x=self.home.x,z=self.home.z},home_memory=self.home_memory,landmarks=self.landmarks,stock=self.stock,
        trip_seconds=self.trip_seconds,projects=self.projects,worksites=self.worksites,ignored_gardens=self.ignored_gardens,
        goal_board=self.goal_board,action_events=self.action_events,eventsequence=self.eventsequence,action_gap=self.action_gap,
        staged_cargo=self.staged_cargo,job=self.job,task_history=self.task_history,task_sequence=self.task_sequence,
        resource_memory=self.resource_memory,terrain_memory=self.terrain_memory,procurement=self.procurement,nav_memory=self.nav_memory,resource_debts=self.resource_debts,
        skillxp=self.inst.components.skilltreeupdater:GetSkillXP(),
        skills=self.inst.components.skilltreeupdater:GetActivatedSkills(),sortcargo=self.sortcargo,
        cookingjob=self.cookingpot and Ents[self.cookingpot] and {
            x=Ents[self.cookingpot]:GetPosition().x,z=Ents[self.cookingpot]:GetPosition().z,
            ingredients=self.cookingredients} or self.cookingjob}
end
function Companion:OnLoad(data)
    if not data or not data.ownerid then return end
    self.ownerid=data.ownerid; self.mode=data.mode or "auto"; self.revision=(data.revision or 0)+1
    self.goal_board=data.goal_board;self.action_events=data.action_events or {};self.eventsequence=data.eventsequence or 0;self.action_gap=data.action_gap or 0
    self.plan=data.plan or self.plan; self.trip_seconds=data.trip_seconds
    self.saved_skillxp=data.skillxp;self.saved_skills=data.skills
    self.sortcargo=data.sortcargo
    self.cookingjob=data.cookingjob
    self.home=data.home and Vector3(data.home.x,0,data.home.z)
    self.home_memory=data.home_memory;self.landmarks=data.landmarks or {}
    self.stock=data.stock or {};for _,box in pairs(self.stock) do box.current=false end
    self.projects=data.projects or {};for _,p in pairs(self.projects) do p.nextcheck=0 end
    self.worksites=data.worksites or {}
    self.ignored_gardens=data.ignored_gardens or {}
    self.staged_cargo=data.staged_cargo or {}
    self.resource_memory=data.resource_memory or {};self.terrain_memory=data.terrain_memory or {}
    self.procurement=data.procurement
    require("ai_navigation").Load(self,data.nav_memory)
    self.resource_debts=data.resource_debts or {}
    T.Load(self,data)
end
function Companion:OnRemoveFromEntity() if self.task then self.task:Cancel() end end
return Companion
