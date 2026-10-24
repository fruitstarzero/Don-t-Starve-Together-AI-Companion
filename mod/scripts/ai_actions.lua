-- The plan validator and model both consume this executor-owned capability catalog.
local A={}
local definitions={
    auto={"本地生存优先、可达地表","按实际需求持续生活","持续活动，无单一完成回执"},
    collect={"可拾取/采摘/砍伐/采矿的来源、对应工具和背包空间","背包及本次已入库达到目标数","实际取得/转移物品及库存计数"},
    craft={"当前注册配方、角色可学、实际科技/材料/空间","递归补料并制作目标成品","原版builditem/buildstructure；接单不算完成"},
    store={"同分片已知基地与允许存取的箱子","保留所需物资，将余货存入箱子","实际转移回执且无未回收暂存物资"},
    sort={"原版容器与现有分类；不碰正在被别人打开的箱子","按同类箱分类","实际取放，持续活动"},
    farm={"已观察耕地/作物、相应工具/种子/肥料","播种、收割、照料和浇水","原版动作及作物状态；持续活动"},
    transplant={"普通草/树苗/浆果丛、铲子与可种空位","带回已记区域种下","目标区实际株数"},
    fish={"地表池塘、普通鱼竿及背包空间","原版池塘抛竿与收竿","实际渔获；未适配海钓"},
    cook={"当前锅食谱、可用普通食材、锅或可烤制条件","真实装锅/烤制/取餐","原版动作与实际产物；持续活动"},
    explore={"本分片地表可通行且生存条件允许","局部探索并积累资源与地形线索","实际观察；持续活动"},
    rest={"已知基地或当前安全位置","回去休整并处理生存","持续活动"},
    visit={"本分片已记真实地点","前往指定地点","核对实际到达距离"},
}
A.activities={}
for id in pairs(definitions) do A.activities[id]=true end
function A.Snapshot()
    local out={version=1,activities={},unsupported={"海钓","跨洞穴/分片迁移","专属Boss策略","主动烧林制炭",
        "主动刷蜘蛛巢","未知模组GUI/RPC","从文字记忆生成任意Lua"}}
    for id,d in pairs(definitions) do out.activities[id]={supported=true,requires=d[1],effect=d[2],evidence=d[3]} end
    return out
end
return A
