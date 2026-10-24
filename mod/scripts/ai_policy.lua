-- Engine-independent rules: plans and memories are suggestions, survival is a constraint.
local P = {}
P.activities = require("ai_actions").activities
P.commands = { spawn=true, come=true, follow=true, auto=true, stay=true, home=true,
    retreat=true,teleport=true, sethome=true, abigail_summon=true, abigail_recall=true,resume=true,cancel=true }

function P.ValidPlan(plan)
    return type(plan) == "table" and P.activities[plan.activity] == true
        and type(plan.reason) == "string" and #plan.reason <= 1200
        and (plan.prefab == nil or type(plan.prefab) == "string" and #plan.prefab <= 80)
        and (plan.count == nil or type(plan.count) == "number" and plan.count >= 1 and plan.count <= 500)
        and (plan.activity~="visit" or type(plan.placeId)=="string" and #plan.placeId<=48)
end

function P.ValidWorkflow(workflow)
    if type(workflow)~="table" or type(workflow.goal)~="string" or #workflow.goal==0 or #workflow.goal>1200
        or type(workflow.steps)~="table" or #workflow.steps<1 or #workflow.steps>6 then return false end
    local finite={collect=true,craft=true,transplant=true,visit=true,store=true}
    for _,step in ipairs(workflow.steps) do
        if not P.ValidPlan(step) or not finite[step.activity] then return false end
        if (step.activity=="collect" or step.activity=="craft" or step.activity=="transplant")
            and (type(step.count)~="number" or step.count%1~=0) then return false end
    end
    return true
end

function P.Category(item)
    if item.food then return "food" end
    if item.seed then return "seed" end
    if item.gear then return "gear" end
    if item.prefab == "log" or item.prefab == "boards" or item.prefab == "livinglog" then return "wood" end
    if item.prefab == "rocks" or item.prefab == "flint" or item.prefab == "goldnugget"
        or item.prefab == "nitre" or item.prefab == "cutstone" then return "mineral" end
    if item.prefab == "cutgrass" or item.prefab == "twigs" or item.prefab == "rope" then return "plant" end
    return "other"
end

-- Keep equipment, special personal items, enough calories for the planned trip,
-- emergency lighting ingredients, and the current recipe/task's ingredients.
-- No learned habit can override these constraints.
function P.KeepCounts(items, needs)
    local keep, calories = {}, needs.calories or 0
    local required = needs.materials or {}
    for _, item in ipairs(items) do
        local n = 0
        if item.gear or item.personal or item.equipped then n = item.count
        elseif item.food and item.calories > 0 and calories > 0 then
            n = math.min(item.count, math.ceil(calories / item.calories))
            calories = math.max(0, calories - n * item.calories)
        end
        local wanted = required[item.prefab] or 0
        if wanted > 0 then
            n = math.max(n, math.min(item.count, wanted))
            required[item.prefab] = math.max(0, wanted - n)
        end
        keep[item.id] = n
    end
    return keep
end

function P.ChestScore(item, chest)
    if not chest.available or chest.room <= 0 then return -1000 end
    if chest.ice and not item.food then return -1000 end
    local score = chest.ice and item.food and 5 or 0
    if chest.prefabs[item.prefab] then score = score + 12 end
    if chest.category == P.Category(item) then score = score + 4 end
    if chest.empty then score = score + 1 end
    return score
end

function P.CanApply(result, session, revision, mode, now)
    return type(result) == "table" and result.session == session and result.revision == revision
        and type(result.expires) == "number" and result.expires >= now
        and (result.source == "chat" or result.source=="social" and not result.plan and not result.workflow and not result.command and not result.learnSkill
            or result.source=="autonomy" and mode == "auto")
end
return P
