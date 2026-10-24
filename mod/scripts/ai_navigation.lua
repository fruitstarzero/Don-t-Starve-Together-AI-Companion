-- Route experience is local to the companion's saved world/shard.
local N={}
local function key(p)return string.format("%.0f/%.0f",p.x,p.z)end
local function distance(a,b)return(a.x-b.x)^2+(a.z-b.z)^2 end
function N.Failed(c,dest,reason)
    c.nav_memory=c.nav_memory or {}
    local k=key(dest);local old=c.nav_memory[k] or {attempts=0,tried={}}
    if old.attempts>=6 and GetTime()<(old.retryAt or 0) then return end
    if old.retryAt and GetTime()>=old.retryAt then old.attempts=0;old.tried={} end
    old.attempts=old.attempts+1;old.x=dest.x;old.z=dest.z;old.reason=reason
    local p=c.inst:GetPosition();old.from={x=p.x,z=p.z}
    old.day=TheWorld and TheWorld.state.cycles or 0;old.retryAt=GetTime()+60;old.waypoint=nil;old.traversing=false
    c.nav_memory[k]=old
    local list={};for id,v in pairs(c.nav_memory) do list[#list+1]={id=id,day=v.day or 0} end
    table.sort(list,function(a,b)return a.day<b.day or a.day==b.day and a.id<b.id end)
    for i=1,#list-64 do c.nav_memory[list[i].id]=nil end
end
function N.Waypoint(c,dest)
    local entry=c.nav_memory and c.nav_memory[key(dest)]
    if not entry then return dest end
    local p=c.inst:GetPosition()
    if entry.waypoint then
        if distance(p,entry.waypoint)>3*3 then return Vector3(entry.waypoint.x,0,entry.waypoint.z) end
        entry.waypoint=nil;entry.traversing=true;entry.from={x=p.x,z=p.z};return dest
    end
    if entry.traversing then return dest end
    if GetTime()>=entry.retryAt then entry.retryAt=GetTime()+60;entry.tried={};entry.attempts=0 end
    if entry.attempts>=6 and GetTime()<entry.retryAt then return nil end
    local dx,dz=dest.x-p.x,dest.z-p.z;local len=math.sqrt(dx*dx+dz*dz)
    if len<.1 then return dest end
    local safety=require("ai_safety");local here=safety.Risk(c,p)
    if safety.Risk(c,dest)>math.max(6,here+2) then return nil end
    local caps=c.inst.components and c.inst.components.locomotor and c.inst.components.locomotor.pathcaps
        or {ignorecreep=true,allowocean=false}
    for _,radius in ipairs({8,14,20}) do for _,side in ipairs({1,-1}) do
        local candidate=Vector3(p.x-dz/len*radius*side+dx/len*3,0,p.z+dx/len*radius*side+dz/len*3)
        local k=key(candidate)
        if not entry.tried[k] and TheWorld.Map:IsPassableAtPoint(candidate.x,0,candidate.z)
            and safety.Risk(c,candidate)<=math.max(3,here)
            and (not TheWorld.Pathfinder or TheWorld.Pathfinder:IsClear(p.x,0,p.z,candidate.x,0,candidate.z,caps)) then
            entry.tried[k]=true;entry.waypoint={x=candidate.x,z=candidate.z};return candidate
        end
    end end
    return nil
end
function N.Arrived(c,dest)
    if c.nav_memory then c.nav_memory[key(dest)]=nil end
end
function N.Load(c,records)
    c.nav_memory={}
    for k,v in pairs(records or {}) do
        if type(k)=="string" and type(v)=="table" and type(v.x)=="number" and type(v.z)=="number" then
            c.nav_memory[k]={x=v.x,z=v.z,from=v.from,attempts=math.min(6,tonumber(v.attempts) or 1),
                reason=v.reason,day=v.day,retryAt=GetTime()+10,tried={}}
        end
    end
end
return N
