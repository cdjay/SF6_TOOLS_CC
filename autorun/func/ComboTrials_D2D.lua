-- =========================================================
-- ComboTrials_D2D.lua -- D2D overlay rendering (icons, trial box)
-- Receives shared context (ctx) from the main file.
-- =========================================================

local d2d = d2d
local sdk = sdk
local imgui = imgui

local M = {}
local RuntimeSafety = require("func/RuntimeSafety")

-- Shared context (set by init)
local ctx -- { d2d_cfg, trial_state, players, sf6_menu_state }

local assets = { font = nil, last_pixel_size = -1, title_font = nil, last_title_pixel_size = -1, imgs = {} }
local d2d_anim = { active_y = nil }
local d2d_last_runtime_allowed = nil
local d2d_last_content_visible = nil
local d2d_last_error = nil

-- Keep the D2D command list non-empty while the overlay is disabled. Some
-- reframework-d2d builds retain the previous render target across a D3D12
-- swap-chain reset when every Lua draw callback returns without submitting a
-- command. A fully transparent pixel makes the plugin execute its normal
-- begin/clear/end pass without adding anything visible to the game.
local function submit_transparent_clear_pulse()
    if d2d and d2d.fill_rect then
        d2d.fill_rect(0, 0, 1, 1, 0x00000000)
    end
end

local function is_combo_trials_runtime_allowed()
    if not ctx then return false end
    if ctx and type(ctx.is_runtime_allowed) == "function" then
        local ok, allowed = pcall(ctx.is_runtime_allowed)
        return ok and allowed == true
    end
    return RuntimeSafety.is_training_allowed()
        and _G.CurrentTrainerMode == 4
        and _G.TrainingModeActive == true
        and _G.TrainingScriptManagerActiveThisFrame == true
        and _G.IsInBattleHub ~= true
        and _G.IsInReplay ~= true
        and _G.FlowMapID ~= 9
        and _G.FlowMapID ~= 10
end

local image_files = {
    ["1"] = "1.png",
    ["2"] = "2.png",
    ["3"] = "3.png",
    ["4"] = "4.png",
    ["5"] = "5.png",
    ["6"] = "6.png",
    ["7"] = "7.png",
    ["8"] = "8.png",
    ["9"] = "9.png",
    ["lp"] = "lp.png",
    ["mp"] = "mp.png",
    ["hp"] = "hp.png",
    ["lk"] = "lk.png",
    ["mk"] = "mk.png",
    ["hk"] = "hk.png",
    ["modern_l"] = "modern_l.png",
    ["modern_m"] = "modern_m.png",
    ["modern_h"] = "modern_h.png",
    ["modern_sp"] = "modern_sp.png",
    ["modern_auto"] = "modern_auto.png",
    ["p"] = "P.png",
    ["k"] = "K.png",
    ["360"] = "360.png",
    ["4_hold"] = "4_HOLD.png",
    ["2_hold"] = "2_HOLD.png",
    ["6_hold"] = "6_HOLD.png",
    ["hcb"] = "HCB.png",
    ["hcf"] = "HCF.png",
    ["throw"] = "THROW.png",
    ["arrow"] = "arrow.png",
    ["arrow_success"] = "arrow_green.png",
    ["arrow_fail"] = "arrow_red.png",
    ["followup"] = "FollowUp.png",
    ["validfollowup"] = "validfollowup.png",
    ["cartouche"] = "cartouche.png",
    ["hold"] = "hold.png",
    ["plus"] = "PLUS.png",
    ["parry"] = "parry.png",
    ["dr"] = "dr.png",
    ["drc"] = "drc.png",
    ["rev"] = "rev.png",
    ["di"] = "DI.png"
}

-- =========================================================
-- RAW INPUT SYSTEM (InputVisualiser-style integrated)
-- =========================================================
local raw_state = { history_p1 = {}, history_p2 = {} }

local function raw_get_numpad(dir_val)
    local u = (dir_val & 1) ~= 0
    local d = (dir_val & 2) ~= 0
    local r = (dir_val & 8) ~= 0
    local l = (dir_val & 4) ~= 0
    if u and l then return "7" elseif u and r then return "9" elseif d and l then return "1"
    elseif d and r then return "3" elseif u then return "8" elseif d then return "2"
    elseif l then return "4" elseif r then return "6" end
    return "5"
end

local function raw_get_buttons(val)
    local list = {}
    if (val & 16) ~= 0  then table.insert(list, "lp") end
    if (val & 32) ~= 0  then table.insert(list, "mp") end
    if (val & 64) ~= 0  then table.insert(list, "hp") end
    if (val & 128) ~= 0 then table.insert(list, "lk") end
    if (val & 256) ~= 0 then table.insert(list, "mk") end
    if (val & 512) ~= 0 then table.insert(list, "hk") end
    return list
end

local function raw_update_history(history, d, b, max_size)
    local top = history[1]
    if top and (d == top.dir) and (b == top.btn) and top.active then
        top.frames = top.frames + 1
    else
        table.insert(history, 1, { dir = d, btn = b, frames = 1, active = true })
        while #history > max_size do table.remove(history) end
    end
end

local function _ctd_raw_read_inputs_inner(p_idx, history, max_size)
    local gBattle = sdk.find_type_definition("gBattle")
    if not gBattle then return end
    local mgr = gBattle:get_field("Player"):get_data(nil)
    if not mgr then return end
    local p = mgr:call("getPlayer", p_idx)
    if not p then return end
    local d = p:get_type_definition():get_field("pl_input_new"):get_data(p) or 0
    local b = p:get_type_definition():get_field("pl_sw_new"):get_data(p) or 0
    raw_update_history(history, d, b, max_size)
end

local function raw_read_inputs(p_idx, history, max_size)
    pcall(_ctd_raw_read_inputs_inner, p_idx, history, max_size)
end

-- Helper: apply mirror transform to position and flip
local function apply_mirror(pos, flip)
    return { x = 1.0 - pos.x, y = pos.y }, not flip
end

local function trim_string(value)
    local s = tostring(value or "")
    return s:match("^%s*(.-)%s*$") or ""
end

local function get_meta_table(first)
    if type(first) ~= "table" then return nil end
    if type(first._xt_meta) == "table" then return first._xt_meta end
    if type(first._wtt_cn_meta) == "table" then return first._wtt_cn_meta end
    return nil
end

local function get_trial_meta()
    local state = ctx and ctx.trial_state
    local seq = state and state.sequence
    local first = seq and seq[1]
    return get_meta_table(first) or {}
end

-- =========================================================
-- Follow-up group helpers
-- =========================================================
local MODERN_DISPLAY_DIR = "TrainingComboTrials_data/modern_display/"
local EXCEPTION_DISPLAY_DIR = "TrainingComboTrials_data/exceptions/"
local modern_display_cache = {}
local exception_display_cache = {}

local function get_sequence_meta(sequence)
    if type(sequence) ~= "table" then return nil end
    local first = sequence[1]
    return get_meta_table(first)
end

local function is_modern_sequence(sequence)
    local meta = get_sequence_meta(sequence)
    if not meta then return false end
    local control_mode = tostring(meta.control_mode or ""):lower()
    local control_type = tostring(meta.control_type or ""):lower()
    local input_profile = tostring(meta.timeline_input_profile or ""):lower()
    return control_mode == "modern" or control_type == "modern" or input_profile == "modern"
end

local function get_sequence_character(sequence)
    local meta = get_sequence_meta(sequence)
    if not meta then return nil end
    local character = meta.character
    if type(character) ~= "string" or character == "" then return nil end
    return character
end

local function clean_meta_text(value)
    if value == nil then return "" end
    return trim_string(value)
end

local function get_upload_date(meta)
    if type(meta) ~= "table" then return "" end

    local raw = meta.uploaded_at or meta.uploadDate or meta.uploadedAt or meta.upload_date or
        meta.created_at or meta.createdAt or meta.updated_at or meta.updatedAt
    local value = clean_meta_text(raw)
    if value == "" then return "" end

    local ymd = value:match("^(%d%d%d%d%-%d%d%-%d%d)")
    return ymd or value
end

