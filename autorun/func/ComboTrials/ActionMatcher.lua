local ActionMatcher = {
    name = "ComboTrials.ActionMatcher"
}

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function list_contains_number(value, target)
    local target_number = tonumber(target)
    if value == nil or target_number == nil then return false end

    if type(value) == "table" then
        for _, item in ipairs(value) do
            if tonumber(item) == target_number then return true end
        end
        return false
    end

    for item in tostring(value):gmatch("[^,]+") do
        if tonumber(item:match("^%s*(.-)%s*$")) == target_number then
            return true
        end
    end
    return false
end

local function map_number_for_id(value, action_id)
    if type(value) ~= "table" or action_id == nil then return nil end
    return tonumber(value[tostring(action_id)] or value[tonumber(action_id)])
end

function ActionMatcher.normalize_motion_token(value)
    local s = tostring(value or ""):upper():gsub("%s+", "")
    -- Recorded combo JSON can contain equivalent historical spellings.
    -- Normalize them so old recordings keep their motion fallback when the
    -- unified command table adopts one canonical display form.
    s = s:gsub("DRIVERUSH", "RAWDR")
    s = s:gsub("LP%+LK", "THROW")
    s = s:gsub("%(THROW%)", "THROW")
    s = s:gsub("%+", "")
    s = s:gsub("^>%s*", "")
    s = s:gsub("%(空挥%)", "")
    s = s:gsub("%(绌烘尌%)", "")
    s = s:gsub("%(WHIFF%)", "")
    s = s:gsub("（空挥）", "")
    s = s:gsub("（绌烘尌）", "")
    s = s:gsub("（WHIFF）", "")
    return s
end

function ActionMatcher.motion_matches_expected(actual_motion, actual_input, expected)
    if not expected then return false end
    local actual_m = ActionMatcher.normalize_motion_token(actual_motion)
    local actual_i = ActionMatcher.normalize_motion_token(actual_input)
    local expected_m = ActionMatcher.normalize_motion_token(expected.motion)
    if actual_m ~= "" and actual_m == expected_m then return true end
    if actual_i ~= "" and actual_i == expected_m then return true end
    if type(expected.motion_aliases) == "table" then
        for _, alias in ipairs(expected.motion_aliases) do
            local a = ActionMatcher.normalize_motion_token(alias)
            if a ~= "" and (actual_m == a or actual_i == a) then return true end
        end
    end
    return false
end

function ActionMatcher.matches_expected_action_id(expected, actual_action_id, expected_exception)
    if type(expected) ~= "table" then return false end
    local expected_id = tonumber(expected.id)
    local actual_id = tonumber(actual_action_id)
    if expected_id == nil or actual_id == nil then return false end
    if expected_id == actual_id then return true end
    return list_contains_number(expected_exception and expected_exception.action_alias_ids, actual_id)
end

function ActionMatcher.effective_expected_combo(expected, previous_step, expected_exception)
    if type(expected) ~= "table" then return nil, "missing_expected" end
    local recorded_combo = tonumber(expected.expected_combo)
    local runtime_action_id = tonumber(expected._runtime_action_id)
    local variant_delta = map_number_for_id(
        expected_exception and expected_exception.action_alias_combo_deltas,
        runtime_action_id
    )
    local previous_combo = type(previous_step) == "table"
        and tonumber(previous_step.expected_combo) or nil

    if variant_delta ~= nil and previous_combo ~= nil then
        return previous_combo + variant_delta, "action_alias_combo_delta"
    end
    return recorded_combo, "recorded_expected_combo"
end

function ActionMatcher.is_completion_satisfied(expected, previous_step, expected_exception, observed_combo)
    local required_combo, combo_source = ActionMatcher.effective_expected_combo(
        expected,
        previous_step,
        expected_exception
    )
    local observed = tonumber(observed_combo) or 0

    if expected_exception and expected_exception.finish_on_first_hit == true then
        if expected and expected._runtime_connected_on_match == true then
            return true, required_combo, "connected_on_action_match"
        end

        local match_combo = expected and tonumber(expected._runtime_combo_on_match) or nil
        if match_combo ~= nil and observed > match_combo then
            return true, required_combo, "connected_after_action_match"
        end
    end

    local satisfied = required_combo == nil or required_combo == 0 or observed >= required_combo
    return satisfied, required_combo, combo_source
end

function ActionMatcher.match_expected_action(expected, actual_action_id, actual_motion, actual_input, expected_exception)
    local exact_id_matched = expected
        and tonumber(actual_action_id) ~= nil
        and tonumber(actual_action_id) == tonumber(expected.id)
    local alias_id_matched = not exact_id_matched
        and ActionMatcher.matches_expected_action_id(expected, actual_action_id, expected_exception)
    local motion_matched = expected and ActionMatcher.motion_matches_expected(actual_motion, actual_input, expected)
    return {
        matched = exact_id_matched or alias_id_matched or motion_matched or false,
        match_reason = exact_id_matched and "id"
            or (alias_id_matched and "action_alias_id")
            or (motion_matched and "motion" or "none"),
        expected_id = expected and expected.id or nil,
        actual_action_id = actual_action_id,
        expected_entry = expected,
        actual_entry = {
            id = actual_action_id,
            motion = actual_motion,
            input = actual_input
        }
    }
