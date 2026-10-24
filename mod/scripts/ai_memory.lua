local M={}
function M.IsHomeDeclaration(text)
    -- Exact affirmative declarations only; longer natural language goes to the
    -- model with the original speaker anchor, never a substring keyword trigger.
    text=text:gsub("%s+","")
    for _,p in ipairs({"，","。","！",",","!"}) do text=text:gsub(p,"") end
    local phrases={ ["家在这里"]=true,["我们的家在这里"]=true,["这里是家"]=true,
        ["这里就是家"]=true,["这里是我们的家"]=true,["记住这里是我们的家"]=true,
        ["记住家在这里"]=true,["记住这里是家"]=true,["基地在这里"]=true,
        ["这里是基地"]=true,["这里就是基地"]=true,["把这里设为基地"]=true,
        ["以后这里就是家"]=true }
    return phrases[text]==true
end
function M.SetHome(c,pos,evidence)
    if not pos or type(pos.x)~="number" or type(pos.z)~="number" then return false end
    c.home=Vector3(pos.x,0,pos.z)
    c.home_memory={id="home",kind="place",text="家／基地",evidence=evidence or "主人设置基地",
        position={x=pos.x,z=pos.z,shard=TheShard:GetShardId()}}
    c.landmarks=c.landmarks or {};c.landmarks.home=c.home_memory
    c.status="已记下基地位置"
    c:Event("home_set",c.home_memory)
    return true
end
function M.ApplyPlaces(c,updates)
    c.landmarks=c.landmarks or {}
    for _,m in ipairs(updates or {}) do
        if type(m.id)=="string" and #m.id<=48 then
            if m.operation=="remove" then
                c.landmarks[m.id]=nil
                if m.id=="home" then c.home_memory=nil;c.home=nil end
            elseif m.position and m.position.shard==TheShard:GetShardId()
                and type(m.position.x)=="number" and type(m.position.z)=="number" then
                if m.id=="home" then M.SetHome(c,m.position,m.evidence)
                else c.landmarks[m.id]=m end
            end
        end
    end
end
return M
