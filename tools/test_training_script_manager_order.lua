local file = assert(io.open("autorun/Training_ScriptManager.lua", "r"))
local source = file:read("*a")
file:close()

local function ordered_positions(patterns, label)
    local previous = 0
    for _, pattern in ipairs(patterns) do
        local position = assert(source:find(pattern, previous + 1, true),
            label .. " missing: " .. pattern)
        assert(position > previous, label .. " is out of order at: " .. pattern)
        previous = position
    end
end

ordered_positions({
    '{ id = 4, label = "连段训练" }',
    '{ id = 2, label = "确认训练" }',
    '{ id = 5, label = "随机斩杀" }',
}, "top bar and mode cycle")

ordered_positions({
    'imgui.checkbox("连段训练"',
    'imgui.checkbox("确认训练"',
    'imgui.checkbox("随机斩杀"',
}, "REFramework mode selector")

ordered_positions({
    'styled_header("连段训练配置"',
    'styled_header("确认训练配置"',
    'styled_header("随机斩杀配置"',
    'styled_header("木人库配置管理"',
    'styled_header("距离查看器"',
    'styled_header("碰撞框查看器(by Sheldon)"',
    'styled_header("快捷键设置"',
}, "REFramework config sections")

ordered_positions({
    "hdr_combo_config = UIKit.THEME.hdr_rainbow_red",
    "hdr_confirm_config = UIKit.THEME.hdr_rainbow_orange",
    "hdr_random_kill_config = UIKit.THEME.hdr_rainbow_yellow",
    "hdr_training_config = UIKit.THEME.hdr_rainbow_green",
    "hdr_distance_viewer = UIKit.THEME.hdr_rainbow_cyan",
    "hdr_collision_boxes = UIKit.THEME.hdr_rainbow_blue",
    "hdr_hotkeys = UIKit.THEME.hdr_rainbow_violet",
}, "rainbow headers")

print("training script manager order tests passed")