end

function ActionMatcher.is_exact_expected_action(expected, actual_action_id)
    if type(expected) ~= "table" then return false end
    local expected_id = tonumber(expected.id)
    local actual_id = tonumber(actual_action_id)
    return expected_id ~= nil and actual_id ~= nil and expected_id == actual_id
end

local function list_contains_token(value, token, normalizer)
    if value == nil or token == nil then return false end
    token = normalizer and normalizer(token) or tostring(token)

    if type(value) == "table" then
        for _, item in ipairs(value) do
            local candidate = normalizer and normalizer(item) or tostring(item)
            if candidate == token then return true end
        end
        return false
    end

    for item in tostring(value):gmatch("[^,]+") do
        local candidate = item:match("^%s*(.-)%s*$")
        candidate = normalizer and normalizer(candidate) or candidate
        if candidate == token then return true end
    end
    return false
end

local function motion_has_followup_marker(value)
    local motion = trim(value)
    return motion:sub(1, 1) == ">" or motion:find(">", 1, true) ~= nil
end

function ActionMatcher.is_optional_parent_for_followup(actual_motion, expected_step, actual_action_id, expected_exception)
    if type(actual_motion) ~= "string" or type(expected_step) ~= "table" then return false end
    local expected_motion = trim(expected_step.motion)
    local exception_motion = expected_exception and expected_exception.follow_up_motion or nil
    if not motion_has_followup_marker(exception_motion or expected_motion) then return false end

    if expected_exception then
        if list_contains_token(expected_exception.optional_parent_ids, tonumber(actual_action_id), tonumber) then
            return true
        end
        if list_contains_token(expected_exception.optional_parent_motions, actual_motion, ActionMatcher.normalize_motion_token) then
            return true
        end
    end

    if expected_motion:sub(1, 1) ~= ">" then return false end
    local motion = actual_motion:match("^%s*(.-)%s*$")
    return motion == "214+P"
end

function ActionMatcher.build_edit_exception(p_state)
    local parsed_prev = nil
    if p_state.edit_ignore_prev_id ~= "" then
        local ids = {}
        for tok in p_state.edit_ignore_prev_id:gmatch("[^,]+") do
            local n = tonumber(tok:match("^%s*(.-)%s*$"))
            if n then ids[#ids+1] = n end
        end
        if #ids == 1 then parsed_prev = ids[1]
        elseif #ids > 1 then parsed_prev = ids end
    end
    return {
        ignore = p_state.edit_ignore,
        force = p_state.edit_force,
        is_holdable = p_state.edit_holdable,
        hold_partial_check = p_state.edit_hold_partial_check,
        absorb_ids = p_state.edit_absorb_ids,
        charge_min = tonumber(p_state.edit_charge_min),
        charge_max = tonumber(p_state.edit_charge_max),
        ignore_prev_id = parsed_prev,
        ignore_prev_frames = tonumber(p_state.edit_ignore_prev_frames) or 5
    }
end

function ActionMatcher.matches_absorb_id(exception, actual_action_id)
    if not exception or not exception.absorb_ids or type(exception.absorb_ids) ~= "string" or exception.absorb_ids == "" then
        return false
    end
    for absorb_str in string.gmatch(exception.absorb_ids, "([^,]+)") do
        local absorb_num = tonumber(absorb_str:match("^%s*(.-)%s*$"))
        if absorb_num and absorb_num == actual_action_id then
            return true
        end
    end
    return false
end

function ActionMatcher.evaluate_ignore_prev(exception, log, frame_count)
    if not (exception and exception.ignore_prev_id) then
        return { ignored = false, reason = nil }
    end
    local check_ids = type(exception.ignore_prev_id) == "table" and exception.ignore_prev_id or { exception.ignore_prev_id }
    for i = 1, math.min(10, #log) do
        local prev_log = log[i]
        for _, cid in ipairs(check_ids) do
            if prev_log.id == cid then
                local frames_since = frame_count - (prev_log.start_frame or frame_count)
                if frames_since <= (exception.ignore_prev_frames or 5) then
                    local id_disp = type(exception.ignore_prev_id) == "table" and table.concat(exception.ignore_prev_id, ",") or tostring(exception.ignore_prev_id)
                    return {
                        ignored = true,
                        reason = "[例外：在 ID " .. id_disp .. " 后忽略]"
                    }
                end
            end
        end
    end
    return { ignored = false, reason = nil }
end

function ActionMatcher.is_force_enabled(exception)
    return exception and exception.force == true
end

function ActionMatcher.is_exception_ignored(exception)
    return exception and exception.ignore == true
end

function ActionMatcher.hold_partial_check_enabled(exception)
    return (exception and exception.hold_partial_check ~= false) and true or false
end

return ActionMatcher
