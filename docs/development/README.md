# 可复用开发资料

这些文档来自两款游戏原型的脱敏开发经验，帮助继续适配其他游戏。历史原型中的QQ联动只是当时的架构记录；当前分享版已独立，不需要或读取QQ项目。

- [通用架构与制作流程](01-通用架构与制作流程.md)
- [星露谷与饥荒实现复盘](02-星露谷与饥荒实现复盘.md)
- [新游戏设计工作单](03-新游戏设计工作单.md)
- [测试部署与交接模板](04-测试部署与交接模板.md)

## 当前源码入口

`mod/modmain.lua`是游戏挂接和RPC；`mod/scripts/components/aicompanionmanager.lua`管理主人、快照和模型回执；`aicompanion.lua`执行动作；`ai_tasks.lua`保存目标与阶段。

`bridge/engine.mjs`负责调度，`schema.mjs`限制可执行计划，`model.mjs`调用安装者的Codex CLI，`diary.mjs`只管理本项目的本地日记。`tools/setup.mjs`生成自己的配置并安装模组。

`docs/testing-checklist.md`列出实际游玩验收。新的游戏接口、原生人物和成功证据需要重新适配；攻略文字不能生成尚不存在的执行能力。
