-- =========================================================
-- ComboTrials_Hotkeys.lua - Action registration for combo trials.
-- Hotkeys are disabled and unbound by default; Training_Hotkeys owns UI/bindings.
-- =========================================================

local M = {}
local RuntimeSafety = require("func/RuntimeSafety")

local function can_use_combo_trials()
    if not RuntimeSafety.is_training_allowed() then return false end
    if _G.CurrentTrainerMode ~= 4 then return false end
    if _G._ct_bar_collapsed then return false end
    return true
end

function M.init(ctx, Hotkeys)
    if not Hotkeys or not Hotkeys.register_scope then return false end
    local commands = ctx.commands or {}

    Hotkeys.register_scope("combo_trials", {
        title = "连段训练",
        order = 20,
        enabled_default = false,
        actions = {
            { id = "record_p1", label = "录制 P1", enabled = can_use_combo_trials, run = commands.record_p1 },
            { id = "record_p2", label = "录制 P2", enabled = can_use_combo_trials, run = commands.record_p2 },
            { id = "save_recording", label = "停止并保存录制", enabled = can_use_combo_trials, run = commands.save_recording },
            { id = "cancel_recording", label = "取消录制", enabled = can_use_combo_trials, run = commands.cancel_recording },
            { id = "start_trial", label = "开始连段训练", enabled = can_use_combo_trials, run = commands.start_trial },
            { id = "reset_trial", label = "重置连段", enabled = can_use_combo_trials, run = commands.reset_trial },
            { id = "stop_trial", label = "停止连段训练", enabled = can_use_combo_trials, run = commands.stop_trial },
            { id = "start_demo", label = "自动演示连段", enabled = can_use_combo_trials, run = commands.start_demo },
            { id = "restart_demo", label = "重播演示", enabled = can_use_combo_trials, run = commands.restart_demo },
            { id = "quit_demo", label = "退出演示", enabled = can_use_combo_trials, run = commands.quit_demo },
            { id = "switch_position", label = "切换位置模式", enabled = can_use_combo_trials, run = commands.switch_position },
            { id = "open_combo_dropdown", label = "打开连段文件列表", enabled = can_use_combo_trials, run = commands.open_combo_dropdown },
        },
    })
    return true
end

return M
