-- Keep full speech records within a bounded HUD RPC. Planning data stays local.
local U={}
function U.Pack(s,encode)
    if not s.ready then return s end
    local out={ready=true,owner=s.owner,world=s.world,shard=s.shard,session=s.session,mode=s.mode,
        time=s.time,status=s.status,bridge=s.bridge,companion=s.companion,abigail=s.abigail,
        taskJournal=s.taskJournal,goalBoard=s.goalBoard,actionState=s.actionState,projects={},responses={}}
    for i=math.max(1,#(s.responses or {})-5),#(s.responses or {}) do out.responses[#out.responses+1]=s.responses[i] end
    for i=1,math.min(3,#(s.projects or {})) do out.projects[i]=s.projects[i] end
    local stock=s.baseResources or {}
    out.baseResources={items={},observedBoxes=stock.observedBoxes,locationCounts={}}
    for i=1,math.min(60,#(stock.items or {})) do
        local item=stock.items[i];out.baseResources.items[i]=item
        out.baseResources.locationCounts[item.prefab]=#(stock.locations and stock.locations[item.prefab] or {})
    end
    -- Drop oldest whole records, never ellipsize the text of the retained ones.
    while #out.responses>1 and #encode(out)>55000 do table.remove(out.responses,1) end
    return out
end
return U
