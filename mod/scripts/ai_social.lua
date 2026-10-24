-- Pure policy: observes facts and proposes topics, never issues game actions.
local S={}
function S.New(now)
    return {started=now,lastspoken=now,nextidle=now+120,topics={},texts={},seen={},sequence=0}
end
local function ready(s,kind,urgent,now)
    return now-s.started>=15 and now-s.lastspoken>=(urgent and 20 or 45)
        and now-(s.topics[kind] or -10000)>=180
end
local function propose(s,kind,detail,urgent,now)
    if not ready(s,kind,urgent,now) then return end
    s.sequence=s.sequence+1
    s.candidate={id=tostring(s.started).."-"..s.sequence,kind=kind,detail=detail,
        urgent=urgent==true,at=now,expires=now+180}
    -- A silent answer does not cause another request every poll.
    s.topics[kind]=now
    return s.candidate
end
function S.Observe(s,f,now)
    if s.candidate and s.candidate.expires<=now then s.candidate=nil end
    if s.candidate and (s.candidate.kind=="health" and (f.health or 1)>=.3
        or s.candidate.kind=="danger" and not f.danger) then s.candidate=nil end
    if s.candidate and (s.candidate.kind=="obstacle" or s.candidate.kind=="need_help") then
        local p=f.problem
        if not p or now-(p.updated or 0)>15 or s.candidate.problemKey~=p.key then s.candidate=nil end
    end
    local kind,detail,urgent
    if (f.health or 1)<.3 then kind="health";detail="生命偏低，需要避险和治疗";urgent=true
    elseif f.danger then kind="danger";detail="附近出现正在攻击的威胁";urgent=true
    elseif (f.hunger or 1)<.22 then kind="hunger";detail="食物补给不足，需要先照顾生存";urgent=(f.hunger or 1)<.08
    elseif f.phase=="night" and s.phase~="night" then kind="night";detail="刚进入夜晚，注意照明" end
    if not kind and f.problem and now-(f.problem.updated or 0)<15 then
        kind=now-f.problem.since>=45 and "need_help" or "obstacle"
        detail={kind=f.problem.kind,context=f.problem.detail,since=f.problem.since}
    end
    s.phase=f.phase
    for _,e in ipairs(f.events or {}) do
        local id=e.id or (tostring(e.at)..":"..e.kind)
        if not s.seen[id] then
            s.seen[id]=true
            if now-(e.at or 0)<150 and not kind and (e.kind=="task_complete" or e.kind=="action_blocked") then
                kind=e.kind;detail=e.detail
            end
            if now-(e.at or 0)<150 and (e.kind=="task_started" or e.kind=="method_started" or e.kind=="task_stage") then
                s.pendingplan={kind="plan",detail=e.detail,at=e.at}
            end
        end
    end
    -- At most the event ring is retained, avoiding an unbounded session set.
    local seen={};for _,e in ipairs(f.events or {}) do
        local id=e.id or (tostring(e.at)..":"..e.kind);seen[id]=true
    end;s.seen=seen
    if kind and (not s.candidate or urgent and not s.candidate.urgent
        or kind=="need_help" and not s.candidate.urgent and s.candidate.kind~="need_help"
        or kind=="obstacle" and s.candidate.kind=="idle") then
        if s.candidate and s.candidate.kind==kind and urgent and not s.candidate.urgent then
            s.candidate.urgent=true;s.candidate.detail=detail
        else propose(s,kind,detail,urgent,now) end
        if s.candidate and (kind=="obstacle" or kind=="need_help") and f.problem then
            s.candidate.problemKey=f.problem.key
        end
    end
    if not s.candidate and f.near and f.safe and now>=s.nextidle then
        propose(s,"idle","在主人身边，可以自然说一两句，也可以沉默",false,now)
        s.nextidle=now+120
    end
    if not s.candidate and f.near and f.safe and s.pendingplan and now-(s.pendingplan.at or 0)<180 then
        if propose(s,"plan",s.pendingplan.detail,false,now) then s.pendingplan=nil end
    end
    local c=s.candidate
    return {candidate=c,nearOwner=f.near==true,
        canSpeak=c~=nil and (c.urgent or c.kind=="need_help" or f.near and f.safe)
            and now-s.lastspoken>=(c.urgent and 20 or 45)}
end
function S.Record(s,text,now,kind)
    s.lastspoken=now;s.nextidle=now+120;s.texts[text]=now
    if kind then s.topics[kind]=now end
    s.candidate=nil
    for value,at in pairs(s.texts) do if now-at>600 then s.texts[value]=nil end end
end
function S.Accept(s,id,text,now)
    local c=s.candidate
    if not c or c.id~=id or c.expires<=now or text==""
        or now-s.lastspoken<(c.urgent and 20 or 45)
        or now-(s.texts[text] or -10000)<600 then return false end
    S.Record(s,text,now,c.kind);return true
end
return S
