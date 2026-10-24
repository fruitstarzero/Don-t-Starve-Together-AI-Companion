local S={}
local controlled={campfire=true,firepit=true,coldfire=true,coldfirepit=true}
function S.Hostile(c,e)
    if e==c.inst or not e:IsValid() or e:HasTag("player") or e:HasTag("companion") then return false end
    local combat=e.components.combat
    if not combat or e.components.health and e.components.health:IsDead() then return false end
    local owner=c:Owner()
    return combat.target==c.inst or owner and combat.target==owner or e:HasTag("hostile") or e:HasTag("epic")
end
function S.Risk(c,pos,entities)
    local score=0
    for _,e in ipairs(entities or c:Scan(28)) do
        local d=e:GetDistanceSqToPoint(pos)
        if S.Hostile(c,e) then
            local radius=e:HasTag("epic") and 14 or 7
            if d<radius*radius then score=score+(radius-math.sqrt(d))*(e:HasTag("epic") and 4 or 2) end
        elseif not controlled[e.prefab] and e.components.burnable and e.components.burnable:IsBurning() and d<6*6 then
            score=score+(6-math.sqrt(d))*5
        end
    end
    return score
end
function S.RetreatPoint(c,threat)
    local p=c.inst:GetPosition();local seen=c:Scan(28)
    local best,score=nil,-math.huge
    for radius=6,10,4 do for i=1,16 do
        local pt=p+Vector3(math.cos(i*PI/8)*radius,0,math.sin(i*PI/8)*radius)
        if TheWorld.Map:IsPassableAtPoint(pt.x,0,pt.z) then
            local away=threat and math.sqrt(threat:GetDistanceSqToPoint(pt)) or 0
            local value=away-3*S.Risk(c,pt,seen)
            if c.home then value=value-.01*c.inst:GetDistanceSqToPoint(c.home) end
            if value>score then best=pt;score=value end
        end
    end end
    return best
end
function S.RetreatNeeded(c,enemy,armed,armored)
    if enemy:HasTag("epic") then return true end -- boss-specific mechanics are not adapted yet
    local n=0
    for _,e in ipairs(c:Scan(10)) do if S.Hostile(c,e) then n=n+1 end end
    local hp=c.inst.components.health:GetPercent()
    return hp<.4 or n>=3 and (not armored or hp<.7) or n>=2 and not armed
end
function S.Route(c,pos)
    local p=c.inst:GetPosition();local seen=c:Scan(28)
    local here=S.Risk(c,p,seen);local there=S.Risk(c,pos,seen)
    if there>math.max(6,here+2) then return nil end
    -- Check the known corridor. Choose a nearby safe waypoint if the straight
    -- route crosses danger; vanilla pathfinding still handles actual obstacles.
    local d=pos-p
    if d:LengthSq()>18*18 then d=d:GetNormalized()*18 end
    local risk=0
    for _,t in ipairs({.33,.66,1}) do risk=math.max(risk,S.Risk(c,p+d*t,seen)) end
    if risk<=math.max(6,here) then return pos end
    local best,score
    for i=1,12 do
        local pt=p+Vector3(math.cos(i*PI/6)*8,0,math.sin(i*PI/6)*8)
        if TheWorld.Map:IsPassableAtPoint(pt.x,0,pt.z) then
            local value=S.Risk(c,pt,seen)*15+(pt-pos):LengthSq()*.02
            if not score or value<score then best=pt;score=value end
        end
    end
    if best and S.Risk(c,best,seen)<risk then return best end
    return nil
end
return S
