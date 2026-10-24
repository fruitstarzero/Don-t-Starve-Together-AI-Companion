import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import luaparse from 'luaparse';
import {lua,lauxlib,lualib,to_luastring,to_jsstring} from 'fengari';
const read=file=>fs.readFileSync(new URL('../'+file,import.meta.url),'utf8');
const editSource=read('reference/scripts/widgets/textedit.lua');
const ast=luaparse.parse(editSource,{luaVersion:'5.1',ranges:true});
const editMethods=['SetEditing','SetIdleTextColour','SetEditTextColour','SetEditCursorColour'].map(name=>{
 const n=ast.body.find(n=>n.type==='FunctionDeclaration'&&n.identifier?.identifier?.name===name);
 if(!n)throw Error('Installed TextEdit method missing: '+name);
 return editSource.slice(...n.range);
}).join('\n');
const buttonSource=read('reference/scripts/widgets/button.lua');
const buttonAst=luaparse.parse(buttonSource,{luaVersion:'5.1',ranges:true});
const colourMethods=['SetTextColour','SetTextFocusColour'].map(name=>{
 const n=buttonAst.body.find(n=>n.type==='FunctionDeclaration'&&n.identifier?.identifier?.name===name);
 return buttonSource.slice(...n.range).replaceAll('Button:','TextButton:');
}).join('\n');
function run(code){const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);const status=lauxlib.luaL_dostring(L,to_luastring(code));
 const err=status?to_jsstring(lua.lua_tostring(L,-1)):undefined;lua.lua_close(L);assert.equal(status,lua.LUA_OK,err);}
const widgets=`
 unpack=table.unpack
 Class=function(base,ctor)
   if ctor==nil then ctor=base;base=nil end
   local c={_ctor=ctor,_base=base};c.__index=c
   return setmetatable(c,{__index=base,__call=function(cls,...)
     local self=setmetatable({},cls);ctor(self,...);return self end})
 end
 local Widget=Class(function(self,name)self.name=name;self.children={};self.shown=true;self.inst={IsValid=function()return true end}end)
 function Widget:AddChild(w)table.insert(self.children,w);w.parent=self;return w end
 function Widget:OnControl()return false end
 function Widget:OnMouseButton()return false end
 function Widget:SetColour(r,g,b,a)self.colour=type(r)=='table' and r or {r,g,b,a}end
 function Widget:SetTint(...)self.tint={...}end
 function Widget:SetString(s)self.string=s end
 function Widget:GetString()return self.string or ''end
 function Widget:SetText(s)self.text.string=s end
 function Widget:SetOnClick(fn)self.onclick=fn end
 function Widget:SetOnDown(fn)self.ondown=fn end
 function Widget:SetSize(w,h)self.size=w;self.height=h end
 function Widget:Hide()self.shown=false;if self.OnHide then self:OnHide()end end
 function Widget:Show()self.shown=true;if self.OnShow then self:OnShow()end end
 function Widget:StartUpdating()self.updating=true end
 function Widget:StopUpdating()self.updating=false end
 function Widget:SetTextSize(size)self.text.size=size end
 function Widget:SetRegionSize(w,h)self.region={w,h}end
 function Widget:SetPosition(x,y)self.position=type(x)=='table' and {x.x,x.y} or {x,y}end
 function Widget:GetPosition()return {x=self.position and self.position[1] or 0,y=self.position and self.position[2] or 0}end
 function Widget:GetScale()local n=self.scale or 1;local parent=self.parent and self.parent:GetScale() or {x=1,y=1};return{x=n*parent.x,y=n*parent.y}end
 function Widget:GetWorldPosition()
  if self.anchor then return{x=self.anchor[1],y=self.anchor[2]}end
  local p=self:GetPosition();local origin=self.parent and self.parent:GetWorldPosition() or{x=0,y=0}
  local scale=self.parent and self.parent:GetScale() or{x=1,y=1}
  return{x=origin.x+p.x*scale.x,y=origin.y+p.y*scale.y}
 end
 for _,name in ipairs({'SetHAnchor','SetVAnchor','SetScaleMode','EnableWordWrap','SetHAlign','SetVAlign',
   'SetTextLengthLimit','SetAllowNewline','SetFocus','DoSelectedImage','DoHoverImage','DoIdleImage','_TryUpdateTextPrompt',
   'SetClickable','MoveToFront','ScaleToSize','ForceImageSize','SetFont','SetTooltip'})do Widget[name]=function()end end
 local Text=Class(Widget,function(self,font,size,text)Widget._ctor(self,'Text');self.size=size;self.string=text end)
 local Image=Class(Widget,function(self)Widget._ctor(self,'Image')end)
 local TextButton=Class(Widget,function(self)Widget._ctor(self,'Button');self.text=Text('',20,'')end)
 function TextButton:IsNormalState()return not self.focus end
 function TextButton:IsFocusedState()return self.focus end
 ${colourMethods}
 local Screen=Class(Widget,function(self,name)Widget._ctor(self,name)end)
 local TextEdit=Class(Text,function(self,font,size,text)
   Text._ctor(self,font,size,text);self.editing=false
   self.idle_text_color={0,0,0,1};self.edit_text_color={0,0,0,1}
   self.inst={TextWidget={ShowEditCursor=function()end,SetEditCursorColour=function(_,...)self.cursor={...}end}}
 end)
 ${editMethods}
 local mx,my,mouseDown=0,0,false
 TheInput={EnableDebugToggle=function()end,IsMouseDown=function()return mouseDown end,
  GetScreenPosition=function()return{x=mx,y=my}end}
 TheFrontEnd={GetActiveScreen=function()return{name='HUD'}end}
 local screenw,screenh=1920,1080
 TheSim={GetScreenSize=function()return screenw,screenh end};MOUSEBUTTON_LEFT=1
 TITLEFONT='font';BODYTEXTFONT='font';ANCHOR_LEFT=1;ANCHOR_TOP=2
 package.preload['widgets/widget']=function()return Widget end
 package.preload['widgets/text']=function()return Text end
 package.preload['widgets/textedit']=function()return TextEdit end
 package.preload['widgets/textbutton']=function()return TextButton end
 package.preload['widgets/imagebutton']=function()return TextButton end
 package.preload['widgets/image']=function()return Image end
 package.preload['widgets/screen']=function()return Screen end
 package.preload.ai_speechhistory=function()${read('mod/scripts/ai_speechhistory.lua')}end
 package.preload['widgets/aistyle']=function()${read('mod/scripts/widgets/aistyle.lua')}end
 `;

