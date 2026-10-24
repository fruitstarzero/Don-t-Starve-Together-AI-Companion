name = "AI 温蒂共玩"
description = "原版温蒂玩家实体、真实生存与动作；F10／伙伴按钮远程聊天和控制。需启动本机 AI 服务。"
author = "Local companion"
version = "0.8.0"
api_version = 10
dst_compatible = true
client_only_mod = false
all_clients_require_mod = true
server_filter_tags = { "AI companion" }
configuration_options = {
    { name = "hotkey", label = "伙伴窗口按键", options = {
        {description = "F10", data = 291}, {description = "F9", data = 290}, {description = "F8", data = 289}
    }, default = 291 },
    { name = "autospawn", label = "房主入场后自动加入", options = {
        {description = "是", data = true}, {description = "否，点击加入伙伴", data = false}
    }, default = true },
    { name = "selftest", label = "开发测试（正常游玩请关闭）", options = {
        {description = "关闭", data = false}, {description = "隔离测试世界", data = true},
        {description = "隔离测试（不调用模型）", data = "local"},
        {description = "基地专项隔离测试", data = "reliability"}
    }, default = false },
}
