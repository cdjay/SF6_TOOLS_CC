package.path = package.path
    .. ";./autorun/?.lua"
    .. ";./autorun/?/init.lua"

local files = {
    "TrainingComboTrials_data\\CustomCombos\\Ryu\\Ryu_COMBO_2MK_6000_D3_SA3.json",
    "TrainingComboTrials_data\\CustomCombos\\Ryu\\Ryu_COMBO_236_LP_MP_2300_D2_7_SA1.json",
    "TrainingComboTrials_data\\CustomCombos\\Ryu\\Ryu_COMBO_3050_D1_SA0.json",
}

local titles = {
    Ryu_COMBO_2MK_6000_D3_SA3 = "版边连",
    Ryu_COMBO_236_LP_MP_2300_D2_7_SA1 = "波动连",
    Ryu_COMBO_3050_D1_SA0 = "无起手",
}

json = {
    load_file = function(path)
        local key = tostring(path):match("([^/\\]+)%.json$")
        return { { _xt_meta = { title = titles[key], control_mode = "classic" } } }
    end,
}
fs = {
    create_dir = function() end,
    glob = function() return files end,
}
log = {}
sdk = {}

package.loaded["func/ComboTrials_Files"] = nil
local ComboTrialsFiles = require("func/ComboTrials_Files")

local file_system = {
    combo_control_filter = "all",
    saved_combos_display_p1 = {},
    saved_combos_paths_p1 = {},
    saved_combos_control_p1 = {},
    saved_combos_all_display_p1 = {},
    saved_combos_all_paths_p1 = {},
    saved_combos_all_control_p1 = {},
}

ComboTrialsFiles.init({
    trial_state = {},
    players = {
        [0] = { profile_name = "Ryu" },
    },
    file_system = file_system,
    ui_state = { viewed_player = 0 },
    d2d_cfg = {},
}, {
    normalize_sequence_counter_types = function() end,
    assign_groups = function() end,
})