test('input stays light when actual installed TextEdit enters and leaves editing',()=>run(`
 ${widgets}
 local Screen=(function()${read('mod/scripts/screens/aicompanionscreen.lua')}end)()
 local screen=Screen(function()end,{responses={}})
 screen.entry:SetEditing(true)
 assert(screen.entry.colour[1]>.9 and screen.entry.colour[2]>.9,'editing resets typed Chinese to black')
 screen.entry:SetEditing(false)
 assert(screen.entry.colour[1]>.9,'blur resets typed Chinese to black')
 assert(screen.entry.cursor and screen.entry.cursor[1]>.9,'cursor needs contrast too')
 `));

test('latest long speech is readable without preview truncation and scroll consumes only focused wheel',()=>run(`
 ${widgets}
 Widget.OnControl=function()return false end
 Widget.OnMouseButton=function()return false end
 CONTROL_SCROLLBACK=101;CONTROL_SCROLLFWD=102
 package.preload.ai_speechhistory=function()${read('mod/scripts/ai_speechhistory.lua')}end
 local History=(function()${read('mod/scripts/widgets/aicompanionhistory.lua')}end)()
 local panel=History();local text=string.rep('缺材料时先查看箱子再去采集。',20)..'这是真正的结尾'
 panel:Refresh({ready=true,owner='o',world='w',shard='1',responses={{id='long',text=text}}})
 assert(panel.selected=='long','latest speech must open in full, not a truncated list preview')
 local lines=panel.lines;assert(table.concat(lines,''):gsub('\\n','')==text,'all original characters must remain reachable')
 panel.focus=true;assert(panel:OnControl(CONTROL_SCROLLFWD,true));assert(panel.lineoffset==1)
 for i=1,#lines do panel:OnControl(CONTROL_SCROLLFWD,true)end
 assert(panel.detail:GetString():find('这是真正的结尾',1,true),'last line must be visible')
 panel.focus=false;local before=panel.lineoffset
 assert(not panel:OnControl(CONTROL_SCROLLBACK,true) and panel.lineoffset==before)
 assert(not panel.heading.ondown,'history must not compete with character movement by dragging')
 `));

