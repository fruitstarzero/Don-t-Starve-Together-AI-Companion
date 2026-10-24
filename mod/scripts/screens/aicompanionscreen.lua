local Screen=require("widgets/screen")
local Widget=require("widgets/widget")
local Text=require("widgets/text")
local TextEdit=require("widgets/textedit")
local Style=require("widgets/aistyle")
local TextButton=Style.Button
local Image=require("widgets/image")
local H=require("ai_speechhistory")

local CompanionScreen=Class(Screen,function(self,send,snapshot)
    Screen._ctor(self,"AICompanionScreen")
    self.send=send
    self.root=self:AddChild(Widget("root"))
    self.root:SetHAnchor(ANCHOR_MIDDLE); self.root:SetVAnchor(ANCHOR_MIDDLE)
    self.root:SetScaleMode(SCALEMODE_PROPORTIONAL)
    self.shade=self.root:AddChild(Style.Panel(900,650))
    self.title=self.root:AddChild(Text(TITLEFONT,32,"AI伙伴 · 温蒂"))
    self.title:SetPosition(0,286)
    self.state=self.root:AddChild(Text(BODYTEXTFONT,21,""))
    self.state:SetRegionSize(840,100); self.state:EnableWordWrap(true); self.state:SetPosition(0,214)
    local buttons={{"加入伙伴","spawn"},{"传送到身边","teleport"},{"跟随帮忙","follow"},{"自主行动","auto"},
        {"待命／暂停","stay"},{"回基地","home"},{"紧急撤退","retreat"},{"此处设基地","sethome"},
        {"召唤阿比盖尔","abigail_summon"},{"收回阿比盖尔","abigail_recall"},{"目标／物资","resources"},{"背包／对话","inventory"}}
    for i,row in ipairs(buttons) do
        local button=self.root:AddChild(TextButton())
        button:SetText(row[1]); button:SetTextSize(22)
        button:SetPosition(-320+((i-1)%4)*215,140-math.floor((i-1)/4)*48)
        button:SetOnClick(function()
            if row[2]=="inventory" then self.show_inventory=not self.show_inventory;self.show_resources=false; self:Refresh(self.snapshot)
            elseif row[2]=="resources" then self.show_resources=not self.show_resources;self.show_inventory=false;self:Refresh(self.snapshot)
            else self.send(row[2],"") end
        end)
    end
    self.history=self.root:AddChild(Text(BODYTEXTFONT,22,""))
    self.history:SetRegionSize(820,170); self.history:EnableWordWrap(true)
    self.history:SetHAlign(ANCHOR_LEFT); self.history:SetVAlign(ANCHOR_TOP); self.history:SetPosition(0,-76)
    self.history_offset=0
    self.historyprev=self.root:AddChild(TextButton(75,24));self.historyprev:SetText("向上")
    self.historyprev:SetTextSize(18);self.historyprev:SetPosition(-380,-173)
    self.historyprev:SetOnClick(function()self:ScrollHistory(-4)end)
    self.historynext=self.root:AddChild(TextButton(75,24));self.historynext:SetText("向下")
    self.historynext:SetTextSize(18);self.historynext:SetPosition(380,-173)
    self.historynext:SetOnClick(function()self:ScrollHistory(4)end)
    self.entrybg=self.root:AddChild(Image("images/global_redux.xml","textbox3_gold_normal.tex"))
    self.entrybg:SetSize(680,48);self.entrybg:SetPosition(-50,-202)
    self.entry=self.root:AddChild(TextEdit(BODYTEXTFONT,26,""))
    self.entry:SetRegionSize(650,45); self.entry:SetPosition(-50,-202)
    self.entry:SetHAlign(ANCHOR_LEFT)
    self.entry:SetIdleTextColour(.97,.97,1,1)
    self.entry:SetEditTextColour(1,1,1,1)
    self.entry:SetEditCursorColour(1,1,1,1)
    self.entry:SetTextLengthLimit(1000)
    self.entry:SetAllowNewline(false)
    self.entry.OnTextEntered=function() self:Submit() end
    local sendbutton=self.root:AddChild(TextButton(100,42))
    sendbutton:SetText("发送"); sendbutton:SetTextSize(25); sendbutton:SetPosition(350,-202)
    sendbutton:SetOnClick(function() self:Submit() end)
    self.tip=self.root:AddChild(Text(BODYTEXTFONT,18,"远程安排任务或聊天；世界继续运行，请注意安全。Esc 关闭。"))
    self.tip:SetPosition(0,-253)
    self.close=self.root:AddChild(TextButton(130,38))
    self.close:SetText("关闭"); self.close:SetPosition(0,-293)
    self.close:SetOnClick(function() self:Close() end)
    self.local_lines={}
    self.seen_responses={}
    self:Refresh(snapshot)
end)

