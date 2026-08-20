package.path = package.path
    .. ";./autorun/?.lua"
    .. ";./autorun/?/init.lua"

local files = {
    "TrainingComboTrials_data\\CustomCombos\\Ryu\\Ryu_COMBO_2MK_6000_D3_SA3.json",
    "TrainingComboTrials_data\\CustomCombos\\Ryu\\Ryu_COMBO_236_LP_MP_2300_D2_7_SA1.json",
    "TrainingComboTrials_data\\CustomCombos\\Ryu\\Ryu_COMBO_RAW_DR_3756_D1.1_SA1.json",
    "TrainingComboTrials_data\\CustomCombos\\Ryu\\Ryu_COMBO_3050_D1_SA0.json",
    "TrainingComboTrials_data\\CustomCombos\\Ryu\\community-upload.json",
}

local titles = {
    Ryu_COMBO_2MK_6000_D3_SA3 = "版边连",
    Ryu_COMBO_236_LP_MP_2300_D2_7_SA1 = "波动连",
    ["Ryu_COMBO_RAW_DR_3756_D1.1_SA1"] = "小数点斗气",
    Ryu_COMBO_3050_D1_SA0 = "无起手",
    ["community-upload"] = "社区投稿",
}

json = {
    load_file = function(path)
        local key = tostring(path):match("([^/\\]+)%.json$")
        if key == "community-upload" then
            return {
                {
                    _xt_meta = {
                        title = titles[key],
                        author = "社区作者",
                        control_mode = "modern",
                    },
                    motion = "2+MP",
                    combo_stats = { damage = 3420, drive_used = 26750, super_used = 10000 },
                },
                { id = 900, motion = "236+MP", delay_from_prev = 12 },
            }
        end
        if key == "Ryu_COMBO_RAW_DR_3756_D1.1_SA1" then
            return {
                {
                    _xt_meta = { title = titles[key], control_mode = "classic" },
                    id = 17,
                    motion = "66",
                    combo_stats = {
                        damage = 3756,
                        drive_used = 11000,
                        super_used = 10000,
                    },
                },
                { id = 500, motion = "RAW_DR", delay_from_prev = 4 },
            }
        end
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
local UnifiedActionConsumer = require("func/ComboTrials/UnifiedActionConsumer")

local file_system = {
    combo_control_filter = "all",
    saved_combos_display_p1 = {},
    saved_combos_paths_p1 = {},
    saved_combos_control_p1 = {},
    saved_combos_all_display_p1 = {},
    saved_combos_all_paths_p1 = {},
    saved_combos_all_control_p1 = {},
}

local removed_paths = {}
local remove_should_fail = false
local function remove_combo_fixture(path)
    removed_paths[#removed_paths + 1] = path
    if remove_should_fail then return nil, "access denied" end
    for index, candidate in ipairs(files) do
        if candidate:gsub("\\", "/") == path:gsub("\\", "/") then
            table.remove(files, index)
            return true
        end
    end
    return nil, "missing"
end

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
    normalize_action_sequence = UnifiedActionConsumer.normalize_sequence,
    assign_groups = function() end,
    remove_file = remove_combo_fixture,
})

