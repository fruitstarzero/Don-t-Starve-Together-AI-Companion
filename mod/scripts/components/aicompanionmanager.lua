local P=require("ai_policy")
local I=require("ai_inventory")
local S=require("ai_social")
local M=require("ai_memory")
local C=require("ai_capabilities")
local H=require("ai_speechhistory")
local R=require("ai_resources")
local Manager=Class(function(self,inst)
    self.inst=inst
    self.session=tostring(os.time()).."-"..tostring(math.random(100000,999999))
    self.sequence=0
    self.chatsequence=0
    self.chats={}
    self.responses={}
    self.seen_results={}
    self.bridge="等待本机 AI 服务"
    inst:ListenForEvent("ms_playerjoined",function(_,player)
        if player:HasTag("ai_companion") or not self.autospawn then return end
        inst:DoTaskInTime(2,function()
            if player:IsValid() and self:Authorized(player,true) and not self.bot then self:Spawn(player) end
        end)
    end)
    self.task=inst:DoPeriodicTask(2,function() self:Poll() end,4)
end)

function Manager:Authorized(player,claim)
    if not player or not player:IsValid() or player:HasTag("ai_companion") or not player.userid or player.userid=="" then return false end
    if self.ownerid then return self.ownerid==player.userid end
    local client=TheNet:GetClientTableForUser(player.userid)
    if claim and client and client.admin then self.ownerid=player.userid; return true end
    return false
end

function Manager:ConfigureBot(bot)
    self.bot=bot
    bot:AddTag("ai_companion")
    bot:AddTag("companion")
    -- A player without a remote network client otherwise falls asleep outside
    -- client simulation range, freezing animation completion and real physics.
    bot.entity:SetCanSleep(false)
    local bond=bot.components.ghostlybond
    if bond and not bot._ai_bond_awake then
        bot._ai_bond_awake=true
        local old=bond.onsummonfn
        bond.onsummonfn=function(inst,ghost,...)
            ghost.entity:SetCanSleep(false)
            if old then old(inst,ghost,...) end
        end
    end
    bot:DoTaskInTime(.1,function()
        local ghost=bot.components.ghostlybond and bot.components.ghostlybond.ghost
        if ghost then
            ghost.entity:SetCanSleep(false)
            -- Retain vanilla Lua limbo/hide/physics rules while keeping the
            -- native entity awake enough to resume its summon animation.
            ghost:ForceOutOfLimbo(true)
        end
    end)
    bot.persists=false -- Saved once in this world component, never in account saves.
    if not bot.components.aicompanion then bot:AddComponent("aicompanion") end
    bot.components.aicompanion.ownerid=self.ownerid
    bot.components.aicompanion:Start()
    bot.components.inventory:Open()
    if not bot.components.named then bot:AddComponent("named") end
    bot.components.named:SetName("AI伙伴")
    self.social=S.New(GetTime())
    bot:ListenForEvent("onremove",function() if self.bot==bot then self.bot=nil end end)
end

function Manager:Spawn(player)
    if self.bot and self.bot:IsValid() then return self.bot end
    if TheWorld:HasTag("cave") then self.bridge="跨洞穴迁移尚待专项验收，暂不在洞穴另建同伴"; return end
    local bot=SpawnPrefab("wendy")
    if not bot then self.bridge="原版温蒂未能生成"; return end
    self:ConfigureBot(bot)
    local p=player:GetPosition()
    bot.Transform:SetPosition(p.x+1,0,p.z+1)
    bot.components.aicompanion.home=p
    if bot.OnNewSpawn then bot:OnNewSpawn() end
    bot.components.aicompanion:Event("joined",{prefab="wendy"})
    self.bridge="原版温蒂已加入，连接 AI 服务中"
    return bot
end

