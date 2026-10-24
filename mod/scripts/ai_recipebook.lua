local B={}
local essentials={researchlab=true,researchlab2=true,cookpot=true,icebox=true,firepit=true,torch=true,
    heatrock=true,winterhat=true,armorwood=true,footballhat=true,spear=true,backpack=true,
    panflute=true,eyebrellahat=true,birdcage=true,shovel=true,axe=true,pickaxe=true,
    rope=true,boards=true,cutstone=true,transistor=true,treasurechest=true}
function B.ForConversation(c,chats)
    local wanted={};for name in pairs(essentials) do wanted[name]=true end
    if c.plan and c.plan.recipe then wanted[c.plan.recipe]=true end
    local function dependencies(id,trail,depth)
        if depth>6 or trail[id] then return end
        local recipe=AllRecipes[id];if not recipe then return end
        trail[id]=true
        for _,ing in ipairs(recipe.ingredients or {}) do
            local sub=require("ai_procurement").RecipeFor(ing.type)
            if sub then wanted[sub.name]=true;dependencies(sub.name,trail,depth+1) end
        end
    end
    if c.plan and c.plan.recipe then dependencies(c.plan.recipe,{},0) end
    local text="";for _,m in ipairs(chats or {}) do text=text..m.text end
    if text~="" then
        for id,recipe in pairs(AllRecipes) do
            local name=STRINGS.NAMES[string.upper(recipe.product or id)]
            if name and text:find(name,1,true) or text:find(id,1,true) then wanted[id]=true end
        end
    end
    local out={};local builder=c.inst.components.builder
    local ids={};for id in pairs(wanted) do ids[#ids+1]=id end;table.sort(ids)
    if c.plan and c.plan.recipe then table.insert(ids,1,c.plan.recipe) end
    local included={}
    for _,id in ipairs(ids) do
        local recipe=AllRecipes[id]
        if recipe and not included[id] then
            included[id]=true
            local level=recipe.level or {};local ordinary=(level.SCIENCE or 0)<=2
            for kind,n in pairs(level) do if kind~="SCIENCE" and n>0 then ordinary=false end end
            local ingredients={}
            for _,i in ipairs(recipe.ingredients) do ingredients[#ingredients+1]={prefab=i.type,
                name=STRINGS.NAMES[string.upper(i.type)] or i.type,count=i.amount} end
            out[#out+1]={id=id,name=STRINGS.NAMES[string.upper(recipe.product or id)] or id,
                ingredients=ingredients,tech=recipe.level,known=builder:KnowsRecipe(recipe),
                canLearn=builder:CanLearn(id),canPrepare=ordinary and builder:CanLearn(id),
                canMakeNow=builder:HasIngredients(recipe) and (builder:KnowsRecipe(recipe)
                    or CanPrototypeRecipe(recipe.level,builder.accessible_tech_trees))}
        end
        if #out>=40 then break end
    end
    return out
end
return B
