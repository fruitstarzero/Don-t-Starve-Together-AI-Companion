local Widget=require("widgets/widget")
local Text=require("widgets/text")
local TextButton=require("widgets/textbutton")
local H=require("ai_speechhistory")
local Style=require("widgets/aistyle")
local WIDTH,HEIGHT,TITLE_Y=480,390,167
local VISIBLE_LINES=7
local PREFS="wendy_ai_history_ui"

local History=Class(Widget,function(self)
    Widget._ctor(self,"AICompanionHistory")
    self.records={};self.lineoffset=0;self.colourmode="auto"
    self.bg=self:AddChild(Style.Panel(WIDTH,HEIGHT,{plain=true,opacity=.72}))
    -- Give the history its own hit region; left clicks here must not move the player.
    self.bg:SetClickable(true);self.bg.fill:SetClickable(true)
    self.heading=self:AddChild(Text(BODYTEXTFONT,22,""));self.heading:SetPosition(-96,TITLE_Y)
    self.heading:SetClickable(false)
    self.colourbutton=self:AddChild(TextButton())
    self.colourbutton:SetFont(BODYTEXTFONT);self.colourbutton:SetTextSize(20);self.colourbutton:SetPosition(100,TITLE_Y)
    self.colourbutton:SetTooltip("切换自动配色／黑字／白字")
    self.colourbutton:SetOnClick(function()
        local modes={auto="black",black="white",white="auto"}
        self.colourmode=modes[self.colourmode] or "auto";self.preferences_changed=true
        self:UpdateColours(true);self:SavePreferences()
    end)
    self.toggle=self:AddChild(TextButton())
    self.toggle:SetFont(BODYTEXTFONT);self.toggle:SetTextSize(20);self.toggle:SetText("收起");self.toggle:SetPosition(208,TITLE_Y)
    self.toggle:SetOnClick(function()self.collapsed=not self.collapsed;self:Render();self:PlaceAt()end)
    self.body=self:AddChild(Widget("speech_body"))
    self.context=self.body:AddChild(Text(BODYTEXTFONT,20,""))
    self.context:SetRegionSize(436,26);self.context:SetHAlign(ANCHOR_LEFT);self.context:SetPosition(0,128);self.context:SetClickable(false)
    self.detail=self.body:AddChild(Text(BODYTEXTFONT,26,""))
    self.detail:SetRegionSize(436,232);self.detail:SetHAlign(ANCHOR_LEFT);self.detail:SetVAlign(ANCHOR_TOP)
    self.detail:SetPosition(0,-10);self.detail:SetClickable(false)
    self.previous=self.body:AddChild(TextButton())
    self.previous:SetFont(BODYTEXTFONT);self.previous:SetTextSize(20);self.previous:SetText("更早一条");self.previous:SetPosition(-166,-164)
    self.previous:SetOnClick(function()self:Navigate(-1)end)
    self.next=self.body:AddChild(TextButton())
    self.next:SetFont(BODYTEXTFONT);self.next:SetTextSize(20);self.next:SetText("更新一条");self.next:SetPosition(166,-164)
    self.next:SetOnClick(function()self:Navigate(1)end)
    self.back=self.body:AddChild(TextButton())
    self.back:SetFont(BODYTEXTFONT);self.back:SetTextSize(18);self.back:SetPosition(0,-164)
    self.back:SetOnClick(function()self:ScrollLines(VISIBLE_LINES)end)
    self:UpdateColours(true);self:LoadPreferences();self:Hide()
end)
function History:LoadPreferences()
    if not TheSim or not TheSim.GetPersistentString or not json then return end
    TheSim:GetPersistentString(PREFS,function(success,text)
        if not success or self.preferences_changed or not self.inst:IsValid() or type(text)~="string" or #text>1000 then return end
        local ok,data=pcall(json.decode,text)
        if not ok or type(data)~="table" then return end
        if data.colour=="auto" or data.colour=="black" or data.colour=="white" then self.colourmode=data.colour end
        -- Deliberately ignore old x/y preferences: the window is now fixed bottom-left.
        self:UpdateColours(true)
    end)
end
function History:SavePreferences()
    if TheSim and TheSim.SetPersistentString and json then
        TheSim:SetPersistentString(PREFS,json.encode({colour=self.colourmode}),false)
    end
end
function History:UpdateColours(force)
    local light
    if self.colourmode=="black" then light=true
    elseif self.colourmode=="white" then light=false
    else
        local world=TheWorld and TheWorld.state
        if world and world.isday and not TheWorld:HasTag("cave") then light=true
        elseif ThePlayer and ThePlayer.LightWatcher then
            local value=ThePlayer.LightWatcher:GetLightValue()
            -- Hysteresis avoids flickering while passing a torch or fire.
            light=value>=(self.lighttheme and .4 or .6)
        else light=world and world.phase=="day" or not world and self.phase=="day" end
    end
    if not force and self.lighttheme==light then return end
    self.lighttheme=light
    local normal=light and {.08,.07,.05,1} or {.98,.98,1,1}
    local focus=light and {0,0,0,1} or {1,.91,.65,1}
    local muted=light and {.27,.20,.11,1} or {.88,.82,.67,1}
    if light then self.bg:SetFillColour(.98,.95,.86) else self.bg:SetFillColour(.035,.045,.06) end
    self.heading:SetColour(normal);self.detail:SetColour(normal);self.context:SetColour(muted)
    for _,button in ipairs({self.colourbutton,self.toggle,self.previous,self.next,self.back}) do
        button:SetTextColour(normal);button:SetTextFocusColour(focus)
    end
    self.colourbutton:SetText(({auto="配色:自动",black="配色:黑字",white="配色:白字"})[self.colourmode])