test('actual HUD widget pages records, retains selection, collapses and clears across worlds',()=>run(`
 ${widgets}
 package.preload.ai_speechhistory=function()${read('mod/scripts/ai_speechhistory.lua')}end
 local History=(function()${read('mod/scripts/widgets/aicompanionhistory.lua')}end)()
 local panel=History()
 local snapshot={ready=true,owner='owner',world='world',shard='1',responses={}}
 for i=1,5 do snapshot.responses[i]={id=tostring(i),text=string.rep('中文',90),context={day=i,phase='day',topic='chat'}}end
 panel:Refresh(snapshot)
 assert(panel.shown and #panel.records==5)
 assert(panel.selected=='5')
 panel:Navigate(-1);panel:Navigate(-1)
 assert(panel.selected=='3' and panel.detail.shown)
 panel:ScrollLines(1);assert(panel.lineoffset==1)
 snapshot.responses[6]={id='6',text='新的发言'}
 panel:Refresh(snapshot);assert(panel.selected=='3' and panel.lineoffset==1)
 panel.toggle.onclick();assert(panel.collapsed and not panel.body.shown)
 panel:Refresh(snapshot);assert(panel.collapsed)
 panel.toggle.onclick();assert(panel.body.shown)
 panel:Navigate(-1);local first=panel.selected
 snapshot.responses[7]={id='7',text='又一句'}
 panel:Refresh(snapshot);assert(panel.selected==first,'new speech should not move an older page')
 snapshot.world='other';snapshot.responses={}
 panel:Refresh(snapshot);assert(not panel.shown and #panel.records==0)
 `));

test('speech history keeps full UTF-8 across pages and formats factual context',()=>run(`
 local H=(function()${read('mod/scripts/ai_speechhistory.lua')}end)()
 local text=string.rep('中文长消息',50)..'结尾'
 local pages=H.Pages(text)
 assert(#pages>1)
 assert(table.concat(pages,''):gsub('\\n','')==text)
 local label=H.ContextLabel({day=3,phase='dusk',topic='task_complete'})
 assert(label:find('第3天',1,true) and label:find('黄昏',1,true) and label:find('任务完成',1,true))
 assert(H.Limit('你好吗',2)=='你好')
 local records={};for i=1,25 do H.Push(records,{id=tostring(i),text='消息'..i})end
 assert(#records==20 and records[1].id=='6')
 H.Push(records,{id='model-failed',text='连接未完成',modelError=true})
 assert(H.Restore(records)[#records].modelError==true,'failure marker must survive history/save restoration')
 `));

test('HUD packets keep whole long messages and leave resource planning data on the server',()=>run(`
 local U=(function()${read('mod/scripts/ai_clientstatus.lua')}end)()
 local records={};for i=1,20 do records[i]={id=tostring(i),text=string.rep('完整消息',600)} end
 local s={ready=true,responses=records,projects={},resourceMemory={private_planning=true}}
 local function bytes(data)local n=12000;for _,r in ipairs(data.responses)do n=n+#r.text end;return string.rep('x',n)end
 local out=U.Pack(s,bytes)
 assert(#bytes(out)<=55000 and #out.responses<6)
 assert(out.responses[#out.responses].text==records[20].text,'retained text cannot be shortened to fit transport')
 assert(#records==20 and not out.resourceMemory,'server history and planner must not be modified')
 `));