function Manager:Snapshot()
    local b=self.bot
    if not b or not b:IsValid() then return {ready=false,status=self.bridge,session=self.session,owner=self.ownerid} end
    local c=b.components.aicompanion
    local h=b.components.health
    local bond=b.components.ghostlybond
    local ghost=bond and bond.ghost
    local entities={}
    for _,v in ipairs(c:Scan(25)) do
        if v~=b and #entities<100 then
            local p=v:GetPosition()
            local d={id=v.GUID,prefab=v.prefab,name=v:GetDisplayName(),x=p.x,z=p.z,capabilities=C.Entity(v)}
            if v.components.inventoryitem and not v.components.inventoryitem.owner then d.pickup=true end
            if v.components.pickable then d.pickable=v.components.pickable:CanBePicked(); d.product=v.components.pickable.product end
            if v.components.workable then d.work=v.components.workable:GetWorkAction().id end
            if v.components.health then d.health=v.components.health:GetPercent() end
            if v.components.combat and v.components.combat.target then d.attacking=v.components.combat.target.GUID end
            if v.components.container and I.AllowedChest(b,v) then
                d.chest=I.Chest(c,v)
                d.items={}
                for _,item in pairs(v.components.container.slots) do table.insert(d.items,I.Describe(item)) end
            end
            if v.components.prototyper then d.science=true end
            if v.components.farmplanttendable then d.needs_tending=v.components.farmplanttendable.tendable end
            table.insert(entities,d)
        end
    end
    local recipes,knownRecipes={},{}
    local builder=b.components.builder
    for name,recipe in pairs(AllRecipes) do
        if builder:KnowsRecipe(recipe) then table.insert(knownRecipes,name) end
        if #recipes<100 and builder:HasIngredients(recipe) and (builder:KnowsRecipe(recipe)
            or builder:CanLearn(name) and CanPrototypeRecipe(recipe.level,builder.accessible_tech_trees)) then
            table.insert(recipes,name)
        end
    end
    local p=b:GetPosition()
    local owner=c:Owner()
    local op=owner and owner:GetPosition()
    self.enabledmods=self.enabledmods or C.Mods()
    local landmarks={};for _,m in pairs(c.landmarks or {}) do landmarks[#landmarks+1]=m end
    local danger=c.threat and c.threat:IsValid() and b:GetDistanceSqToInst(c.threat)<18*18
    local social=S.Observe(self.social,{near=owner and b:GetDistanceSqToInst(owner)<=10*10,
        safe=not danger and not b:HasTag("playerghost") and not b.sg:HasStateTag("attack"),
        danger=danger,health=h:GetPercent(),hunger=b.components.hunger:GetPercent(),
        phase=TheWorld.state.phase,events=c.events,problem=c.problem},GetTime())
    if b:HasTag("playerghost") then social.canSpeak=false end
    return {ready=true,session=self.session,sequence=self.sequence,revision=c.revision,
        world=TheNet:GetSessionIdentifier(),shard=TheShard:GetShardId(),
        at=GetTime(),owner=self.ownerid,ownerHere=owner~=nil,saveSerial=self.saveserial or 0,
        status=c.status,bridge=self.bridge,mode=c.mode,plan=c.plan,taskJournalVersion=1,taskJournal=c.job,taskHistory=c.task_history,
        time={day=TheWorld.state.cycles,dayFraction=TheWorld.state.time,phase=TheWorld.state.phase,season=TheWorld.state.season,
            remainingDays=TheWorld.state.remainingdaysinseason,
            raining=TheWorld.state.israining,temperature=TheWorld.state.temperature},
        player=op and {x=op.x,z=op.z,ghost=owner:HasTag("playerghost"),inventory=I.Items(owner),
            tech=owner.components.builder and owner.components.builder.accessible_tech_trees},
        social=social,enabledMods=self.enabledmods,landmarks=landmarks,baseResources=R.Snapshot(c),problem=c.problem,
        projects=require("ai_projects").Snapshot(c),worksites=c.worksites,preparation=c.preparation,stagedCargo=c.staged_cargo,
        procurement=c.procurement,resourceMemory=c.resource_memory,terrainMemory=c.terrain_memory,
        actionCatalog=require("ai_actions").Snapshot(),
        routeExperience=c.nav_memory,
        companion={prefab=b.prefab,name=b:GetDisplayName(),x=p.x,z=p.z,health=h.currenthealth,maxHealth=h.maxhealth,
            hunger=b.components.hunger.current,maxHunger=b.components.hunger.max,
            sanity=b.components.sanity.current,maxSanity=b.components.sanity.max,
            ghost=b:HasTag("playerghost"),temperature=b:GetTemperature(),moisture=b:GetMoisture(),
            inventory=I.Items(b),home=c.home and {x=c.home.x,z=c.home.z},homeMemory=c.home_memory,
            skills=b.components.skilltreeupdater and b.components.skilltreeupdater:GetActivatedSkills(),
            skillXP=b.components.skilltreeupdater and b.components.skilltreeupdater:GetSkillXP()},
        abigail=bond and {summoned=bond.summoned==true,level=bond.bondlevel,
            health=ghost and ghost.components.health.currenthealth,maxHealth=ghost and ghost.components.health.maxhealth,
            defensive=ghost and ghost.is_defensive},
        recipeDetails=require("ai_recipebook").ForConversation(c,self.chats),
        availableSkills=require("ai_skills").Options(b),observed=entities,craftable=recipes,knownRecipes=knownRecipes,events=c.events,chats=self.chats,
        goalBoard=c.goal_board,actionEvents=c.action_events,actionGap=c.action_gap,
        actionState={current=c.status,action=c.pending and c.pending.action,since=c.pending and c.pending.since,
            task=c.job and c.job.goal,method=c.job and c.job.method,next=c.goal_board and c.goal_board.next},
        supersededChats=self.superseded,responses=self.responses,receipts=self.receipts or {}}
end

function Manager:SendStatus(player)
    if self.send and player and player.userid and TheNet:GetClientTableForUser(player.userid) then
        self.send(player.userid,require("ai_clientstatus").Pack(self:Snapshot(),json.encode_compliant))
    end
end

function Manager:RecordReply(id,text,source,topic,speak,modelError,remoteId,userText,actionAccepted)
    local state=TheWorld and TheWorld.state or {}
    local record={id=id,text=text,source=source,actionAccepted=actionAccepted,modelError=modelError==true,remoteId=remoteId,userText=userText,at=GetTime(),context={
        day=state.cycles and state.cycles+1,phase=state.phase,topic=topic}}
    if not H.Push(self.responses,record) then return end
    if speak and self.bot and self.bot.components.talker then
        self.bot.components.talker:Say(H.Limit(text,160),8)
    end
end

function Manager:Command(player,command,text,remoteId)
    if not self:Authorized(player,true) then return end
    if type(command)~="string" or #command>40 or type(text)~="string" or #text>3600 then return end
    if command=="spawn" then self:Spawn(player)
    elseif command=="status" then -- read-only
    elseif command=="chat" then
        if not self.bot then self:Spawn(player) end
        if self.bot and text:match("%S") then
            local normalized=text:gsub("^%s+",""):gsub("%s+$","")
            local speaker=player:GetPosition()
            if M.IsHomeDeclaration(normalized) then
                M.SetHome(self.bot.components.aicompanion,speaker,normalized)
            end
            local quick={ ["跟随"]="follow",["跟着我"]="follow",["跟我走"]="follow",["停下"]="stay",
                ["停止"]="stay",["待命"]="stay",["自主行动"]="auto",["自由行动"]="auto",["过来"]="come",
                ["到我身边"]="come",["回家"]="home",["回基地"]="home",["撤退"]="retreat",["快撤"]="retreat" }
            quick["传送过来"]="teleport";quick["传送到我身边"]="teleport"
            quick["继续原任务"]="resume";quick["恢复原任务"]="resume";quick["取消任务"]="cancel";quick["取消原任务"]="cancel"
            if quick[normalized] then
                self.chats={};self.bot.components.aicompanion:Command(quick[normalized])
                self:RecordReply(self.session.."-quick-"..self.bot.components.aicompanion.revision,
                    "已接受："..normalized.."。","chat","command",false,false,remoteId,text)
                self:SendStatus(player);return
            end
            local last=self.chats[#self.chats]
            if last and GetTime()-last.at<1 then return end
            self.chatsequence=self.chatsequence+1
            -- New text invalidates older model replies, but local work continues
            -- until an actual command/plan is returned. Questions never freeze it.
            local c=self.bot.components.aicompanion
            c.revision=c.revision+1
            c.awaiting_chat=nil
            -- Keep superseded text as conversation context, not executable jobs.
            self.superseded=self.superseded or {}
            for _,old in ipairs(self.chats) do
                table.insert(self.superseded,{text=old.text,at=old.at})
            end
            while #self.superseded>10 do table.remove(self.superseded,1) end
            self.chats={}
            self.chats[#self.chats+1]={id=self.session.."-"..self.chatsequence,text=text,
                remoteId=remoteId,
                revision=c.revision,at=GetTime(),expires=GetTime()+185,
                context={speaker={x=speaker.x,z=speaker.z},shard=TheShard:GetShardId()}}
            self.bridge="已收到，正在思考"
        end
    elseif P.commands[command] and self.bot then
        self.chats={}; self.bot.components.aicompanion:Command(command)
    end
    self:SendStatus(player)
end

local function RejectActions(result,reason)
    result.plan=nil;result.workflow=nil;result.command=nil;result.learnSkill=nil;result.projectUpdates={};result.placeUpdates={}
    result.method=nil;result.goalBoard=nil
    result.staleAction=true;result.reply=result.source=="chat" and reason or ""
end
function Manager:Apply(result)
    if not self.bot or type(result)~="table" or type(result.id)~="string" or self.seen_results[result.id] then return end
    local c=self.bot.components.aicompanion
    if not P.CanApply(result,self.session,c.revision,c.mode,GetTime()) then return end
    if (result.decisionContext or result.taskGuard) and require("ai_decisionguard").Stale(result,c) then
        RejectActions(result,"环境或任务阶段已变化，这份旧方案没有执行；原任务仍保留。")
    end
    self.seen_results[result.id]=true
    if result.source=="chat" then c.awaiting_chat=nil end
    if result.learnSkill and not require("ai_skills").Learn(self.bot,result.learnSkill) then
        RejectActions(result,"技能条件暂未满足，学习没有成功；这份新方案没有执行，原任务保留。")
    end
    if result.chatid then
        for i=#self.chats,1,-1 do if self.chats[i].id==result.chatid then table.remove(self.chats,i) end end
    end
    if result.method then
        if not require("ai_tasks").Repair(c,result.method.plan,result.method.reason) then
            RejectActions(result,"当前目标或模式已变化，这次方法调整没有执行。")
        end
    elseif result.command and P.commands[result.command] and result.source=="chat" then
        c:Command(result.command,result.speakerPosition)
    elseif result.source~="social" and (P.ValidPlan(result.plan) or result.workflow) then
        -- Autonomous planning cannot switch manual follow/stay/home to another mode.
        local valid=true
        if result.workflow then
            valid=result.source=="chat" and P.ValidWorkflow(result.workflow)
        end
        if valid and (result.source=="chat" or c.mode=="auto") then
            if require("ai_tasks").Accept(c,result.plan,result.workflow,result.source,result.taskGoal) then
                c.trip_seconds=result.tripSeconds;c.status="计划："..c.plan.reason
            else
                RejectActions(result,"当前任务仍需保留，新方案没有替换正在执行的目标。")
            end
        end
    end
    if not result.staleAction then
        M.ApplyPlaces(c,result.placeUpdates)
        if result.projectUpdates and #result.projectUpdates>0 then require("ai_projects").Apply(c,result.projectUpdates) end
        if result.goalBoard then c.goal_board=result.goalBoard end
    end
    self.receipts=self.receipts or {}
    self.receipts[#self.receipts+1]={id=result.id,text=result.reply or "",source=result.source,
        actionAccepted=not result.staleAction,at=GetTime()}
    while #self.receipts>20 do table.remove(self.receipts,1) end
    if type(result.reply)=="string" and #result.reply>0 then
        local topic=result.source=="chat" and "chat" or self.social.candidate and self.social.candidate.kind
        local allowed=result.source=="chat"
        if not allowed then
            local status=self:Snapshot().social
            allowed=status.canSpeak and S.Accept(self.social,result.speechId,result.reply,GetTime())
        else S.Record(self.social,result.reply,GetTime()) end
        if allowed then self:RecordReply(result.id,result.reply,result.source,topic,true,result.modelError,result.remoteId,result.userText,not result.staleAction) end
    end
    self.bridge="AI 已连接"
end

function Manager:Poll()
    if self.selftest then return end
    if not self.config or not self.bot or self.polling then return end
    local c=self.bot.components.aicompanion
    local owner=c:Owner()
    -- Waiting requests have bounded life and cannot unexpectedly act after reconnect.
    for i=#self.chats,1,-1 do if self.chats[i].expires<GetTime() then
        table.remove(self.chats,i); self.bridge="上条对话已超时，请重发"
    end end
    if not owner then return end
    self.sequence=self.sequence+1
    local snapshot=self:Snapshot()
    local body=json.encode_compliant({token=self.config.token,snapshot=snapshot})
    self.polling=true
    local epoch=self.sequence
    self.inst:DoTaskInTime(12,function() if self.sequence==epoch then self.polling=false end end)
    TheSim:QueryServer(self.config.url.."/v1/tick",function(data,success,code)
        self.polling=false
        if not self.inst:IsValid() then return end
        if not success or code~=200 then self.bridge="本机 AI 未连接；快捷控制与本地生存仍可用"; self:SendStatus(owner); return end
        local ok,result=pcall(json.decode,data)
        if ok and type(result)=="table" then
            if type(result.actionAck)=="number" then
                for i=#(c.action_events or {}),1,-1 do if c.action_events[i].id<=result.actionAck then table.remove(c.action_events,i) end end
            end
            for _,cancel in ipairs(result.cancellations or {}) do self:CancelRemote(cancel) end
            for _,remote in ipairs(result.commands or {}) do self:RemoteCommand(owner,remote) end
            for _,r in ipairs(result.results or {}) do self:Apply(r) end
            if result.health=="ready" and #self.chats==0 then self.bridge="AI 已连接" end
            if result.health=="model_error" then self.bridge="AI 模型调用未完成，正在退避重试；快捷按钮可用" end
        end
        self:SendStatus(owner)
    end,"POST",body)
end

function Manager:RemoteCommand(owner,r)
    if type(r)~="table" or type(r.id)~="string" or #r.id>100 or type(r.text)~="string" or #r.text>3600
        or r.session~=self.session or type(r.expires)~="number" or r.expires<GetTime() or not self.bot then return false end
    self.remote_seen=self.remote_seen or {}
    if self.remote_seen[r.id] or r.revision~=self.bot.components.aicompanion.revision then return false end
    if not self:Authorized(owner,false) then return false end
    for id,at in pairs(self.remote_seen) do if GetTime()-at>600 then self.remote_seen[id]=nil end end
    self.remote_seen[r.id]=GetTime()
    self:Command(owner,"chat",r.text,r.id)
    return true
end
function Manager:CancelRemote(r)
    if type(r)~="table" or r.session~=self.session or type(r.id)~="string" then return end
    for i=#self.chats,1,-1 do
        if self.chats[i].remoteId==r.id then
            table.remove(self.chats,i)
            if self.bot then local c=self.bot.components.aicompanion;c.revision=c.revision+1;c.awaiting_chat=nil end
        end
    end
end

function Manager:OnSave()
    self.saveserial=(self.saveserial or 0)+1
    return {ownerid=self.ownerid,responses=self.responses,saveserial=self.saveserial,
        bot=self.bot and self.bot:IsValid() and self.bot:GetSaveRecord() or self.savedbot}
end
function Manager:OnLoad(data)
    if not data then return end
    self.ownerid=data.ownerid
    self.saveserial=data.saveserial or 0
    self.responses=H.Restore(data.responses)
    self.savedbot=data.bot
    if data.bot then self.inst:DoTaskInTime(0,function()
        local bot=SpawnSaveRecord(data.bot)
        if bot then self:ConfigureBot(bot); self.savedbot=nil end
    end) end
end
function Manager:OnRemoveFromEntity() if self.task then self.task:Cancel() end end
return Manager