end

function History:ScreenMetrics()
    local p=self:GetPosition();local origin=self:GetWorldPosition()
    self:SetPosition(p.x+1,p.y+1)
    local unit=self:GetWorldPosition();self:SetPosition(p)
    return origin,math.max(.01,math.abs(unit.x-origin.x)),math.max(.01,math.abs(unit.y-origin.y))
end
function History:PlaceAt()
    if not self.parent or not TheSim then return end
    local origin,sx,sy=self:ScreenMetrics();local p=self:GetPosition()
    local w,h=TheSim:GetScreenSize()
    local cx=math.min(w-(WIDTH/2+24)*sx, (WIDTH/2+60)*sx)
    local cy=math.min(h-(HEIGHT/2+28)*sy,(HEIGHT/2+100)*sy)
    self:SetPosition(p.x+(cx-origin.x)/sx,p.y+(cy-origin.y)/sy)
end
function History:OnShow()self:StartUpdating()end
function History:OnHide()self:StopUpdating()end
function History:OnUpdate(dt)
    self.colourclock=(self.colourclock or 0)+dt
    if self.colourclock>=.5 or not self.position_ready then
        self.colourclock=0;self:UpdateColours();self:PlaceAt();self.position_ready=true
    end
end
function History:Refresh(snapshot)
    if not snapshot or snapshot.ready~=true then self:Hide();return end
    self.phase=snapshot.time and snapshot.time.phase
    local key=tostring(snapshot.owner).."/"..tostring(snapshot.world).."/"..tostring(snapshot.shard)
    if key~=self.worldkey then self.worldkey=key;self.records={};self.selected=nil;self.lineoffset=0 end
    local wasLatest=#self.records==0 or self.selected==self.records[#self.records].id
    local added=0
    for _,r in ipairs(snapshot.responses or {}) do if H.Push(self.records,r) then added=added+1 end end
    if #self.records==0 then self:Hide();return end
    if not self:SelectedIndex() or added>0 and wasLatest and self.lineoffset==0 then
        self.selected=self.records[#self.records].id;self.lineoffset=0
    end
    self:Show();self:Render()
end
function History:SelectedIndex()
    for i,r in ipairs(self.records) do if r.id==self.selected then return i end end
end
function History:Navigate(direction)
    local index=self:SelectedIndex() or #self.records
    index=math.max(1,math.min(#self.records,index+direction))
    if self.records[index] then self.selected=self.records[index].id;self.lineoffset=0;self:Render() end
end
function History:ScrollLines(delta)
    local max=math.max(0,#(self.lines or {})-VISIBLE_LINES)
    self.lineoffset=math.max(0,math.min(max,(self.lineoffset or 0)+delta));self:Render()
end
function History:OnControl(control,down)
    if History._base.OnControl(self,control,down) then return true end
    if not self.focus or self.collapsed then return false end
    if control==CONTROL_SCROLLBACK or control==CONTROL_SCROLLFWD then
        if down then self:ScrollLines(control==CONTROL_SCROLLBACK and -1 or 1) end
        return true
    end
    if control==CONTROL_PRIMARY then return true end
    return false
end
function History:OnMouseButton(button,down,x,y)
    if History._base.OnMouseButton(self,button,down,x,y) then return true end
    return self.focus and button==MOUSEBUTTON_LEFT or false
end
function History:Render()
    self.toggle:SetText(self.collapsed and "展开" or "收起")
    self.heading:SetString("AI伙伴 · 发言 ("..#self.records..")");self:UpdateColours()
    if self.collapsed then
        self.body:Hide();self.bg:SetSize(WIDTH,44);self.bg:SetPosition(0,TITLE_Y);return
    end
    self.body:Show();self.bg:SetSize(WIDTH,HEIGHT);self.bg:SetPosition(0,0)
    local index=self:SelectedIndex();if not index then return end
    local record=self.records[index]
    self.lines=H.Lines(record.text,14)
    self.lineoffset=math.max(0,math.min(self.lineoffset,math.max(0,#self.lines-VISIBLE_LINES)))
    local visible={}
    for i=self.lineoffset+1,math.min(#self.lines,self.lineoffset+VISIBLE_LINES) do visible[#visible+1]=self.lines[i] end
    self.detail:SetString(table.concat(visible,"\n"))
    self.context:SetString(H.ContextLabel(record.context).."  "..index.."/"..#self.records)
    self.back:SetText(#self.lines>VISIBLE_LINES and (self.lineoffset+1).."/"..#self.lines.."行 ↓" or "全文")
end
return History
