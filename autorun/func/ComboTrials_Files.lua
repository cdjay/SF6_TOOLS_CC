-- =========================================================
-- ComboTrials_Files.lua - Combo JSON loading and list management.
-- Receives shared context via init(); mutates ctx.file_system in place.
-- =========================================================

local json = json
local fs = fs
local log = log

local M = {}

local ctx
local trial_state, players, file_system
local normalize_sequence_counter_types, assign_groups
local restore_trial_dummy_action_type

local function warn_combo_file_once(path, reason)
    local warnings = file_system.combo_file_warnings
    local key = tostring(path) .. "|" .. tostring(reason)
    if warnings[key] then return end
    warnings[key] = true

    local message = string.format("[ComboTrials] Skipping combo file: %s (%s)", tostring(path), tostring(reason))
    pcall(print, message)
    if log and log.warn then pcall(log.warn, message) end
end

local function diag_combo_files(message)
    if file_system and file_system.diag_enabled and file_system.diag_log then
        file_system.diag_log("[Files] " .. tostring(message))
    end
end

local function is_valid_combo_sequence(sequence)
    if type(sequence) ~= "table" or type(sequence[1]) ~= "table" then
        return false, "not a combo sequence"
    end

    for idx, step in ipairs(sequence) do
        if type(step) ~= "table" then
            return false, "invalid step " .. tostring(idx)
        end
    end
    return true
end

local function load_combo_json(path)
    local ok, loaded = pcall(json.load_file, path)
    if not ok then return nil, tostring(loaded) end
    local valid, reason = is_valid_combo_sequence(loaded)
    if not valid then return nil, reason end
    return loaded
end

function M.load_combo_from_file(path, force)
    if trial_state._xt_pending_save and not force then return false end
    if not path then return false end

    local loaded, load_error = load_combo_json(path)
    if not loaded then
        warn_combo_file_once(path, load_error or "JSON load failed")
        return false
    end

    local prepared, prepare_error = pcall(function()
        normalize_sequence_counter_types(loaded)
        assign_groups(loaded)
    end)
    if not prepared then
        warn_combo_file_once(path, prepare_error or "combo preparation failed")
        return false
    end

    if restore_trial_dummy_action_type then
        pcall(restore_trial_dummy_action_type)
    end

    trial_state.sequence = loaded
    trial_state.current_step = 1
    trial_state.is_playing = false
    trial_state.current_file = path
    trial_state.current_file_path = path
    trial_state.current_file_name = tostring(path):match("([^/\\]+)$") or tostring(path)
    trial_state._match_probe = nil
    trial_state._match_probe_history = nil
    trial_state._verify_trace_dump = nil
    if loaded[1] then
        trial_state.start_pos_p1 = loaded[1].start_pos_p1
        trial_state.start_pos_p2 = loaded[1].start_pos_p2
        trial_state.start_pos_p1_raw = loaded[1].start_pos_p1_raw
        trial_state.start_pos_p2_raw = loaded[1].start_pos_p2_raw
    end
    return true
end

function M.clear_combo_state()
    if restore_trial_dummy_action_type then
        pcall(restore_trial_dummy_action_type)
    end

    trial_state.sequence = {}
    trial_state.current_step = 1
    trial_state.is_playing = false
    trial_state.start_pos_p1 = nil
    trial_state.start_pos_p2 = nil
    trial_state.start_pos_p1_raw = nil
    trial_state.start_pos_p2_raw = nil
    trial_state.live_start_pos_p1 = nil
    trial_state.live_start_pos_p2 = nil
    trial_state.live_start_pos_p1_raw = nil
    trial_state.live_start_pos_p2_raw = nil
    trial_state.current_file = nil
    trial_state.current_file_path = nil
    trial_state.current_file_name = nil
    trial_state._match_probe = nil
    trial_state._match_probe_history = nil
    trial_state._verify_trace_dump = nil
end

