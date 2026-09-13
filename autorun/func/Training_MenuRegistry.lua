-- Training_MenuRegistry.lua
-- Shared registry for configuration panels hosted by Training_ScriptManager.

local M = {}
local panels = {}
local quick_panels = {}
local quick_specs = {}

local function draw_registered(panel_id, draw_fn, missing_message)
    if type(draw_fn) ~= "function" then
        imgui.text_colored(missing_message or "配置模块尚未加载。", 0xFF888888)
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
    return draw_registered(panel_id, panels[panel_id], "配置模块尚未加载。")
end

function M.register_quick(panel_id, draw_fn, spec)
    if type(panel_id) ~= "string" or panel_id == "" then return false end
    if type(draw_fn) ~= "function" then return false end
    quick_panels[panel_id] = draw_fn
    quick_specs[panel_id] = type(spec) == "table" and spec or {}
    return true
end

function M.has_quick(panel_id)
    return type(quick_panels[panel_id]) == "function"
end

function M.get_quick_spec(panel_id)
    return quick_specs[panel_id]
end

function M.draw_quick(panel_id)
    return draw_registered(panel_id, quick_panels[panel_id], "快捷设置模块尚未加载。")
end

return M