assert(file_system.update_combo_file_list(0) == true, "combo list scan failed")
assert(#file_system.saved_combos_info_p1 == 5, "structured combo rows were not cached")

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

assert(rows["小数点斗气"].starter == "RAW_DR", "dot-decimal starter parse failed")
assert(rows["小数点斗气"].damage == "3756", "dot-decimal damage parse failed")
assert(rows["小数点斗气"].drive == "1.1", "dot-decimal drive parse failed")
assert(rows["小数点斗气"].energy == "1", "dot-decimal energy parse failed")

assert(rows["无起手"].starter == "", "missing starter must remain empty")
assert(rows["无起手"].damage == "3050", "damage-only filename parse failed")

assert(rows["社区投稿"].starter == "2+MP", "JSON starter must override a non-standard filename")
assert(rows["社区投稿"].damage == "3420", "JSON damage must override a non-standard filename")
assert(rows["社区投稿"].drive == "2.675", "JSON decimal drive must preserve significant precision")
assert(rows["社区投稿"].energy == "1", "JSON super usage must override a non-standard filename")
assert(rows["社区投稿"].author == "社区作者", "combo author must be exposed as a list column")
assert(rows["社区投稿"].step_count == 2, "combo step count must use the normalized instruction sequence")

assert(type(file_system.delete_combo_file) == "function",
    "combo files module must expose the bounded physical-delete interface")
local unsafe_count = #file_system.saved_combos_paths_p1
local unsafe_ok, unsafe_reason = file_system.delete_combo_file(
    0,
    "TrainingComboTrials_data\\CustomCombos\\Ken\\outside.json"
)
assert(unsafe_ok == false and unsafe_reason == "path_not_listed",
    "delete must reject files outside the current character list")
assert(#removed_paths == 0 and #file_system.saved_combos_paths_p1 == unsafe_count,
    "rejected delete must not touch storage or refresh the list")

local failed_target = file_system.saved_combos_paths_p1[2]
remove_should_fail = true
local failed_ok, failed_reason = file_system.delete_combo_file(0, failed_target)
assert(failed_ok == false and failed_reason == "delete_failed",
    "physical delete failures must be reported")
assert(#file_system.saved_combos_paths_p1 == unsafe_count,
    "failed physical delete must preserve the current list")

remove_should_fail = false
file_system.selected_file_idx_p1 = #file_system.saved_combos_paths_p1
local deleted_target = file_system.saved_combos_paths_p1[file_system.selected_file_idx_p1]
local deleted_ok, deleted_reason = file_system.delete_combo_file(0, deleted_target)
assert(deleted_ok == true and deleted_reason == nil, "listed combo JSON should be physically deleted")
assert(removed_paths[#removed_paths] == deleted_target,
    "delete must pass the exact validated data-relative path to the native bridge")
assert(#file_system.saved_combos_paths_p1 == unsafe_count - 1,
    "successful delete must refresh the visible combo list immediately")
assert(file_system.selected_file_idx_p1 == #file_system.saved_combos_paths_p1,
    "successful delete must clamp the selected index to the refreshed list")
for _, path in ipairs(file_system.saved_combos_paths_p1) do
    assert(path ~= deleted_target, "deleted combo remained in the refreshed list")
end

local installed_trial_state = {}
json.load_file = function()
    return {
        {
            _xt_meta = { title = "前导投影", control_mode = "classic" },
            motion = "66",
            timeline = { "1f : 6", "1f : 6+MP+MK" },
        },
        { motion = "DR", id = 500, delay_from_prev = 4 },
        { motion = "2MP", id = 623, delay_from_prev = 22 },
    }
end
ComboTrialsFiles.init({
    trial_state = installed_trial_state,
    players = {},
    file_system = file_system,
    ui_state = { viewed_player = 0 },
}, {
    normalize_sequence_counter_types = function() end,
    normalize_action_sequence = UnifiedActionConsumer.normalize_sequence,
    assign_groups = function() end,
})
assert(ComboTrialsFiles.load_combo_from_file("LeadingPrefix.json", true) == true,
    "leading-prefix fixture failed to load")
assert(#installed_trial_state.source_sequence == 3
        and installed_trial_state.source_sequence[1].motion == "66"
        and #installed_trial_state.sequence == 2
        and installed_trial_state.sequence[1].id == 500
        and installed_trial_state.sequence[1].timeline[2] == "1f : 6+MP+MK",
    "file loading must preserve frozen V2 while installing the shared projection")

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
assert(ui_source:find('table_setup_column("作者"', 1, true), "author column is missing")
assert(ui_source:find('table_setup_column("步数"', 1, true), "step-count column is missing")
assert(ui_source:find('table_setup_column("反馈"', 1, true), "feedback column is missing")
assert(ui_source:find('table_setup_column("删除"', 1, true), "delete column is missing")
assert(ui_source:find('imgui.push_style_color(0, COMBO_DELETE_TEXT_COLOR)', 1, true),
    "delete button text must be red")
assert(ui_source:find('file_system.delete_combo_file', 1, true),
    "delete UI must use the bounded combo-files interface")
assert(ui_source:find('ComboFeedback.submit', 1, true), "feedback UI does not submit through the feedback producer")
for _, category in ipairs({ "未识别ID", "检测错误", "演示错误", "其他" }) do
    assert(ui_source:find(category, 1, true), "feedback category is missing: " .. category)
end
assert(ui_source:find("不支持中文输入", 1, true), "feedback text input must explain the IME limitation")
assert(ui_source:find("imgui.input_text_multiline", 1, true),
    "feedback description must use the supported multiline text binding")
assert(ui_source:find('imgui.text("问题类型")', 1, true),
    "feedback category label must be rendered above its control")
assert(ui_source:find('"##ComboFeedbackCategory"', 1, true),
    "feedback category control must use a hidden ImGui label")
assert(ui_source:find('imgui.text("具体描述（可选）")', 1, true),
    "feedback description label must be rendered above its control")
assert(ui_source:find('"##ComboFeedbackDescription"', 1, true),
    "feedback description control must use a hidden ImGui label")
assert(ui_source:find("local FEEDBACK_WINDOW_FLAGS", 1, true)
        and ui_source:find("(1 << 5)", 1, true),
    "feedback window must disable title-bar collapsing")
local frame_callback_pos = assert(ui_source:find("re.on_frame(function()", 1, true),
    "combo UI frame callback is missing")
assert(ui_source:find("draw_combo_feedback_window()", frame_callback_pos, true),
    "feedback window must render from the standalone frame lifecycle")
assert(not ui_source:find("re.on_draw_ui(draw_combo_feedback_window)", 1, true),
    "feedback window must not depend on the REFramework script tree being expanded")
assert(ui_source:find("local max_visible = 20", 1, true),
    "combo popup must show up to twenty rows")
assert(ui_source:find("local table_flags = COMBO_TABLE_FLAGS | COMBO_TABLE_SCROLL_Y", 1, true),
    "the table must always own programmatic and mouse scrolling")
assert(ui_source:find("local COMBO_POPUP_FLAGS = (1 << 3) | (1 << 4)", 1, true),
    "combo popup must disable outer-window scrolling")
assert(ui_source:find("imgui.begin_popup(popup_id, COMBO_POPUP_FLAGS)", 1, true),
    "combo popup must give vertical scrolling ownership to the table")
assert(ui_source:find(
        "local table_outer_height = math%.max%(line_h %* 3, popup_h %- 18%)"
    ),
    "scrolling combo tables must use an explicit positive outer height")
assert(ui_source:find(
        'Vector2f.new(0, table_outer_height)',
        1,
        true
    ),
    "combo table scrolling must remain inside the table container")
assert(ui_source:find(
        "imgui.table_setup_scroll_freeze(0, 1)",
        1,
        true
    ),
    "combo tables must always freeze the header row")
assert(not ui_source:find("needs_vertical_scroll", 1, true),
    "popup opening must never fall back to scrolling the outer window")
assert(ui_source:find("local popup_h = ((visible_count + 2) * line_h) + 18", 1, true),
    "popup height must reserve enough padding for every short-list row")
assert(not ui_source:find("selected == true", 1, true),
    "selected combo row must not use the menu-item checkmark")
assert(ui_source:find("texture.draw_window", 1, true), "starter icons are not drawn in the popup window layer")
assert(ui_source:find("renderer.parse_starter_icons", 1, true), "starter notation parser is not reused")
for _, header in ipairs({ "C/完", "名称", "作者", "步数", "起手", "伤害", "斗气", "能量", "反馈", "删除" }) do
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

local native_file_source = read_all("native/reframework-sf6cc-atomic-file/src/plugin.cpp")
assert(native_file_source:find('k_combo_root = "TrainingComboTrials_data/CustomCombos/"', 1, true),
    "native combo delete root is missing")
assert(native_file_source:find('lua_setfield(state, -2, "remove_combo")', 1, true),
    "native bridge does not expose bounded combo deletion")
assert(native_file_source:find("FILE_ATTRIBUTE_REPARSE_POINT", 1, true),
    "native combo deletion must reject reparse-point targets")
assert(native_file_source:find("DeleteFileW", 1, true),
    "native combo deletion does not physically delete the validated JSON")

print("combo multicolumn list tests passed")
