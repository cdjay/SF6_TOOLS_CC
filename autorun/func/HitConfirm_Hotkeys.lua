-- =========================================================
-- HitConfirm_Hotkeys.lua - Action registration for hit confirm training.
-- =========================================================

local M = {}
local RuntimeSafety = require("func/RuntimeSafety")

local function can_use_hit_confirm()
    return RuntimeSafety.is_training_allowed() and _G.CurrentTrainerMode == 2
end

function M.init(commands, Hotkeys)
    if not Hotkeys or not Hotkeys.register_scope then return false end
    commands = commands or {}

    Hotkeys.register_scope("hit_confirm", {
        title = "确认训练",
        order = 10,
        enabled_default = false,
        actions = {
            { id = "decrease_amount", label = "减少本次训练量", enabled = can_use_hit_confirm, run = commands.decrease_amount },
            { id = "increase_amount", label = "增加本次训练量", enabled = can_use_hit_confirm, run = commands.increase_amount },
            { id = "reset_or_stop", label = "重置 / 停止训练", enabled = can_use_hit_confirm, run = commands.reset_or_stop },
            { id = "start_or_pause", label = "开始 / 暂停训练", enabled = can_use_hit_confirm, run = commands.start_or_pause },
        },
    })
    return true
end

return M