assert(file_system.update_combo_file_list(0) == true, "combo list scan failed")
assert(#file_system.saved_combos_info_p1 == 3, "structured combo rows were not cached")

local rows = {}
for _, row in ipairs(file_system.saved_combos_info_p1) do
    rows[row.name] = row
end

assert(rows["版边连"].starter == "2MK", "starter column parse failed")
assert(rows["版边连"].damage == "6000", "damage column parse failed")
assert(rows["版边连"].drive == "3", "drive column parse failed")
assert(rows["版边连"].energy == "3", "energy column parse failed")

assert(rows["波动连"].starter == "236_LP_MP", "multi-token starter parse failed")
assert(rows["波动连"].damage == "2300", "multi-token damage parse failed")
assert(rows["波动连"].drive == "2.7", "decimal drive parse failed")
assert(rows["波动连"].energy == "1", "multi-token energy parse failed")

assert(rows["无起手"].starter == "", "missing starter must remain empty")
assert(rows["无起手"].damage == "3050", "damage-only filename parse failed")

local function read_all(path)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    return source
end

local ui_source = read_all("autorun/func/ComboTrials_UI.lua")

assert(ui_source:find('imgui.begin_table("##ComboListTable"', 1, true), "combo popup is not rendered as a table")
assert(ui_source:find("local COMBO_COLUMN_FIXED = 1 << 4", 1, true), "fixed column flag is incorrect")
assert(ui_source:find("local COMBO_COLUMN_STRETCH = 1 << 3", 1, true), "stretch column flag is incorrect")
assert(ui_source:find("local COMBO_TABLE_FLAGS = (1 << 3)", 1, true), "sortable table flag is missing")
assert(ui_source:find("imgui.table_get_sort_specs()", 1, true), "table sort specifications are not read")
assert(ui_source:find("table.sort(order", 1, true), "table rows are not sorted")
assert(ui_source:find("imgui.table_set_bg_color(", 1, true),
    "selected combo row does not receive a persistent table background")
assert(ui_source:find("COMBO_SELECTED_ROW_BG_COLOR", 1, true),
    "selected combo row background color is missing")
assert(ui_source:find("local is_selected = (i == current_idx)", 1, true),
    "selected combo row background must follow the active combo index")
assert(ui_source:find("local is_scroll_target = (i == _dropdown_highlight_idx)", 1, true),
    "initial popup scroll target must remain separate from the selected combo")
assert(ui_source:find("local function combo_centered_overlay", 1, true),
    "compact combo columns do not use centered overlay text")
assert(not ui_source:find("COMBO_SELECTABLE_TEXT_ALIGN", 1, true),
    "combo table must not use an incompatible SelectableTextAlign style variable")
assert(ui_source:find("draw_list:add_text", 1, true),
    "centered combo text must use the window draw list")
local centered_overlay_source = assert(ui_source:match(
    "local function combo_centered_overlay.-\nend"),
    "centered combo overlay implementation is missing")
assert(not centered_overlay_source:find("set_cursor_pos", 1, true),
    "centered combo text must not reposition the ImGui cursor")
assert(ui_source:find('table_setup_column("能量", COMBO_COLUMN_FIXED, 72)', 1, true),
    "energy column is not wide enough for its header and values")
assert(ui_source:find("local max_visible = 20", 1, true),
    "combo popup must show up to twenty rows")
assert(ui_source:find("local needs_vertical_scroll = #items > max_visible", 1, true),
    "short combo lists must not force a vertical scrollbar")
assert(ui_source:find("if needs_vertical_scroll then table_flags = table_flags | COMBO_TABLE_SCROLL_Y end", 1, true),
    "vertical scrolling must only be enabled after the visible-row limit")
assert(ui_source:find("local popup_h = ((visible_count + 2) * line_h) + 18", 1, true),
    "popup height must reserve enough padding for every short-list row")
assert(not ui_source:find("selected == true", 1, true),
    "selected combo row must not use the menu-item checkmark")
assert(ui_source:find("texture.draw_window", 1, true), "starter icons are not drawn in the popup window layer")
assert(ui_source:find("renderer.parse_starter_icons", 1, true), "starter notation parser is not reused")
for _, header in ipairs({ "C/完", "名称", "起手", "伤害", "斗气", "能量" }) do
    assert(ui_source:find('table_setup_column("' .. header .. '"', 1, true), "missing table column: " .. header)
end
assert(not ui_source:find("imgui.selectable", 1, true), "unsupported REFramework selectable binding was used")

local renderer_source = read_all("autorun/func/ComboTrials_ImGui.lua")
assert(renderer_source:find("function M.parse_starter_icons(starter)", 1, true),
    "combo renderer does not expose starter icon parsing")

re = re or {}
imgui = imgui or {}
package.loaded["func/ComboTrials_ImGui"] = nil
local renderer = require("func/ComboTrials_ImGui")
local function starter_icon_values(starter)
    local tokens = assert(renderer.parse_starter_icons(starter), "starter parse failed: " .. starter)
    local values = {}
    for _, token in ipairs(tokens) do values[#values + 1] = token.val end
    return table.concat(values, ",")
end

assert(starter_icon_values("2LP") == "2,plus,lp", "normal starter icons are incorrect")
assert(starter_icon_values("214_PP") == "2,1,4,plus,p,p", "multi-button starter icons are incorrect")
assert(starter_icon_values("236_LP_MP") == "2,3,6,plus,lp,mp", "multi-token starter icons are incorrect")
assert(starter_icon_values("DI") == "di", "DI starter icon is incorrect")
assert(starter_icon_values("PARRY") == "parry", "parry starter icon is incorrect")
assert(starter_icon_values("RAW_DR") == "dr", "raw drive rush starter icon is incorrect")
assert(starter_icon_values("DRIVERUSH") == "dr", "drive rush starter icon is incorrect")

local texture_source = read_all("native/reframework-imgui-texture/src/plugin.cpp")
assert(texture_source:find('"igGetWindowDrawList"', 1, true), "texture bridge does not resolve the window draw list")
assert(texture_source:find('"draw_window", lua_texture_draw_window', 1, true),
    "texture bridge does not expose draw_window")

print("combo multicolumn list tests passed")
