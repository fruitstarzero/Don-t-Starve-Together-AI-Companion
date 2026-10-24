-- Enabled ONLY in the disposable offline cluster, never in normal saves.
local T={}
function T.Run(m,runModel,reliabilityOnly)
    m.selftest=true
    local rows={}
    local function check(name,ok,detail)
        rows[#rows+1]={name=name,ok=ok==true,detail=tostring(detail or "")}
        print("[AI_TEST]",name,ok and "PASS" or "FAIL",detail or "")
    end
    local function later(t,fn)
        if reliabilityOnly then if t<195 then return end;t=t-190+(t>=220 and 15 or 0) end
        TheWorld:DoTaskInTime(t,function()
            local ok,err=pcall(fn)
            if not ok then check("exception_"..t,false,err) end
        end)
    end
    TheSim:QueryServer(m.config.url.."/health",function(data,ok,code)
        check("localhost_bridge",ok and code==200 and data:find("wendy%-ai")~=nil,code)
    end,"GET")
    local portal
    for _,e in pairs(Ents) do if e:HasTag("multiplayer_portal") then portal=e;break end end
    local p=portal and portal:GetPosition() or Vector3(0,0,0)
    local owner=SpawnPrefab("wilson"); owner.userid="AI_TEST_OWNER";owner:AddTag("ai_test_owner")
    owner.Transform:SetPosition(p.x,0,p.z);owner.components.health:SetInvincible(true)
    m.ownerid=owner.userid
    local bot=m:Spawn(owner)
    if not bot then check("spawn",false);return end
    local c=bot.components.aicompanion
    local axe,tree,soil,pot
    owner.entity:SetCanSleep(false)
    TheWorld:DoPeriodicTask(5,function()
        if not bot:IsValid() then return end
        local g=bot.components.ghostlybond.ghost
        print("[AI_DEBUG]",c.mode,c.status,bot.sg.currentstate.name,bot:IsAsleep(),bot:GetPosition(),
            g.sg.currentstate.name,g:IsAsleep(),g:IsInLimbo())
    end)
    c:Command("stay")
    local box=SpawnPrefab("treasurechest");box.Transform:SetPosition(p.x+3,0,p.z)
    local function give(prefab,count)
        local item=SpawnPrefab(prefab)
        if item.components.stackable then item.components.stackable:SetStackSize(count or 1) end
        bot.components.inventory:GiveItem(item)
        return item
    end
    later(1,function()
        check("vanilla_wendy",bot.prefab=="wendy" and bot.components.hunger~=nil and bot.sg.sg.name=="wilson")
        check("wendy_damage",bot.components.combat.damagemultiplier==TUNING.WENDY_DAMAGE_MULT)
        check("abigail_bound",bot.components.ghostlybond.ghost~=nil)
        check("starting_flower",bot.components.inventory:FindItem(function(v)return v.prefab=="abigail_flower" end)~=nil)
        give("log",12);give("cutgrass",8);give("twigs",8);give("berries",10);give("flint",4)
        c:Command("abigail_summon")
    end)
    later(2,function()
        local snapshot=m:Snapshot()
        snapshot.mode="stay";snapshot.chats={}
        TheSim:QueryServer("http://127.0.0.1:3131/v1/tick",function(data,ok,code)
            check("authenticated_snapshot_post",ok and code==200,code)
        end,"POST",json.encode_compliant({token=m.config.token,snapshot=snapshot}))
    end)
    later(5,function()
        local g=bot.components.ghostlybond.ghost
        check("abigail_summon",bot.components.ghostlybond.summoned==true and not g.sg:HasStateTag("busy")
            and not g.components.health:IsInvincible(),g.sg.currentstate.name)
        c:Command("abigail_recall")
    end)
    later(9,function()
        check("abigail_recall",bot.components.ghostlybond.notsummoned==true)
        c:Command("auto");c.plan={activity="store",reason="隔离测试：多余物资入箱"}
    end)
    later(24,function()
        check("store_actual_items",box.components.container:NumItems()>0,box.components.container:NumItems())
        check("keeps_food",bot.components.inventory:Has("berries",1))
        check("keeps_light_materials",bot.components.inventory:Has("cutgrass",2) and bot.components.inventory:Has("twigs",2))
        c:Command("come")
        owner.Transform:SetPosition(p.x+10,0,p.z)
    end)
    later(37,function()
        check("come_walked",bot:GetDistanceSqToInst(owner)<5*5,bot:GetDistanceSqToInst(owner))
        c:Command("stay")
        local ba=BufferedAction(bot,box,ACTIONS.AI_TRANSFER,box.components.container:FindItem(function(v)return v.prefab=="log" end))
        if ba.invobject then ba.options.ai_take=true;ba.options.ai_count=3;c.inst.components.locomotor:PushAction(ba,true) end
    end)
    later(49,function()
        check("withdraw_actual_items",bot.components.inventory:Has("log",3))
        c:Command("stay");give("log",3)
        require("ai_memory").SetHome(c,owner:GetPosition(),"家在这里")
        local R=require("ai_resources")
        local stock=R.Snapshot(c)
        check("base_inventory_observed",stock.observedBoxes>=1)
        check("home_uses_owner_position",c.home.x==owner:GetPosition().x and c.home.z==owner:GetPosition().z)
        local health=bot.components.health.currenthealth
        local food=bot.components.hunger.current
        c:Command("teleport")
        check("teleport_to_owner",bot:GetDistanceSqToInst(owner)<4*4,c.status)
        check("teleport_keeps_survival",bot.components.health.currenthealth==health and bot.components.hunger.current==food)
        local record=bot:GetSaveRecord()
        check("save_contains_inventory",record.data and record.data.inventory~=nil)
        check("save_contains_ai",record.data and record.data.aicompanion~=nil)
        local oldghost=bot.components.ghostlybond.ghost
        -- Reconstruct with vanilla save/load, then ensure only this one companion remains.
        if oldghost then
            bot:RemoveEventCallback("onremove",bot.components.ghostlybond._ghost_onremove,oldghost)
            oldghost:Remove()
        end
        bot:Remove()
        local restored=SpawnSaveRecord(record)
        m:ConfigureBot(restored)
        check("load_keeps_inventory",restored.components.inventory:Has("log",6))
        check("load_keeps_owner",restored.components.aicompanion.ownerid==owner.userid)
        check("load_keeps_wendy",restored.prefab=="wendy")
        check("load_keeps_home_memory",restored.components.aicompanion.home_memory
            and restored.components.aicompanion.home_memory.position.x==owner:GetPosition().x)
        local oldstock=restored.components.aicompanion.stock
        local stale=true;for _,entry in pairs(oldstock or {}) do if entry.current then stale=false end end
        check("load_inventory_is_stale",stale and next(oldstock)~=nil)
        bot=restored;c=bot.components.aicompanion
        c:Command("abigail_summon")
    end)
    later(54,function()
        local g=bot.components.ghostlybond.ghost
        check("summon_after_save_load",bot.components.ghostlybond.summoned==true and not g:IsAsleep()
            and not g.sg:HasStateTag("busy") and not g.components.health:IsInvincible())
        c:Command("abigail_recall")
    end)
    later(58,function()
        give("flint",2);give("twigs",4)
        c:Command("auto");c.plan={activity="craft",recipe="axe",count=1,reason="测试仅制作一把斧头"}
    end)
    later(64,function()
        c:Command("stay")
        axe=require("ai_inventory").Find(bot,function(v)return v.prefab=="axe" end)
        check("craft_real_axe",axe~=nil)
        local all=require("ai_inventory").Items(bot)
        local axes=0
        for _,item in ipairs(all)do if item.prefab=="axe" then axes=axes+item.count end end
        check("craft_stops_at_one",axes==1,axes)
        if axe then
            if not axe.components.equippable:IsEquipped() then bot.components.inventory:Equip(axe) end
            local again=c:EquipTool(ACTIONS.CHOP,"axe")
            check("find_equipped_tool",again==axe)
            tree=SpawnPrefab("evergreen")
            tree.Transform:SetPosition(bot:GetPosition().x+2,0,bot:GetPosition().z)
            tree.components.workable:SetWorkLeft(2)
            c:Act(ACTIONS.CHOP,tree,axe)
        end
    end)
    later(68,function()
        if axe and tree and tree:IsValid() then c:Act(ACTIONS.CHOP,tree,axe) end
    end)
    later(73,function()
        check("chop_consumes_durability",axe and axe.components.finiteuses:GetPercent()<1)
        c:Command("stay")
        bot.components.hunger:SetPercent(.4)
        give("berries",4)
    end)
    later(78,function()
        check("eats_real_food",bot.components.hunger:GetPercent()>.4)
        c:Command("stay")
        soil=SpawnPrefab("farm_soil")
        local pt=bot:GetPosition()
        soil.Transform:SetPosition(pt.x+1,0,pt.z+1)
        local seed=give("seeds",2)
        c:Act(ACTIONS.PLANTSOIL,soil,seed)
    end)
    later(83,function()
        local plants=c:Find(function(v)return v:HasTag("farm_plant") end,5)
        check("plants_real_seed",plants~=nil)
        c:Command("stay")
        if plants and plants.components.farmplanttendable then
            c:Act(ACTIONS.INTERACT_WITH,plants)
        end
    end)
    later(88,function()
        local plant=c:Find(function(v)return v:HasTag("farm_plant") end,5)
        check("tends_real_plant",plant and plant.components.farmplanttendable
            and not plant.components.farmplanttendable.tendable)
        c:Command("auto")
        bot.components.hunger:SetPercent(1)
        pot=SpawnPrefab("cookpot");pot.Transform:SetPosition(bot:GetPosition().x+2,0,bot:GetPosition().z+2)
        pot.entity:SetCanSleep(false)
        give("meat",1);give("carrot",3)
        c.plan={activity="cook",reason="测试原版烹饪配方与四格材料消耗"}
    end)
    later(105,function()
        local cooked=false
        for _,e in ipairs(c.events) do if e.kind=="action_success" and e.detail.action=="COOK" and e.detail.target==pot.GUID then cooked=true end end
        check("pot_started_real_cooking",cooked,
            pot and pot.components.container:NumItems())
    end)
    later(140,function()
        local cooked=bot.components.inventory:FindItem(function(v)return v.prefab=="meatballs" or v.prefab=="meatstew" or v.prefab=="ratatouille" end)
        check("pot_food_harvested",cooked~=nil,c.status)
        c:Command("stay")
        local count=0
        for _,player in ipairs(AllPlayers) do if player:HasTag("ai_companion") then count=count+1 end end
        check("one_companion_after_load",count==1,count)
        local before=c.revision
        m:Apply({id="stale-test",session=m.session,revision=before-1,expires=GetTime()+10,
            source="autonomy",plan={activity="collect",prefab="log",count=500,reason="stale"}})
        check("stale_plan_ignored",c.mode=="stay" and c.revision==before)
        local intruder=SpawnPrefab("wilson");intruder.userid="AI_TEST_OTHER"
        m:Command(intruder,"follow","")
        check("other_player_cannot_control",c.mode=="stay" and c.revision==before)
        intruder:Remove()
        if not runModel then print("[AI_TEST] SKIPPED model_roundtrip (local-only run)");return end
        m.chats={{id=m.session.."-integration",text="连接验收，只聊天回复一句你好，不执行任何游戏动作，也不用记忆或写日记。",
            revision=c.revision,at=GetTime(),expires=GetTime()+100}}
        local sent=false
        local pump
        pump=TheWorld:DoPeriodicTask(2,function()
            if sent or #m.chats==0 then return end
            sent=true
            TheSim:QueryServer("http://127.0.0.1:3131/v1/tick",function(data,ok,code)
                sent=false
                if ok and code==200 then
                    local valid,value=pcall(json.decode,data)
                    if valid then for _,r in ipairs(value.results or {}) do m:Apply(r) end end
                end
            end,"POST",json.encode_compliant({token=m.config.token,snapshot=m:Snapshot()}))
        end)
    end)
    later(150,function()
        local R=require("ai_resources")
        local original=c.home
        c.home=Vector3(original.x+100,0,original.z+100);R.Refresh(c)
        check("new_base_excludes_old_boxes",next(c.stock)==nil)
        c.home=original
        local mandrake=give("mandrake",1);give("cutreeds",5);give("rope",1)
        local builder=bot.components.builder
        builder:UnlockRecipe("panflute")
        local blocked=builder:DoBuild("panflute")
        check("real_builder_protects_mandrake",blocked==false and bot.components.inventory:Has("mandrake",1)
            and c.problem and c.problem.kind=="precious_resource")
        -- Test genuine surplus with normal ingredient removal in this disposable world.
        give("mandrake",4)
        local made=builder:DoBuild("panflute")
        local has,count=bot.components.inventory:Has("mandrake",4)
        check("real_builder_uses_surplus",made==true and has and count==4)
        check("runtime_recipe_details",#require("ai_recipebook").ForConversation(c,{{text="排箫怎么做"}})>0)
    end)
    later(190,function()
        local chatreply=false
        for _,r in ipairs(m.responses) do if r.source=="chat" and not r.modelError then chatreply=true end end
        if runModel then check("game_codex_reply_roundtrip",chatreply and #m.chats==0,
            #m.responses>0 and m.responses[#m.responses].text or m.bridge)
        check("chat_did_not_change_mode",c.mode=="stay") end
        local S=require("ai_social")
        m.social=S.New(GetTime()-400)
        local notice=S.Observe(m.social,{near=true,safe=true,health=1,hunger=1,phase="day",events={}},GetTime()).candidate
        local old=m.Snapshot
        m.Snapshot=function(self)local s=old(self);s.social.canSpeak=true;return s end
        m:Apply({id="native-social",session=m.session,revision=c.revision,source="social",expires=GetTime()+10,
            speechId=notice.id,taskStatus="none",reply="我们在基地歇一会儿吧。"})
        check("native_social_talker",m.responses[#m.responses].id=="native-social" and c.mode=="stay")
        m.Snapshot=old
    end)
    local capacitybox,boxcountbefore,gardenid,nitreTotal
    local function clearCargo()
        local items={};bot.components.inventory:ForEachItem(function(v)
            if v.prefab~="abigail_flower" then items[#items+1]=v end
        end)
        for _,v in ipairs(items) do v:Remove() end
    end
    local function boxCount()
        local n=0;for _,e in ipairs(TheSim:FindEntities(c.home.x,0,c.home.z,24)) do if e.prefab=="treasurechest" then n=n+1 end end;return n
    end
    later(195,function()
        c:Command("stay");clearCargo()
        c.home=bot:GetPosition()
        capacitybox=SpawnPrefab("treasurechest");capacitybox.Transform:SetPosition(c.home.x+1,0,c.home.z)
        local wood=SpawnPrefab("log");wood.components.stackable:SetStackSize(20);capacitybox.components.container:GiveItem(wood)
        local stone=SpawnPrefab("rocks");stone.components.stackable:SetStackSize(7);capacitybox.components.container:GiveItem(stone)
        local moved=require("ai_inventory").Transfer(c,{target=capacitybox,invobject=wood,options={ai_count=20,ai_take=true,ai_keep_sample=true}})
        check("withdraw_keeps_chest_sample",moved and wood:IsValid() and wood.components.stackable:StackSize()==1
            and bot.components.inventory:Has("log",19))
        check("withdraw_leaves_other_items",stone:IsValid() and stone.components.stackable:StackSize()==7
            and capacitybox.components.container:IsHolding(stone))
        local spare=SpawnPrefab("axe");capacitybox.components.container:GiveItem(spare)
        local got=require("ai_inventory").Transfer(c,{target=capacitybox,invobject=spare,options={ai_count=1,ai_take=true}})
        check("whole_tool_leaves_source_chest",got and bot.components.inventory:IsHolding(spare,true))
        local index=require("ai_resources").Snapshot(c)
        check("same_item_chest_index",index.locations.log and #index.locations.log>=1)
        bot.components.builder:UnlockRecipe("treasurechest")
        give("goldnugget",1) -- boards needs science one; let the bot build a real lab
        boxcountbefore=boxCount();c:Command("auto")
        c.plan={activity="craft",recipe="treasurechest",count=1,reason="递归加工木板后造真实箱子"}
    end)
    later(220,function()
        check("crafts_intermediate_then_chest",boxCount()==boxcountbefore+1 and c.plan.activity=="auto",c.status)
        check("craft_builds_needed_science",c:Find(function(v)return v.prefab=="researchlab" end,24)~=nil)
        c:Command("stay")
        for _,b in ipairs(require("ai_inventory").NearChests(c)) do
            for slot=1,b.components.container:GetNumSlots() do
                if not b.components.container.slots[slot] then
                    local item=SpawnPrefab("rocks");item.components.stackable:SetStackSize(40)
                    b.components.container:GiveItem(item,slot)
                end
            end
        end
        give("log",12);give("goldnugget",10)
        boxcountbefore=boxCount();c:Command("auto")
        c.plan={activity="store",reason="仓库满时真实造箱存余货"}
    end)
    later(252,function()
        check("storage_expands_when_full",boxCount()==boxcountbefore+1,c.status)
        local gold=0
        for _,b in ipairs(require("ai_inventory").NearChests(c)) do for _,item in pairs(b.components.container.slots) do
            if item.prefab=="goldnugget" then gold=gold+item.components.stackable:StackSize() end
        end end
        check("new_storage_receives_cargo",gold==10,gold)
        c:Command("stay");clearCargo();give("seeds",3);give("cutgrass",4);give("twigs",4);give("berries",4)
        bot.components.hunger:SetPercent(1)
        local field=SpawnPrefab("farm_soil");field.Transform:SetPosition(bot:GetPosition().x+1,0,bot:GetPosition().z+1)
        c.projects={}
        gardenid=require("ai_projects").RememberGarden(c,field:GetPosition(),"隔离测试真实空耕地").id
        c:Command("auto")
    end)
    later(262,function()
        local location=c.projects[gardenid].position
        local plant
        for _,e in ipairs(TheSim:FindEntities(location.x,0,location.z,2)) do if e:HasTag("farm_plant") then plant=e;break end end
        check("idle_garden_replants_real_seed",plant~=nil)
        local saved=bot:GetSaveRecord()
        check("garden_plan_in_native_save",saved.data.aicompanion.projects[gardenid]~=nil)
        c:Command("stay")
        local data=c:OnSave();c.projects={};c:OnLoad(data)
        check("garden_plan_restored",c.projects[gardenid]~=nil and c.projects[gardenid].nextcheck==0)
        local project=c.projects[gardenid]
        require("ai_projects").Apply(c,{{id=gardenid,operation="remove"}})
        check("cancelled_garden_not_rediscovered",require("ai_projects").RememberGarden(c,Vector3(project.position.x,0,project.position.z),"再次看见") == nil)
        project.operation="upsert";require("ai_projects").Apply(c,{project})
        give("dug_grass",1)
        local count=0
        for _,e in ipairs(TheSim:FindEntities(c.home.x,0,c.home.z,7)) do if e.prefab=="grass" then count=count+1 end end
        c:Command("auto");c.plan={activity="transplant",prefab="dug_grass",count=count+1,reason="持续执行真实移植直到新增一株"}
    end)
    later(272,function()
        local found=false
        for _,e in ipairs(TheSim:FindEntities(c.home.x,0,c.home.z,7)) do if e.prefab=="grass" then found=true end end
        check("transplant_deploys_real_plant",not bot.components.inventory:Has("dug_grass",1) and found,c.status)
        c:Command("stay");clearCargo();give("mandrake",1)
        bot.components.hunger:SetPercent(.04)
    end)
    later(282,function()
        check("emergency_eats_real_precious_food",bot.components.hunger:GetPercent()>.04
            and not bot.components.inventory:Has("mandrake",1),bot.components.hunger:GetPercent())
    end)
    later(304,function()
        c:Command("stay");clearCargo();bot.components.hunger:SetPercent(1)
        -- Fixture setup must fill the whole base, including a chest just beyond
        -- the actor's current 22-unit observation radius. Otherwise using an
        -- existing empty chest correctly would look like a failed expansion.
        local boxes={}
        for _,b in ipairs(TheSim:FindEntities(c.home.x,0,c.home.z,24,{"_container"},{"INLIMBO"})) do
            if require("ai_inventory").AllowedChest(bot,b) then boxes[#boxes+1]=b end
        end
        for _,b in ipairs(boxes) do
            for slot=1,b.components.container:GetNumSlots() do
                local old=b.components.container.slots[slot]
                if old then b.components.container:RemoveItem(old,true);old:Remove() end
                local item=SpawnPrefab("rocks");item.components.stackable:SetStackSize(40);b.components.container:GiveItem(item,slot)
            end
        end
        local bin=boxes[1].components.container
        local old=bin.slots[1];bin:RemoveItem(old,true);old:Remove()
        local wood=SpawnPrefab("log");wood.components.stackable:SetStackSize(40);bin:GiveItem(wood,1)
        for slot=1,bot.components.inventory:GetNumSlots() do
            if not bot.components.inventory.itemslots[slot] then bot.components.inventory:GiveItem(SpawnPrefab("nitre"),slot) end
        end
        local full=#boxes>0;local probe=SpawnPrefab("nitre")
        for _,b in ipairs(boxes) do full=full and b.components.container:IsFull()
            and b.components.container:CanAcceptCount(probe)==0 end
        probe:Remove()
        check("full_bag_storage_fixture",full and bot.components.inventory:IsFull() and not bot.components.inventory:Has("log",1))
        nitreTotal=require("ai_inventory").Count(bot,"nitre")
        boxcountbefore=boxCount();c:Command("auto");c.plan={activity="store",reason="满背包和满仓库时腾位补箱"}
    end)
    later(349,function()
        check("full_bag_builds_storage",boxCount()==boxcountbefore+1,c.status)
        check("temporary_cargo_recovered",#(c.staged_cargo or {})==0,#(c.staged_cargo or {}))
        local total=0
        for _,b in ipairs(TheSim:FindEntities(c.home.x,0,c.home.z,24,{"_container"},{"INLIMBO"})) do for _,item in pairs(b.components.container.slots) do
            if item.prefab=="nitre" then total=total+item.components.stackable:StackSize() end
        end end
        check("full_bag_cargo_conserved",total==nitreTotal,total.."/"..nitreTotal)
        c:Command("stay")
    end)
    later(352,function()
        c:Command("stay");c.work_context="objective"
        local Tasks=require("ai_tasks")
        Tasks.Accept(c,{activity="collect",prefab="log",count=30,reason="隔离验证原目标"},nil,"chat","保留30木头目标")
        c.plan.delivered=8;local id=c.job.id
        Tasks.Block(c,"missing_materials",{prefab="goldnugget",reason="隔离缺料"})
        check("blocked_method_preserves_root",c.job.id==id and c.job.status=="blocked" and c.plan.delivered==8)
        check("blocked_goal_rejects_replacement",not Tasks.Accept(c,{activity="craft",recipe="axe",reason="不能覆盖"},nil,"autonomy"))
        c.task_last_progress=GetTime()-10;local before=c.task_last_progress
        c:Event("action_success",{action="EAT"})
        check("survival_not_objective_progress",c.task_last_progress==before)
        give("log",16)
        Tasks.Accept(c,nil,{goal="营火后箱子",steps={{activity="craft",recipe="campfire",count=1,reason="营火"},
            {activity="craft",recipe="treasurechest",count=1,reason="后续箱子"}}},"chat")
        local reserves=require("ai_reservations").Compute(c,"campfire")
        check("future_recipe_reserves_materials",(reserves.protected.log or 0)>0)
        local saved=c:OnSave();check("approach_in_native_save",saved.job and saved.job.goal=="营火后箱子" and saved.job.approach~=nil)
        local N=require("ai_navigation");local pos=bot:GetPosition();local dest=Vector3(pos.x+12,0,pos.z)
        N.Failed(c,dest,"route_blocked");local route=next(c.nav_memory)
        local record=c:OnSave();N.Load(c,record.nav_memory)
        check("route_experience_in_native_save",route~=nil and next(c.nav_memory)~=nil)
        check("old_decision_rejected_locally",require("ai_decisionguard").Stale({plan={activity="explore"},decisionContext={at=GetTime()-46}},c))
        check("native_world_clock_available",type(m:Snapshot().time.dayFraction)=="number")
        give("greengem",5);c.projects={gems={id="gems",kind="stockpile",prefab="greengem",count=5}}
        check("precious_stockpile_respected",not require("ai_resources").CanUse(c,"greengem",1))
        c.projects={}
        local replyid="native-stale-chat-070"
        m:Apply({id=replyid,session=m.session,revision=c.revision,source="chat",expires=GetTime()+10,
            taskGuard={id=c.job.id,index=0,closed=false},plan={activity="explore",reason="旧阶段"},reply="我开始探索了"})
        local receipt=m.receipts and m.receipts[#m.receipts]
        check("stale_chat_has_negative_receipt",receipt and receipt.id==replyid and receipt.actionAccepted==false)
        check("stale_chat_preserves_workflow",c.job.goal=="营火后箱子" and c.job.index==1)
        m:Apply({id="native-skill-rejected-070",session=m.session,revision=c.revision,source="chat",expires=GetTime()+10,
            learnSkill="nonexistent_skill_test",reply="我学会了"})
        check("failed_skill_has_negative_receipt",m.receipts[#m.receipts].actionAccepted==false)
        local rootid=c.job.id;local progress=c.plan.built or 0
        m:Apply({id="native-goal-board-080",session=m.session,revision=c.revision,source="chat",expires=GetTime()+10,
            goalBoard={short={"补工具材料"},medium={"稳定食物"},long={"跨季生存"},next="先补树枝",reason="隔离验证"},
            method={reason="先补工具材料但保留根目标",plan={activity="collect",prefab="twigs",count=1,reason="补树枝"}},reply=""})
        check("repair_keeps_root_goal",c.job.id==rootid and (c.plan.built or 0)==progress and c.method_plan~=nil)
        local methodsave=c:OnSave();c.method_plan=nil;Tasks.Load(c,methodsave)
        check("method_restored_from_native_save",c.method_plan and c.method_plan.prefab=="twigs" and c.job.id==rootid)
        give("twigs",1);Tasks.Method(c)
        check("method_finishes_from_real_inventory",c.method_plan==nil and c.job.id==rootid)
        local current=c:OnSave()
        check("goal_board_in_native_save",current.goal_board and current.goal_board.long[1]=="跨季生存")
        check("action_queue_in_native_save",current.eventsequence>0 and #(current.action_events or {})>0)
        check("live_action_and_goals_snapshot",m:Snapshot().goalBoard~=nil and m:Snapshot().actionState~=nil)
        Tasks.Repair(c,{activity="collect",prefab="twigs",count=50,reason="隔离过期验证"},"有界方法")
        c.method_until=GetTime()-1;Tasks.Method(c)
        check("method_expiry_retains_root_goal",c.method_plan==nil and c.job.id==rootid)
        c:Command("stay")
        m:Apply({id="native-rejected-board-080",session=m.session,revision=c.revision,source="chat",expires=GetTime()+10,
            goalBoard={long={"不应覆盖"}},method={reason="手动模式不应接受",plan={activity="collect",prefab="twigs",count=1,reason="拒绝"}},reply=""})
        check("rejected_method_preserves_goal_board",m.receipts[#m.receipts].actionAccepted==false and c.goal_board.long[1]=="跨季生存")
    end)
    later(360,function()
        local file=io.open("unsafedata/ai_companion_test.json","w")
        if file then file:write(json.encode_compliant({results=rows,modelTested=runModel==true,reliabilityOnly=reliabilityOnly==true,snapshot=m:Snapshot()}));file:close() end
        print("[AI_TEST] FINISHED",#rows)
        TheWorld:DoTaskInTime(1,function() c_shutdown(false) end)
    end)
end
return T
