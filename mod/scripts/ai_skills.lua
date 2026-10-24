local S={}
local defs=require("prefabs/skilltree_defs").SKILLTREE_DEFS.wendy
function S.Start(c)
    local updater=c.inst.components.skilltreeupdater
    if not updater then return end
    local xp=c.saved_skillxp
    if xp then
        updater.skilltree:AddSkillXP(xp,"wendy")
        local remaining={}
        for name in pairs(c.saved_skills or {}) do remaining[name]=true end
        for _=1,32 do
            local changed=false
            for name in pairs(remaining) do
                updater:ActivateSkill(name,nil,true)
                if updater:IsActivated(name) then remaining[name]=nil;changed=true end
            end
            if not changed then break end
        end
        updater.skilltreeblob=nil
        c.saved_skillxp=nil;c.saved_skills=nil
    end
    -- Keep the original one-XP-per-survived-day timer, without attempting to
    -- send client account RPCs to the virtual player's empty network userid.
    c.inst.components.experiencecollector.UpdateXp=function()
        if not c.inst:HasTag("playerghost") then updater:AddSkillXP(1,nil,true) end
    end
end
function S.Options(inst)
    local u=inst.components.skilltreeupdater
    local out={}
    if not u or u:GetAvailableSkillPoints()<=0 then return out end
    for name,d in pairs(defs or {}) do
        if d.rpc_id and not u:IsActivated(name) and not name:find("shadow") and not name:find("lunar") then
            out[#out+1]={id=name,title=d.title,description=type(d.desc)=="string" and d.desc or name}
        end
    end
    return out
end
function S.Learn(inst,name)
    if type(name)~="string" then return false end
    for _,option in ipairs(S.Options(inst)) do
        if option.id==name then
            inst.components.skilltreeupdater:ActivateSkill(name,nil,true)
            return inst.components.skilltreeupdater:IsActivated(name)
        end
    end
    return false
end
return S
