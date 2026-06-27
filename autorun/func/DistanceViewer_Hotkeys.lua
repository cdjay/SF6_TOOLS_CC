-- =========================================================
-- DistanceViewer_Hotkeys.lua - Action registration for distance viewer.
-- =========================================================

local M = {}
local RuntimeSafety = require("func/RuntimeSafety")

local function can_use_distance_viewer()
    return RuntimeSafety.is_training_allowed() and _G.SF6_DistanceViewer_Enabled == true
end

function M.init(commands, Hotkeys)
    if not Hotkeys or not Hotkeys.register_scope then return false end
    commands = commands or {}

    Hotkeys.register_scope("distance_viewer", {
        title = "距离查看器",
        order = 30,
        enabled_default = false,
        actions = {
            { id = "cycle_p1", label = "切换 P1 显示", enabled = can_use_distance_viewer, run = commands.cycle_p1 },
            { id = "cycle_p2", label = "切换 P2 显示", enabled = can_use_distance_viewer, run = commands.cycle_p2 },
            { id = "toggle_window", label = "显示 / 隐藏设置窗口", enabled = can_use_distance_viewer, run = commands.toggle_window },
        },
    })
    return true
end

return M
