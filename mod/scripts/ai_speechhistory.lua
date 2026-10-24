-- Shared pure formatting/storage rules. UTF-8 must never be cut by byte count.
local H={}
local function chars(text)
    local out={}
    for c in (text or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do out[#out+1]=c end
    return out
end
function H.Limit(text,count)
    local list=chars(text);local out={}
    for i=1,math.min(count,#list) do out[i]=list[i] end
    return table.concat(out)
end
function H.Pages(text)
    -- Six lines of at most sixteen wide glyphs fit the HUD detail region
    -- (436px at 26px), leaving room for context and navigation.
    local pages,lines,line={}, {}, {}
    local function flushline() lines[#lines+1]=table.concat(line);line={} end
    local function flushpage() pages[#pages+1]=table.concat(lines,"\n");lines={} end
    for _,c in ipairs(chars((text or ""):gsub("\r",""):gsub("\t","    "))) do
        if c=="\n" then flushline()
        else
            if #line>=16 then flushline() end
            if #lines>=6 then flushpage() end
            line[#line+1]=c
        end
        if #lines>=6 then flushpage() end
    end
    if #line>0 then flushline() end
    if #lines>0 then flushpage() end
    if #pages==0 then pages[1]="" end
    return pages
end
function H.Lines(text,width)
    local lines,line={},{}
    local function flush()lines[#lines+1]=table.concat(line);line={}end
    for _,c in ipairs(chars((text or ""):gsub("\r",""):gsub("\t","    "))) do
        if c=="\n" then flush()
        else
            if #line>=(width or 14) then flush() end
            line[#line+1]=c
        end
    end
    if #line>0 then flush() end
    if #lines==0 then lines[1]="" end
    return lines
end
local topics={health="生命偏低",danger="遇到危险",hunger="需要补给",night="进入夜晚",
    task_complete="任务完成",action_blocked="行动受阻",obstacle="遇到麻烦",need_help="需要你帮忙",
    idle="在你身边",plan="接下来的打算",chat="回应你的话",command="快捷指令"}
local phases={day="白天",dusk="黄昏",night="夜晚"}
function H.ContextLabel(context)
    context=context or {}
    local day=type(context.day)=="number" and "第"..math.floor(context.day).."天 · " or ""
    local phase=phases[context.phase]
    return day..(phase and phase.." · " or "")..(topics[context.topic] or "交流")
end
function H.Push(list,record)
    if type(record)~="table" or type(record.id)~="string" or #record.id>160
        or type(record.text)~="string" or record.text=="" then return false end
    for _,old in ipairs(list) do if old.id==record.id then return false end end
    list[#list+1]={id=record.id,text=H.Limit(record.text,2400),source=record.source,at=record.at,modelError=record.modelError==true,
        remoteId=record.remoteId,userText=record.userText,actionAccepted=record.actionAccepted,
        context=type(record.context)=="table" and {day=record.context.day,phase=record.context.phase,topic=record.context.topic} or nil}
    while #list>20 do table.remove(list,1) end
    return true
end
function H.Restore(records)
    local list={}
    for _,r in ipairs(type(records)=="table" and records or {}) do H.Push(list,r) end
    return list
end
return H
