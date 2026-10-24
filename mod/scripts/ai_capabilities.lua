local C={}
function C.Mods()
    local out={}
    if not KnownModIndex then return out end
    for _,id in ipairs(KnownModIndex:GetModsToLoad()) do
        local info=KnownModIndex:GetModInfo(id)
        out[#out+1]={id=id,name=info and tostring(info.name):sub(1,160) or id,
            version=info and tostring(info.version):sub(1,40) or ""}
        if #out>=60 then break end
    end
    return out
end
function C.Entity(inst)
    local c=inst.components
    return {pick=c.pickable~=nil,work=c.workable and c.workable:GetWorkAction().id or nil,
        cook=c.stewer~=nil,farm=c.farmplanttendable~=nil,container=c.container~=nil,
        teleport=c.travelable~=nil,customTeleportSupported=false}
end
return C