local function get_step_notes_table(meta)
    if type(meta) ~= "table" or type(meta.step_notes) ~= "table" then return nil end
    return meta.step_notes
end

local function get_display_line_note(meta, first_idx, last_idx)
    local step_notes = get_step_notes_table(meta)
    if not step_notes then return "" end

    local parts = {}
    for idx = first_idx or 1, last_idx or first_idx or 1 do
        local note = clean_meta_text(step_notes[idx])
        if note == "" then note = clean_meta_text(step_notes[tostring(idx)]) end
        if note ~= "" then table.insert(parts, note) end
    end
    return table.concat(parts, " / ")
end

local function has_nonempty_step_note(meta)
    local step_notes = get_step_notes_table(meta)
    if not step_notes then return false end
    for _, value in pairs(step_notes) do
        if clean_meta_text(value) ~= "" then return true end
    end
    return false
end

local function has_trial_note_content(meta)
    if type(meta) ~= "table" then return false end
    return clean_meta_text(meta.author) ~= "" or clean_meta_text(meta.note) ~= "" or
        get_upload_date(meta) ~= "" or has_nonempty_step_note(meta)
end

local function build_author_upload_line(meta)
    if not has_trial_note_content(meta) then return "" end

    local author = clean_meta_text(meta.author)
    if author == "" then author = "不明" end

    local upload = get_upload_date(meta)
    local line = "连段由 " .. author .. " 录制于"
    if upload == "" then upload = "不明" end
    line = line .. " " .. upload
    return line
end

local function load_modern_display_map(character)
    local key = tostring(character or "")
    key = key:gsub("[^%w_]", "")
    if key == "" then return nil end

    if modern_display_cache[key] ~= nil then
        return modern_display_cache[key] ~= false and modern_display_cache[key] or nil
    end

    local path = MODERN_DISPLAY_DIR .. key .. ".json"
    local ok, loaded = false, nil
    if type(_G.safe_load_json) == "function" then
        ok, loaded = pcall(_G.safe_load_json, path)
    elseif json and json.load_file then
        ok, loaded = pcall(json.load_file, path)
    end

    local meta = ok and type(loaded) == "table" and loaded._meta or nil
    if type(meta) == "table"
        and tostring(meta.schema or ""):lower() == "xt.modern_display.v2"
        and tostring(meta.generated_from or ""):lower() == "ac_bcm" then
        modern_display_cache[key] = loaded
        return loaded
    end

    modern_display_cache[key] = false
    return nil
end

local function get_modern_display_motion(modern_map, step)
    if type(modern_map) ~= "table" or type(step) ~= "table" then return nil end
    local entry = modern_map[tostring(step.id or "")]
    if type(entry) == "string" and entry ~= "" then return entry end
    if type(entry) == "table" and type(entry.modern_display) == "string" and entry.modern_display ~= "" then
        return entry.modern_display
    end
    return nil
end

local function load_exception_display_map(character)
    if type(character) ~= "string" or character == "" then return nil end
    local safe_character = character:gsub("[^%w_]", "")
    if safe_character == "" then return nil end
    if exception_display_cache[safe_character] ~= nil then
        return exception_display_cache[safe_character] ~= false and exception_display_cache[safe_character] or nil
    end

    local loaded = nil
    local ok = false
    local path = EXCEPTION_DISPLAY_DIR .. safe_character .. ".json"
    if type(_G.safe_load_json) == "function" then
        ok, loaded = pcall(_G.safe_load_json, path)
    end
    if ok and type(loaded) == "table" then
        exception_display_cache[safe_character] = loaded
        return loaded
    end

    exception_display_cache[safe_character] = false
    return nil
end

local function get_exception_display_motion(exception_map, step)
    if type(exception_map) ~= "table" or type(step) ~= "table" then return nil end
    local entry = exception_map[tostring(step.id or "")]
    if type(entry) == "table" then
        for _, key in ipairs({ "display_motion", "display_override", "override_name" }) do
            if type(entry[key]) == "string" and entry[key] ~= "" then return entry[key] end
        end
    end
    return nil
end

local function clone_step_for_display(step, motion)
    if not motion then return step end
    local copy = {}
    for k, v in pairs(step) do copy[k] = v end
    copy.motion = motion
    copy._ct_modern_display = true
    return copy
end

