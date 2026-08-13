local ActionSequenceNormalizer = {
    name = "ComboTrials.ActionSequenceNormalizer",
}

local function deep_copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end

    local copy = {}
    seen[value] = copy
    for key, child in pairs(value) do
        copy[deep_copy(key, seen)] = deep_copy(child, seen)
    end
    return copy
end

local function compact_motion(value)
    local motion = tostring(value or ""):upper():gsub("[%s_+%-]+", "")
    motion = motion:gsub("^>", "")
    motion = motion:gsub("%b()", "")
    return motion
end

local function is_raw_drive_rush_step(step, options)
    if type(step) ~= "table" then return false end
    options = type(options) == "table" and options or {}
    local motion = compact_motion(step.motion)
    if motion == "DRC" then return false end
    return (type(options.is_raw_drive_rush_action_id) == "function"
            and options.is_raw_drive_rush_action_id(step.id) == true)
        or motion == "RAWDR"
        or motion == "DR"
        or motion == "DRIVERUSH"
end

local FIRST_STEP_PAYLOAD_KEYS = {
    _xt_meta = true,
    _wtt_cn_meta = true,
    scene_state = true,
    relative_raw_inputs = true,
    raw_inputs = true,
    raw_input_file = true,
    timeline = true,
    combo_stats = true,
    recorded_by = true,
    start_pos_p1 = true,
    start_pos_p2 = true,
    start_pos_p1_raw = true,
    start_pos_p2_raw = true,
    recording_start_pos_p1 = true,
    recording_start_pos_p2 = true,
    recording_start_pos_p1_raw = true,
    recording_start_pos_p2_raw = true,
    first_action_pos_p1 = true,
    first_action_pos_p2 = true,
    first_action_pos_p1_raw = true,
    first_action_pos_p2_raw = true,
    dummy_action_type = true,
    dummy_jump_type = true,
    dummy_stance = true,
    requires_dummy_crouch = true,
    dummy_counter_type = true,
    dummy_counter_weight_normal = true,
    dummy_counter_weight_counter = true,
    dummy_counter_weight_punish = true,
    dummy_guard_type = true,
    dummy_guard_count = true,
    dummy_guard_only_type = true,
    dummy_drive_parry_type = true,
    dummy_drive_reversal_type = true,
    dummy_drive_reversal_delay = true,
    dummy_drive_reversal_count = true,
    dummy_drive_reversal_weight_none = true,
    dummy_drive_reversal_weight_guard = true,
    dummy_drive_reversal_weight_wakeup = true,
    dummy_throw_escape_type = true,
    dummy_wakeup_type = true,
    has_piyo = true,
    piyo_frame = true,
}

function ActionSequenceNormalizer.is_leading_precursor_step(step, options)
    if type(step) ~= "table" then return false end
    local motion = compact_motion(step.motion)
    return motion:match("^[1-9]$") ~= nil
        or motion == "44"
end

function ActionSequenceNormalizer.is_leading_precursor_action(params)
    params = type(params) == "table" and params or {}
    if ActionSequenceNormalizer.is_leading_precursor_step({
        motion = params.motion,
    }) then
        return true
    end

    local anchor_motion = compact_motion(params.input_anchor_motion)
    return params.input_anchor_kind == "double_tap"
        and anchor_motion == "44"
end

local function move_first_step_payload(source_first, projected_first, source_indices)
    for key, value in pairs(source_first) do
        if FIRST_STEP_PAYLOAD_KEYS[key] == true then
            projected_first[key] = deep_copy(value)
        end
    end

    local meta = type(projected_first._xt_meta) == "table"
        and projected_first._xt_meta or nil
    if meta and type(meta.step_notes) == "table" then
        local notes = {}
        for _, source_index in ipairs(source_indices or {}) do
            notes[#notes + 1] = meta.step_notes[source_index]
        end
        meta.step_notes = notes
    end
end

function ActionSequenceNormalizer.normalize(sequence, options)
    if type(sequence) ~= "table" or type(sequence[1]) ~= "table" then
        return {
            ok = false,
            reason = "invalid_sequence",
            sequence = {},
            prefix_length = 0,
        }
    end
    options = type(options) == "table" and options or {}

    local prefix_length = 0
    while prefix_length < #sequence
        and ActionSequenceNormalizer.is_leading_precursor_step(
            sequence[prefix_length + 1],
            options
        ) do
        prefix_length = prefix_length + 1
    end

    if prefix_length == #sequence then
        return {
            ok = false,
            reason = "no_detectable_action_after_leading_prefix",
            sequence = {},
            prefix_length = prefix_length,
        }
    end

    local projected = {}
    local source_indices = {}
    local inline_removed_count = 0
    for source_index = prefix_length + 1, #sequence do
        local source_step = sequence[source_index]
        local projected_step = deep_copy(source_step)
        if is_raw_drive_rush_step(source_step, options)
            and type(options.classify_raw_drive_rush_precursor) == "function" then
            local merged_delay = tonumber(source_step.delay_from_prev) or 0
            local successor = source_step
            local successor_owned = false
            local removed_kinds = {}
            while #projected > 0 do
                local candidate = projected[#projected]
                local owned, precursor_kind =
                    options.classify_raw_drive_rush_precursor(
                        candidate,
                        successor,
                        successor_owned,
                        projected[#projected - 1]
                    )
                if owned ~= true or precursor_kind == nil
                    or removed_kinds[precursor_kind] == true then
                    break
                end
                removed_kinds[precursor_kind] = true
                merged_delay = merged_delay
                    + (tonumber(candidate.delay_from_prev) or 0)
                successor = candidate
                successor_owned = true
                table.remove(projected)
                table.remove(source_indices)
                inline_removed_count = inline_removed_count + 1
            end
            projected_step.delay_from_prev = #projected == 0 and 0 or merged_delay
        end
        projected[#projected + 1] = projected_step
        source_indices[#source_indices + 1] = source_index
    end

    projected[1].delay_from_prev = 0
    move_first_step_payload(sequence[1], projected[1], source_indices)

    return {
        ok = true,
        reason = inline_removed_count > 0 and "raw_drive_rush_precursors_removed"
            or (prefix_length > 0 and "leading_prefix_removed" or "unchanged"),
        sequence = projected,
        prefix_length = prefix_length,
        inline_removed_count = inline_removed_count,
        first_source_index = source_indices[1],
        source_indices = source_indices,
    }
end

return ActionSequenceNormalizer
