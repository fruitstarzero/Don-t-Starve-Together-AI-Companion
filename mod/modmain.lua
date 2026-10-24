local G = GLOBAL
local namespace = "wendy_ai_companion"
local private = require("ai_private")
local function Manager() return G.TheWorld and G.TheWorld.components.aicompanionmanager end

-- Recheck at the real crafting entry points, not only when planning. Human
-- Wendy has no AI ownerid, so her builder and other players remain untouched.
AddComponentPostInit("builder",function(builder)
    for _,method in ipairs({"DoBuild","BufferBuild"}) do
        local original=builder[method]
        builder[method]=function(self,name,...)
            local c=self.inst.components.aicompanion
            if c and c.ownerid and not self:IsBuildBuffered(name)
                and not require("ai_resources").CheckRecipe(c,name,true) then return false end
            return original(self,name,...)
        end
    end
end)

-- Attach before vanilla SpawnSaveRecord applies component save data. Human Wendy
-- stays inert: no ownerid, no AI task, no changed player statistics or controls.
AddPrefabPostInit("wendy", function(inst)
    if G.TheWorld.ismastersim then inst:AddComponent("aicompanion") end
end)

-- Transfers are normal short actions, with ownership, range, permissions and
-- survival reserves rechecked when the action actually executes.
local transfer = AddAction("AI_TRANSFER", "整理物品", function(act)
    local c = act.doer.components.aicompanion
    return c ~= nil and c:Transfer(act)
end)
transfer.distance = 2
AddStategraphActionHandler("wilson", G.ActionHandler(transfer, "doshortaction"))
local cookstore=AddAction("AI_COOKSTORE","放入锅料",function(act)
    local c=act.doer.components.aicompanion
    return c and require("ai_life").CookStore(c,act)
end)
cookstore.distance=2
AddStategraphActionHandler("wilson",G.ActionHandler(cookstore,"doshortaction"))

AddPrefabPostInit("world", function(inst)
    if not inst.ismastersim then return end
    inst:AddComponent("aicompanionmanager")
    local m = inst.components.aicompanionmanager
    m.config = private
    m.autospawn = GetModConfigData("autospawn")
    m.send = function(userid, snapshot)
        SendModRPCToClient(GetClientModRPC(namespace, "snapshot"), userid, G.json.encode(snapshot))
    end
    if GetModConfigData("selftest") then inst:DoTaskInTime(3, function()
        local mode=GetModConfigData("selftest")
        require("ai_selftest").Run(m,mode==true,mode=="reliability")
    end) end
end)

AddModRPCHandler(namespace, "command", function(player, command, text)
    local m = Manager()
    if m then m:Command(player, command, text) end
end)

local latest = { status = "进入世界后可连接伙伴。" }
AddClientModRPCHandler(namespace, "snapshot", function(encoded)
        local ok, value = G.pcall(G.json.decode, encoded)
        if ok and type(value) == "table" then
            latest = value
            local s = G.TheFrontEnd:GetActiveScreen()
            if s and s.name == "AICompanionScreen" then s:Refresh(value) end
            local controls=G.ThePlayer and G.ThePlayer.HUD and G.ThePlayer.HUD.controls
            if controls and controls.ai_speech_history then controls.ai_speech_history:Refresh(value) end
        end
end)
if not G.TheNet:IsDedicated() then
    local function Open()
        if not G.ThePlayer or not G.ThePlayer.HUD then return end
        local active = G.TheFrontEnd:GetActiveScreen()
        if active and active.name == "AICompanionScreen" then active:Close(); return end
        if active ~= G.ThePlayer.HUD then return end
        local screen = require("screens/aicompanionscreen")
        G.TheFrontEnd:PushScreen(screen(function(command, text)
            SendModRPCToServer(GetModRPC(namespace, "command"), command, text or "")
        end, latest))
        SendModRPCToServer(GetModRPC(namespace, "command"), "status", "")
    end
    G.TheInput:AddKeyUpHandler(GetModConfigData("hotkey") or G.KEY_F10, Open)
    AddClassPostConstruct("widgets/controls", function(self)
        local TextButton = require("widgets/textbutton")
        self.ai_companion_button = self.top_root:AddChild(TextButton())
        self.ai_companion_button:SetText("伙伴 F10")
        self.ai_companion_button:SetTextSize(25)
        self.ai_companion_button:SetPosition(-125, -100)
        self.ai_companion_button:SetOnClick(Open)
        local History=require("widgets/aicompanionhistory")
        self.ai_speech_history=self.bottomright_root:AddChild(History())
        self.ai_speech_history:Refresh(latest)
    end)
end