local function sanitize_utf8_display(value)
    local s = tostring(value or "")
    local out = {}
    local i = 1

    while i <= #s do
        local b1 = s:byte(i)
        if b1 == 0 or b1 < 32 or b1 == 127 then
            out[#out + 1] = "?"
            i = i + 1
        elseif b1 < 128 then
            out[#out + 1] = s:sub(i, i)
            i = i + 1
        else
            local length = 0
            if b1 >= 194 and b1 <= 223 then
                length = 2
            elseif b1 >= 224 and b1 <= 239 then
                length = 3
            elseif b1 >= 240 and b1 <= 244 then
                length = 4
            end

            local valid = length > 0 and (i + length - 1) <= #s
            if valid then
                for offset = 1, length - 1 do
                    local bx = s:byte(i + offset)
                    if not bx or bx < 128 or bx > 191 then
                        valid = false
                        break
                    end
                end
            end

            if valid and length == 3 then
                local b2 = s:byte(i + 1)
                valid = not ((b1 == 224 and b2 < 160) or (b1 == 237 and b2 >= 160))
            elseif valid and length == 4 then
                local b2 = s:byte(i + 1)
                valid = not ((b1 == 240 and b2 < 144) or (b1 == 244 and b2 >= 144))
            end

            if valid then
                out[#out + 1] = s:sub(i, i + length - 1)
                i = i + length
            else
                out[#out + 1] = "?"
                i = i + 1
            end
        end
    end

    return table.concat(out)
end

local function combo_display_name_from_file(filepath)
    local fallback = sanitize_utf8_display(filepath:match("([^/\\]+)$") or filepath)
    local sequence, load_error = load_combo_json(filepath)
    if not sequence then
        return nil, load_error or "JSON load failed"
    end

    local function clean_title(value)
        if type(value) ~= "string" then return nil end
        local title = value:match("^%s*(.-)%s*$") or ""
        if title == "" then return nil end
        return sanitize_utf8_display(title)
    end

    local xt_meta = sequence[1]._xt_meta
    local xt_title = type(xt_meta) == "table" and clean_title(xt_meta.title) or nil
    if xt_title then
        return fallback .. " " .. xt_title, nil
    end

    local wtt_meta = sequence[1]._wtt_cn_meta
    local wtt_title = type(wtt_meta) == "table" and clean_title(wtt_meta.title) or nil
    if wtt_title then
        return fallback .. " " .. wtt_title, nil
    end

    return fallback, nil
end

local function scan_combo_files(player_idx)
    local display_list, path_list = {}, {}
    local skipped_count = 0
    if not players[player_idx] then
        diag_combo_files("scan skipped player=" .. tostring(player_idx) .. " reason=missing_player")
        return display_list, path_list, false, skipped_count
    end

    local char_name = players[player_idx].profile_name
    if char_name == "Unknown" then
        diag_combo_files("scan skipped player=" .. tostring(player_idx) .. " reason=unknown_character")
        return display_list, path_list, false, skipped_count
    end

    if fs.create_dir then
        pcall(fs.create_dir, "TrainingComboTrials_data/CustomCombos")
        pcall(fs.create_dir, "TrainingComboTrials_data/CustomCombos/" .. char_name)
    end

    local glob_pattern = "TrainingComboTrials_data\\\\CustomCombos\\\\" .. char_name .. "\\\\.*json"
    diag_combo_files("scan begin player=" .. tostring(player_idx) .. " char=" .. tostring(char_name) .. " pattern=" .. tostring(glob_pattern))
    local glob_ok, files = pcall(fs.glob, glob_pattern)
    if not glob_ok or type(files) ~= "table" then
        warn_combo_file_once(char_name, glob_ok and "glob returned invalid data" or files)
        diag_combo_files("glob failed player=" .. tostring(player_idx) .. " char=" .. tostring(char_name)
            .. " ok=" .. tostring(glob_ok) .. " error=" .. tostring(files))
        return display_list, path_list, false, skipped_count
    end
    diag_combo_files("glob result player=" .. tostring(player_idx) .. " char=" .. tostring(char_name)
        .. " found=" .. tostring(#files))

    if files then
        local function filename_only(filepath)
            filepath = tostring(filepath or "")
            return (filepath:match("([^/\\]+)$") or filepath):lower()
        end

        local function next_sort_token(s, pos)
            local c = s:sub(pos, pos)
            local is_num = c:match("%d") ~= nil
            local start_pos = pos
            while pos <= #s do
                local ch = s:sub(pos, pos)
                if (ch:match("%d") ~= nil) ~= is_num then break end
                pos = pos + 1
            end
            local raw = s:sub(start_pos, pos - 1)
            return is_num, raw, tonumber(raw) or 0, pos
        end

        local function windows_filename_less(a, b)
            local sa = filename_only(a)
            local sb = filename_only(b)
            local ia, ib = 1, 1

            while ia <= #sa and ib <= #sb do
                local a_num, a_raw, a_val, next_a = next_sort_token(sa, ia)
                local b_num, b_raw, b_val, next_b = next_sort_token(sb, ib)

                if a_num and b_num then
                    if a_val ~= b_val then return a_val < b_val end
                    if #a_raw ~= #b_raw then return #a_raw < #b_raw end
                elseif a_raw ~= b_raw then
                    return a_raw < b_raw
                end

                ia, ib = next_a, next_b
            end

            return #sa < #sb
        end

        local sort_ok, sort_error = pcall(table.sort, files, function(a, b)
            return windows_filename_less(a, b)
        end)
        if not sort_ok then
            warn_combo_file_once(char_name, "file sort failed: " .. tostring(sort_error))
        end

        for _, filepath in ipairs(files) do
            if type(filepath) == "string" and not filepath:find("_FAIL_", 1, true) then
                local display_name, display_error = combo_display_name_from_file(filepath)
                if display_name then
                    table.insert(path_list, filepath)
                    table.insert(display_list, display_name)
                else
                    skipped_count = skipped_count + 1
                    warn_combo_file_once(filepath, display_error or "invalid combo file")
                end
            elseif type(filepath) ~= "string" then
                skipped_count = skipped_count + 1
                warn_combo_file_once(char_name, "glob returned a non-string entry")
            end
        end
    end

    diag_combo_files("scan result player=" .. tostring(player_idx) .. " char=" .. tostring(char_name)
        .. " found=" .. tostring(files and #files or 0)
        .. " loaded=" .. tostring(#path_list)
        .. " skipped=" .. tostring(skipped_count)
        .. " displayed=" .. tostring(#display_list))
    return display_list, path_list, true, skipped_count
end

local function update_combo_file_list(player_idx)
    local display_list, path_list, scan_ok, skipped_count = scan_combo_files(player_idx)
    if not scan_ok then return false end

    if player_idx == 0 then
        file_system.saved_combos_display_p1 = display_list
        file_system.saved_combos_paths_p1 = path_list
        file_system.skipped_combos_p1 = skipped_count
    else
        file_system.saved_combos_display_p2 = display_list
        file_system.saved_combos_paths_p2 = path_list
        file_system.skipped_combos_p2 = skipped_count
    end
    return true
end

local function find_combo_path_index(paths, old_path, old_idx)
    if old_path then
        for idx, path in ipairs(paths) do
            if path == old_path then return idx end
        end
    end
    if #paths == 0 then return 1 end
    return math.min(old_idx or 1, #paths)
end

local function reload_selected_combo_if_idle()
    if trial_state.is_playing or trial_state.is_recording or trial_state._xt_pending_save or (ctx.demo_state and ctx.demo_state.is_playing) then return end

    local player_idx = ctx.ui_state.viewed_player or trial_state.playing_player or 0
    local paths = (player_idx == 0) and file_system.saved_combos_paths_p1 or file_system.saved_combos_paths_p2
    local idx = (player_idx == 0) and (file_system.selected_file_idx_p1 or 1) or (file_system.selected_file_idx_p2 or 1)
    local path_to_load = paths and paths[idx]

    if path_to_load then
        if not M.load_combo_from_file(path_to_load) then
            M.clear_combo_state()
        end
    else
        M.clear_combo_state()
    end
end

function M.refresh_combo_list_preserve_selection(reload_current_file)
    local old_p1_path = file_system.saved_combos_paths_p1[file_system.selected_file_idx_p1 or 1]
    local old_p2_path = file_system.saved_combos_paths_p2[file_system.selected_file_idx_p2 or 1]
    local old_p1_idx = file_system.selected_file_idx_p1 or 1
    local old_p2_idx = file_system.selected_file_idx_p2 or 1

    update_combo_file_list(0)
    update_combo_file_list(1)

    file_system.selected_file_idx_p1 = find_combo_path_index(file_system.saved_combos_paths_p1, old_p1_path, old_p1_idx)
    file_system.selected_file_idx_p2 = find_combo_path_index(file_system.saved_combos_paths_p2, old_p2_path, old_p2_idx)

    if reload_current_file then
        reload_selected_combo_if_idle()
    end
end

function M.refresh_combo_list(recent_saved_player)
    if trial_state._xt_pending_save then
        M.refresh_combo_list_preserve_selection(false)
        return
    end

    update_combo_file_list(0)
    update_combo_file_list(1)

    local target_player = recent_saved_player or 0
    if target_player == 1 and #file_system.saved_combos_paths_p2 == 0 then target_player = 0 end
    if target_player == 0 and #file_system.saved_combos_paths_p1 == 0 then target_player = 1 end

    local path_to_load = nil
    if target_player == 0 and #file_system.saved_combos_paths_p1 > 0 then
        file_system.selected_file_idx_p1 = 1
        path_to_load = file_system.saved_combos_paths_p1[1]
    elseif target_player == 1 and #file_system.saved_combos_paths_p2 > 0 then
        file_system.selected_file_idx_p2 = 1
        path_to_load = file_system.saved_combos_paths_p2[1]
    end

    if not M.load_combo_from_file(path_to_load) then
        M.clear_combo_state()
    end
end

function M.init(context, opts)
    ctx = context
    opts = opts or {}
    trial_state = assert(ctx.trial_state, "ComboTrials_Files requires ctx.trial_state")
    players = assert(ctx.players, "ComboTrials_Files requires ctx.players")
    file_system = assert(ctx.file_system, "ComboTrials_Files requires ctx.file_system")
    normalize_sequence_counter_types = assert(opts.normalize_sequence_counter_types, "ComboTrials_Files requires normalize_sequence_counter_types")
    assign_groups = assert(opts.assign_groups, "ComboTrials_Files requires assign_groups")
    restore_trial_dummy_action_type = opts.restore_trial_dummy_action_type

    file_system.combo_file_warnings = file_system.combo_file_warnings or {}
    file_system.warn_combo_file_once = warn_combo_file_once
    file_system.is_valid_combo_sequence = is_valid_combo_sequence
    file_system.load_combo_json = load_combo_json
    file_system.sanitize_utf8_display = sanitize_utf8_display
    file_system.combo_display_name_from_file = combo_display_name_from_file
    file_system.scan_combo_files = scan_combo_files
    file_system.update_combo_file_list = update_combo_file_list

    return M
end

return M