function CompanionScreen:Submit()
    local text=self.entry:GetString()
    if text and text:match("%S") then
        self.local_lines[#self.local_lines+1]="你："..text
        self.send("chat",text); self.entry:SetString("")
        self:Refresh(self.snapshot)
    end
end
function CompanionScreen:Refresh(s)
    self.snapshot=s or {}
    s=self.snapshot
    local c=s.companion
    local a=s.abigail
    local abi=a and string.format("阿比盖尔：%s Lv%d  %.0f/%.0f",a.summoned and "随行" or "花中休整",a.level or 1,a.health or 0,a.maxHealth or 0) or ""
    self.state:SetString(c and string.format("%s · %s\n生命 %.0f/%.0f  饥饿 %.0f/%.0f  理智 %.0f/%.0f\n%s · %s",s.mode or "",s.status or "",c.health,c.maxHealth,c.hunger,c.maxHunger,c.sanity,c.maxSanity,abi,s.bridge or "") or s.status or "尚未加入")
    for _,r in ipairs(s.responses or {}) do
        if not self.seen_responses[r.id] then
            self.seen_responses[r.id]=true
            table.insert(self.local_lines,"她："..r.text)
        end
    end
    while #self.local_lines>20 do table.remove(self.local_lines,1) end
    local lines=self.local_lines
    if self.show_resources then
        local stock=s.baseResources or {items={},observedBoxes=0}
        local out={"已观察箱子："..(stock.observedBoxes or 0).."，长期计划："..#(s.projects or {}).."。旧库存取用前核对。"}
        local board=s.goalBoard
        if board then
            out[#out+1]="眼前："..table.concat(board.short or {},"；")
            out[#out+1]="中期："..table.concat(board.medium or {},"；")
            out[#out+1]="长期："..table.concat(board.long or {},"；")
            out[#out+1]="下一步："..(board.next or "等待判断")
        end
        if s.actionState then out[#out+1]="正在做："..(s.actionState.current or "观察中") end
        if s.taskJournal then
            local j=s.taskJournal
            out[#out+1]="当前目标："..j.goal.."（"..j.index.."/"..#j.steps.."，"..j.status.."）"
            if j.interruption then out[#out+1]="暂离原因："..j.interruption end
        end
        for i,item in ipairs(stock.items or {}) do
            if i>8 then break end
            local places=stock.locations and stock.locations[item.prefab] or {}
            out[#out+1]=item.name.." ×"..item.count.."（"..(stock.locationCounts and stock.locationCounts[item.prefab] or #places).."箱"..(item.confirmed<item.count and "，含旧记录" or "").."）"
        end
        for i,p in ipairs(s.projects or {}) do if i<=3 then out[#out+1]="计划："..p.text end end
        if #(stock.items or {})==0 then out[#out+1]="还没检查基地箱子；把家设好，回基地附近查看。" end
        self:SetHistoryText(table.concat(out,"\n"));return
    end
    if self.show_inventory then
        lines={"随身背包（含已装备物品）："}
        for _,item in ipairs(c and c.inventory or {}) do
            table.insert(lines,(item.equipped and "[装备] " or "")..item.name.." ×"..item.count)
        end
        self:SetHistoryText(table.concat(lines,"\n"))
        return
    end
    self:SetHistoryText(table.concat(lines,"\n\n"))
end
function CompanionScreen:SetHistoryText(text)
    if self.history_text~=text then
        local wasLatest=self.history_offset>=math.max(0,#(self.history_lines or {})-5)
        self.history_lines=H.Lines(text,32);self.history_text=text
        if wasLatest then self.history_offset=math.max(0,#self.history_lines-5) end
    end
    self:ScrollHistory(0)
end
function CompanionScreen:ScrollHistory(delta)
    local lines=self.history_lines or {}
    self.history_offset=math.max(0,math.min(math.max(0,#lines-5),self.history_offset+delta))
    local out={};for i=self.history_offset+1,math.min(#lines,self.history_offset+5) do out[#out+1]=lines[i] end
    self.history:SetString(table.concat(out,"\n"))
end
function CompanionScreen:OnControl(control,down)
    if CompanionScreen._base.OnControl(self,control,down) then return true end
    if not down and control==CONTROL_CANCEL then self:Close(); return true end
    if self.history.focus and (control==CONTROL_SCROLLBACK or control==CONTROL_SCROLLFWD) then
        if down then self:ScrollHistory(control==CONTROL_SCROLLBACK and -1 or 1) end
        return true
    end
end
function CompanionScreen:Close()
    self.entry:SetEditing(false)
    TheFrontEnd:PopScreen(self)
end
function CompanionScreen:OnDestroy()
    if self.entry then self.entry:SetEditing(false) end
    if CompanionScreen._base.OnDestroy then CompanionScreen._base.OnDestroy(self) end
end
return CompanionScreen
