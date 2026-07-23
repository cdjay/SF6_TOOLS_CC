-- Training_MenuRegistry.lua
-- Shared registry for configuration panels hosted by Training_ScriptManager.

local M = {}
local panels = {}

function M.register(panel_id, draw_fn)
    if type(panel_id) ~= "string" or panel_id == "" then return false end
    if type(draw_fn) ~= "function" then return false end
    panels[panel_id] = draw_fn
    return true
end

function M.has(panel_id)
    return type(panels[panel_id]) == "function"
end

function M.draw(panel_id)
    local draw_fn = panels[panel_id]
    if type(draw_fn) ~= "function" then
        imgui.text_colored("配置模块尚未加载。", 0xFF888888)
        return false
    end

    local ok, err = pcall(draw_fn)
    if not ok then
        imgui.text_colored("配置界面绘制失败。", 0xFF0000FF)
        imgui.text_colored(tostring(err), 0xFF00A5FF)
        print("[Training_MenuRegistry] " .. tostring(panel_id) .. ": " .. tostring(err))
        return false
    end
    return true
end

return M
