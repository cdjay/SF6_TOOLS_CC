local ActionMatcher = {
    name = "ComboTrials.ActionMatcher",
    -- Keep runtime validation and ActionEventCompiler on the same definition
    -- of how long a physical input may bind to a later Action transition.
    PLAYER_ACTION_BIND_WINDOW = 45,
    DRIVE_PARRY_TRANSITION_WINDOW = 12,
}

local DRIVE_PARRY_INPUT_ACTIONS = {
    [480] = true,
}

local RAW_DRIVE_RUSH_ACTIONS = {
    [500] = true,
    [501] = true,
    [731] = true,
    [740] = true,
    [760] = true,
}

local DRIVE_RUSH_ACTIONS = {
    [500] = true,
    [501] = true,
    [502] = true,
    [504] = true,
    [730] = true,
    [731] = true,
    [739] = true,
    [740] = true,
    [741] = true,
    [760] = true,
    [761] = true,
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

function ActionMatcher.is_drive_parry_action_id(action_id)
    return DRIVE_PARRY_INPUT_ACTIONS[tonumber(action_id)] == true
end

function ActionMatcher.is_raw_drive_rush_action_id(action_id)
    return RAW_DRIVE_RUSH_ACTIONS[tonumber(action_id)] == true
end

function ActionMatcher.is_drive_rush_action_id(action_id)
    return DRIVE_RUSH_ACTIONS[tonumber(action_id)] == true
end

function ActionMatcher.is_drive_rush_motion(motion)
    local normalized = ActionMatcher.normalize_motion_token(motion)
    return normalized == "RAWDR" or normalized == "DRC"
end

-- raw_inputs is the portable input truth produced by the current recorder and
-- transcriber. Its generated steps already contain the Action IDs that were
-- actually observed during that exact replay, so legacy absorb/substitution
-- rules must not be allowed to replace those steps.
function ActionMatcher.sequence_uses_input_truth(sequence)
    local first = type(sequence) == "table" and sequence[1] or nil
    return type(first) == "table"
        and type(first.raw_inputs) == "table"
        and #first.raw_inputs > 0
end

-- A physical frame has one input intent. When an attack button changes on the
-- same frame as a direction, the button command owns that frame; the direction
-- must not also seed a later dash pair. This is the priority already used by
-- ActionEventCompiler and must also govern the live validator.
function ActionMatcher.should_observe_dash_direction_edge(pressed_buttons, released_buttons)
    return ((tonumber(pressed_buttons) or 0) & 0xFFF0) == 0
        and ((tonumber(released_buttons) or 0) & 0xFFF0) == 0
end

local function is_drive_parry_step(step)
    if type(step) ~= "table" then return false end
    if ActionMatcher.is_drive_parry_action_id(step.id) then return true end
    local motion = ActionMatcher.normalize_motion_token(step.motion)
    return motion == "PARRY" or motion == "DP"
end

local function is_drive_rush_step(step)
    return type(step) == "table"
        and (ActionMatcher.is_drive_rush_action_id(step.id)
            or ActionMatcher.is_drive_rush_motion(step.motion))
end

-- Runtime Action IDs are the matching truth, but an Action transition is not
-- automatically a second player command. It must also have a fresh input
-- anchor. In particular, held Drive Parry exposes a short RAW-DR-family phase
-- before a following normal on some routes. ActionEventCompiler correctly
-- leaves that unanchored phase out; this policy keeps live trial validation on
-- the same semantics without suppressing an explicitly recorded Drive Rush.
function ActionMatcher.classify_runtime_transition(params)
    params = type(params) == "table" and params or {}
    local result = {
        ignored = false,
        reason = nil,
        input_anchor_kind = params.input_anchor_kind,
        input_anchor_motion = params.input_anchor_motion,
        frames_since_previous = tonumber(params.frames_since_previous),
    }

    if params.expected_action_matches_current == true then
        result.reason = "expected_action"
        return result
    end

    local has_input_anchor = type(params.input_anchor_kind) == "string"
        and params.input_anchor_kind ~= ""
    if params.input_truth_mode == true and not has_input_anchor then
        local is_unanchored_drive_parry_phase = is_drive_parry_step(params.previous_step)
            and ActionMatcher.is_raw_drive_rush_action_id(params.actual_action_id)
            and not is_drive_rush_step(params.expected_step)
        result.ignored = true
        result.reason = is_unanchored_drive_parry_phase
            and "unanchored_drive_parry_phase_transition"
            or "unanchored_input_truth_transition"
        return result
    end

    if not is_drive_parry_step(params.previous_step) then
        result.reason = has_input_anchor and "player_input_anchored"
            or "previous_step_not_drive_parry"
        return result
    end
    if not ActionMatcher.is_raw_drive_rush_action_id(params.actual_action_id) then
        result.reason = "actual_action_not_raw_drive_rush_family"
        return result
    end
    if is_drive_rush_step(params.expected_step) then
        result.reason = "drive_rush_expected"
        return result
    end

    local elapsed = result.frames_since_previous
    if elapsed == nil or elapsed < 0
        or elapsed > ActionMatcher.DRIVE_PARRY_TRANSITION_WINDOW then
        result.reason = "outside_drive_parry_transition_window"
        return result
    end

    local incompatible_dash_anchor = params.input_anchor_kind == "double_tap"
        and ActionMatcher.normalize_motion_token(params.input_anchor_motion) ~= "66"
    if has_input_anchor and not incompatible_dash_anchor then
        result.reason = "player_input_anchored"
        return result
    end

    result.ignored = true
    result.reason = incompatible_dash_anchor
        and "drive_rush_incompatible_direction_anchor"
        or "unanchored_drive_parry_phase_transition"
    return result
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

-- Legacy exception tables can ignore a parent Action because old motion-only
-- JSON omitted it. A current raw-input recording is stronger evidence: when
-- that exact (or explicitly aliased) Action is the active expected step, the
-- legacy ignore rule must not erase it. Timeline-only WTT files keep the old
-- compatibility behavior.
function ActionMatcher.should_admit_ignored_expected_action(
    input_truth_mode,
    expected,
    actual_action_id,
    expected_exception
)
    return input_truth_mode == true
        and ActionMatcher.matches_expected_action_id(
            expected,
            actual_action_id,
            expected_exception
        )
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
    -- A recorded Action ID is the validation ground truth. Motion/input text is
    -- display and legacy fallback data; it must not advance a step when the
    -- runtime has produced a different Action ID. Known runtime variants remain
    -- supported through the explicit action_alias_ids rule above.
    local has_expected_id = expected and tonumber(expected.id) ~= nil
    local motion_matched = not has_expected_id
        and expected
        and ActionMatcher.motion_matches_expected(actual_motion, actual_input, expected)
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

function ActionMatcher.is_optional_parent_for_followup(
    actual_motion,
    expected_step,
    actual_action_id,
    expected_exception,
    previous_step,
    actual_input
)
    if type(actual_motion) ~= "string" or type(expected_step) ~= "table" then return false end
    -- An Action that is already the exact recorded expectation is never an
    -- optional parent. This guard must run before motion-based heuristics:
    -- adjacent follow-ups can legitimately share the same displayed command
    -- (for example Alex 982 -> 983, both rendered as >HK).
    if tonumber(expected_step.id) ~= nil
        and tonumber(actual_action_id) == tonumber(expected_step.id) then
        return false
    end
    local expected_motion = trim(expected_step.motion)
    local exception_motion = expected_exception and expected_exception.follow_up_motion or nil
    -- Explicit character rules describe observed runtime transitions and do
    -- not require the display notation to use a generic `>` marker. This also
    -- covers button chords such as Cammy's staggered j.Throw input.
    if expected_exception then
        if list_contains_token(expected_exception.optional_parent_ids, tonumber(actual_action_id), tonumber) then
            return true
        end
        if list_contains_token(expected_exception.optional_parent_motions, actual_motion, ActionMatcher.normalize_motion_token) then
            return true
        end
    end

    if not motion_has_followup_marker(exception_motion or expected_motion) then return false end

    -- Some commands enter an internal runtime phase after the follow-up button
    -- is pressed, before the follow-up's recorded Action ID becomes observable.
    -- Ignore only a new Action ID that still resolves to the previous command
    -- while the physical input matches the expected follow-up. The real
    -- expected Action ID must still arrive before the step can advance.
    if type(previous_step) == "table"
        and tonumber(actual_action_id) ~= nil
        and tonumber(previous_step.id) ~= nil
        and tonumber(actual_action_id) ~= tonumber(previous_step.id) then
        local actual_m = ActionMatcher.normalize_motion_token(actual_motion)
        local previous_m = ActionMatcher.normalize_motion_token(previous_step.motion)
        if actual_m ~= ""
            and actual_m == previous_m
            and ActionMatcher.motion_matches_expected(nil, actual_input, expected_step) then
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