local function build_display_lines(sequence)
    local lines = {}
    local modern_map = nil
    local exception_map = load_exception_display_map(get_sequence_character(sequence))
    if is_modern_sequence(sequence) then
        modern_map = load_modern_display_map(get_sequence_character(sequence))
    end

    for i, raw_step in ipairs(sequence) do
        local modern_motion = get_modern_display_motion(modern_map, raw_step)
        local exception_motion = get_exception_display_motion(exception_map, raw_step)
        local step = clone_step_for_display(raw_step, modern_motion or exception_motion)
        local gid = step.group_id or i
        if #lines == 0 or lines[#lines].group_id ~= gid then
            table.insert(lines, { group_id = gid, first = i, last = i, steps = { step } })
        else
            lines[#lines].last = i
            table.insert(lines[#lines].steps, step)
        end
    end
    return lines
end

local function merge_group_log_item(steps)
    local motions = {}

    -- Count holdable steps
    local holdable_count = 0
    for _, s in ipairs(steps) do
        if s.is_holdable then holdable_count = holdable_count + 1 end
    end

    local first_holdable_done = false
    for _, s in ipairs(steps) do
        local m = s.motion or ""
        -- For follow-ups: ensure > is BEFORE [AIR]/J. (not reversed)
        m = m:gsub("^(%[AIR%])%s*(>)", "%2%1")
        m = m:gsub("^(J%.)%s*(>)", "%2%1")
        if s.is_holdable then
            if holdable_count > 3 then
                -- Only display the first holdable with "(xN)", ignore the rest
                if not first_holdable_done then
                    first_holdable_done = true
                    table.insert(motions, m)
                end
                -- subsequent ones: not added
            else
                -- 3 or fewer: individual hold on each step
                local frames = s.hold_frames
                if frames and frames > 0 then
                    m = m .. " (Hold " .. frames .. ")"
                else
                    m = m .. " (Hold)"
                end
                table.insert(motions, m)
            end
        else
            table.insert(motions, m)
        end
    end

    local first = steps[1]
    local last  = steps[#steps]
    local all_hit = true
    for _, s in ipairs(steps) do if not s.has_hit then all_hit = false; break end end
    local has_modern_display = false
    for _, s in ipairs(steps) do
        if s._ct_modern_display then has_modern_display = true; break end
    end
    local ui_result_text = nil
    local ui_result_kind = nil
    for _, s in ipairs(steps) do
        if s.ui_result_text then
            ui_result_text = s.ui_result_text
            ui_result_kind = s.ui_result_kind
        end
    end

    return {
        motion         = table.concat(motions, " "),
        is_holdable    = false,  -- handled inline in the motion
        hold_repeat    = holdable_count > 3 and holdable_count or nil,
        expected_combo = last.expected_combo,
        actual_combo   = last.actual_combo,
        has_hit        = all_hit,
        combo_stats    = first.combo_stats,
        facing_left    = first.facing_left,
        _ct_modern_display = has_modern_display,
        ui_result_text = ui_result_text,
        ui_result_kind = ui_result_kind,
    }
end

-- =========================================================
-- parse_motion_to_icons
-- =========================================================
local function localize_motion_text(s)
    s = tostring(s or "")

    -- Longer phrases must be replaced before their shorter components.
    s = s:gsub("FULLY%s+DELAYED", "完全延迟")
    s = s:gsub("CANCEL%s+ACTION", "取消动作")
    s = s:gsub("DO%s+NOTHING", "不操作")
    s = s:gsub("RUN%s+STOP", "急停")
    s = s:gsub("1ST%s+HALF", "前半段")
    s = s:gsub("2ND%s+HALF", "后半段")
    s = s:gsub("FLASH%s+KICK", "脚刀")
    s = s:gsub("SHUN%s+GOKU%s+SATSU", "瞬狱杀")

    s = s:gsub("ENHANCED", "强化")
    s = s:gsub("PERFECT", "完美")
    s = s:gsub("INSTANT", "即时")
    s = s:gsub("DELAYED", "延迟")
    s = s:gsub("FEINT", "假动作")
    s = s:gsub("CANCEL", "取消")
    s = s:gsub("SLIDE", "滑步")
    s = s:gsub("UNKNOWN", "未知")

    s = s:gsub("LVL%s*(%d+)", "等级 %1")
    s = s:gsub("LEVEL%s*(%d+)", "等级 %1")
    s = s:gsub("(%d+)%s+MEDALS", "%1 枚奖牌")
    s = s:gsub("(%d+)%s+MEDAL", "%1 枚奖牌")
    return s
end

local function is_shun_goku_satsu_motion(motion)
    local s = tostring(motion or ""):upper()
    return s:find("SHUN%s+GOKU%s+SATSU") ~= nil or s:find("瞬狱杀") ~= nil
end

local function parse_motion_to_icons(log_entry, trial_mode, should_flip, reverse_layout)
    local d2d_cfg = ctx.d2d_cfg
    local motion_tokens = {}
    local s = log_entry.motion or ""

    -- Convert to uppercase IMMEDIATELY so that j. becomes J.
    s = s:upper()
    s = s:gsub("＋", "+")
    if log_entry.id == 1231 and is_shun_goku_satsu_motion(s) then
        s = "LP,LP,6,LK,HP (瞬狱杀)"
    end

    -- 1. Inline normalization of aerial state (J. -> [空中], keeps each [空中] at its position)
    s = s:gsub("J%.", "[空中]")
    s = s:gsub("%[空中%]%s*", "[空中] ")

    -- 2. Command inversion (Visual Only) for P2
    if should_flip then
        -- Protect content inside parentheses (plain text, e.g. "(4 Medals)")
        -- Markers without digits so they are not affected by the swap
        local paren_store = {}
        s = s:gsub("(%b())", function(match)
            table.insert(paren_store, match)
            return "##P" .. string.char(64 + #paren_store) .. "##"
        end)

        -- Protect full circle motions
        s = s:gsub("720", "{C2}")
        s = s:gsub("360", "{C1}")
        s = s:gsub("5252", "{D2}")

        -- Swap left and right (1<->3, 4<->6, 7<->9)
        local swap = { ["1"] = "3", ["3"] = "1", ["4"] = "6", ["6"] = "4", ["7"] = "9", ["9"] = "7" }
        s = s:gsub("%d", function(c) return swap[c] or c end)

        -- Restore circle motions
        s = s:gsub("{C2}", "720")
        s = s:gsub("{C1}", "360")
        s = s:gsub("{D2}", "5252")

        -- Restore parentheses intact
        s = s:gsub("##P(.)##", function(c)
            return paren_store[string.byte(c) - 64]
        end)
    end

    local text_blocks = {}
    local text_idx = 0

    s = s:gsub("%(THROW%)", "{throw}")
    s = s:gsub("THROW", "{throw}")
    s = s:gsub("LP%+LK", "{throw}")

    s = s:gsub("FORWARD DASH", "{6}{6}")
    s = s:gsub("BACK DASH", "{4}{4}")
    s = s:gsub("5252", "{2}{2}")
    s = s:gsub("720", "{360}{360}")

    -- Auto-translate to icons (Parry and Drive Rush)
    s = s:gsub("MP%+MK %(PARRY%)", "{parry}") -- Intercept native game text
    s = s:gsub("%(PARRY_JUST_[LMH]%)", "{parry}")
    s = s:gsub("PARRY_JUST_[LMH]", "{parry}")
    s = s:gsub("%(PARRY_HIT_[LMH]%)", "{parry}")
    s = s:gsub("PARRY_HIT_[LMH]", "{parry}")
    s = s:gsub("%(PARRY%)", "{parry}")
    s = s:gsub("PARRY", "{parry}")

    s = s:gsub("HP%+HK", "{di}") -- Replace raw button combo
    s = s:gsub("DI", "{di}")     -- Replace DI keyword
    s = s:gsub("%(DI%)", "")     -- Remove leftover (DI)

    s = s:gsub("%(REVERSAL%)", "{rev}")
    s = s:gsub("REVERSAL", "{rev}")

    s = s:gsub("%(WHIFF%)", "(空挥)")
    s = s:gsub("WHIFF", "空挥")

    s = s:gsub("DRIVE RUSH CANCEL", "{drc}")
    s = s:gsub("%(DRC%)", "{drc}")
    s = s:gsub("DRC", "{drc}")

    s = s:gsub("RAW DR", "{dr}")
    s = s:gsub("DRIVE RUSH", "{dr}")
    s = s:gsub("%(DR%)", "{dr}")

    -- Commas separate sequential command inputs without drawing a plus sign.
    s = s:gsub(",", "{seq}")

    -- Break the parenthesis trap for follow-ups
    s = s:gsub("%(>%)", "{followup}")
    s = s:gsub("%(> (.-)%)", "{followup} %1")
    s = s:gsub(">", "{followup}")

    s = s:gsub("%(HOLD%)", "{hold}")
    s = s:gsub("%(HOLD (.-)%)", "{hold} (%1)")
    s = s:gsub("HOLD", "{hold}")

    s = s:gsub("FOLLOW%-UP", "{followup}")
    s = localize_motion_text(s)

    if log_entry._ct_modern_display then
        s = s:gsub("%+", "{plus}")
    end

    s = s:gsub("63214", "{6}{3}{2}{1}{4}")
    s = s:gsub("41236", "{4}{1}{2}{3}{6}")
    s = s:gsub("%[4%]", "{4_hold}")
    s = s:gsub("%[2%]", "{2_hold}")
    s = s:gsub("%[6%]", "{6_hold}")
    s = s:gsub("360", "{360}")

    s = s:gsub("(%b())", function(match)
        text_idx = text_idx + 1
        text_blocks[text_idx] = match
        return string.format("{txt_%d}", text_idx)
    end)

    s = s:gsub("%f[%a]PPP%f[%A]", "{p}{p}{p}")
    s = s:gsub("%f[%a]PP%f[%A]", "{p}{p}")
    s = s:gsub("%f[%a]KKK%f[%A]", "{k}{k}{k}")
    s = s:gsub("%f[%a]KK%f[%A]", "{k}{k}")
    s = s:gsub("%f[%a]LP%f[%A]", "{lp}")
    s = s:gsub("%f[%a]MP%f[%A]", "{mp}")
    s = s:gsub("%f[%a]HP%f[%A]", "{hp}")
    s = s:gsub("%f[%a]LK%f[%A]", "{lk}")
    s = s:gsub("%f[%a]MK%f[%A]", "{mk}")
    s = s:gsub("%f[%a]HK%f[%A]", "{hk}")
    s = s:gsub("%f[%a]P%f[%A]", "{p}")
    s = s:gsub("%f[%a]K%f[%A]", "{k}")
    s = s:gsub("%f[%a]MODERN_L%f[%A]", "{modern_l}")
    s = s:gsub("%f[%a]MODERN_M%f[%A]", "{modern_m}")
    s = s:gsub("%f[%a]MODERN_H%f[%A]", "{modern_h}")
    s = s:gsub("%f[%a]MODERN_SP%f[%A]", "{modern_sp}")
    s = s:gsub("%f[%a]MODERN_AUTO%f[%A]", "{modern_auto}")
    s = s:gsub("%f[%a]AUTO%f[%A]", "{modern_auto}")
    s = s:gsub("%f[%a]SP%f[%A]", "{modern_sp}")

    local function replace_modern_text_token(src, token, img)
        local repl = "{" .. img .. "}"
        -- A modern display can contain alternate routes separated by / or |.
        -- Treat those separators as token boundaries so the final button of
        -- the first route (for example `SP + 强/236236 + 弱`) becomes an icon.
        local sep = "[%s%+%{%}/|]"
        for _ = 1, 3 do
            local before = src
            src = src:gsub("^" .. token .. "$", repl)
            src = src:gsub("^" .. token .. "(" .. sep .. ")", repl .. "%1")
            src = src:gsub("(" .. sep .. ")" .. token .. "$", "%1" .. repl)
            src = src:gsub("(" .. sep .. ")" .. token .. "(" .. sep .. ")", "%1" .. repl .. "%2")
            if src == before then break end
        end
        return src
    end

    s = replace_modern_text_token(s, "弱", "modern_l")
    s = replace_modern_text_token(s, "中", "modern_m")
    s = replace_modern_text_token(s, "強", "modern_h")
    s = replace_modern_text_token(s, "强", "modern_h")
    s = s:gsub("攻撃二つ", "{modern_l}{modern_m}")
    s = s:gsub("攻击二つ", "{modern_l}{modern_m}")
    s = s:gsub("攻撃", "{modern_h}")
    s = s:gsub("攻击", "{modern_h}")

    local i = 1
    local current_text = ""

    local function flush_text()
        if current_text ~= "" then
            local trimmed = current_text:match("^%s*(.-)%s*$")
            if trimmed ~= "" then table.insert(motion_tokens, { type = "text", val = trimmed }) end
            current_text = ""
        end
    end

    while i <= #s do
        local c = s:sub(i, i)
        if c == "{" then
            flush_text()
            local end_idx = s:find("}", i)
            if end_idx then
                local tok = s:sub(i + 1, end_idx - 1)
                if tok:sub(1, 4) == "txt_" then
                    local idx = tonumber(tok:sub(5))
                    table.insert(motion_tokens, { type = "text", val = text_blocks[idx] })
                else
                    table.insert(motion_tokens, { type = "img", val = tok:lower() })
                end
                i = end_idx + 1
            else
                i = i + 1
            end
        elseif c:match("%d") then
            flush_text()
            if c ~= "0" then table.insert(motion_tokens, { type = "img", val = c }) end
            i = i + 1
        elseif c == "+" then
            flush_text()
            i = i + 1
        else
            current_text = current_text .. c
            i = i + 1
        end
    end
    flush_text()

    -- NEW: Auto-insert PLUS icon between directions and attack buttons
    local is_btn = {
        p = true, k = true, lp = true, mp = true, hp = true, lk = true, mk = true, hk = true, throw = true,
        modern_l = true, modern_m = true, modern_h = true, modern_sp = true, modern_auto = true,
    }
    local processed_tokens = {}
    local suppress_plus = false
    for _, tok in ipairs(motion_tokens) do
        if tok.type == "img" and tok.val == "seq" then
            suppress_plus = true
        else
            if #processed_tokens > 0 then
                local prev = processed_tokens[#processed_tokens]
                if not suppress_plus and tok.type == "img" and is_btn[tok.val] then
                    if prev.type == "img" and not is_btn[prev.val] and prev.val ~= "plus" and prev.val ~= "followup" and prev.val ~= "validfollowup" then
                        table.insert(processed_tokens, { type = "img", val = "plus" })
                    end
                end
            end
            table.insert(processed_tokens, tok)
            suppress_plus = false
        end
    end
    motion_tokens = processed_tokens

    -- Swap validated followups -> validfollowup
    if log_entry.validated_followups and log_entry.validated_followups > 0 then
        local swapped = 0
        for _, tok in ipairs(motion_tokens) do
            if swapped >= log_entry.validated_followups then break end
            if tok.type == "img" and tok.val == "followup" then
                tok.val = "validfollowup"
                swapped = swapped + 1
            end
        end
    end

    -- 3. Hold status handling
    local hold_tokens = {}
    if log_entry.hold_repeat then
        -- Repeated hold case (>3): hold icon + "(xN)"
        table.insert(hold_tokens, { type = "img",  val = "hold" })
        table.insert(hold_tokens, { type = "text", val = "(x" .. log_entry.hold_repeat .. ")", col = 0xFFFFFFFF })
    elseif log_entry.is_holdable then
        local frames = log_entry.hold_frames or 0
        local status = log_entry.charge_status or "蓄力中"

        -- Universal Math Logic: Independent of engine's is_holding flag
        if log_entry.charge_min and log_entry.charge_max then
            if frames <= log_entry.charge_min then
                status = "即时"
            elseif frames >= log_entry.charge_max then
                status = "蓄满"
            else
                status = "部分"
            end
        elseif log_entry.charge_min then
            if frames <= log_entry.charge_min then
                status = "即时"
            else
                status = "部分"
            end
        end

        -- Preserve specific engine statuses like perfect timing
        if log_entry.charge_status == "PERFECT!" then
            status = "完美!"
        elseif log_entry.charge_status == "FAKE" then
            status = "伪连"
        elseif log_entry.charge_status == "LATE" then
            status = "过晚"
        elseif log_entry.charge_status == "Maxed" then
            status = "蓄满"
        end

        local col = 0xFFFFFFFF -- White (Instant default)
        local show_icon = false

        if status == "Instant" then
            col = 0xFFFFFFFF
            show_icon = false
        elseif status:match("Partial") then
            col = 0xFFFFA500 -- Orange
            show_icon = true
        elseif status:match("Maxed") or status == "PERFECT!" or status == "FAKE" then
            col = 0xFFFFFF00 -- Yellow
            show_icon = true
        elseif status == "LATE" then
            col = 0xFFFF0000 -- Red
            show_icon = true
        elseif status == "Lv1" then
            col = 0xFF00AAFF  -- Orange (ABGR)
            show_icon = true
        elseif status == "Lv2" then
            col = 0xFF00FFFF  -- Yellow (ABGR)
            show_icon = true
        else
            if frames > 0 then show_icon = true end
        end

        -- Always show frames, but hide the yellow icon if Instant
        local charge_str = ""
        if frames > 0 then
            charge_str = string.format("(%d)", frames)
        else
            charge_str = "(Hold)"
        end

        if show_icon then table.insert(hold_tokens, { type = "img", val = "hold" }) end
        table.insert(hold_tokens, { type = "text", val = charge_str, col = col })
    end

    -- 4. Combo counter management
    local combo_token = nil
    if d2d_cfg.show_combo_count then
        if trial_mode == "playing" then
            if log_entry.expected_combo ~= nil and log_entry.expected_combo > 0 then
                local actual = log_entry.actual_combo or 0
                local col = (actual >= log_entry.expected_combo) and 0xFF00FF00 or 0xFF888888
                combo_token = {
                    type = "text",
                    val = string.format("[连段: %d / %d]", actual, log_entry.expected_combo),
                    col = col
                }
            end
        elseif trial_mode == "recording" or trial_mode == "saved" then
            if log_entry.expected_combo ~= nil and log_entry.expected_combo > 0 then
                combo_token = { type = "text", val = string.format("[连段: %d]", log_entry.expected_combo), col = 0xFF00FF00 }
            end
        elseif trial_mode == "log" then
            if log_entry.combo_count ~= nil and log_entry.combo_count > 0 then
                combo_token = { type = "text", val = string.format("[连段: %d]", log_entry.combo_count), col = 0xFF00FF00 }
            end
        end
    end

    -- 5. ASSEMBLY (Inline: each [AIR] and (XXX) stays at its natural position)
    local final_tokens = {}
    if reverse_layout then
        if combo_token then
            table.insert(final_tokens, { type = "text", val = combo_token.val .. " ", col = combo_token.col })
        end

        for _, t in ipairs(motion_tokens) do table.insert(final_tokens, t) end

        if #hold_tokens > 0 then table.insert(final_tokens, { type = "text", val = " " }) end
        for _, t in ipairs(hold_tokens) do
            if t.type == "text" then
                table.insert(final_tokens, { type = "text", val = t.val .. " ", col = t.col })
            else
                table.insert(final_tokens, t)
            end
        end
    else
        for _, t in ipairs(motion_tokens) do table.insert(final_tokens, t) end

        if #hold_tokens > 0 then table.insert(final_tokens, { type = "text", val = " " }) end
        for _, t in ipairs(hold_tokens) do table.insert(final_tokens, t) end

        if combo_token then
            table.insert(final_tokens, { type = "text", val = " " .. combo_token.val, col = combo_token.col })
        end
    end

    -- Tag (打康) or (确反康) per step
    local ct = log_entry.counter_type
    if ct == 1 then
        table.insert(final_tokens, { type = "text", val = " (打康)", col = 0xFFFFFFFF })
    elseif ct == 2 then
        table.insert(final_tokens, { type = "text", val = " (确反康)", col = 0xFFFFFFFF })
    end

    return final_tokens
end

-- =========================================================
-- get_d2d_logs
-- =========================================================
local function get_d2d_logs(p_log, max_count)
    local limit = max_count or ctx.d2d_cfg.max_history
    local draw_logs = {}
    for _, log in ipairs(p_log) do
        local is_gray = not log.intentional
        if not (ctx.d2d_cfg.ignore_auto and is_gray) then
            table.insert(draw_logs, log)
            if #draw_logs >= limit then break end
        end
    end
    return draw_logs
end

-- =========================================================
-- draw_parsed_line
-- =========================================================
local function draw_parsed_line(tokens, base_x, y, icon_w, icon_h, spacing_x, final_text_y_offset, align_right,
                                color_override)
    local special_icons = { dr = true, drc = true, parry = true, rev = true, di = true }
    local line_elements = {}
    local total_w = 0

    for _, tok in ipairs(tokens) do
        if tok.type == "img" then
            if assets.imgs[tok.val] then
                local scale = (special_icons[tok.val] and ctx.d2d_cfg.special_icon_scale or 1.0)
                local current_w = icon_w * scale
                table.insert(line_elements, { type = "img", val = tok.val, w = current_w, scale = scale })
                total_w = total_w + current_w + spacing_x
            end
        elseif tok.type == "text" then
            local text_to_draw = tok.val
            if tok.val:match("{hold}") then
                table.insert(line_elements, { type = "img", val = "hold", w = icon_w, scale = 1.0 })
                total_w = total_w + icon_w + spacing_x
                text_to_draw = tok.val:gsub("{hold}%s*", "")
            end
            local w = 0
            if assets.font then w, _ = assets.font:measure(text_to_draw) end
            table.insert(line_elements, { type = "text", val = text_to_draw, w = w, col = tok.col })
            total_w = total_w + w + spacing_x
        end
    end
    if total_w > 0 then total_w = total_w - spacing_x end

    local cur_x = base_x
    if align_right then cur_x = base_x - total_w end

    for _, elem in ipairs(line_elements) do
        if elem.type == "img" then
            local img = assets.imgs[elem.val]
            if img then
                local current_h = icon_h * elem.scale
                local offset_y = (current_h - icon_h) / 2
                d2d.image(img, cur_x, y - offset_y, elem.w, current_h)
            end
            cur_x = cur_x + elem.w + spacing_x
        elseif elem.type == "text" then
            if assets.font then
                local text_color = color_override or elem.col or 0xFFFFFFFF
                d2d.text(assets.font, elem.val, cur_x + 2, y + final_text_y_offset + 2, 0xFF000000)
                d2d.text(assets.font, elem.val, cur_x, y + final_text_y_offset, text_color)
            end
            cur_x = cur_x + elem.w + spacing_x
        end
    end
    return total_w
end

local function measure_text(text)
    if assets.font then
        local w, h = assets.font:measure(tostring(text or ""))
        return w or 0, h or (assets.text_h or 0)
    end
    return 0, assets.text_h or 0
end

local function next_utf8_char(s, index)
    local b = s:byte(index)
    if not b then return nil, index + 1 end

    local len = 1
    if b >= 240 and b <= 244 then
        len = 4
    elseif b >= 224 and b <= 239 then
        len = 3
    elseif b >= 194 and b <= 223 then
        len = 2
    end

    if index + len - 1 > #s then len = 1 end
    return s:sub(index, index + len - 1), index + len
end

local function append_wrapped_text(lines, text, max_w)
    local source = tostring(text or "")
    for raw_line in (source .. "\n"):gmatch("(.-)\n") do
        local line = trim_string(raw_line)
        if line == "" then
            table.insert(lines, "")
        else
            local cur = ""
            local i = 1
            while i <= #line do
                local ch
                ch, i = next_utf8_char(line, i)
                local next_line = cur .. (ch or "")
                local w = measure_text(next_line)
                if cur ~= "" and max_w > 0 and w > max_w then
                    table.insert(lines, cur)
                    cur = ch or ""
                else
                    cur = next_line
                end
            end
            if cur ~= "" then table.insert(lines, cur) end
        end
    end
end

local function draw_text_with_shadow(font, text, x, y, color)
    d2d.text(font, text, x + 2, y + 2, 0xFF000000)
    d2d.text(font, text, x, y, color)
end

local function draw_step_note(note, x, y, final_text_y_offset)
    if not assets.font or note == "" then return end
    local text = "# " .. tostring(note)
    draw_text_with_shadow(assets.font, text, x, y + final_text_y_offset, 0xFFFFA000)
end

local function draw_trial_meta_note(sw, sh, spacing_y)
    local d2d_cfg = ctx and ctx.d2d_cfg
    if not d2d_cfg or d2d_cfg.show_trial_notes ~= true then return end
    if not assets.font then return end

    local meta = get_trial_meta()
    if not has_trial_note_content(meta) then return end

    local author_line = build_author_upload_line(meta)
    if author_line ~= "" then
        local _, author_h = measure_text(author_line)
        local author_x = sw * 0.796875
        local author_y = (sh * 0.972222) - ((author_h or 0) * 0.5)
        draw_text_with_shadow(assets.font, author_line, author_x, author_y, 0xFFE0E0E0)
    end

    local note = clean_meta_text(meta.note)
    if note == "" then return end

    local x = sw * 0.332031
    if x < 0 or x > sw then x = sw * 0.25 end
    local max_w = math.min(sw * 0.50, sw - x - (sw * 0.08))
    local lines = {}
    append_wrapped_text(lines, note, max_w)
    if #lines == 0 then return end

    local max_lines = 5
    if #lines > max_lines then
        while #lines > max_lines do table.remove(lines) end
        lines[#lines] = lines[#lines] .. "..."
    end

    local line_h = math.max((assets.text_h or 0), spacing_y * 0.60)
    local y = (sh * 0.256944) - (line_h * 0.5)
    local color = 0xFFE0E0E0
    for i, line in ipairs(lines) do
        draw_text_with_shadow(assets.font, line, x, y + (i - 1) * line_h, color)
    end
end

-- =========================================================
-- d2d_init & d2d_draw
-- =========================================================
local _img_arrow_down = nil
local _img_arrow_up = nil

local function d2d_init()
    local folder = "buttonsAndArrows/"
    for k, filename in pairs(image_files) do
        assets.imgs[k] = d2d.Image.new(folder .. filename)
    end
    _img_arrow_down = d2d.Image.new("ui_icons/chevron_down_ios.png")
    _img_arrow_up = d2d.Image.new("ui_icons/chevron_up_ios.png")
    -- Cartouche bar images (with built-in arrow + gradient)
    assets.imgs["done_bar"] = d2d.Image.new("done-bar.png")
    assets.imgs["active_bar"] = d2d.Image.new("active-bar.png")
    assets.imgs["fail_bar"] = d2d.Image.new("fail-bar.png")
    assets.imgs["success_bar"] = d2d.Image.new("success-bar.png")
end

local function draw_bar_toggle_arrows()
    if not is_combo_trials_runtime_allowed() then return end
    local pm = sdk.get_managed_singleton("app.PauseManager")
    if pm then
        local pb = pm:get_field("_CurrentPauseTypeBit")
        if pb ~= 64 and pb ~= 2112 then return end
    end
    local geo = _G._ct_bar_geometry
    if not geo then return end

    local sw, sh = d2d.surface_size()
    local collapsed = (_G._ct_bar_collapsed == true)
    local icon_sz = math.floor(sh * 0.022)
    local margin_x = math.floor(sw * 0.008)
    local arrow_y = sh - icon_sz - math.floor(sh * 0.012)

    local lx = margin_x
    local rx = sw - margin_x - icon_sz

    local img = collapsed and _img_arrow_up or _img_arrow_down
    if img then
        d2d.image(img, lx, arrow_y, icon_sz, icon_sz)
        d2d.image(img, rx, arrow_y, icon_sz, icon_sz)
    end

    -- Click detection
    if imgui.is_mouse_clicked(0) then
        local m = imgui.get_mouse()
        if m then
            local pad = 10
            if (m.x >= lx - pad and m.x <= lx + icon_sz + pad and m.y >= arrow_y - pad and m.y <= arrow_y + icon_sz + pad) or
               (m.x >= rx - pad and m.x <= rx + icon_sz + pad and m.y >= arrow_y - pad and m.y <= arrow_y + icon_sz + pad) then
                _G._ct_bar_collapsed = not _G._ct_bar_collapsed
            end
        end
    end
end

local function d2d_draw_inner()
    local runtime_allowed = is_combo_trials_runtime_allowed()
    if runtime_allowed ~= d2d_last_runtime_allowed then
        d2d_last_runtime_allowed = runtime_allowed
        local rs = _G.SF6CC_RuntimeSafety or {}
        RuntimeSafety.trace("runtime_allowed=" .. tostring(runtime_allowed)
            .. " reason=" .. tostring(rs.reason)
            .. " battle_input=" .. tostring(rs.battle_input_type)
            .. " online=" .. tostring(rs.in_online_battle)
            .. " mode=" .. tostring(_G.CurrentTrainerMode)
            .. " d2d=" .. tostring(_G.ComboTrialsD2DEnabled), "ComboTrialsD2D")
    end

    if not runtime_allowed then
        _G._ct_bar_geometry = nil
        submit_transparent_clear_pulse()
        return
    end

    local d2d_cfg = ctx and ctx.d2d_cfg
    local trial_state = ctx and ctx.trial_state
    local players = ctx and ctx.players

    local should_draw = d2d_cfg and d2d_cfg.enabled and (_G.ComboTrialsD2DEnabled == true)
    local has_training_context = _G.TrainingScriptManagerActiveThisFrame == true

    local content_visible = should_draw
        and has_training_context
        and _G.TrainingBarsDrawn == true
        and _G.CurrentTrainerMode == 4
    if content_visible ~= d2d_last_content_visible then
        d2d_last_content_visible = content_visible
        RuntimeSafety.trace("content_visible=" .. tostring(content_visible)
            .. " enabled=" .. tostring(_G.ComboTrialsD2DEnabled)
            .. " bars=" .. tostring(_G.TrainingBarsDrawn)
            .. " manager=" .. tostring(_G.TrainingScriptManagerActiveThisFrame)
            .. " mode=" .. tostring(_G.CurrentTrainerMode), "ComboTrialsD2D")
    end

    -- The matchmaking confirmation/pause UI disables ComboTrialsD2DEnabled
    -- before FlowMap leaves training. Clear at that earlier signal so the
    -- transparent frame is presented before the imminent swap-chain reset.
    if not content_visible then
        _G._ct_bar_geometry = nil
        submit_transparent_clear_pulse()
        return
    end

    local sw, sh = d2d.surface_size()

    -- content_visible is the final gate for every ComboTrials D2D command.
    if content_visible then

    ctx.cached_sw, ctx.cached_sh = sw, sh

    -- SF6 NEON MENU BACKGROUND: handled by NeonBarQueue from ComboTrials_UI on_frame only


    local pixel_font_h = d2d_cfg.font_size * sh
    if math.abs(assets.last_pixel_size - pixel_font_h) > 1.0 or assets.font == nil then
        assets.font = d2d.Font.new("msyhbd.ttc", math.floor(pixel_font_h))
        assets.last_pixel_size = pixel_font_h
        -- Measure the real rendered box height for font-independent vertical centering.
        -- d2d.text draws from the top-left of this box, and msyh's box is taller than
        -- its nominal em size, so centering on pixel_font_h would mis-align the glyphs.
        local _, mh = assets.font:measure("Combo: 8")
        assets.text_h = (mh and mh > 0) and mh or pixel_font_h
    end

    local icon_h = d2d_cfg.icon_size * sh
    local icon_w = icon_h
    local spacing_y = d2d_cfg.spacing_y * sh
    local spacing_x = d2d_cfg.spacing_x * sh

    local base_text_y = (icon_h - (assets.text_h or pixel_font_h)) / 2
    local final_text_y_offset = base_text_y + (d2d_cfg.text_y_offset * sh)

    local function draw_player_icons(p_idx, base_x, base_y, align_right, max_count, reverse_layout)
        local logs_to_draw = get_d2d_logs(players[p_idx].log, max_count)
        for i, log in ipairs(logs_to_draw) do
            local y = base_y + (i - 1) * spacing_y
            local should_flip = log.facing_left or false
            local tokens = parse_motion_to_icons(log, "log", should_flip, reverse_layout)
            draw_parsed_line(tokens, base_x, y, icon_w, icon_h, spacing_x, final_text_y_offset, align_right, nil)
        end
    end

    -- RAW INPUT DRAW (InputVisualiser-style, uses d2d_cfg.raw.* settings)
    local function draw_raw_player(history, base_x, base_y, is_right_side, max_count)
        local rc = d2d_cfg.raw or {}
        local r_icon = (rc.icon_size or 0.030) * sh
        local r_spacing_y = (rc.spacing_y or 0.040) * sh
        local r_text_y = (rc.text_y_offset or 0.002) * sh
        local mirror = is_right_side and -1.0 or 1.0

        local r_font = assets.font
        local ref_w = 0
        if r_font then ref_w, _ = r_font:measure("99") end

        local slots = {
            rc.col_frame or 0.000, rc.col_dir or 0.050,
            rc.slot1 or 0.100, rc.slot2 or 0.140, rc.slot3 or 0.180,
            rc.slot4 or 0.220, rc.slot5 or 0.260, rc.slot6 or 0.300
        }

        for i, entry in ipairs(history) do
            if i > max_count then break end
            if entry.active then
                local y = base_y + (i - 1) * r_spacing_y

                if r_font then
                    local txt = tostring(entry.frames > 99 and 99 or entry.frames)
                    local w, _ = r_font:measure(txt)
                    local off_x = slots[1] * sh * mirror
                    local anchor_x = base_x + off_x
                    local fx = is_right_side and (anchor_x + (ref_w - w)) or (anchor_x - w)
                    d2d.text(r_font, txt, fx + 2, y + r_text_y + 2, 0xFF000000)
                    d2d.text(r_font, txt, fx, y + r_text_y, 0xFFFFFFFF)
                end

                local dir_str = raw_get_numpad(entry.dir)
                local img_dir = assets.imgs[dir_str]
                if img_dir then
                    local off_x = slots[2] * sh * mirror
                    local fx = base_x + off_x
                    if is_right_side then fx = fx - r_icon end
                    d2d.image(img_dir, fx, y, r_icon, r_icon)
                end

                if entry.btn >= 16 then
                    local files = raw_get_buttons(entry.btn)
                    for idx, fname in ipairs(files) do
                        local img_btn = assets.imgs[fname]
                        if img_btn and slots[idx + 2] then
                            local off_x = slots[idx + 2] * sh * mirror
                            local fx = base_x + off_x
                            if is_right_side then fx = fx - r_icon end
                            d2d.image(img_btn, fx, y, r_icon, r_icon)
                        end
                    end
                end
            end
        end
    end

    -- Who is active in the trial?
    local target_trial_p = -1
    if trial_state.is_recording then
        target_trial_p = trial_state.recording_player
    elseif trial_state.is_playing then
        target_trial_p = trial_state.playing_player
    end

    local in_trial = (trial_state.is_recording or trial_state.is_playing)

    -- Resolve per-mode config
    local live_show_p1, live_show_p2, live_max
    local live_raw_p1, live_raw_p2, live_raw_max
    local live_mirror_p1, live_mirror_p2
    local base_pos_p1, base_pos_p2
    local base_raw_pos_p1, base_raw_pos_p2

    if in_trial then
        live_show_p1 = d2d_cfg.show_p1;       live_show_p2 = d2d_cfg.show_p2
        live_raw_p1  = d2d_cfg.raw_p1 or false; live_raw_p2 = d2d_cfg.raw_p2 or false
        live_mirror_p1 = d2d_cfg.mirror_p1 or false; live_mirror_p2 = d2d_cfg.mirror_p2 or false
        base_pos_p1  = d2d_cfg.pos_p1;        base_pos_p2 = d2d_cfg.pos_p2
        base_raw_pos_p1 = d2d_cfg.raw_pos_p1 or d2d_cfg.pos_p1
        base_raw_pos_p2 = d2d_cfg.raw_pos_p2 or d2d_cfg.pos_p2
        live_max     = d2d_cfg.max_history
        live_raw_max = d2d_cfg.raw_max_history or 19
    else
        live_show_p1 = d2d_cfg.idle_show_p1;   live_show_p2 = d2d_cfg.idle_show_p2
        live_raw_p1  = d2d_cfg.idle_raw_p1 or false; live_raw_p2 = d2d_cfg.idle_raw_p2 or false
        live_mirror_p1 = d2d_cfg.idle_mirror_p1 or false; live_mirror_p2 = d2d_cfg.idle_mirror_p2 or false
        base_pos_p1  = d2d_cfg.idle_pos_p1;   base_pos_p2 = d2d_cfg.idle_pos_p2
        base_raw_pos_p1 = d2d_cfg.raw_pos_p1 or d2d_cfg.pos_p1  -- idle raw uses trial raw positions as base
        base_raw_pos_p2 = d2d_cfg.raw_pos_p2 or d2d_cfg.pos_p2
        live_max     = d2d_cfg.idle_max_history
        live_raw_max = d2d_cfg.idle_raw_max_history or 19
    end

    -- NON-RAW : base alignment (P1=left in trial, P2=always right)
    local nr_align_p1 = in_trial
    local nr_align_p2 = true

    -- Apply mirror to non-raw
    local nr_pos_p1, nr_pos_p2 = base_pos_p1, base_pos_p2
    if live_mirror_p1 then nr_pos_p1, nr_align_p1 = apply_mirror(base_pos_p1, nr_align_p1) end
    if live_mirror_p2 then nr_pos_p2, nr_align_p2 = apply_mirror(base_pos_p2, nr_align_p2) end

    -- RAW : base flip (P1=left, P2=right)
    local raw_flip_p1 = false
    local raw_flip_p2 = true
    local raw_pos_p1, raw_pos_p2 = base_raw_pos_p1, base_raw_pos_p2

    -- Apply mirror to raw
    if live_mirror_p1 then raw_pos_p1, raw_flip_p1 = apply_mirror(base_raw_pos_p1, raw_flip_p1) end
    if live_mirror_p2 then raw_pos_p2, raw_flip_p2 = apply_mirror(base_raw_pos_p2, raw_flip_p2) end

    -- Read raw inputs
    if live_show_p1 and live_raw_p1 then raw_read_inputs(0, raw_state.history_p1, live_raw_max) end
    if live_show_p2 and live_raw_p2 then raw_read_inputs(1, raw_state.history_p2, live_raw_max) end

    -- DRAW P1
    if live_show_p1 then
        if live_raw_p1 then
            draw_raw_player(raw_state.history_p1, raw_pos_p1.x * sw, raw_pos_p1.y * sh, raw_flip_p1, live_raw_max)
        else
            draw_player_icons(0, nr_pos_p1.x * sw, nr_pos_p1.y * sh, nr_align_p1, live_max, in_trial)
        end
    end
    -- DRAW P2
    if live_show_p2 then
        if live_raw_p2 then
            draw_raw_player(raw_state.history_p2, raw_pos_p2.x * sw, raw_pos_p2.y * sh, raw_flip_p2, live_raw_max)
        else
            draw_player_icons(1, nr_pos_p2.x * sw, nr_pos_p2.y * sh, nr_align_p2, live_max, true)
        end
    end

    local function draw_trial_title()
        if d2d_cfg.trial_title_show == false then return end
        if not trial_state.sequence or not trial_state.sequence[1] then return end

        local first = trial_state.sequence[1]
        local title = first.display_name or first.title
        if type(title) ~= "string" or title == "" then return end

        local title_px = math.floor((d2d_cfg.trial_title_font_size or 0.030) * sh)
        if title_px < 10 then title_px = 10 end
        if math.abs((assets.last_title_pixel_size or -1) - title_px) > 1.0 or assets.title_font == nil then
            assets.title_font = d2d.Font.new("msyhbd.ttc", title_px)
            assets.last_title_pixel_size = title_px
        end
        if not assets.title_font then return end

        local pos = d2d_cfg.pos_trial_header or { x = 0.5, y = 0.05 }
        local tw, th = assets.title_font:measure(title)
        local x = (pos.x * sw) - ((tw or 0) * 0.5)
        local y = (pos.y * sh) - ((th or title_px) * 0.5)

        d2d.text(assets.title_font, title, x + 2, y + 2, 0xFF000000)
        d2d.text(assets.title_font, title, x, y, 0xFFFFFFFF)
    end

    draw_trial_title()

    -- TRIAL CARTOUCHE (Scrolling sequence display)
    if target_trial_p ~= -1 then
        local trial_x = (d2d_cfg.pos_trial_p1 and d2d_cfg.pos_trial_p1.x or d2d_cfg.pos_p1.x) * sw
        local trial_y = (d2d_cfg.pos_trial_p1 and d2d_cfg.pos_trial_p1.y or d2d_cfg.pos_p1.y) * sh
        local is_aligned_right = false
        local visible = d2d_cfg.trial_visible_steps
        local cartouche_w = d2d_cfg.cartouche_width * sw

        local mode = "saved"
        if trial_state.is_recording then
            mode = "recording"
        elseif trial_state.is_playing then
            mode = "playing"
        end

        local padding_y = spacing_y * 0.15
        local rect_x = is_aligned_right and (trial_x - cartouche_w + spacing_x * 2) or (trial_x - spacing_x * 2)
        local target_anim_y = nil
        local active_bg_h = spacing_y * (d2d_cfg.cartouche_height or 1.0)
        local c_off_x = (d2d_cfg.cartouche_offset_x or 0) * sw
        local c_off_y = (d2d_cfg.cartouche_offset_y or 0) * sh
        local b_off_x = (d2d_cfg.bar_img_offset_x or 0) * sw
        local b_off_y = (d2d_cfg.bar_img_offset_y or 0) * sh
        local final_rect_x = rect_x + c_off_x

        -- Build display lines (follow-up groups)
        local display_lines = build_display_lines(trial_state.sequence)
        local n_lines = #display_lines
        local trial_meta = get_trial_meta()
        local final_step = trial_state.sequence and trial_state.sequence[#trial_state.sequence] or nil
        local final_visual_complete = false
        if mode == "playing" and final_step and trial_state.current_step > #trial_state.sequence then
            local expected_combo = final_step.expected_combo or 0
            final_visual_complete = (expected_combo == 0) or ((final_step.actual_combo or 0) >= expected_combo)
        end
        local is_succ = (trial_state.success_timer > 0) or final_visual_complete

        local visual_step_idx = trial_state.current_step or 1
        local hold_step = trial_state._ui_step_hold_step
        local hold_until = trial_state._ui_step_hold_until_frame
        local frame_now = trial_state._engine_frame_count or 0
        if mode == "playing" and hold_step and hold_until and frame_now <= hold_until then
            visual_step_idx = math.max(1, math.min(hold_step, #trial_state.sequence))
        elseif hold_until and frame_now > hold_until then
            trial_state._ui_step_hold_step = nil
            trial_state._ui_step_hold_until_frame = nil
        end

        -- Find the active display_line (the one containing visual_step_idx)
        local raw_visual_dl = 1
        for dl_idx, dl in ipairs(display_lines) do
            if visual_step_idx >= dl.first and visual_step_idx <= dl.last then
                raw_visual_dl = dl_idx
                break
            end
            if visual_step_idx > dl.last then
                raw_visual_dl = dl_idx + 1
            end
        end
        if raw_visual_dl > n_lines then raw_visual_dl = n_lines end

        -- VISUAL FREEZE: Wait for button release (LILY ONLY)
        local visual_dl = raw_visual_dl
        

        -- Scroll
        local start_idx = 1
        if mode == "recording" then
            start_idx = math.max(1, n_lines - math.floor(visible / 2))
        else
            start_idx = math.max(1, visual_dl - math.floor(visible / 2))
            if start_idx + visible - 1 > n_lines then
                start_idx = math.max(1, n_lines - visible + 1)
            end
        end

        -- Animation target Y
        if mode == "playing" and n_lines > 0 then
            target_anim_y = trial_y + (visual_dl - start_idx) * spacing_y
        elseif mode == "recording" and n_lines > 0 then
            target_anim_y = trial_y + (n_lines - start_idx) * spacing_y
        end

        -- Completed step backgrounds
        if mode == "playing" then
            for dl_idx = start_idx, math.min(start_idx + visible - 1, n_lines) do
                local cur_y_pos = trial_y + (dl_idx - start_idx) * spacing_y
                if is_succ or (dl_idx < visual_dl) then
                    local sy = cur_y_pos - padding_y + c_off_y
                    if assets.imgs["done_bar"] then
                        d2d.image(assets.imgs["done_bar"], final_rect_x + b_off_x, sy + b_off_y, cartouche_w, active_bg_h)
                    else
                        d2d.fill_rect(final_rect_x, sy, cartouche_w, active_bg_h, d2d_cfg.colors.bg_success)
                        d2d.fill_rect(final_rect_x, sy, cartouche_w, 1, d2d_cfg.colors.bg_success_line)
                        d2d.fill_rect(final_rect_x, sy + active_bg_h - 1, cartouche_w, 1, d2d_cfg.colors.bg_success_line)
                    end
                end
            end
        end

        -- Animated cursor
        if target_anim_y then
            if not d2d_anim.active_y or math.abs(d2d_anim.active_y - target_anim_y) > (spacing_y * 3) then
                d2d_anim.active_y = target_anim_y
            end
            d2d_anim.active_y = d2d_anim.active_y + (target_anim_y - d2d_anim.active_y) * 0.15

            local is_fail_state = (trial_state.fail_timer and trial_state.fail_timer > 0) or trial_state.manual_reset_pending
            local bar_img = nil
            if mode == "recording" then
                bar_img = assets.imgs["success_bar"]
            elseif is_succ then
                bar_img = assets.imgs["success_bar"]
            elseif is_fail_state then
                bar_img = assets.imgs["fail_bar"]
            else
                bar_img = assets.imgs["active_bar"]
            end

            local sy = d2d_anim.active_y - padding_y + c_off_y
            if bar_img then
                d2d.image(bar_img, final_rect_x + b_off_x, sy + b_off_y, cartouche_w, active_bg_h)
            else
                local bg_c, li_c
                if mode == "recording" then
                    bg_c = 0x90FF0000; li_c = 0xFFFF0000
                else
                    bg_c = d2d_cfg.colors.bg_active; li_c = d2d_cfg.colors.bg_active_line
                end
                d2d.fill_rect(final_rect_x, sy, cartouche_w, active_bg_h, bg_c)
                d2d.fill_rect(final_rect_x, sy, cartouche_w, 3, li_c)
                d2d.fill_rect(final_rect_x, sy + active_bg_h - 3, cartouche_w, 3, li_c)
            end
        else
            d2d_anim.active_y = nil
        end

        local result_col_w = (d2d_cfg.result_col_width or 0.027) * sw
        local result_colors = {
            ok = 0xFFFFA500,
            early = 0xFF00FFAD,
            late = 0xFF00A5FF,
            wrong = 0xFFFF0000,
            missing = 0xFFFF0000,
            drop = 0xFFFF0000,
            fail = 0xFFFF0000,
        }
        draw_trial_meta_note(sw, sh, spacing_y)

        -- Draw text and icons for each visible display line
        for dl_idx = start_idx, math.min(start_idx + visible - 1, n_lines) do
            local dl = display_lines[dl_idx]
            local log_item = (#dl.steps > 1) and merge_group_log_item(dl.steps) or dl.steps[1]

            -- Number of validated follow-ups in this group (to swap followup -> validfollowup)
            if mode == "playing" and #dl.steps > 1 then
                log_item.validated_followups = math.max(0, math.min(trial_state.current_step - dl.first, #dl.steps - 1))
            end
            local y = trial_y + (dl_idx - start_idx) * spacing_y

            local current_should_flip = false
            if mode == "recording" then
                current_should_flip = log_item.facing_left or false
            else
                local step_facing_left = log_item.facing_left or false
                local init_facing_left = trial_state.sequence and trial_state.sequence[1] and trial_state.sequence[1].facing_left or false
                current_should_flip = (trial_state.flip_inputs ~= step_facing_left) ~= init_facing_left
            end

            local result_x = trial_x
            local command_x = trial_x + result_col_w
            if assets.font and log_item.ui_result_text and log_item.ui_result_text ~= "" then
                local result_text = tostring(log_item.ui_result_text)
                local result_color = result_colors[log_item.ui_result_kind or ""] or 0xFFFFFFFF
                d2d.text(assets.font, result_text, result_x + 2, y + final_text_y_offset + 2, 0xFF000000)
                d2d.text(assets.font, result_text, result_x, y + final_text_y_offset, result_color)
            end

            local tokens = parse_motion_to_icons(log_item, mode, current_should_flip, true)
            local line_w = draw_parsed_line(tokens, command_x, y, icon_w, icon_h, spacing_x, final_text_y_offset, is_aligned_right, nil)
            if d2d_cfg.show_trial_notes == true then
                local note = get_display_line_note(trial_meta, dl.first, dl.last)
                if note ~= "" then
                    draw_step_note(note, command_x + line_w + spacing_x * 3, y, final_text_y_offset)
                end
            end

            -- Smart overlay removed — bar images (done/fail/success) handle all visual states
        end

        -- Arrow on top (bar images have arrow built-in)
        if trial_state.is_playing and d2d_anim.active_y then
            -- Bar images (recording/success/fail/active) all have arrows built-in.
            -- Only draw standalone arrow when bar images are unavailable.
            if not assets.imgs["active_bar"] and not assets.imgs["fail_bar"] and not assets.imgs["success_bar"] then
                local arrow_tex = "arrow"
                local is_fail_state = (trial_state.fail_timer and trial_state.fail_timer > 0) or trial_state.manual_reset_pending
                if trial_state.success_timer > 0 then
                    arrow_tex = "arrow_success"
                elseif is_fail_state then
                    arrow_tex = "arrow_fail"
                end

                if assets.imgs[arrow_tex] then
                    local arr_w = d2d_cfg.arrow_size * sh
                    local arr_x = is_aligned_right and (trial_x - (d2d_cfg.offset_x_arrow * sw)) or
                        (trial_x + (d2d_cfg.offset_x_arrow * sw))
                    local arr_y = d2d_anim.active_y + (spacing_y - arr_w) / 2 + (d2d_cfg.offset_y_arrow * sh)
                    d2d.image(assets.imgs[arrow_tex], arr_x, arr_y, arr_w, arr_w)
                end
            end
        end
    end

    -- Mouse clicks use ImGui coordinates. Do not draw a D2D software cursor here:
    -- the game/system cursor is already visible and drawing another one creates double cursors.

    end -- close "if should_draw and not is_paused and CurrentTrainerMode == 4"

    if should_draw then
        draw_bar_toggle_arrows()
    else
        _G._ct_bar_geometry = nil
    end
end

-- =========================================================
-- Public API
-- =========================================================
local function d2d_draw()
    local ok, err = pcall(d2d_draw_inner)
    if ok then
        d2d_last_error = nil
    elseif tostring(err) ~= d2d_last_error then
        d2d_last_error = tostring(err)
        RuntimeSafety.trace("draw_error=" .. d2d_last_error, "ComboTrialsD2D")
    end
end

function M.init(shared_ctx)
    ctx = shared_ctx
    ctx.localize_motion_text = function(motion, action_id)
        if action_id == 1231 and is_shun_goku_satsu_motion(motion) then
            return "LP,LP,6,LK,HP (瞬狱杀)"
        end
        return localize_motion_text(tostring(motion or ""):upper())
    end
    d2d.register(d2d_init, d2d_draw)
end

function M.reset_anim()
    d2d_anim.active_y = nil
end

function M.reset_raw()
    raw_state.history_p1 = {}
    raw_state.history_p2 = {}
end

return M