const historySetup=`
 ${widgets}
 package.preload.ai_speechhistory=function()${read('mod/scripts/ai_speechhistory.lua')}end
 local History=(function()${read('mod/scripts/widgets/aicompanionhistory.lua')}end)()
 local function panelAt(scale)
  local root=Widget('bottomright');root.anchor={screenw,0};root.scale=scale or 1
  local panel=root:AddChild(History())
  panel:Refresh({ready=true,owner='owner',world='world',shard='1',time={phase='day'},responses={{id='1',text='中文消息用于查看',context={phase='day'}}}})
  panel:OnUpdate(.5)
  return panel,root
 end
 `;

test('history uses larger readable text and translucent contrasting day/night themes',()=>run(`
 ${historySetup}
 local brightness=.8
 TheWorld={state={isday=true,phase='day'},HasTag=function()return false end}
 ThePlayer={LightWatcher={GetLightValue=function()return brightness end}}
 local panel=panelAt()
 assert(panel.detail.size==26 and panel.context.size==20)
 assert(panel.detail.region[1]>=16*26 and panel.detail.region[2]>=6*26,'larger font still fits pagination')
 assert(panel.lighttheme and panel.detail.colour[1]<.15 and panel.bg.fill.tint[1]>.9)
 assert(panel.bg.fill.tint[4]==.72,'history fill must be translucent')
 local normalPanel=require('widgets/aistyle').Panel(400,300)
 assert(normalPanel.fill.tint[4]==.97,'shared F10 panel default must stay unchanged')
 TheWorld.state.isday=false;TheWorld.state.phase='night';brightness=.1
 panel.colourbutton.focus=true
 panel:OnUpdate(.5)
 assert(not panel.lighttheme and panel.detail.colour[1]>.9 and panel.bg.fill.tint[1]<.1)
 assert(panel.colourbutton.text.colour[1]>.9,'hover must use the current light text too')
 brightness=.5;panel:OnUpdate(.5);assert(not panel.lighttheme,'dim transition must not flicker')
 brightness=.8;panel:OnUpdate(.5);assert(panel.lighttheme,'bright fire/light can restore black text')
 brightness=.5;panel:OnUpdate(.5);assert(panel.lighttheme)
 brightness=.1;panel:OnUpdate(.5);assert(not panel.lighttheme)
 panel.colourbutton.onclick();assert(panel.colourmode=='black' and panel.lighttheme)
 panel.colourbutton.onclick();assert(panel.colourmode=='white' and not panel.lighttheme)
 panel.colourbutton.onclick();assert(panel.colourmode=='auto' and not panel.lighttheme)
 TheWorld.state.isday=true;panel:OnUpdate(.5);assert(panel.lighttheme)
 `));

test('fixed bottom-left history ignores pointer movement and survives scale changes',()=>run(`
 ${historySetup}
 local panel,root=panelAt(1.5)
 local p=panel:GetWorldPosition()
 assert(math.abs(p.x-300*1.5)<.01 and math.abs(p.y-295*1.5)<.01)
 assert(not panel.heading.ondown,'no drag interception')
 mx=1000;my=700;mouseDown=true;panel:OnUpdate(.5)
 assert(panel:GetWorldPosition().x==p.x)
 screenw=1280;screenh=720;root.anchor={screenw,0};panel:OnUpdate(.5)
 local q=panel:GetWorldPosition()
 assert(q.x<screenw/2 and q.y+223*1.5<=screenh)
 panel:Hide();assert(not panel.updating)
 `));

test('old position preferences cannot override bottom-left placement or newer theme choice',()=>run(`
 ${historySetup}
 local pending,lastSaved
 json={decode=function()return{x=-520,y=380,colour='white'}end,encode=function(data)lastSaved=data;return 'encoded'end}
 TheSim.GetPersistentString=function(_,key,cb)pending=cb end
 TheSim.SetPersistentString=function()end
 local panel=panelAt()
 pending(true,'valid');panel:OnUpdate(.5)
 assert(panel.colourmode=='white' and panel:GetWorldPosition().x==300)
 panel.colourbutton.onclick();pending(true,'valid');assert(panel.colourmode=='auto')
 local keys=0;for _ in pairs(lastSaved)do keys=keys+1 end
 assert(keys==1 and lastSaved.colour=='auto','only colour is persisted')
 `));
