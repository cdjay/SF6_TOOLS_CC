-- =========================================================
-- ComboTrials_UI.lua - All ImGui UI code
-- Received shared context via init(). Registers re.on_frame and re.on_draw_ui.
-- =========================================================



local sdk = sdk
local imgui = imgui
local re = re
local json = json
local UIKit = require("func/UIKit")

local M = {}
local ctx

-- Forward declarations resolved in init()
local d2d_cfg, trial_state, players, file_system
local common_exceptions, sf6_menu_state
local load_and_start_trial, start_recording, stop_recording_and_save, cancel_recording, cancel_recording_due_to_menu
local refresh_combo_list, restore_trial_vital, save_d2d_config, get_exc_filename
local ui_state

local dump_status = ""
local exc_status = ""

local _replay_status_p1 = "waiting"
local _replay_status_p2 = "waiting"
local _replay_save_clock = 0
local _replay_saved_clock = 0
local _replay_save_player = nil
local _replay_saved_fname_p1 = nil
local _replay_saved_fname_p2 = nil
local _prev_is_recording = false

-- =========================================================
-- UI THEME AND STYLES (Inspired by Training Hit Confirm)
local RuntimeSafety = require("func/RuntimeSafety")
-- =========================================================
local COLORS = UIKit.COLORS

local UI_THEME = {
    hdr_info    = UIKit.THEME.hdr_gold,
    hdr_session = UIKit.THEME.hdr_purple,
    hdr_rules   = UIKit.THEME.hdr_blue,
    hdr_matrix  = UIKit.THEME.hdr_green,
    btn_neutral = UIKit.THEME.btn_neutral,
    btn_green   = UIKit.THEME.btn_green,
    btn_red     = UIKit.THEME.btn_red,
    btn_orange  = UIKit.THEME.btn_easy,
}

local function zh_status_text(text)
    if not text or text == "" then return text end
    local s = tostring(text)
    local n

    n = s:match("^TOO EARLY %((%d+)f%)$")
    if n then return "过早 (" .. n .. "f)" end
    n = s:match("^TOO LATE %((%d+)f%)$")
    if n then return "过晚 (" .. n .. "f)" end
    n = s:match("^(%d+) frames too early$")
    if n then return "早了 " .. n .. " 帧" end
    n = s:match("^(%d+) frames too late$")
    if n then return "晚了 " .. n .. " 帧" end
    n = s:match("^SETUP TOO EARLY %((%d+)f%)$")
    if n then return "Setup 过早 (" .. n .. "f)" end
    n = s:match("^SETUP TOO LATE %((%d+)f%)$")
    if n then return "Setup 过晚 (" .. n .. "f)" end
    n = s:match("^HOLD TIMING%s*(%[[^%]]+%])%s*%(Combo Drop%)$")
    if n then return "按住时机错误 " .. n .. "（连段断开）" end
    local got, exp, diff = s:match("^WRONG HOLD %(Got: (.-), Exp: (.-)%)(.*)$")
    if got then return "按住状态错误（实际：" .. got .. "，期望：" .. exp .. "）" .. (diff or "") end

    local map = {
        ["FAILED"] = "失败",
        ["WRONG MOVE"] = "错误动作",
        ["COMBO DROPPED"] = "连段断开",
        ["TOO LATE (Missed Input)"] = "过晚（未输入）",
        ["TOO LATE (Combo Drop)"] = "过晚（连段断开）",
        ["HOLD TIMING (Combo Drop)"] = "按住时机错误（连段断开）",
        ["WRONG HOLD TIMING"] = "按住时机错误",
        ["WRONG HP (Setup Dropped)"] = "HP 不匹配（Setup 失败）",
        ["MEATY TIMING FAILED"] = "压起身时机失败",
        ["SETUP INTERRUPTED (Got hit)"] = "Setup 被打断",
        ["MEATY INTERRUPTED (Got hit)"] = "压起身被打断",
        ["INTERRUPTED (Got hit)"] = "被打断",
        ["MEATY TOO LATE (Missed Input)"] = "压起身过晚（未输入）",
        ["Perfect timing"] = "完美时机",
    }
    return map[s] or s
end

