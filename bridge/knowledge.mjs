// Checked against installed mod source. Descriptions are data, never instructions.
const mods={
 '3223103565':{name:'自动整理箱子',support:'standard',guide:'打开已适配的箱子时触发该模组 onopenfn；存取仍走原版容器规则。AI sort 负责箱间分类，开箱整理负责箱内排序。'},
 '2999581232':{name:'自动堆叠',support:'passive',guide:'世界被动堆叠，按实际物品堆叠上限／数量存取；不自行假设无限堆叠。'},
 '727774324':{name:'Craft Pot',support:'standard',guide:'UI 提示不等于材料。AI 根据当前 cooking 注册食谱评估四格锅料，实际装锅烹饪取餐。'},
 '375850593':{name:'Extra Equip Slots',support:'standard',guide:'从实际 inventory.equipslots 识别装备，不假设所有装备只占原版三个槽。'},
 '3436020204':{name:'Show Me Refresh',support:'display',guide:'显示辅助；生存判断使用原版组件的实际数值，不能把鼠标提示当作新增操作。'},
 '1172839635':{name:'Better Ice Box',support:'standard',guide:'冰箱使用已安装模组修改后的实际容量、保鲜和容器验收规则；不假设默认容量。'},
 '462372013':{name:'Always fresh',support:'passive',guide:'按实际 perishable 组件观察保鲜状态，不根据模组名字声称食物永远不会腐败。'},
 '2119742489':{name:'木牌传送 GUI',support:'limited',guide:'该版本依赖 travelable 目的地列表、权限、消耗和客户端界面。当前没有完成无客户端 AI 的传送适配，只能解释及记地点，不能声称已传送。'},
 '1392778117':{name:'棱镜',support:'partial',guide:'只有注册到当前配方及标准 pickable/workable/edible/tool 等组件的能力可按已有执行器使用；专属祭坛、技能、UI 和动作须逐项适配。'},
};
export function gameKnowledge(snapshot){
 return {materialMethods:{
   log:'树木→斧头砍伐→捡原木；木板需要按实际配方加工原木。',
   minerals:'金块优先带金纹矿rock2；普通矿rock1有石头/燧石/硝石；冰矿只有冰，不能用来补金块或燧石。缺镐时先找地面散落燧石与树枝。',
   plants:'草丛产草、树苗产树枝、浆果丛产浆果、芦苇产芦苇；按实际pickable组件，不拿地形猜测当已经找到。沼泽仍先避开可见威胁。',
   refinements:'绳索、木板、石砖、电子元件等从真实配方递归拆料，先核对箱中成品；科技不足先找已记的合适设施，必要时按真实成本建设科学机器/炼金引擎。',
   limits:'木炭与蜘蛛丝当前可从箱子、地面或已观察的标准可采集来源取用；还未适配安全烧林制炭和主动刷巢，不为缺料自动放火或冒充已完成。',
   evidence:'resourceMemory是实际近处见过的节点；terrainMemory是实际经过的地形。远处记录只是线索，到达后须重新观察；不全图透视。'
 },execution:{
   finiteSteps:['collect: 指定目标数，核对背包加本轮实际入库','craft: 指定制作数，原版 builditem/buildstructure 回执',
     'transplant: 指定目标株数，重新观察目标区','visit: 已记同分片地点，核对实际到达','store: 留生存物资后无余货、无待回收暂存物资'],
   continuous:['farm','fish','cook','explore','rest','sort'],
   recovery:'游戏存档保存目标与阶段；生存中断不改任务，主人暂停等 resume/auto，cancel 不复活。',
   unsupported:['跨分片洞穴迁移','海上专项','Boss 专项策略','骑牛','未知模组 GUI/RPC'],
   preconditions:'实际工具、材料、科技、位置、容量和原版动作成功；缺条件进入问题状态，不以攻略文字冒充执行。'
 },workflows:[
  '生存：检查照明、生命、饥饿、理智和气温；实际准备工具食物，风险时先撤退。',
  '制作：使用可见配方与实际科技；缺材料先取箱或采集，等真实成功再记为完成。',
  '长期基地：projects 保存实际种植区与照料目标；自主空闲时回访收割、补种和照料，手动跟随/待命优先。transplant 只适配普通草、树苗、浆果丛。',
  '箱子索引：baseResources.locations 区分当前可核对与旧记录，同类物品优先同类箱；按缺额拆堆，平时留下样品。无容量时先补一只普通箱，再检查是否足够。',
  '农务：耕地、取种播种、浇水、照料、施肥；没有专用道具不能假称操作完成。',
  '做饭：按当前注册食谱评估锅料、装锅、烹饪、等待、取餐，不使用他人半锅材料。',
  '仓储：按现有分类存余货，留足出行物资；开箱和放入可触发已安装模组的原版组件钩子。',
  '学习：owner_action_success 与 action_success 是已完成证据；action_failed 说明需要调整。附近的示范可归纳为带适用条件的 procedure，不能生成可执行脚本。',
 ],communityTips:[
  '推进不是固定任务链。先照明、食物与基础防具，再按当前季节、现有科技补下一步；冬前补保暖和热暖石，准备充分再探索洞穴和首领。',
  '优先复用已有基地设施与箱中成品；缺什么才制作什么，不囤一堆相同工具。旧库存不是远程实时库存，取用前重新检查。',
  '炼金引擎是二级科学。原版二本用4木板、2石砖、2电子元件；当前实际配方以 recipeDetails 为准。不要自动拆一本或建筑。',
  '暖石需要加热，不是永久热源；做暖石可优先消耗快坏的普通镐。衣服只保温，寒冷时仍需补热。',
  '原版安全肉丸例子：1怪物肉+3浆果，或1怪物肉+3冰。不是任意肉+任意三填料；树枝不做肉丸，2怪物值可能变怪物千层饼，半肉加多冰可能变炖兔子。',
  '曼德拉草早期稀少，普通采摘不自然回长；克劳斯战利品存在随机补给。优先为排箫等用途留储备，不当普通填料或零食，不为刷资源放火。',
  '阿比盖尔平时防御安抚，确有近处战斗再按血量和风险激怒，低血或撤退考虑收回；召唤/收回仍有原版成本和动作。',
 ],sources:'已读取的 wiki.gg、Steam 社区与本机756039源码，证据见 docs/community-research.md。社区路线是经验，不是强制规则；模组实际配方优先。',
 mods:(snapshot.enabledMods||[]).slice(0,60).map(m=>({id:m.id,name:m.name,
    ...(mods[m.id.replace('workshop-','')]||{support:'unknown',guide:'未适配专属操作；只使用实际报告的标准组件与配方，不因看到名字就自称会用。'})}))};
}
