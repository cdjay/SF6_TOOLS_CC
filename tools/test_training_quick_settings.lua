local function read_all(path)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    return source:gsub("\r\n", "\n")
end

local manager = read_all("autorun/Training_ScriptManager.lua")
local registry = read_all("autorun/func/Training_MenuRegistry.lua")
local combo_ui = read_all("autorun/func/ComboTrials_UI.lua")
local hotkeys = read_all("autorun/func/Training_Hotkeys.lua")
local shared_ui = read_all("autorun/func/Training_SharedUI.lua")

assert(manager:find('TRAINING_MODE_MODULES[1].settings_panel = "combo_config"', 1, true),
    "combo top-bar button must declare its settings panel")
assert(manager:find("SharedUI.draw_quick_settings_gear", 1, true),
    "combo top bar must expose a gear button")
assert(manager:find("SharedUI.draw_open_quick_settings", 1, true),
    "script manager must forward drawing to the settings shell")
assert(not manager:find('require("func/Training_QuickSettings")', 1, true),
    "external settings must use the existing whitelisted shared UI module")

assert(registry:find("function M.register_quick", 1, true),
    "menu registry must own quick-panel registration")
assert(registry:find("function M.draw_quick", 1, true),
    "menu registry must draw quick panels through the shared owner")
assert(not registry:find('require("func/Training_QuickSettings")', 1, true),
    "menu registry must not depend on a non-whitelisted runtime module")

local quick_start = assert(combo_ui:find("local function draw_combo_trials_quick_settings()", 1, true))
local full_start = assert(combo_ui:find("local function draw_combo_trials_menu_ui()", quick_start, true))
local quick_body = combo_ui:sub(quick_start, full_start - 1)
assert(quick_body:find('imgui.checkbox("显示备注"', 1, true),
    "quick settings must contain ordinary combo preferences")
assert(not quick_body:find("draw_transcription_debug_tools", 1, true),
    "quick settings must not expose transcription/debug tooling")
assert(combo_ui:find("draw_combo_trials_quick_settings()", full_start, true),
    "REFramework menu must reuse the same quick settings renderer")
assert(combo_ui:find('TrainingMenuRegistry.register_quick("combo_config"', full_start, true),
    "combo UI must publish its shared quick settings panel")
assert(combo_ui:find('hotkey_scope = "combo_trials"', full_start, true),
    "combo quick settings must bind only the combo hotkey scope")

assert(hotkeys:find("function M.draw_scope(scope_id)", 1, true),
    "hotkey registry must expose one scope without debug device state")
assert(shared_ui:find("menu_registry.draw_quick(panel_id)", 1, true),
    "external panel must reuse registered feature settings")
assert(shared_ui:find('"设置##quick_settings_"', 1, true),
    "icon-only gear must retain a non-empty ImGui label")
assert(shared_ui:find("hotkeys.draw_scope(hotkey_scope)", 1, true),
    "external panel must reuse registered hotkey state")
assert(not shared_ui:find("hotkeys.draw_menu", 1, true),
    "external panel must not expose global hotkey diagnostics")

package.path = "autorun/?.lua;autorun/?/init.lua;" .. package.path

local gear_clicked = false
local quick_draws = 0
local hotkey_draws = 0

Vector2f = { new = function(x, y) return { x = x, y = y } end }
texture = {
    load = function() return {} end,
    draw_window = function() return true end,
}
imgui = {
    get_cursor_screen_pos = function() return { x = 100, y = 20 } end,
    is_item_hovered = function() return false end,
    is_item_active = function() return false end,
    set_tooltip = function() end,
    button = function(label)
        if label:find("设置##quick_settings_", 1, true) then
            local result = gear_clicked
            gear_clicked = false
            return result
        end
        return false
    end,
    push_style_color = function() end,
    pop_style_color = function() end,
    push_style_var = function() end,
    pop_style_var = function() end,
    push_font = function() end,
    pop_font = function() end,
    set_next_window_pos = function() end,
    set_next_window_size = function() end,
    begin_window = function() return true end,
    end_window = function() end,
    get_cursor_pos = function() return { x = 0, y = 0 } end,
    set_cursor_pos = function() end,
    text_colored = function() end,
    separator = function() end,
    spacing = function() end,
    is_mouse_clicked = function() return false end,
    get_window_draw_list = function() return nil end,
}

package.loaded["func/Training_MenuRegistry"] = nil
local runtime_registry = require("func/Training_MenuRegistry")
local runtime_shared_ui = assert(loadfile("autorun/func/Training_SharedUI.lua"))()
local runtime_hotkeys = {
    draw_scope = function(scope_id)
        assert(scope_id == "combo_trials")
        hotkey_draws = hotkey_draws + 1
    end,
}
assert(runtime_registry.register_quick("combo_config", function()
    quick_draws = quick_draws + 1
end, {
    title = "连段训练设置",
    hotkey_scope = "combo_trials",
}))

gear_clicked = true
assert(runtime_shared_ui.draw_quick_settings_gear(runtime_registry, "combo_config", 30) == true)
assert(runtime_shared_ui.draw_open_quick_settings(runtime_registry, runtime_hotkeys) == true)
assert(quick_draws == 1, "external shell must invoke the registered shared settings renderer")
assert(hotkey_draws == 1, "external shell must invoke only the declared hotkey scope")

assert(runtime_registry.draw("missing") == false)
assert(runtime_registry.draw_quick("combo_config") == true)
assert(quick_draws == 2, "registry entry points must share the same settings owner")

gear_clicked = true
assert(runtime_shared_ui.draw_quick_settings_gear(runtime_registry, "combo_config", 30) == true)
assert(runtime_shared_ui.draw_open_quick_settings(runtime_registry, runtime_hotkeys) == false,
    "clicking the active gear must close the external settings panel")

print("training quick settings tests passed")