-- Externally-openable combo dropdown (replaces imgui.combo for ##FilesP1)
local _dropdown_highlight_idx = nil
local _dropdown_scroll_needed = false

local CONTROL_CLASSIC_COLOR = 0xFFDDA0CC
local CONTROL_MODERN_COLOR = 0xFF66A0DD

local function combo_control_color(value)
    local mode = tostring(value or ""):lower()
    if mode == "classic" or mode:find("^%[c%]") then return CONTROL_CLASSIC_COLOR end
    if mode == "modern" or mode:find("^%[m%]") then return CONTROL_MODERN_COLOR end
    return nil
end

local function combo_openable(label, current_idx, items, force_open, btn_width)
    local popup_id = label .. "_popup"
    local preview = (items and items[current_idx]) or "---"

    -- Capture button screen position before drawing it
    local win_pos = imgui.get_window_pos()
    local cursor_pos = imgui.get_cursor_pos()
    local btn_screen_x = win_pos.x + cursor_pos.x
    local btn_screen_y = win_pos.y + cursor_pos.y

    -- Full-width button with down arrow
    local w = btn_width or -1
    local preview_color = combo_control_color(preview)
    if preview_color then imgui.push_style_color(0, preview_color) end
    local clicked = imgui.button(preview .. "  \xe2\x96\xbc" .. label, Vector2f.new(w, 0))
    if preview_color then imgui.pop_style_color(1) end

    local should_open = force_open or clicked
    if should_open then
        -- Estimate popup height: item count * line height, capped
        local line_h = imgui.calc_text_size("W").y + 6
        local max_visible = 10
        local visible_count = math.min(#items, max_visible)
        local popup_h = (visible_count * line_h) + 8

        -- Position the popup just above the button, left-aligned
        imgui.set_next_window_pos(Vector2f.new(btn_screen_x, btn_screen_y - popup_h), 1)

        imgui.open_popup(popup_id)
        _dropdown_highlight_idx = current_idx
        _dropdown_scroll_needed = true
        if force_open then _G.ComboTrials_OpenDropdown = false end
    end

    local changed = false
    local new_idx = current_idx

    if imgui.begin_popup(popup_id) then
        _G.ComboTrials_DropdownOpen = true

        for i = 1, #items do
            local is_highlighted = (i == _dropdown_highlight_idx)
            local row_color = combo_control_color(items[i])
            if row_color then imgui.push_style_color(0, row_color) end
            if imgui.menu_item(items[i], "", is_highlighted, true) then
                new_idx = i
                changed = true
            end
            if row_color then imgui.pop_style_color(1) end
            -- Scroll to highlighted item
            if is_highlighted and _dropdown_scroll_needed then
                pcall(imgui.set_scroll_here_y)
                _dropdown_scroll_needed = false
            end
        end
        imgui.end_popup()
    else
        _G.ComboTrials_DropdownOpen = false
        _dropdown_highlight_idx = nil
    end

    return changed, new_idx
end

local CONTROL_FILTER_VALUES = { "auto", "all", "classic", "modern" }
local CONTROL_FILTER_LABELS = { "Auto", "All", "Classic", "Modern" }

local function combo_control_filter_index()
    local current = "auto"
    if file_system then
        current = tostring(file_system.combo_control_filter or "auto"):lower()
    end
    for idx, value in ipairs(CONTROL_FILTER_VALUES) do
        if value == current then return idx end
    end
    return 1
end

local function apply_combo_control_filter_idx(idx)
    local value = CONTROL_FILTER_VALUES[idx or 1] or "auto"
    if not file_system then return end
    if file_system.combo_control_filter == value then return end
    file_system.combo_control_filter = value
    if file_system.refresh_combo_list_preserve_selection then
        file_system.refresh_combo_list_preserve_selection(false)
    elseif refresh_combo_list then
        refresh_combo_list()
    end
end

local function draw_combo_control_filter(id, width)
    if file_system and file_system.combo_control_filter == "auto" and file_system.effective_combo_control_filter then
        local effective_filter = file_system.effective_combo_control_filter("auto")
        if effective_filter ~= file_system.combo_control_effective_filter then
            file_system.combo_control_effective_filter = effective_filter
            if file_system.refresh_combo_list_preserve_selection then
                file_system.refresh_combo_list_preserve_selection(false)
            end
        end
    end

    local current_filter = tostring(file_system and file_system.combo_control_filter or "auto"):lower()
    local filter_color = nil
    if current_filter == "auto" then
        filter_color = combo_control_color(file_system and file_system.combo_control_effective_filter or "classic")
    else
        filter_color = combo_control_color(current_filter)
    end
    if filter_color then imgui.push_style_color(0, filter_color) end
    imgui.push_item_width(width)
    local changed, new_idx = imgui.combo("##ControlFilter" .. tostring(id or ""), combo_control_filter_index(), CONTROL_FILTER_LABELS)
    imgui.pop_item_width()
    if filter_color then imgui.pop_style_color(1) end
    if changed then apply_combo_control_filter_idx(new_idx) end
end

local function combo_empty_text(player_label)
    local filter = tostring(file_system and file_system.combo_control_filter or "auto"):lower()
    local effective_filter = filter
    if filter == "auto" then
        effective_filter = tostring(file_system and file_system.combo_control_effective_filter or "classic"):lower()
    end
    local skipped = (file_system and file_system.skipped_combos_p1 or 0) > 0
    if skipped then return "连段文件无法读取（查看日志）" end
    if effective_filter == "modern" then return "没有 Modern 文件" end
    if effective_filter == "classic" then return "没有 Classic 文件" end
    return "没有 " .. tostring(player_label or "P1") .. " 文件"
end

local function draw_top_combo_picker(id, dd_w, sp)
    local filter_w = math.max(76, math.min(110, dd_w * 0.32))
    local filtered_dd_w = math.max(50, dd_w - filter_w - sp)
    draw_combo_control_filter(id, filter_w)
    imgui.same_line(0, sp)

    if #file_system.saved_combos_display_p1 == 0 then
        imgui.push_item_width(filtered_dd_w)
        imgui.combo("##EmptyP1", 1, { combo_empty_text("P1") })
        imgui.pop_item_width()
        return
    end

    local should_open = (_G.ComboTrials_OpenDropdown == true)
    local changed, new_idx = combo_openable("##FilesP1", file_system.selected_file_idx_p1, file_system.saved_combos_display_p1, should_open, filtered_dd_w)
    if changed then
        file_system.selected_file_idx_p1 = new_idx
        load_and_start_trial(0)
    end
end

local function publish_top_combo_picker_left(dd_w, sp, local_x)
    local pos = imgui.get_window_pos()
    if not pos then return end
    local filter_w = math.max(76, math.min(110, dd_w * 0.32))
    _G.ComboTrialsFileListLeft = pos.x + (local_x or 0) + filter_w + sp
end

local function update_replay_recording_status(is_replay_mode)
    if _G.ComboTrials_ReplayCancelPlayer ~= nil then
        local cp = _G.ComboTrials_ReplayCancelPlayer
        _G.ComboTrials_ReplayCancelPlayer = nil
        if cp == 0 then _replay_status_p1 = "canceled" else _replay_status_p2 = "canceled" end
        _replay_saved_clock = os.clock()
    end

    if _G.ComboTrials_ReplaySavePlayer ~= nil then
        _replay_save_player = _G.ComboTrials_ReplaySavePlayer
        _G.ComboTrials_ReplaySavePlayer = nil
    end
    if _G.ComboTrials_ReplayCanceled ~= nil then
        local cp = _G.ComboTrials_ReplayCanceled
        _G.ComboTrials_ReplayCanceled = nil
        if cp == 0 then _replay_status_p1 = "canceled" else _replay_status_p2 = "canceled" end
        _replay_saved_clock = os.clock()
    end
    if _G.ComboTrials_PendingSaveCanceled ~= nil then
        local cp = _G.ComboTrials_PendingSaveCanceled
        _G.ComboTrials_PendingSaveCanceled = nil
        if cp == 0 then _replay_status_p1 = "canceled"
        elseif cp == 1 then _replay_status_p2 = "canceled" end
        _replay_saved_clock = os.clock()
    end
    if _G.ComboTrials_SaveFailedPlayer ~= nil then
        local cp = _G.ComboTrials_SaveFailedPlayer
        _G.ComboTrials_SaveFailedPlayer = nil
        if cp == 0 then _replay_status_p1 = "save_failed"
        elseif cp == 1 then _replay_status_p2 = "save_failed" end
        _replay_saved_clock = os.clock()
    end

    if _prev_is_recording and not trial_state.is_recording then
        local cur_st = (_replay_save_player == 0) and _replay_status_p1 or _replay_status_p2
        if cur_st ~= "canceled" and cur_st ~= "save_failed" then
            _replay_save_clock = os.clock()
            _replay_saved_clock = 0
            if _replay_save_player == 0 then _replay_status_p1 = "saving"
            elseif _replay_save_player == 1 then _replay_status_p2 = "saving" end
        end
    end
    _prev_is_recording = trial_state.is_recording

    local now = os.clock()
    for _, pi in ipairs({0, 1}) do
        local st = (pi == 0) and _replay_status_p1 or _replay_status_p2
        if st == "saving" and _replay_save_clock > 0 then
            local fn = _G.ComboTrials_LastSavedFilename
            local saved_pi = _G.ComboTrials_LastSavedPlayer
            if fn and (saved_pi == nil or saved_pi == pi) then
                if pi == 0 then _replay_status_p1 = "saved" else _replay_status_p2 = "saved" end
                _replay_saved_clock = now
                fn = fn:gsub("%.json$", "")
                if pi == 0 then _replay_saved_fname_p1 = fn else _replay_saved_fname_p2 = fn end
                _G.ComboTrials_LastSavedFilename = nil
                _G.ComboTrials_LastSavedPlayer = nil
            end
        elseif st == "saved" and _replay_saved_clock > 0 then
            if now - _replay_saved_clock >= 3.0 then
                if pi == 0 then _replay_status_p1 = "waiting" else _replay_status_p2 = "waiting" end
            end
        elseif st == "canceled" and _replay_saved_clock > 0 then
            if now - _replay_saved_clock >= 1.0 then
                if pi == 0 then _replay_status_p1 = "waiting" else _replay_status_p2 = "waiting" end
            end
        elseif st == "save_failed" and _replay_saved_clock > 0 then
            if now - _replay_saved_clock >= 3.0 then
                if pi == 0 then _replay_status_p1 = "waiting" else _replay_status_p2 = "waiting" end
            end
        end
    end

    if trial_state.is_recording then
        if trial_state.recording_player == 0 then _replay_status_p1 = "recording"
        elseif trial_state.recording_player == 1 then _replay_status_p2 = "recording" end
    end

    return now
end

local function replay_status_label(player_idx, width, now)
    local st = (player_idx == 0) and _replay_status_p1 or _replay_status_p2
    local label, color
    if st == "waiting" then
        label = "等待 P" .. (player_idx + 1) .. " 录制"
        color = COLORS.DarkGrey
    elseif st == "recording" then
        label = "录制中"
        color = COLORS.Red
    elseif st == "saving" then
        local dots_count = math.floor(((now or os.clock()) - _replay_save_clock) / 0.333) % 3 + 1
        label = "正在保存" .. string.rep(".", dots_count)
        color = COLORS.Orange
    elseif st == "saved" then
        local fn = (player_idx == 0) and _replay_saved_fname_p1 or _replay_saved_fname_p2
        label = fn and ("已保存为 " .. fn) or "录制已保存"
        color = COLORS.Green
    elseif st == "canceled" then
        label = "录制已取消"
        color = COLORS.Orange
    elseif st == "save_failed" then
        label = "保存失败"
        color = COLORS.Red
    else
        label = "---"
        color = COLORS.DarkGrey
    end
    imgui.push_style_color(0, color)
    imgui.button(label .. "##status_p" .. player_idx, Vector2f.new(width, 0))
    imgui.pop_style_color(1)
end

local styled_button = UIKit.styled_button
local styled_header = UIKit.styled_header

-- Alphanumeric sort function for exceptions
local function sort_ids(dict)
    local keys = {}
    for k in pairs(dict) do table.insert(keys, k) end
    table.sort(keys, function(a, b)
        local num_a, num_b = tonumber(a), tonumber(b)
        if num_a and num_b then return num_a < num_b end
        return tostring(a) < tostring(b)
    end)
    return keys
end

-- =========================================================
-- SHARED FUNCTION: TAB 1 CONTENT
-- =========================================================
local show_trial_overlay = true

local sf6_btn_font = nil
local custom_ui_font = nil
local hud_overlay_font = nil
local font_attempted = false

-- =========================================================
-- BUTTON FUNCTION (Chameleon: Neon or Native)
-- =========================================================
-- Dynamic colors from Training Script Manager (_G.TrainingSCColors)
-- Fallbacks in case ScriptManager hasn't loaded yet
local SC_FALLBACKS = {
    c1 = { text = 0xFF4444FF, base = 0x784444FF, hover = 0xA04444FF, active = 0xC84444FF, border = 0xFFFFFFFF },
    c2 = { text = 0xFF44FF44, base = 0x7844FF44, hover = 0xA044FF44, active = 0xC844FF44, border = 0xFFFFFFFF },
    c3 = { text = 0xFFFF4444, base = 0x78FF4444, hover = 0xA0FF4444, active = 0xC8FF4444, border = 0xFFFFFFFF },
    c4 = { text = 0xFF00A5FF, base = 0x7800A5FF, hover = 0xA000A5FF, active = 0xC800A5FF, border = 0xFFFFFFFF },
}
local function get_sc(key) local g = _G.TrainingSCColors; return (g and g[key]) or SC_FALLBACKS[key] end

-- P1=c1(red), TRIAL=c2(green), P2=c3(blue), SWITCH=c4(orange)
-- These are now functions, called at render time to get live colors
local function P1_COLORS()     return get_sc("c1") end
local function TRIAL_COLORS()  return get_sc("c2") end
local function P2_COLORS()     return get_sc("c3") end
local function SWITCH_COLORS() return get_sc("c4") end
local function NOTE_ON_COLORS()
    return { text = 0xFFFFFFFF, base = 0xFFE07000, hover = 0xFFFF9000, active = 0xFFFFA000, border = 0xFFFFC070 }
end
local function NOTE_OFF_COLORS()
    return { text = 0xFFFFFFFF, base = 0xFF4A4A4A, hover = 0xFF606060, active = 0xFF707070, border = 0xFF909090 }
end

local function styled_sf6_button(label, is_active, width, is_floating, is_disabled, color_override)
    width = width or 0
    -- Resolve color_override: call it if it's a function
    local co = color_override
    if type(co) == "function" then co = co() end

    -- DOCKED MODE (Native Debug Menu)
    if not is_floating then
        if co then
            imgui.push_style_color(5,  co.text)
            imgui.push_style_color(21, co.base)
            imgui.push_style_color(22, co.hover)
            imgui.push_style_color(23, co.active)
            imgui.push_style_color(0,  co.border)
            local clicked = imgui.button(label, Vector2f.new(width, 0))
            imgui.pop_style_color(5)
            return clicked
        else
            local style = is_active and UI_THEME.btn_green or UI_THEME.btn_neutral
            imgui.push_style_color(21, style.base)
            imgui.push_style_color(22, style.hover)
            imgui.push_style_color(23, style.active)
            local clicked = imgui.button(label, Vector2f.new(width, 0))
            imgui.pop_style_color(3)
            return clicked
        end
    end

    -- FLOATING MODE (SF6 Neon)
    if sf6_btn_font then imgui.push_font(sf6_btn_font) end

    if co then
        imgui.push_style_color(5, co.text)
        imgui.push_style_color(21, co.base)
        imgui.push_style_color(22, co.hover)
        imgui.push_style_color(23, co.active)
        imgui.push_style_color(0, co.border)
    elseif is_active then
        if label:upper():match("RECORD") or label:upper():match("SAVE") then
            imgui.push_style_color(5, 0xFFFFFFFF)
            imgui.push_style_color(21, 0xFF2222AA)
            imgui.push_style_color(22, 0xFF3333DD)
            imgui.push_style_color(23, 0xFF5555FF)
            imgui.push_style_color(0, 0xFFAAAAFF)
        else
            imgui.push_style_color(5, 0xFFFFFFFF)
            imgui.push_style_color(21, 0xFF228B22)
            imgui.push_style_color(22, 0xFF32CD32)
            imgui.push_style_color(23, 0xFF55FF55)
            imgui.push_style_color(0, 0xFFAAFFAA)
        end
    elseif is_disabled then
        imgui.push_style_color(5, 0xFFEEEEEE)
        imgui.push_style_color(21, 0xFF333333)
        imgui.push_style_color(22, 0xFF555555)
        imgui.push_style_color(23, 0xFF777777)
        imgui.push_style_color(0, 0xFF777777)
    else
        imgui.push_style_color(5, 0xFFFF33CC)
        imgui.push_style_color(21, 0xFF330055)
        imgui.push_style_color(22, 0xFF660088)
        imgui.push_style_color(23, 0xFF8822AA)
        imgui.push_style_color(0, 0xFFDDDDDD)
    end

    local clicked = imgui.button(label, Vector2f.new(width, 0))

    imgui.pop_style_color(5)
    if sf6_btn_font then imgui.pop_font() end
    return clicked
end

-- Utility function to calculate the width of the longest button
local function get_max_text_width(texts, is_floating)
    local use_custom = is_floating and sf6_btn_font
    if use_custom then imgui.push_font(sf6_btn_font) end
    local max_w = 0
    for _, text in ipairs(texts) do
        local w = imgui.calc_text_size(text).x
        if w > max_w then max_w = w end
    end
    if use_custom then imgui.pop_font() end
    return max_w + (use_custom and 30 or 15) -- Margins adjusted per mode
end



-- =========================================================
-- SWITCH POS LABEL (shows current state → next state)
-- =========================================================
local POS_LABELS = { "任意位置", "原始位置", "镜像位置" }
local function switch_pos_label()
    local cur = d2d_cfg.forced_position_idx or 1
    return POS_LABELS[cur] or "不重置"
end

-- =========================================================
-- SINGLE LINE MODE
-- =========================================================
local function draw_single_line_content()
    local sw, sh = ctx.cached_sw, ctx.cached_sh
    local w_width = imgui.get_window_size().x
    local win_h = imgui.get_window_size().y
    local sp = 4 * (sh / 1080.0)
    local pad_x = sw * 0.01
    local pad_y = sh * 0.01

    -- Widths excluding P2 buttons
    local rec_btn_w_base = get_max_text_width({ "停止并保存", "取消", "录制 P1", "录制 P2", "重置连段", "自动演示连段" }, true)
    local play_btn_w_base = get_max_text_width({ "开始训练", "返回", "镜像位置" }, true)

    local absolute_btn_w = math.max(rec_btn_w_base, play_btn_w_base)

    local arrow_margin = 0

    -- Dynamic layout: buttons = fixed text size, dropdown = remaining space
    local usable_w = w_width - (pad_x * 2) - (sp * 5)

    -- 1. Buttons take their natural text width (all same size, based on longest label)
    local actual_btn_w = absolute_btn_w

    -- 2. Dropdown keeps same size, idle buttons expand to fill the button area
    local return_gap = math.max(actual_btn_w / 3, sp * 5)
    local dd_w = usable_w - (actual_btn_w * 4) - return_gap
    if trial_state.is_playing then
        dd_w = dd_w - actual_btn_w - sp
    end
    if dd_w < 80 then dd_w = 80 end
    local idle_btn_w = (usable_w - dd_w) / 2

    local dynamic_rec_w = actual_btn_w
    local is_demo_active_early = (ctx.demo_state and ctx.demo_state.is_playing)
    local is_replay_mode = (_G.IsInReplay == true) or (_G.FlowMapID == 10) or (_G.IsInBattleHub == true)
    if trial_state.is_recording or is_demo_active_early or is_replay_mode then
        -- In record/demo/replay/spectate mode, distribute the massive 4-button space into 2
        dynamic_rec_w = (actual_btn_w * 4 + sp * 2) / 2
    end
    -- Fixed width for replay: always based on idle layout
    -- dd_P1 + sp + btn + sp + btn + sp + dd_P2 = usable_w
    local replay_btn_w = actual_btn_w
    local replay_dd_w = (usable_w - (replay_btn_w * 2) - (sp * 3)) / 2
    if replay_dd_w < 50 then replay_dd_w = 50 end

    -- No progress_bar background (causes ghost in ranked mode)

    imgui.set_cursor_pos(Vector2f.new(pad_x + arrow_margin, pad_y))

    local is_demo_active = (ctx.demo_state and ctx.demo_state.is_playing)
    local is_replay_rec_p1 = (trial_state.is_recording and trial_state.recording_player == 0 and is_replay_mode)
    local is_replay_rec_p2 = (trial_state.is_recording and trial_state.recording_player == 1 and is_replay_mode)

    -- === STATUS ENGINE (shared by replay and training) ===
    local now = update_replay_recording_status(is_replay_mode)

    if is_replay_mode then
        -- === REPLAY : status P1 | btn | btn | status P2 ===
        replay_status_label(0, replay_dd_w, now)
        imgui.same_line(0, sp)
        if trial_state.is_recording then
            if styled_sf6_button("停止并保存", true, replay_btn_w, true, false, TRIAL_COLORS) then _replay_save_player = trial_state.recording_player; stop_recording_and_save() end
            imgui.same_line(0, sp)
            if styled_sf6_button("取消", false, replay_btn_w, true, false, P1_COLORS) then
                local cp = trial_state.recording_player
                cancel_recording()
                if cp == 0 then _replay_status_p1 = "canceled" else _replay_status_p2 = "canceled" end
                _replay_saved_clock = os.clock()
            end
        else
            if styled_sf6_button("录制 P1", false, replay_btn_w, true, false, P1_COLORS) then _replay_save_player = 0; start_recording(0) end
            imgui.same_line(0, sp)
            if styled_sf6_button("录制 P2", false, replay_btn_w, true, false, P2_COLORS) then _replay_save_player = 1; start_recording(1) end
        end
        imgui.same_line(0, sp)
        replay_status_label(1, replay_dd_w, now)
    elseif trial_state.is_recording or (_replay_status_p1 ~= "waiting" and not is_replay_mode) then
        -- === TRAINING RECORD (or post-record animation) ===
        if trial_state.is_recording then
            _replay_status_p1 = "recording"
            _replay_save_player = trial_state.recording_player or 0
        end

        replay_status_label(0, dd_w, now)
        imgui.same_line(0, sp)
        if trial_state.is_recording then
            if styled_sf6_button("停止并保存", true, dynamic_rec_w, true, false, TRIAL_COLORS) then _replay_save_player = trial_state.recording_player; stop_recording_and_save() end
            imgui.same_line(0, sp)
            if styled_sf6_button("取消", false, dynamic_rec_w, true, false, P1_COLORS) then
                local cp = trial_state.recording_player
                cancel_recording()
                if cp == 0 then _replay_status_p1 = "canceled" else _replay_status_p2 = "canceled" end
                _replay_saved_clock = os.clock()
            end
        end
    elseif is_demo_active then
        -- === DEMO ===
        publish_top_combo_picker_left(dd_w, sp, pad_x + arrow_margin)
        draw_top_combo_picker("TopDemo", dd_w, sp)
        imgui.same_line(0, sp)
        if styled_sf6_button("重播演示", false, dynamic_rec_w, true, false, TRIAL_COLORS) then
            if ctx.start_demo then ctx.start_demo() end
        end
        imgui.same_line(0, sp)
        if styled_sf6_button("退出演示", false, dynamic_rec_w, true, false, P1_COLORS) then
            if ctx.stop_demo then ctx.stop_demo() end
        end
    else
        -- Normal / Playing mode: P1 dropdown + idle buttons, or playback controls
        publish_top_combo_picker_left(dd_w, sp, pad_x + arrow_margin)
        draw_top_combo_picker("TopNormal", dd_w, sp)
        imgui.same_line(0, sp)
        local btn_w = trial_state.is_playing and actual_btn_w or idle_btn_w
        if trial_state.is_playing then
            local note_label = (d2d_cfg.show_trial_notes == true) and "备注开" or "备注关"
            local note_colors = (d2d_cfg.show_trial_notes == true) and NOTE_ON_COLORS or NOTE_OFF_COLORS
            if styled_sf6_button(note_label, d2d_cfg.show_trial_notes == true, btn_w, true, false, note_colors) then
                d2d_cfg.show_trial_notes = not (d2d_cfg.show_trial_notes == true)
                ctx.save_d2d_config()
            end
            imgui.same_line(0, sp)
            if styled_sf6_button("重置连段", false, btn_w, true, false, P1_COLORS) then
                ctx.reset_trial_steps_and_load(trial_state.playing_player)
            end
        else
            if styled_sf6_button("录制连段", false, btn_w, true, false, P1_COLORS) then start_recording(0) end
        end

        if not trial_state.is_playing and not trial_state.is_recording then
            imgui.same_line(0, sp)
            local is_p1_active = (trial_state.is_playing and trial_state.playing_player == 0)
            if styled_sf6_button(is_p1_active and "停止训练" or "开始训练", is_p1_active, btn_w, true, false, TRIAL_COLORS) then
                if is_p1_active then trial_state.is_playing = false
                else load_and_start_trial(0) end
            end
        end

        if trial_state.is_playing then
            imgui.same_line(0, sp)
            if styled_sf6_button(switch_pos_label(), false, btn_w, true, false, SWITCH_COLORS) then
                d2d_cfg.forced_position_idx = d2d_cfg.forced_position_idx + 1
                if d2d_cfg.forced_position_idx > 3 then d2d_cfg.forced_position_idx = 1 end
                ctx.save_d2d_config()
                ctx.apply_forced_position()
                ctx.reset_trial_steps_and_load(trial_state.playing_player)
                if ctx.reset_visuals then ctx.reset_visuals() end
            end
            imgui.same_line(0, sp)
            local first_stun_step = trial_state.sequence and trial_state.sequence[1]
            local first_stun_gauges = type(first_stun_step) == "table" and first_stun_step.snapshot_gauges or nil
            local manual_stun_demo_required = type(first_stun_step) == "table"
                and first_stun_step.has_piyo == true
                and not (type(first_stun_gauges) == "table" and first_stun_gauges.defender_burnout == true)
            if manual_stun_demo_required and not _G._allow_stun_demo then
                imgui.push_style_color(21, 0xFF444444)
                imgui.push_style_color(22, 0xFF444444)
                imgui.push_style_color(23, 0xFF444444)
                styled_sf6_button("演示(晕厥)", false, btn_w, true, false, { base = 0x78444444, hover = 0x78444444, active = 0x78444444, text = 0xFF888888, border = 0xFF666666 })
                imgui.pop_style_color(3)
            else
                if styled_sf6_button("自动演示连段", false, btn_w, true, false, P2_COLORS) then
                    if ctx.start_demo then ctx.start_demo() end
                end
            end
            imgui.same_line(0, sp)
            local return_pos = imgui.get_cursor_pos()
            imgui.set_cursor_pos(Vector2f.new(return_pos.x + return_gap, return_pos.y))
            if styled_sf6_button("返回", true, btn_w, true, false, TRIAL_COLORS) then
                trial_state.is_playing = false
            end
        end

    end
end

local function draw_combo_trials_content(is_floating)
    local sw, sh = ctx.cached_sw, ctx.cached_sh
    local size = imgui.get_window_size()
    local w_width = (size.x > 50) and size.x or (sw * 0.44)

    local rec_btn_w_base = get_max_text_width({ "停止并保存", "取消", "录制 P1", "录制 P2", "重置连段", "自动演示连段" }, is_floating)
    local play_btn_w_base = get_max_text_width({ "开始训练", "返回", "镜像位置" }, is_floating)

    local absolute_btn_w = math.max(rec_btn_w_base, play_btn_w_base)
    local spacing_cols = 20 * (sh / 1080.0)
    local spacing_x = 8.0

    local min_inline_w = 150 + (absolute_btn_w * 2) + (spacing_cols * 3)
    local mode_all_inline = w_width >= min_inline_w
    local mode_all_stacked = w_width < (absolute_btn_w * 1.5)
    local mode_col2_3_inline = not mode_all_inline and not mode_all_stacked

    local rec_btn_w = absolute_btn_w
    local play_btn_w = absolute_btn_w

    local col3_x, col2_x, col1_w

    if mode_all_inline then
        if trial_state.is_recording then
            -- Record mode: Column 3 empty, Column 2 takes all remaining space
            col1_w = math.max(150, (w_width - (spacing_cols * 3)) / 3)
            col2_x = col1_w + spacing_cols
            col3_x = w_width -- Ignored
            rec_btn_w = w_width - col2_x - spacing_cols
        else
            col3_x = math.max(w_width - play_btn_w - spacing_cols, 10)
            col2_x = math.max(col3_x - rec_btn_w - spacing_cols, 10)
            col1_w = math.max(col2_x - spacing_cols, 150)
        end
    else
        col1_w = w_width - (40 * (sh / 1080.0))
        if mode_col2_3_inline then
            if trial_state.is_recording then
                -- Make recording buttons dynamically fill the entire column width
                rec_btn_w = col1_w
            else
                local half_w = (col1_w - spacing_x) / 2
                rec_btn_w = half_w
                play_btn_w = half_w
            end
        elseif mode_all_stacked then
            rec_btn_w = col1_w
            play_btn_w = col1_w
        end
    end

    -- =====================================
    -- Column 1: MANAGEMENT
    -- =====================================
    imgui.begin_group()
    if not is_floating then imgui.text_colored("1. 文件管理", COLORS.Cyan) end
    draw_combo_control_filter("Main", math.min(160, col1_w))
    imgui.spacing()

    -- DROPDOWN COMBO FILES (full width)
    if #file_system.saved_combos_display_p1 == 0 then
        imgui.push_item_width(col1_w)
        local empty_text = combo_empty_text("P1")
        imgui.combo("##EmptyP1", 1, { empty_text })
        imgui.pop_item_width()
    else
        local should_open = (_G.ComboTrials_OpenDropdown == true)
        local f1_changed, new_idx1 = combo_openable("##FilesP1", file_system.selected_file_idx_p1, file_system.saved_combos_display_p1, should_open, col1_w)
        if f1_changed then
            file_system.selected_file_idx_p1 = new_idx1
            load_and_start_trial(0)
        end
    end

    imgui.end_group()

    -- =====================================
    -- Column 2: RECORDING
    -- =====================================
    if mode_all_inline then imgui.same_line(col2_x) else imgui.spacing(); imgui.separator(); imgui.spacing() end

    imgui.begin_group()
    if not is_floating then imgui.text_colored("2. 录制", COLORS.White) end
    
    local is_demo_active = (ctx.demo_state and ctx.demo_state.is_playing)
    if trial_state.is_playing or is_demo_active then
        if styled_sf6_button("重置连段", false, rec_btn_w, is_floating) then
            if is_demo_active then
                if ctx.start_demo then ctx.start_demo() end
            else
                ctx.reset_trial_steps_and_load(trial_state.playing_player)
            end
        end
        if mode_all_stacked then imgui.spacing() end
        local first_stun_step = trial_state.sequence and trial_state.sequence[1]
        local first_stun_gauges = type(first_stun_step) == "table" and first_stun_step.snapshot_gauges or nil
        local manual_stun_demo_required = type(first_stun_step) == "table"
            and first_stun_step.has_piyo == true
            and not (type(first_stun_gauges) == "table" and first_stun_gauges.defender_burnout == true)
        if manual_stun_demo_required and not is_demo_active and not _G._allow_stun_demo then
            imgui.push_style_color(21, 0xFF444444)
            imgui.push_style_color(22, 0xFF444444)
            imgui.push_style_color(23, 0xFF444444)
            styled_sf6_button("演示(晕厥)", false, rec_btn_w, is_floating, false, { base = 0x78444444, hover = 0x78444444, active = 0x78444444, text = 0xFF888888, border = 0xFF666666 })
            imgui.pop_style_color(3)
        elseif styled_sf6_button("自动演示连段", is_demo_active, rec_btn_w, is_floating, false, P2_COLORS) then
            if is_demo_active then
                if ctx.stop_demo then ctx.stop_demo() end
            else
                if ctx.start_demo then ctx.start_demo() end
            end
        end
    elseif trial_state.is_recording then
        if styled_sf6_button("停止并保存", true, rec_btn_w, is_floating, false, TRIAL_COLORS) then
            stop_recording_and_save()
        end

        -- Always force stacking with spacing in windowed mode
        imgui.spacing()

        if styled_sf6_button("取消", false, rec_btn_w, is_floating, false, P1_COLORS) then
            cancel_recording()
        end
    else
        if styled_sf6_button("录制 P1", false, rec_btn_w, is_floating, false, P1_COLORS) then
            start_recording(0)
        end
        if mode_all_stacked then imgui.spacing() end
        if styled_sf6_button("录制 P2", false, rec_btn_w, is_floating, false, P2_COLORS) then
            start_recording(1)
        end
    end
    imgui.end_group()

    -- =====================================
    -- Column 3: PLAYBACK
    -- =====================================
    if mode_all_stacked then imgui.spacing(); imgui.separator(); imgui.spacing()
    elseif mode_col2_3_inline then imgui.same_line(0, spacing_x)
    else imgui.same_line(col3_x) end

    imgui.begin_group()
    if not is_floating then imgui.text_colored("3. 播放连段", COLORS.White) end

    if trial_state.is_playing or is_demo_active then
        if styled_sf6_button("返回", true, play_btn_w, is_floating, false, TRIAL_COLORS) then
            trial_state.is_playing = false
            if ctx.stop_demo then ctx.stop_demo() end
        end
    elseif not trial_state.is_recording then
        local is_p1_active = (trial_state.is_playing and trial_state.playing_player == 0)
        if styled_sf6_button(is_p1_active and "停止训练" or "开始训练", is_p1_active, play_btn_w, is_floating, false, TRIAL_COLORS) then
            if is_p1_active then trial_state.is_playing = false
            else load_and_start_trial(0) end
        end
    end
    
    if mode_all_stacked then imgui.spacing() end
    
    -- SWITCH POS (Hidden until playback/demo starts)
    if not trial_state.is_recording and (trial_state.is_playing or is_demo_active) then
        if styled_sf6_button(switch_pos_label(), false, play_btn_w, is_floating, false, SWITCH_COLORS) then
            d2d_cfg.forced_position_idx = d2d_cfg.forced_position_idx + 1
            if d2d_cfg.forced_position_idx > 3 then d2d_cfg.forced_position_idx = 1 end
            ctx.save_d2d_config()
            
            local is_demo_active = (ctx.demo_state and ctx.demo_state.is_playing)
            -- Only physically apply position if a trial or demo is active
            if d2d_cfg.forced_position_idx == 1 or is_demo_active or trial_state.is_playing then
                ctx.apply_forced_position()
                if is_demo_active then
                    if ctx.start_demo then ctx.start_demo() end
                elseif trial_state.is_playing then
                    if ctx.reset_trial_steps_and_load then ctx.reset_trial_steps_and_load(trial_state.playing_player) end
                end
                if ctx.reset_visuals then ctx.reset_visuals() end
            end
        end
    end
    imgui.end_group()
    imgui.spacing()
end

-- =========================================================
-- STANDALONE FLOATING WINDOW RENDERING (In re.on_frame)
-- =========================================================
-- sf6_menu_state is received from ctx in init()

local function _ctui_get_x(v) return v.x end
local function _ctui_get_y(v) return v.y end

local function get_imgui_screen_size()
    local result = imgui.get_display_size()
    local w, h = 0, 0
    if type(result) == "userdata" then
        local ok, x = pcall(_ctui_get_x, result)
        local ok2, y = pcall(_ctui_get_y, result)
        if ok and ok2 then
            w = x; h = y
        else
            w = result.w or 0; h = result.h or 0
        end
    elseif type(result) == "number" then
        w, h = imgui.get_display_size()
    end
    return w, h
end

local ui_dirty = false
local ui_save_timer = 0
local ui_dirty_age = 0
local ui_save_retry_timer = 0
local D2D_SAVE_DEBOUNCE_FRAMES = 60
local D2D_SAVE_MAX_DIRTY_FRAMES = 60
local last_sw, last_sh = 0, 0
local res_cooldown = 0
local force_float_resize = 0

local _was_bars_drawn = true

local function _ctui_mark_d2d_dirty()
    if not ui_dirty then ui_dirty_age = 0 end
    ui_dirty = true
    ui_save_timer = 0
end

local function _ctui_flush_d2d_config()
    if not ui_dirty or not save_d2d_config then return true end
    local ok, saved = pcall(save_d2d_config)
    if ok and saved then
        ui_dirty = false
        ui_save_timer = 0
        ui_dirty_age = 0
        ui_save_retry_timer = 0
        return true
    end
    ui_save_timer = 0
    ui_dirty_age = 0
    ui_save_retry_timer = D2D_SAVE_DEBOUNCE_FRAMES
    return false
end

local function _ctui_flush_d2d_config_for_exit()
    if not ui_dirty then return true end
    if ui_save_retry_timer > 0 then
        ui_save_retry_timer = ui_save_retry_timer - 1
        if ui_save_retry_timer > 0 then
            return false
        end
    end
    return _ctui_flush_d2d_config()
end

local function _ctui_tick_d2d_save()
    if not ui_dirty then return end
    if ui_save_retry_timer > 0 then
        ui_save_retry_timer = ui_save_retry_timer - 1
        if ui_save_retry_timer > 0 then
            return
        end
        _ctui_flush_d2d_config()
        return
    end
    ui_save_timer = ui_save_timer + 1
    ui_dirty_age = ui_dirty_age + 1
    if ui_save_timer >= D2D_SAVE_DEBOUNCE_FRAMES or ui_dirty_age >= D2D_SAVE_MAX_DIRTY_FRAMES then
        _ctui_flush_d2d_config()
    end
end

local function _ctui_flush_trial_display()
    local ts = ctx and ctx.trial_state
    if ts then
        if ts._xt_pending_save then return end
        if ts.is_recording or ts.is_playing then return end
        ts.is_playing = false
        ts.sequence = {}
        ts.current_step = 1
    end
end

local function _ctui_hide_visual_state()
    sf6_menu_state.active = false
    _G.ComboTrials_HideNativeHUD = false
    _G.ComboTrialsD2DEnabled = false
    _G._ct_bar_geometry = nil
    _G.TrainingBarsDrawn = false
end

local function _ctui_clear_visual_state()
    _ctui_hide_visual_state()
    if ctx and ctx.trial_state and not ctx.trial_state._xt_pending_save then
        ctx.trial_state.is_playing = false
        ctx.trial_state.is_recording = false
    end
    pcall(_ctui_flush_trial_display)
end

local function _ctui_cancel_recording_for_menu(reason)
    if not trial_state or not trial_state.is_recording then return false end

    if cancel_recording_due_to_menu then
        local ok, canceled = pcall(cancel_recording_due_to_menu, reason or "menu")
        if ok and canceled then return true end
    end

    local cp = trial_state.recording_player
    if cancel_recording then cancel_recording() end
    _G.ComboTrials_SaveFailedPlayer = nil
    _G.ComboTrials_ReplaySavePlayer = nil
    _G.ComboTrials_PendingSaveCanceled = cp
    return true
end

re.on_frame(function()
    if not RuntimeSafety.is_allowed() then
        _ctui_flush_d2d_config_for_exit()
        _ctui_clear_visual_state()
        return
    end
    -- Detect return from ranked: flush combo display
    local bars_now = _G.TrainingBarsDrawn
    if bars_now and not _was_bars_drawn then
        pcall(_ctui_flush_trial_display)
    end
    _was_bars_drawn = bars_now

    local is_game_active = false
    local is_pause_menu = false
    local pm = sdk.get_managed_singleton("app.PauseManager")
    if pm then
        local b = pm:get_field("_CurrentPauseTypeBit")
        if b == 64 or b == 2112 then
            is_game_active = true
        elseif b ~= nil then
            is_pause_menu = true
        end
    end
    if is_pause_menu then
        _ctui_cancel_recording_for_menu("pause_menu")
    end

    local is_replay_context = (_G.FlowMapID == 10) or (_G.IsInReplay == true) or (_G.IsInBattleHub == true)
    if not is_replay_context and _G.CurrentTrainerMode ~= 4 then
        if _ctui_cancel_recording_for_menu("mode_exit") then
            _ctui_flush_d2d_config_for_exit()
            _ctui_hide_visual_state()
        else
            _ctui_clear_visual_state()
        end
        return
    end
    if not is_replay_context and _G.TrainingScriptManagerActiveThisFrame ~= true then
        if is_pause_menu or _ctui_cancel_recording_for_menu("ui_inactive") then
            _ctui_flush_d2d_config_for_exit()
            _ctui_hide_visual_state()
        else
            _ctui_clear_visual_state()
        end
        return
    end

    local in_training_context = (_G.CurrentTrainerMode == 4) and (_G.TrainingModeActive == true) and (is_replay_context or _G.TrainingScriptManagerActiveThisFrame == true)
    local should_enable_ct_ui = in_training_context and is_game_active
    _G.ComboTrialsD2DEnabled = should_enable_ct_ui
    if not should_enable_ct_ui then
        _ctui_flush_d2d_config_for_exit()
        if is_pause_menu or _ctui_cancel_recording_for_menu("ui_hidden") then
            _ctui_hide_visual_state()
        else
            _ctui_clear_visual_state()
        end
        return
    end

    -- Use exact ImGui API for window positioning
    local sw, sh = get_imgui_screen_size()
    if sw == nil or sh == nil or sw <= 0 or sh <= 0 then
        _ctui_flush_d2d_config_for_exit()
        return
    end

    -- DETECTION AND COOLDOWN
    local res_changed = false
    if last_sw ~= sw or last_sh ~= sh then
        if last_sw ~= 0 then
            res_changed = true
            res_cooldown = 5 -- Freeze position for 5 frames
        end
        last_sw = sw
        last_sh = sh
    end

    if res_cooldown > 0 then res_cooldown = res_cooldown - 1 end
    local is_resizing = (res_changed or res_cooldown > 0)

    if not d2d_cfg.float_pos then d2d_cfg.float_pos = { x = 0.0, y = 0.2 } end
    if not d2d_cfg.float_size then d2d_cfg.float_size = { w = 1.0, h = 0.20 } end
    -- Force full screen width
    d2d_cfg.float_pos.x = 0.0
    d2d_cfg.float_size.w = 1.0

    -- FONT RELOAD (Only on the exact frame of change)
    if not font_attempted or res_changed then
        local font_scale = sh / 1080.0
        pcall(function()
            custom_ui_font = imgui.load_font("msyh.ttc",
                math.max(10, math.floor(20 * font_scale)))
        end)
        pcall(function() sf6_btn_font = imgui.load_font("msyhbd.ttc", math.max(10, math.floor(22 * font_scale))) end)
        local hud_size = math.max(10, math.floor((d2d_cfg.hud_font_size or 20) * font_scale))
        pcall(function() hud_overlay_font = imgui.load_font("msyhbd.ttc", hud_size) end)
        font_attempted = true
    end

    -- ComboTrials no longer uses the center HUD overlay; native training info stays visible.
    _G.ComboTrials_HideNativeHUD = false

    if not is_game_active then sf6_menu_state.active = false end
    if show_trial_overlay and is_game_active then
        sf6_menu_state.active = true

        -- Collapse toggle (replay only)
        local is_replay_ctx = (_G.IsInReplay == true) or (_G.IsInBattleHub == true)
        if _G._ct_bar_collapsed == nil then _G._ct_bar_collapsed = false end
        if not is_replay_ctx then _G._ct_bar_collapsed = false end

        if not d2d_cfg.bar_width_pct then d2d_cfg.bar_width_pct = 1.0 end
        local target_w = sw * d2d_cfg.bar_width_pct
        local target_h = sh * 0.0444
        local target_x = (sw - target_w) * 0.5

        -- Publish geometry for D2D arrows (replay only)
        if is_replay_ctx then
            _G._ct_bar_geometry = { x = target_x, y = sh - target_h, w = target_w, h = target_h }
        else
            _G._ct_bar_geometry = nil
        end

        if _G._tsm_hide_ui or (_G._ct_bar_collapsed and is_replay_ctx) then
            _G.TrainingBarsDrawn = true
            sf6_menu_state.active = false
            _ctui_flush_d2d_config_for_exit()
            return
        end

        local SharedUI = require("func/Training_SharedUI")
        local bar_colors = SharedUI.neon_colors
        imgui.push_style_color(2, bar_colors.bg)      -- WindowBg
        imgui.push_style_color(5, bar_colors.border)  -- Border
        imgui.push_style_color(7, 0x00000000)   -- FrameBg transparent
        imgui.push_style_color(8, 0x00000000)   -- TitleBg transparent
        imgui.push_style_var(4, 1.0)            -- WindowBorderSize
		imgui.push_style_var(2, Vector2f.new(sw * 0.01, sh * 0.02))

        -- Centered, fixed at bottom
        imgui.set_next_window_size(Vector2f.new(target_w, target_h), 1)  -- 1 = Always
        imgui.set_next_window_pos(Vector2f.new(target_x, sh - target_h), 1)  -- 1 = Always

        if custom_ui_font then imgui.push_font(custom_ui_font) end

        -- 15 = NoTitleBar(1) + NoResize(2) + NoMove(4) + NoScrollbar(8)
        local visible = imgui.begin_window("ComboTrialsFloating", true, 15)

        local pos = imgui.get_window_pos()
        local size = imgui.get_window_size()
        _G.TrainingBarsDrawn = true

        -- SAVE BLOCKED DURING COOLDOWN (Prevents coordinate corruption)
        if size.x > 0 and size.y > 0 and not is_resizing then
            local norm_x = pos.x / sw
            local norm_y = pos.y / sh
            local norm_w = size.x / sw
            local norm_h = size.y / sh

            if math.abs(norm_x - d2d_cfg.float_pos.x) > 0.001 or math.abs(norm_y - d2d_cfg.float_pos.y) > 0.001 or
                math.abs(norm_w - d2d_cfg.float_size.w) > 0.001 or math.abs(norm_h - d2d_cfg.float_size.h) > 0.001 then
                d2d_cfg.float_pos.x = norm_x
                d2d_cfg.float_pos.y = norm_y
                d2d_cfg.float_size.w = norm_w
                d2d_cfg.float_size.h = norm_h
                _ctui_mark_d2d_dirty()
            end
        end

        sf6_menu_state.x = pos.x
        sf6_menu_state.y = pos.y
        sf6_menu_state.w = size.x
        sf6_menu_state.h = size.y

        if visible then
            local w_width = size.x

            -- Calculate single-line threshold
            local rec_btn_w_check = get_max_text_width({ "停止并保存", "取消", "录制 P1", "录制 P2" }, true)
            local play_btn_w_check = get_max_text_width({ "开始训练", "返回" }, true)
            local min_single_line_w = 200 + (rec_btn_w_check + play_btn_w_check) * 2 + 150 * (sh / 1080.0)

            if w_width >= min_single_line_w then
                -- SINGLE LINE: No header, everything directly on the dark area
                draw_single_line_content()
            else
                -- NORMAL MODE: Header + standard content
                -- Calculate exact actual width to synchronize header transition with UI layout
                local rec_btn_w_base = get_max_text_width({ "停止并保存", "取消", "录制 P1", "录制 P2", "重置连段", "自动演示连段" }, true)
                local play_btn_w_base = get_max_text_width({ "开始训练", "返回", "镜像位置" }, true)
                local absolute_btn_w = math.max(rec_btn_w_base, play_btn_w_base)
                local spacing_cols = 20 * (sh / 1080.0)

                local min_inline_w = 150 + (absolute_btn_w * 2) + (spacing_cols * 3)
                local mode_all_inline = w_width >= min_inline_w
                local mode_all_stacked = w_width < (absolute_btn_w * 1.5)
                local mode_col2_3_inline = not mode_all_inline and not mode_all_stacked

                local header_txt = "连段训练：回放与录制设置"
                if mode_all_stacked then
                    header_txt = "连段训练"
                elseif mode_col2_3_inline then
                    header_txt = "连段训练 设置"
                end

                local cb_width = 35 * (sh / 1080.0)
                local cb_x = w_width - cb_width / 4 - (sw * 0.015)

                local txt_size = imgui.calc_text_size(header_txt)
                local txt_w = txt_size.x
                local txt_h = txt_size.y

                local header_box_h = txt_h + (sh * 0.02)
                local title_x = (w_width - txt_w) / 2

                if (title_x + txt_w) > (cb_x - 15) then
                    title_x = (cb_x - txt_w) / 2
                    if title_x < 5 then title_x = 5 end
                end

                local items_y = (header_box_h - txt_h) / 2
                imgui.set_cursor_pos(Vector2f.new(title_x, items_y))
                imgui.text_colored(header_txt, 0xFFFFFFFF)

                imgui.set_cursor_pos(Vector2f.new(cb_x - 15, 0))
                imgui.push_style_color(7, 0xFF58002C)
                local mask_size = Vector2f.new(w_width, header_box_h)
                if not pcall(imgui.progress_bar, 0.0, mask_size) then
                    pcall(imgui.progress_bar, 0.0, mask_size, "")
                end
                imgui.pop_style_color(1)

                imgui.set_cursor_pos(Vector2f.new(cb_x, items_y))
                local changed, new_val = imgui.checkbox("##close_float", show_trial_overlay)
                if changed then show_trial_overlay = new_val end

                imgui.set_cursor_pos(Vector2f.new(0, header_box_h))
                imgui.spacing(); imgui.separator(); imgui.spacing()

                draw_combo_trials_content(true)
            end
        end

        imgui.end_window()

        if custom_ui_font then imgui.pop_font() end
        imgui.pop_style_color(4)
		imgui.pop_style_var(2)  -- WindowPadding + WindowBorderSize
    else
        sf6_menu_state.active = false
    end

    _ctui_tick_d2d_save()
end)

if re.on_script_reset then
    re.on_script_reset(function()
        _ctui_flush_d2d_config()
    end)
end

-- =========================================================
-- GLOBAL UI MENU DRAWING
-- =========================================================
local function _ctui_draw_live_positions()
    local gB = sdk.find_type_definition("gBattle")
    if not gB then return end
    local sP = gB:get_field("Player"):get_data(nil)
    if not sP or not sP.mcPlayer then return end
    local p1x = sP.mcPlayer[0].pos.x.v or 0
    local p2x = sP.mcPlayer[1].pos.x.v or 0
    imgui.indent(20)
    imgui.text(string.format("P1: %d  (%.2f cm)", p1x, p1x / 65536.0))
    imgui.text(string.format("P2: %d  (%.2f cm)", p2x, p2x / 65536.0))
    imgui.unindent(20)
end

local function draw_combo_trials_menu_ui()
    if not RuntimeSafety.is_training_allowed() then return end
    if _G.CurrentTrainerMode ~= 4 then return end
    if imgui.tree_node("连段训练设置v0.9a") then
        local ok, err = pcall(function()
        local p_state = players[ui_state.viewed_player]
        imgui.spacing()

        -- ==========================================
        -- TAB 1: GLOBAL COMBO TRIAL (Shared P1/P2)
        -- ==========================================
        if styled_header("--- 连段训练（文件与播放）---", UI_THEME.hdr_info) then
            local changed, new_val = imgui.checkbox("分离为浮动窗口", show_trial_overlay)
            if changed then show_trial_overlay = new_val end

            if not show_trial_overlay then
                imgui.separator()
                imgui.spacing()
                draw_combo_trials_content(false)
            else
                imgui.separator()
                imgui.text_colored("当前已被分离为浮动窗口。", COLORS.DarkGrey)
                imgui.spacing()
            end
            local asd_c, asd_v = imgui.checkbox("允许晕厥连段使用演示", _G._allow_stun_demo or false)
            if asd_c then _G._allow_stun_demo = asd_v end
        end

        -- ==========================================
        -- TAB 2: D2D VISUALIZER
        -- ==========================================
        if styled_header("--- D2D 可视化设置（覆盖层）---", UI_THEME.hdr_matrix) then
            local changed = false
            local c, v

            c, v = imgui.checkbox("启用 D2D 覆盖层", d2d_cfg.enabled); if c then
                d2d_cfg.enabled = v; changed = true
            end
            c, v = imgui.checkbox("忽略自动动作（灰色）", d2d_cfg.ignore_auto); if c then
                d2d_cfg.ignore_auto = v; changed = true
            end

            if d2d_cfg.ghost_filter_frames == nil then d2d_cfg.ghost_filter_frames = 4 end
            c, v = imgui.drag_int("误输入过滤（帧）", d2d_cfg.ghost_filter_frames, 1, 0, 10); if c then
                d2d_cfg.ghost_filter_frames = v; changed = true
            end
            if imgui.is_item_hovered() then
                imgui.set_tooltip(
                    "忽略持续少于 X 帧的快速重叠输入。\n可减少 214+PP 前一瞬间被误判为 214+P。\n设为 0 可关闭。推荐：3-4。")
            end


            c, v = imgui.checkbox("显示连段计数", d2d_cfg.show_combo_count); if c then
                d2d_cfg.show_combo_count = v; changed = true
            end
            imgui.spacing()

            imgui.text_colored("--- 实时日志（录制 / 连段中）---", COLORS.Cyan)

            c, v = imgui.checkbox("显示 P1##trial", d2d_cfg.show_p1); if c then d2d_cfg.show_p1 = v; changed = true end
            imgui.same_line()
            c, v = imgui.checkbox("原始输入##trial_p1", d2d_cfg.raw_p1 or false); if c then d2d_cfg.raw_p1 = v; changed = true end
            imgui.same_line()
            c, v = imgui.checkbox("镜像##trial_p1", d2d_cfg.mirror_p1 or false); if c then d2d_cfg.mirror_p1 = v; changed = true end
            if not d2d_cfg.raw_pos_p1 then d2d_cfg.raw_pos_p1 = { x = 0.050, y = 0.350 } end
            local tp1 = d2d_cfg.raw_p1 and d2d_cfg.raw_pos_p1 or d2d_cfg.pos_p1
            local tp1_lbl = d2d_cfg.raw_p1 and "原始 " or ""
            c, v = imgui.drag_float(tp1_lbl .. "P1 X##trial", tp1.x, 0.005, 0.0, 1.0); if c then tp1.x = v; changed = true end
            c, v = imgui.drag_float(tp1_lbl .. "P1 Y##trial", tp1.y, 0.005, 0.0, 1.0); if c then tp1.y = v; changed = true end
            if d2d_cfg.mirror_p1 then imgui.text_colored("  (镜像: X=" .. string.format("%.3f", 1.0 - tp1.x) .. ")", 0xFFAAAAAA) end

            c, v = imgui.checkbox("显示 P2##trial", d2d_cfg.show_p2); if c then d2d_cfg.show_p2 = v; changed = true end
            imgui.same_line()
            c, v = imgui.checkbox("原始输入##trial_p2", d2d_cfg.raw_p2 or false); if c then d2d_cfg.raw_p2 = v; changed = true end
            imgui.same_line()
            c, v = imgui.checkbox("镜像##trial_p2", d2d_cfg.mirror_p2 or false); if c then d2d_cfg.mirror_p2 = v; changed = true end
            if not d2d_cfg.raw_pos_p2 then d2d_cfg.raw_pos_p2 = { x = 0.850, y = 0.350 } end
            local tp2 = d2d_cfg.raw_p2 and d2d_cfg.raw_pos_p2 or d2d_cfg.pos_p2
            local tp2_lbl = d2d_cfg.raw_p2 and "原始 " or ""
            c, v = imgui.drag_float(tp2_lbl .. "P2 X##trial", tp2.x, 0.005, 0.0, 1.0); if c then tp2.x = v; changed = true end
            c, v = imgui.drag_float(tp2_lbl .. "P2 Y##trial", tp2.y, 0.005, 0.0, 1.0); if c then tp2.y = v; changed = true end
            if d2d_cfg.mirror_p2 then imgui.text_colored("  (镜像: X=" .. string.format("%.3f", 1.0 - tp2.x) .. ")", 0xFFAAAAAA) end

            local t_raw_any = d2d_cfg.raw_p1 or d2d_cfg.raw_p2
            local t_max_key = t_raw_any and "raw_max_history" or "max_history"
            local t_max_lbl = t_raw_any and "原始输入最大历史##trial" or "最大历史##trial"
            if not d2d_cfg.raw_max_history then d2d_cfg.raw_max_history = 19 end
            local c_max, v_max = imgui.drag_int(t_max_lbl, d2d_cfg[t_max_key] or 10, 1, 1, 30); if c_max then
                d2d_cfg[t_max_key] = v_max; changed = true
            end
            imgui.spacing()

            imgui.text_colored("--- 实时日志（空闲 / 无连段）---", COLORS.Cyan)

            c, v = imgui.checkbox("显示 P1##idle", d2d_cfg.idle_show_p1); if c then d2d_cfg.idle_show_p1 = v; changed = true end
            imgui.same_line()
            c, v = imgui.checkbox("原始输入##idle_p1", d2d_cfg.idle_raw_p1 or false); if c then d2d_cfg.idle_raw_p1 = v; changed = true end
            imgui.same_line()
            c, v = imgui.checkbox("镜像##idle_p1", d2d_cfg.idle_mirror_p1 or false); if c then d2d_cfg.idle_mirror_p1 = v; changed = true end
            if not d2d_cfg.idle_raw_p1 then
                c, v = imgui.drag_float("P1 X##idle", d2d_cfg.idle_pos_p1.x, 0.005, 0.0, 1.0); if c then d2d_cfg.idle_pos_p1.x = v; changed = true end
                c, v = imgui.drag_float("P1 Y##idle", d2d_cfg.idle_pos_p1.y, 0.005, 0.0, 1.0); if c then d2d_cfg.idle_pos_p1.y = v; changed = true end
                if d2d_cfg.idle_mirror_p1 then imgui.text_colored("  (镜像: X=" .. string.format("%.3f", 1.0 - d2d_cfg.idle_pos_p1.x) .. ")", 0xFFAAAAAA) end
            else
                imgui.text_colored("  (位置来自连段原始输入 P1)", 0xFFAAAAAA)
                if d2d_cfg.idle_mirror_p1 then
                    local src = d2d_cfg.raw_pos_p1 or d2d_cfg.pos_p1
                    imgui.text_colored("  (镜像: X=" .. string.format("%.3f", 1.0 - (src.x or 0.050)) .. ")", 0xFFAAAAAA)
                end
            end

            c, v = imgui.checkbox("显示 P2##idle", d2d_cfg.idle_show_p2); if c then d2d_cfg.idle_show_p2 = v; changed = true end
            imgui.same_line()
            c, v = imgui.checkbox("原始输入##idle_p2", d2d_cfg.idle_raw_p2 or false); if c then d2d_cfg.idle_raw_p2 = v; changed = true end
            imgui.same_line()
            c, v = imgui.checkbox("镜像##idle_p2", d2d_cfg.idle_mirror_p2 or false); if c then d2d_cfg.idle_mirror_p2 = v; changed = true end
            if not d2d_cfg.idle_raw_p2 then
                c, v = imgui.drag_float("P2 X##idle", d2d_cfg.idle_pos_p2.x, 0.005, 0.0, 1.0); if c then d2d_cfg.idle_pos_p2.x = v; changed = true end
                c, v = imgui.drag_float("P2 Y##idle", d2d_cfg.idle_pos_p2.y, 0.005, 0.0, 1.0); if c then d2d_cfg.idle_pos_p2.y = v; changed = true end
                if d2d_cfg.idle_mirror_p2 then imgui.text_colored("  (镜像: X=" .. string.format("%.3f", 1.0 - d2d_cfg.idle_pos_p2.x) .. ")", 0xFFAAAAAA) end
            else
                imgui.text_colored("  (位置来自连段原始输入 P2)", 0xFFAAAAAA)
                if d2d_cfg.idle_mirror_p2 then
                    local src = d2d_cfg.raw_pos_p2 or d2d_cfg.pos_p2
                    imgui.text_colored("  (镜像: X=" .. string.format("%.3f", 1.0 - (src.x or 0.850)) .. ")", 0xFFAAAAAA)
                end
            end

            local i_raw_any = d2d_cfg.idle_raw_p1 or d2d_cfg.idle_raw_p2
            local i_max_key = i_raw_any and "idle_raw_max_history" or "idle_max_history"
            local i_max_lbl = i_raw_any and "原始输入最大历史##idle" or "最大历史##idle"
            if not d2d_cfg.idle_raw_max_history then d2d_cfg.idle_raw_max_history = 19 end
            local c_imax, v_imax = imgui.drag_int(i_max_lbl, d2d_cfg[i_max_key] or 10, 1, 1, 30); if c_imax then
                d2d_cfg[i_max_key] = v_imax; changed = true
            end

            -- Raw Input Settings (shown only when at least one raw checkbox is active)
            local any_raw = (d2d_cfg.raw_p1 or d2d_cfg.raw_p2 or d2d_cfg.idle_raw_p1 or d2d_cfg.idle_raw_p2)
            if any_raw then
                imgui.spacing()
                imgui.text_colored("--- 原始输入显示设置 ---", COLORS.Cyan)
                if not d2d_cfg.raw then d2d_cfg.raw = {} end
                local rc = d2d_cfg.raw
                c, v = imgui.drag_float("原始输入图标大小", rc.icon_size or 0.030, 0.001, 0.01, 0.1, "%.3f"); if c then rc.icon_size = v; changed = true end
                c, v = imgui.drag_float("原始输入字体大小", rc.font_size or 0.028, 0.001, 0.01, 0.1, "%.3f"); if c then rc.font_size = v; changed = true end
                c, v = imgui.drag_float("原始输入行间距", rc.spacing_y or 0.040, 0.001, 0.01, 0.1, "%.3f"); if c then rc.spacing_y = v; changed = true end
                c, v = imgui.drag_float("原始输入文字 Y 偏移", rc.text_y_offset or 0.002, 0.0005, -0.02, 0.02, "%.4f"); if c then rc.text_y_offset = v; changed = true end
                c, v = imgui.drag_float("原始输入帧数列", rc.col_frame or 0.000, 0.005, -0.2, 0.5, "%.3f"); if c then rc.col_frame = v; changed = true end
                c, v = imgui.drag_float("原始输入方向列", rc.col_dir or 0.050, 0.005, -0.2, 0.5, "%.3f"); if c then rc.col_dir = v; changed = true end
                c, v = imgui.drag_float("原始输入槽位 1", rc.slot1 or 0.100, 0.005, 0.0, 0.5, "%.3f"); if c then rc.slot1 = v; changed = true end
                c, v = imgui.drag_float("原始输入槽位 2", rc.slot2 or 0.140, 0.005, 0.0, 0.5, "%.3f"); if c then rc.slot2 = v; changed = true end
                c, v = imgui.drag_float("原始输入槽位 3", rc.slot3 or 0.180, 0.005, 0.0, 0.5, "%.3f"); if c then rc.slot3 = v; changed = true end
                c, v = imgui.drag_float("原始输入槽位 4", rc.slot4 or 0.220, 0.005, 0.0, 0.5, "%.3f"); if c then rc.slot4 = v; changed = true end
                c, v = imgui.drag_float("原始输入槽位 5", rc.slot5 or 0.260, 0.005, 0.0, 0.5, "%.3f"); if c then rc.slot5 = v; changed = true end
                c, v = imgui.drag_float("原始输入槽位 6", rc.slot6 or 0.300, 0.005, 0.0, 0.5, "%.3f"); if c then rc.slot6 = v; changed = true end
            end

            -- NEW: Trial Box Position & Height
            imgui.separator()

            imgui.text_colored("--- 连段框位置与尺寸 ---", COLORS.Cyan)
            c, v = imgui.drag_float("连段框 P1 X", d2d_cfg.pos_trial_p1.x, 0.005, 0.0, 1.0); if c then
                d2d_cfg.pos_trial_p1.x = v; changed = true
            end
            c, v = imgui.drag_float("连段框 P1 Y", d2d_cfg.pos_trial_p1.y, 0.005, 0.0, 1.0); if c then
                d2d_cfg.pos_trial_p1.y = v; changed = true
            end
            c, v = imgui.drag_float("连段框 P2 X", d2d_cfg.pos_trial_p2.x, 0.005, 0.0, 1.0); if c then
                d2d_cfg.pos_trial_p2.x = v; changed = true
            end
            c, v = imgui.drag_float("连段框 P2 Y", d2d_cfg.pos_trial_p2.y, 0.005, 0.0, 1.0); if c then
                d2d_cfg.pos_trial_p2.y = v; changed = true
            end
            c, v = imgui.drag_float("连段框高度", d2d_cfg.cartouche_height, 0.01, 0.1, 3.0); if c then
                d2d_cfg.cartouche_height = v; changed = true
            end
            c, v = imgui.drag_float("连段框宽度", d2d_cfg.cartouche_width, 0.005, 0.1, 1.0); if c then
                d2d_cfg.cartouche_width = v; changed = true
            end
            c, v = imgui.drag_float("框偏移 X", d2d_cfg.cartouche_offset_x, 0.001, -0.1, 0.1); if c then
                d2d_cfg.cartouche_offset_x = v; changed = true
            end
            c, v = imgui.drag_float("框偏移 Y", d2d_cfg.cartouche_offset_y, 0.001, -0.1, 0.1); if c then
                d2d_cfg.cartouche_offset_y = v; changed = true
            end
            c, v = imgui.drag_float("底栏图片 X 偏移", d2d_cfg.bar_img_offset_x, 0.001, -0.1, 0.1); if c then
                d2d_cfg.bar_img_offset_x = v; changed = true
            end
            c, v = imgui.drag_float("底栏图片 Y 偏移", d2d_cfg.bar_img_offset_y, 0.001, -0.1, 0.1); if c then
                d2d_cfg.bar_img_offset_y = v; changed = true
            end
            c, v = imgui.drag_int("可见连段行数", d2d_cfg.trial_visible_steps, 1, 1, 30); if c then
                d2d_cfg.trial_visible_steps = v; changed = true
            end
            if not d2d_cfg.bar_width_pct then d2d_cfg.bar_width_pct = 1.0 end
            c, v = imgui.drag_float("底部栏宽度", d2d_cfg.bar_width_pct, 0.01, 0.3, 1.0, "%.2f"); if c then
                d2d_cfg.bar_width_pct = v; changed = true
            end
            imgui.separator()


            if d2d_cfg.trial_title_show == nil then d2d_cfg.trial_title_show = true end
            c, v = imgui.checkbox("显示连段中文标题", d2d_cfg.trial_title_show); if c then
                d2d_cfg.trial_title_show = v; changed = true
            end
            if d2d_cfg.show_trial_notes == nil then d2d_cfg.show_trial_notes = false end
            c, v = imgui.checkbox("显示备注", d2d_cfg.show_trial_notes); if c then
                d2d_cfg.show_trial_notes = v; changed = true
            end
            if d2d_cfg.auto_next_trial == nil then d2d_cfg.auto_next_trial = true end
            c, v = imgui.checkbox("成功后自动进入下一个连段", d2d_cfg.auto_next_trial); if c then
                d2d_cfg.auto_next_trial = v; changed = true
            end
            imgui.same_line()
            if imgui.button("清除完成标记") and ctx.clear_completed_trials then
                ctx.clear_completed_trials()
            end
            c, v = imgui.drag_float("标题字体大小", d2d_cfg.trial_title_font_size or 0.030, 0.001, 0.010, 0.080, "%.3f"); if c then
                d2d_cfg.trial_title_font_size = v; changed = true
            end
            c, v = imgui.drag_float("标题 X 坐标", d2d_cfg.pos_trial_header.x, 0.005, 0.0, 1.0); if c then
                d2d_cfg.pos_trial_header.x = v; changed = true
            end
            c, v = imgui.drag_float("标题 Y 坐标", d2d_cfg.pos_trial_header.y, 0.005, 0.0, 1.0); if c then
                d2d_cfg.pos_trial_header.y = v; changed = true
            end
            c, v = imgui.drag_float("连段统计 X 坐标", d2d_cfg.pos_combo_stats.x, 0.005, 0.0, 1.0); if c then
                d2d_cfg.pos_combo_stats.x = v; changed = true
            end
            c, v = imgui.drag_float("连段统计 Y 坐标", d2d_cfg.pos_combo_stats.y, 0.005, 0.0, 1.0); if c then
                d2d_cfg.pos_combo_stats.y = v; changed = true
            end
            imgui.separator()

            imgui.text_colored("HUD 覆盖层（原生行）", 0xFFFFAA00)
            c, v = imgui.checkbox("显示 HUD 覆盖层", d2d_cfg.hud_show); if c then
                d2d_cfg.hud_show = v; changed = true
            end
            c, v = imgui.drag_float("HUD 全局 Y", d2d_cfg.hud_global_y, 0.001, -0.5, 0.0); if c then
                d2d_cfg.hud_global_y = v; changed = true
            end
            c, v = imgui.drag_float("HUD 行间距 Y", d2d_cfg.hud_spacing_y, 0.001, 0.01, 0.1); if c then
                d2d_cfg.hud_spacing_y = v; changed = true
            end
            c, v = imgui.drag_float("HUD 字体大小", d2d_cfg.hud_font_size, 0.5, 10, 60); if c then
                d2d_cfg.hud_font_size = v; changed = true; font_attempted = false
            end
            imgui.separator()
            c, v = imgui.drag_float("图标大小", d2d_cfg.icon_size, 0.001, 0.01, 0.1); if c then
                d2d_cfg.icon_size = v; changed = true
            end
            c, v = imgui.drag_float("特殊图标缩放 (DR/DI...)", d2d_cfg.special_icon_scale, 0.01, 1.0, 3.0, "x%.2f"); if c then
                d2d_cfg.special_icon_scale = v; changed = true
            end
            c, v = imgui.drag_float("字体大小", d2d_cfg.font_size, 0.001, 0.01, 0.1); if c then
                d2d_cfg.font_size = v; changed = true
            end
            c, v = imgui.drag_float("水平间距", d2d_cfg.spacing_x, 0.001, 0.01, 0.1); if c then
                d2d_cfg.spacing_x = v; changed = true
            end
            c, v = imgui.drag_float("垂直间距", d2d_cfg.spacing_y, 0.001, 0.01, 0.1); if c then
                d2d_cfg.spacing_y = v; changed = true
            end
            c, v = imgui.drag_float("文字 Y 偏移", d2d_cfg.text_y_offset, 0.001, -0.05, 0.05); if c then
                d2d_cfg.text_y_offset = v; changed = true
            end

            imgui.separator()
            imgui.text_colored("--- 动画箭头 ---", COLORS.Cyan)
            c, v = imgui.drag_float("箭头大小", d2d_cfg.arrow_size, 0.001, 0.01, 0.1); if c then
                d2d_cfg.arrow_size = v; changed = true
            end
            c, v = imgui.drag_float("箭头 X 偏移", d2d_cfg.offset_x_arrow, 0.001, -0.1, 0.1); if c then
                d2d_cfg.offset_x_arrow = v; changed = true
            end
            c, v = imgui.drag_float("箭头 Y 偏移", d2d_cfg.offset_y_arrow, 0.001, -0.1, 0.1); if c then
                d2d_cfg.offset_y_arrow = v; changed = true
            end
            c, v = imgui.drag_int("失败显示时间（帧）", d2d_cfg.fail_display_frames, 1, 0, 300); if c then
                d2d_cfg.fail_display_frames = v; changed = true
            end

            imgui.separator()

            if changed then _ctui_mark_d2d_dirty() end
            imgui.spacing()
        end

        -- ==========================================
        -- TAB 3: EXCEPTION EDITOR MENU
        -- ==========================================
        if styled_header("--- 例外管理 ---", UI_THEME.hdr_session) then
            -- THE EDITOR ONLY APPEARS WHEN "MANAGE" IS CLICKED
            if p_state.editing_id ~= -1 then
                imgui.text_colored("=== 例外设置：ID " .. p_state.editing_id .. " ===", COLORS.Cyan)
                imgui.text_colored("（设置会立即应用到游戏内，便于测试）", COLORS.DarkGrey)
                imgui.spacing()

                local c1, n1 = imgui.checkbox("忽略（从日志隐藏）", p_state.edit_ignore)
                if c1 then
                    p_state.edit_ignore = n1; if n1 then p_state.edit_force = false end
                end

                imgui.same_line()
                local c2, n2 = imgui.checkbox("强制显示", p_state.edit_force)
                if c2 then
                    p_state.edit_force = n2; if n2 then p_state.edit_ignore = false end
                end

                local ch, nh = imgui.checkbox("按住按钮（蓄力追踪）", p_state.edit_holdable)
                if ch then p_state.edit_holdable = nh end

                if p_state.edit_holdable then
                    imgui.indent(20)

                    if p_state.edit_hold_partial_check == nil then p_state.edit_hold_partial_check = true end
                    local chpc, nhpc = imgui.checkbox("连段中验证 Partial", p_state.edit_hold_partial_check)
                    if chpc then p_state.edit_hold_partial_check = nhpc end
                    if imgui.is_item_hovered() then
                        imgui.set_tooltip("关闭后，Instant 和 Partial 的差异会被容忍。\nMaxed / PERFECT / FAKE / LATE 始终严格验证。")
                    end

                    local changed_link, new_link = imgui.input_text("吸收后续 ID（例: 502,503）", p_state.edit_absorb_ids or "")
                    if changed_link then p_state.edit_absorb_ids = new_link end
                    imgui.spacing()

                    if p_state.profile_name == "Luke" then
                        imgui.text_colored("Luke 蓄力设置（留空则自动检测）：", COLORS.Green)

                        local changed_min, new_min = imgui.input_text("Instant / Partial 分界（帧）",
                            p_state.edit_charge_min or "")
                        if changed_min then p_state.edit_charge_min = new_min end

                        local changed_pmin, new_pmin = imgui.input_text("Perfect 起始（帧）",
                            p_state.edit_perfect_min or "")
                        if changed_pmin then p_state.edit_perfect_min = new_pmin end

                        local changed_pmax, new_pmax = imgui.input_text("Perfect 结束（帧）",
                            p_state.edit_perfect_max or "")
                        if changed_pmax then p_state.edit_perfect_max = new_pmax end
                    elseif p_state.profile_name == "JP" then
                        imgui.text_colored("JP 模式：超过阈值即视为 FAKE。", COLORS.Blue)
                        local changed_min, new_min = imgui.input_text("Instant / Partial 分界（帧）",
                            p_state.edit_charge_min or "")
                        if changed_min then p_state.edit_charge_min = new_min end

                        local changed_max, new_max = imgui.input_text("FAKE 取消阈值（帧）",
                            p_state.edit_charge_max or "")
                        if changed_max then p_state.edit_charge_max = new_max end
                    else
                        imgui.text_colored("蓄力设置（Max 留空则自动填充）：", COLORS.Blue)
                        local changed_min, new_min = imgui.input_text("Instant / Partial 分界（帧）",
                            p_state.edit_charge_min)
                        if changed_min then p_state.edit_charge_min = new_min end

                        local changed_max, new_max = imgui.input_text("Maxed 阈值（帧）", p_state
                            .edit_charge_max)
                        if changed_max then p_state.edit_charge_max = new_max end
                    end

                    imgui.unindent(20)
                end

                imgui.spacing()
                local ct, nt = imgui.input_text("新名称（留空保留原名）", p_state.edit_text)
                if ct then p_state.edit_text = nt end

                imgui.spacing()
                local cc, nc = imgui.checkbox("应用到所有角色（通用）", p_state.edit_is_common)
                if cc then p_state.edit_is_common = nc end

                imgui.text_colored("--- 特殊条件 ---", COLORS.Blue)
                local ci, ni = imgui.input_text("若前一个 Action ID 为...##ig_id_" .. p_state.editing_id,
                    p_state.edit_ignore_prev_id)
                if ci then p_state.edit_ignore_prev_id = ni end
                local cf, nf = imgui.input_text("...且在最近 X 帧内则忽略##ig_fr_" .. p_state.editing_id,
                    p_state.edit_ignore_prev_frames)
                if cf then p_state.edit_ignore_prev_frames = nf end
                imgui.spacing()

                imgui.spacing()
                if styled_button("应用并保存", UI_THEME.btn_green) then
                    local id_s = tostring(p_state.editing_id)
                    local parsed_min = tonumber(p_state.edit_charge_min)
                    local parsed_max = tonumber(p_state.edit_charge_max)

                    local _parsed_prev = nil
                    if p_state.edit_ignore_prev_id ~= "" then
                        local ids = {}
                        for tok in p_state.edit_ignore_prev_id:gmatch("[^,]+") do
                            local n = tonumber(tok:match("^%s*(.-)%s*$"))
                            if n then ids[#ids+1] = n end
                        end
                        if #ids == 1 then _parsed_prev = ids[1]
                        elseif #ids > 1 then _parsed_prev = ids end
                    end
                    local new_exc = {
                        ignore = p_state.edit_ignore,
                        force = p_state.edit_force,
                        is_holdable = p_state.edit_holdable,
                        hold_partial_check = p_state.edit_hold_partial_check,
                        absorb_ids = p_state.edit_absorb_ids,
                        charge_min = parsed_min,
                        charge_max = parsed_max,
                        perfect_min = tonumber(p_state.edit_perfect_min),
                        perfect_max = tonumber(p_state.edit_perfect_max),
                        override_name = (p_state.edit_text ~= "") and p_state.edit_text or nil,
                        ignore_prev_id = _parsed_prev,
                        ignore_prev_frames = tonumber(p_state.edit_ignore_prev_frames) or 5
                    }

                    pcall(function() if fs and fs.create_dir then fs.create_dir("TrainingComboTrials_data/exceptions") end end)

                    if p_state.edit_is_common then
                        common_exceptions[id_s] = new_exc
                        p_state.exceptions[id_s] = nil

                        local s1 = json.dump_file("TrainingComboTrials_data/exceptions/Common.json", common_exceptions)
                        local s2 = json.dump_file(get_exc_filename(p_state.profile_name), p_state.exceptions)

                        if s1 and s2 then
                            exc_status = "通用例外已保存。"
                        else
                            exc_status = "严重错误：无法写入文件。"
                        end
                    else
                        p_state.exceptions[id_s] = new_exc

                        local s1 = json.dump_file(get_exc_filename(p_state.profile_name), p_state.exceptions)

                        if s1 then
                            exc_status = "角色专用例外已保存。"
                        else
                            exc_status = "严重错误：无法写入文件。"
                        end
                    end

                    local new_log = {}
                    for _, l in ipairs(p_state.log) do
                        local keep = true
                        if l.id == p_state.editing_id then
                            if new_exc.ignore then
                                keep = false
                            elseif new_exc.force then
                                l.intentional = true
                            end

                            if new_exc.override_name then
                                l.motion = new_exc.override_name
                            else
                                l.motion = l.name
                            end

                            l.is_holdable = new_exc.is_holdable
                            l.charge_min = new_exc.charge_min
                            l.charge_max = new_exc.charge_max
                        end
                        if keep then table.insert(new_log, l) end
                    end
                    p_state.log = new_log

                    for _, step in ipairs(trial_state.sequence) do
                        if step.id == p_state.editing_id then
                            if new_exc.override_name then
                                step.motion = new_exc.override_name
                            else
                                step.motion = step.name or "Unknown"
                            end
                        end
                    end
                    p_state.editing_id = -1
                end

                imgui.same_line()
                if styled_button("取消", UI_THEME.btn_red) then p_state.editing_id = -1 end
                imgui.separator()
            end

            -- LIST OF SAVED EXCEPTIONS (ASCENDING SORT)
            if imgui.tree_node("已启用的异常 (" .. p_state.profile_name .. ")") then
                if exc_status ~= "" then imgui.text_colored(exc_status, COLORS.Yellow) end

                imgui.text_colored("--- 角色专用 ---", COLORS.Green)
                local spec_keys = sort_ids(p_state.exceptions)

                if #spec_keys == 0 then
                    imgui.text_colored("无", COLORS.DarkGrey)
                else
                    for _, id_str in ipairs(spec_keys) do
                        local exc = p_state.exceptions[id_str]
                        local desc = ""
                        if exc.ignore then desc = desc .. "[忽略] " end
                        if exc.force then desc = desc .. "[强制] " end
                        if exc.is_holdable then
                            if p_state.profile_name == "Luke" then
                                local min_s = exc.perfect_min and (exc.perfect_min .. "f") or "自动"
                                local max_s = exc.perfect_max and (exc.perfect_max .. "f") or "自动"
                                desc = desc .. "[HOLD(Luke Perfect: " .. min_s .. "-" .. max_s .. ")] "
                            elseif p_state.profile_name == "JP" then
                                local min_s = exc.charge_min and (exc.charge_min .. "f") or "?"
                                local max_s = exc.charge_max and (exc.charge_max .. "f") or "?"
                                desc = desc .. "[HOLD(" .. min_s .. "-" .. max_s .. " FAKE)] "
                            else
                                local min_s = exc.charge_min and (exc.charge_min .. "f") or "?"
                                local max_s = exc.charge_max and (exc.charge_max .. "f") or "?"
                                desc = desc .. "[HOLD(" .. min_s .. "-" .. max_s .. ")] "
                            end
                        end
                        if exc.override_name then desc = desc .. "[NAME: " .. exc.override_name .. "] " end
                        if exc.ignore_prev_id then
                            local id_disp = type(exc.ignore_prev_id) == "table" and table.concat(exc.ignore_prev_id, ",") or tostring(exc.ignore_prev_id)
                            desc = desc ..
                                "[IGN IF ID " .. id_disp .. " < " .. (exc.ignore_prev_frames or 5) .. "f]"
                        end

                        imgui.text("ID " .. id_str .. " -> " .. desc)
                        imgui.same_line(450)
                        if styled_button("编辑##spec_" .. id_str, UI_THEME.btn_neutral) then
                            p_state.editing_id = tonumber(id_str)
                            p_state.edit_is_common = false
                            p_state.edit_ignore = exc.ignore or false
                            p_state.edit_force = exc.force or false
                            p_state.edit_holdable = exc.is_holdable or false
                            p_state.edit_hold_partial_check = (exc.hold_partial_check ~= false)
                            p_state.edit_absorb_ids = exc.absorb_ids or ""
                            p_state.edit_charge_min = exc.charge_min and tostring(exc.charge_min) or ""
                            p_state.edit_charge_max = exc.charge_max and tostring(exc.charge_max) or ""
                            p_state.edit_perfect_min = exc.perfect_min and tostring(exc.perfect_min) or ""
                            p_state.edit_perfect_max = exc.perfect_max and tostring(exc.perfect_max) or ""
                            p_state.edit_text = exc.override_name or ""
                            p_state.edit_ignore_prev_id = not exc.ignore_prev_id and "" or (type(exc.ignore_prev_id) == "table" and table.concat(exc.ignore_prev_id, ",") or tostring(exc.ignore_prev_id))
                            p_state.edit_ignore_prev_frames = exc.ignore_prev_frames and tostring(exc.ignore_prev_frames) or
                                "5"
                        end
                        imgui.same_line()
                        if styled_button("删除##delspec_" .. id_str, UI_THEME.btn_red) then
                            p_state.exceptions[id_str] = nil
                            pcall(function() if fs and fs.create_dir then fs.create_dir("TrainingComboTrials_data/exceptions") end end)
                            json.dump_file(get_exc_filename(p_state.profile_name), p_state.exceptions)
                            exc_status = "角色专用异常已从磁盘删除。"
                        end
                    end
                end

                imgui.spacing()
                imgui.text_colored("--- 通用 ---", COLORS.Cyan)
                local com_keys = sort_ids(common_exceptions)

                if #com_keys == 0 then
                    imgui.text_colored("无", COLORS.DarkGrey)
                else
                    for _, id_str in ipairs(com_keys) do
                        local exc = common_exceptions[id_str]
                        local desc = ""
                        if exc.ignore then desc = desc .. "[忽略] " end
                        if exc.force then desc = desc .. "[强制] " end
                        if exc.is_holdable then
                            local min_s = exc.charge_min and (exc.charge_min .. "f") or "?"
                            local max_s = exc.charge_max and (exc.charge_max .. "f") or "?"
                            desc = desc .. "[HOLD(" .. min_s .. "-" .. max_s .. ")] "
                        end
                        if exc.override_name then desc = desc .. "[NAME: " .. exc.override_name .. "]" end

                        imgui.text("ID " .. id_str .. " -> " .. desc)
                        imgui.same_line(450)
                        if styled_button("编辑##com_" .. id_str, UI_THEME.btn_neutral) then
                            p_state.editing_id = tonumber(id_str)
                            p_state.edit_is_common = true
                            p_state.edit_ignore = exc.ignore or false
                            p_state.edit_force = exc.force or false
                            p_state.edit_holdable = exc.is_holdable or false
                            p_state.edit_hold_partial_check = (exc.hold_partial_check ~= false)
                            p_state.edit_absorb_ids = exc.absorb_ids or ""
                            p_state.edit_charge_min = exc.charge_min and tostring(exc.charge_min) or ""
                            p_state.edit_charge_max = exc.charge_max and tostring(exc.charge_max) or ""
                            p_state.edit_perfect_min = exc.perfect_min and tostring(exc.perfect_min) or ""
                            p_state.edit_perfect_max = exc.perfect_max and tostring(exc.perfect_max) or ""
                            p_state.edit_text = exc.override_name or ""
                            p_state.edit_ignore_prev_id = not exc.ignore_prev_id and "" or (type(exc.ignore_prev_id) == "table" and table.concat(exc.ignore_prev_id, ",") or tostring(exc.ignore_prev_id))
                            p_state.edit_ignore_prev_frames = exc.ignore_prev_frames and tostring(exc.ignore_prev_frames) or
                                "5"
                        end
                        imgui.same_line()
                        if styled_button("删除##delcom_" .. id_str, UI_THEME.btn_red) then
                            common_exceptions[id_str] = nil
                            pcall(function() if fs and fs.create_dir then fs.create_dir("TrainingComboTrials_data/exceptions") end end)
                            json.dump_file("TrainingComboTrials_data/exceptions/Common.json", common_exceptions)
                            exc_status = "通用例外已从磁盘删除。"
                        end
                    end
                end
                imgui.tree_pop()
            end

            imgui.spacing()
        end

        -- ==========================================
        -- TAB 4: LIVE LOG
        -- ==========================================
        if styled_header("--- 实时日志：玩家 " .. tostring(ui_state.viewed_player + 1) .. " ---", UI_THEME.hdr_rules) then
            -- PLAYER SELECTOR (Forces refresh on change)
            if styled_button(ui_state.viewed_player == 0 and "正在记录 P1 (" .. players[0].profile_name .. ")" or "查看 P1 日志 (" .. players[0].profile_name .. ")", ui_state.viewed_player == 0 and UI_THEME.btn_green or UI_THEME.btn_neutral) then
                if ui_state.viewed_player ~= 0 then
                    ui_state.viewed_player = 0; refresh_combo_list()
                end
            end
            imgui.same_line()
            if styled_button(ui_state.viewed_player == 1 and "正在记录 P2 (" .. players[1].profile_name .. ")" or "查看 P2 日志 (" .. players[1].profile_name .. ")", ui_state.viewed_player == 1 and UI_THEME.btn_green or UI_THEME.btn_neutral) then
                if ui_state.viewed_player ~= 1 then
                    ui_state.viewed_player = 1; refresh_combo_list()
                end
            end
            imgui.spacing()
            imgui.separator()
            imgui.spacing()

            local c_deep, n_deep = imgui.checkbox("启用深度动作扫描（在 JSON 导出中包含 C# DNA）",
                p_state.enable_deep_logging)
            if c_deep then p_state.enable_deep_logging = n_deep end
            if p_state.enable_deep_logging then
                imgui.text_colored("   /!\\ 深度扫描会大量分析代码。", COLORS.Blue)
                imgui.text_colored("       建议仅在研究时开启。", COLORS.Blue)
            end

            imgui.spacing()
            if styled_button("清空日志", UI_THEME.btn_red) then p_state.log = {} end
            imgui.same_line()
            if styled_button("导出日志为 JSON", UI_THEME.btn_neutral) then
                json.dump_file("Final_Log_Dump_P" .. tostring(ui_state.viewed_player + 1) .. ".json", p_state.log)
                dump_status = "完整日志已保存。"
            end

            if dump_status ~= "" then imgui.text_colored(dump_status, COLORS.Green) end
            imgui.spacing(); imgui.separator(); imgui.spacing()

            if #p_state.log == 0 then
                imgui.text_colored("等待动作...", COLORS.Blue)
            else
                for i, log in ipairs(p_state.log) do
                    if log.intentional then
                        local charge_str = ""
                        if log.is_holdable then
                            local trans_str = ""
                            if not log.is_holding and log.transition_id and log.transition_id > 50 then
                                trans_str =
                                    " -> ID " .. log.transition_id
                            end
                            charge_str = string.format(" (%d%s)", log.hold_frames, trans_str)
                        end

                        local combo_str = ""
                        if log.combo_count ~= nil then
                            combo_str = string.format(" [连段: %d]", log.combo_count)
                        end

                        -- Translated keywords: VRAI INPUT -> REAL INPUT, Reel -> Raw
                        local display_motion = ctx.localize_motion_text
                            and ctx.localize_motion_text(log.motion, log.id) or log.motion
                        local left_col = string.format("真实输入 | %s (ID: %d)%s%s", display_motion, log.id,
                            charge_str, combo_str)
                        local right_col = string.format("原始: %s (%s)", log.real_input, log.frame_diff)

                        local line_color = COLORS.White
                        if log.is_holdable then
                            local live_status = log.charge_status or ""
                            -- Real-time calculation for the text UI
                            if log.is_holding then
                                if log.charge_min and log.hold_frames <= log.charge_min then
                                    live_status = "Instant"
                                elseif log.charge_max and log.hold_frames >= log.charge_max then
                                    live_status = "Maxed"
                                else
                                    live_status = "Partial"
                                end
                            end

                            if live_status:match("Partial") then
                                line_color = COLORS.Orange
                            elseif live_status:match("Maxed") or live_status == "PERFECT!" or live_status == "FAKE" then
                                line_color = COLORS.Yellow
                            end
                        end

                        imgui.text_colored(left_col, line_color)

                        imgui.same_line(450)
                        imgui.text_colored("-> " .. right_col, COLORS.Cyan)
                    else
                        if log.is_ignored then
                            local line = string.format("已忽略   | %s (ID: %d) %s", log.name, log.id, log.ignore_reason)
                            imgui.text_colored(line, COLORS.DarkGrey)
                        else
                            local line = string.format("自动     | %s (ID: %d)", log.name, log.id)
                            imgui.text_colored(line, COLORS.DarkGrey)
                        end
                    end

                    imgui.same_line(750)
                        if styled_button("管理##edit_" .. log.id .. "_" .. i, UI_THEME.btn_orange) then
                        p_state.editing_id = log.id
                        local exc_char = p_state.exceptions[tostring(log.id)]
                        local exc_com = common_exceptions[tostring(log.id)]
                        local exc = exc_char or exc_com

                        if exc_char then
                            p_state.edit_is_common = false
                        elseif exc_com then
                            p_state.edit_is_common = true
                        else
                            p_state.edit_is_common = false
                        end

                        if exc then
                            p_state.edit_ignore = exc.ignore or false
                            p_state.edit_force = exc.force or false
                            p_state.edit_holdable = exc.is_holdable or false
                            p_state.edit_hold_partial_check = (exc.hold_partial_check ~= false)
                            p_state.edit_absorb_ids = exc.absorb_ids or ""
                            p_state.edit_charge_min = exc.charge_min and tostring(exc.charge_min) or ""
                            p_state.edit_charge_max = exc.charge_max and tostring(exc.charge_max) or ""
                            p_state.edit_text = exc.override_name or ""
                            p_state.edit_ignore_prev_id = not exc.ignore_prev_id and "" or (type(exc.ignore_prev_id) == "table" and table.concat(exc.ignore_prev_id, ",") or tostring(exc.ignore_prev_id))
                            p_state.edit_ignore_prev_frames = exc.ignore_prev_frames and tostring(exc.ignore_prev_frames) or
                                "5"
                        else
                            p_state.edit_ignore = false
                            p_state.edit_force = false
                            p_state.edit_holdable = false
                            p_state.edit_hold_partial_check = true
                            p_state.edit_absorb_ids = ""
                            p_state.edit_charge_min = ""
                            p_state.edit_charge_max = ""
                            p_state.edit_text = log.motion or log.name
                            p_state.edit_ignore_prev_id = ""
                            p_state.edit_ignore_prev_frames = "5"
                        end
                    end
                end
            end
        end

        imgui.spacing()

        -- ==========================================
        -- TAB 5: DEBUG & SYSTEM INFO
        -- ==========================================
        if styled_header("--- 调试与系统信息 ---", UI_THEME.hdr_rules) then
            imgui.text_colored("检测到的游戏原生分辨率：", 0xFF00FFFF)
            local res_w = ctx.cached_sw or last_sw or 0
            local res_h = ctx.cached_sh or last_sh or 0
            imgui.indent(20)
            imgui.text(string.format("%d px width  x  %d px height", res_w, res_h))
            imgui.unindent(20)
            imgui.spacing()

            -- LIVE POSITIONS
            imgui.text_colored("实时位置（raw sfix）：", 0xFF00FFFF)
            pcall(_ctui_draw_live_positions)
            imgui.text_colored("已保存的连段位置：", 0xFF00FFFF)
            imgui.indent(20)
            imgui.text(string.format("start_pos_p1_raw: %s", tostring(trial_state.start_pos_p1_raw)))
            imgui.text(string.format("start_pos_p2_raw: %s", tostring(trial_state.start_pos_p2_raw)))
            imgui.text(string.format("exact_inject_r1: %s", tostring(trial_state.exact_inject_r1)))
            imgui.text(string.format("exact_inject_r2: %s", tostring(trial_state.exact_inject_r2)))
            imgui.text(string.format("pending_exact_pos: %s", tostring(trial_state.pending_exact_pos)))
            imgui.text(string.format("forced_position_idx: %d", d2d_cfg.forced_position_idx))
            imgui.unindent(20)
            imgui.spacing()

            -- FAIL DUMP BUTTON (Only appears if a fail is in memory)
            --[[
            if ctx.trial_state and ctx.trial_state.last_fail_dump then
                imgui.separator()
                imgui.spacing()
                imgui.text_colored("上次失败连段", COLORS.Red)
                if styled_button("导出失败数据 JSON", UI_THEME.btn_red) then
                    if ctx.dump_last_fail then
                        local path = ctx.dump_last_fail()
                        if path then
                            print("[ComboTrials] Fail dump saved to: " .. path)
                        end
                    end
                end
                imgui.spacing()
            end
            ]]--
        end

        end)
        if not ok then
            imgui.text_colored("连段训练 UI 绘制出错，已保护 ImGui 栈。", COLORS.Red)
            imgui.text_colored(tostring(err), COLORS.Yellow)
            print("[ComboTrials_UI] draw error: " .. tostring(err))
        end

        -- IMPORTANT : Closes the tree_node and the if block
        imgui.tree_pop()
    end
end

-- Register in floating window hub + keep standard menu entry
if _G.FloatingScriptUI then
_G.FloatingScriptUI.register("连段训练设置v0.9a", draw_combo_trials_menu_ui)
end
re.on_draw_ui(draw_combo_trials_menu_ui)

-- =========================================================
-- Public API
-- =========================================================
function M.init(shared_ctx)
    ctx = shared_ctx
    d2d_cfg = ctx.d2d_cfg
    trial_state = ctx.trial_state
    players = ctx.players
    file_system = ctx.file_system
    common_exceptions = ctx.common_exceptions
    sf6_menu_state = ctx.sf6_menu_state
    load_and_start_trial = ctx.load_and_start_trial
    start_recording = ctx.start_recording
    stop_recording_and_save = ctx.stop_recording_and_save
    cancel_recording = ctx.cancel_recording
    cancel_recording_due_to_menu = ctx.cancel_recording_due_to_menu
    refresh_combo_list = ctx.refresh_combo_list
    restore_trial_vital = ctx.restore_trial_vital
    save_d2d_config = ctx.save_d2d_config
    get_exc_filename = ctx.get_exc_filename
    ui_state = ctx.ui_state
end

return M
