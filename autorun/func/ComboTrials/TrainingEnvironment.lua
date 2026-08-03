local TrainingEnvironment = {
    name = "ComboTrials.TrainingEnvironment",
    DUMMY_ACTION = {
        STAND = 0,
        CROUCH = 1,
        JUMP = 2,
    },
    DUMMY_JUMP = {
        VERTICAL = 0,
        FRONT = 1,
        BACK = 2,
        RANDOM = 3,
    },
    DUMMY_GUARD = {
        NONE = 0,
        INTERIM_INVALID = 1,
        AFTER_FIRST_HIT = 2,
        ALL = 3,
        RANDOM = 4,
        COUNT = 5,
    },
    DUMMY_COUNTER = {
        NORMAL = 0,
        COUNTER = 1,
        PUNISH_COUNTER = 2,
        RANDOM = 3,
    },
    DUMMY_GUARD_ONLY = {
        NONE = 0,
        STAND = 1,
        CROUCH = 2,
        RANDOM = 3,
    },
    DUMMY_DRIVE_PARRY = {
        NONE = 0,
        NORMAL = 1,
        PERFECT = 2,
        RANDOM = 3,
    },
    DUMMY_DRIVE_REVERSAL = {
        NONE = 0,
        GUARD = 1,
        WAKEUP = 2,
        RANDOM = 3,
    },
    DUMMY_THROW_ESCAPE = {
        NONE = 0,
        EXECUTE = 1,
        RANDOM = 2,
    },
    DUMMY_WAKEUP = {
        STAY = 0,
        BACK = 1,
        RANDOM = 2,
    },
}

TrainingEnvironment.OPTIONAL_FIELDS = {
    "dummy_action_type",
    "dummy_jump_type",
    "dummy_jump_weight_front",
    "dummy_jump_weight_vertical",
    "dummy_jump_weight_back",
    "dummy_cpu_level",
    "dummy_counter_type",
    "dummy_counter_weight_normal",
    "dummy_counter_weight_counter",
    "dummy_counter_weight_punish",
    "dummy_guard_type",
    "dummy_guard_count",
    "dummy_guard_switching",
    "dummy_guard_weight",
    "dummy_guard_only_type",
    "dummy_drive_parry_type",
    "dummy_drive_reversal_type",
    "dummy_drive_reversal_delay",
    "dummy_drive_reversal_count",
    "dummy_drive_reversal_weight_none",
    "dummy_drive_reversal_weight_guard",
    "dummy_drive_reversal_weight_wakeup",
    "dummy_throw_escape_type",
    "dummy_throw_escape_weight",
    "dummy_wakeup_type",
    "dummy_wakeup_weight",
}

TrainingEnvironment.DEFENSE_FIELDS = {
    "dummy_drive_parry_type",
    "dummy_drive_reversal_type",
    "dummy_drive_reversal_delay",
    "dummy_drive_reversal_count",
    "dummy_drive_reversal_weight_none",
    "dummy_drive_reversal_weight_guard",
    "dummy_drive_reversal_weight_wakeup",
    "dummy_throw_escape_type",
    "dummy_throw_escape_weight",
    "dummy_wakeup_type",
    "dummy_wakeup_weight",
}

local function optional_int(value)
    local number = tonumber(value)
    if number == nil then return nil end
    return math.floor(number)
end

local function optional_bool(value)
    if type(value) == "boolean" then return value end
    if value == 1 or value == "1" or value == "true" then return true end
    if value == 0 or value == "0" or value == "false" then return false end
    return nil
end

local function bounded_int(value, minimum, maximum)
    local number = optional_int(value)
    if number == nil or number < minimum or (maximum ~= nil and number > maximum) then
        return nil
    end
    return number
end

local function valid_counter_type(value)
    return bounded_int(value, 0, 3)
end

local function counter_type_from_hit_type(hit_type)
    local normalized = tostring(hit_type or ""):upper():gsub("%s+", "")
    if normalized == "PC" or normalized == "PUNISHCOUNTER" then
        return TrainingEnvironment.DUMMY_COUNTER.PUNISH_COUNTER
    end
    if normalized == "CH" or normalized == "COUNTERHIT" then
        return TrainingEnvironment.DUMMY_COUNTER.COUNTER
    end
    return nil
end

local function counter_hit_type(counter_type)
    counter_type = valid_counter_type(counter_type)
    if counter_type == TrainingEnvironment.DUMMY_COUNTER.PUNISH_COUNTER then return "PC" end
    if counter_type == TrainingEnvironment.DUMMY_COUNTER.COUNTER then return "CH" end
    return nil
end

function TrainingEnvironment.strip_counter_tags(motion)
    local text = tostring(motion or "")
    local function strip_group(group)
        local inner = group:sub(2, -2)
        local normalized = inner:upper():gsub("[%s_%-]+", "")
        if normalized == "PC"
            or normalized == "CH"
            or normalized == "PUNISHCOUNTER"
            or normalized == "COUNTERHIT"
            or normalized == "确反康"
            or normalized == "打康" then
            return ""
        end
        return group
    end
    text = text:gsub("%b()", strip_group)
    text = text:gsub("%b[]", strip_group)
    text = text:gsub("%s*确反康%s*", " ")
    text = text:gsub("%s*打康%s*", " ")
    text = text:gsub("%s+", " ")
    return (text:match("^%s*(.-)%s*$"))
end

local function sequence_first(sequence_or_first)
    if type(sequence_or_first) ~= "table" then return nil, nil end
    if type(sequence_or_first[1]) == "table" then
        return sequence_or_first[1], sequence_or_first
    end
    return sequence_or_first, nil
end

local function canonical_counter_policy(first)
    local meta = type(first._xt_meta) == "table" and first._xt_meta or nil
    local env = meta and type(meta.environment) == "table" and meta.environment or nil
    for _, candidate in ipairs({
        { value = env and env.dummy_counter_type, source = "environment" },
        { value = meta and meta.dummy_counter_type, source = "meta" },
        { value = first.dummy_counter_type, source = "step" },
    }) do
        local value = valid_counter_type(candidate.value)
        if value ~= nil then return value, candidate.source end
    end
    return nil, nil
end

local function legacy_counter_evidence(first, sequence)
    local stats_counter = type(first.combo_stats) == "table"
        and counter_type_from_hit_type(first.combo_stats.hit_type)
        or nil
    local step_counter = nil
    if sequence then
        for _, step in ipairs(sequence) do
            local value = type(step) == "table" and valid_counter_type(step.counter_type) or nil
            if value ~= nil and value ~= TrainingEnvironment.DUMMY_COUNTER.NORMAL then
                step_counter = value
                break
            end
        end
    else
        local value = valid_counter_type(first.counter_type)
        if value ~= nil and value ~= TrainingEnvironment.DUMMY_COUNTER.NORMAL then
            step_counter = value
        end
    end
    return stats_counter, step_counter
end

function TrainingEnvironment.has_legacy_counter_conflict(sequence_or_first)
    local first, sequence = sequence_first(sequence_or_first)
    if type(first) ~= "table" then return false, nil end
    local canonical = canonical_counter_policy(first)
    local stats_counter, step_counter = legacy_counter_evidence(first, sequence)
    local conflict = canonical == TrainingEnvironment.DUMMY_COUNTER.NORMAL
        and stats_counter ~= nil
        and stats_counter == step_counter
    return conflict, conflict and stats_counter or nil
end

function TrainingEnvironment.resolve_counter_policy(sequence_or_first, infer_legacy)
    local first, sequence = sequence_first(sequence_or_first)
    if type(first) ~= "table" then
        return TrainingEnvironment.DUMMY_COUNTER.NORMAL, "default"
    end
    -- The recorded training-menu value is the fixed rule for the whole trial.
    -- A historical bulk migration wrote NORMAL into all three mirrors before
    -- consuming the old fields. Override that placeholder only when both
    -- independent legacy facts agree on the same non-normal policy.
    local canonical, canonical_source = canonical_counter_policy(first)
    local stats_counter, step_counter = legacy_counter_evidence(first, sequence)
    if infer_legacy ~= false
        and canonical == TrainingEnvironment.DUMMY_COUNTER.NORMAL
        and stats_counter ~= nil
        and stats_counter == step_counter then
        return stats_counter, "legacy_consensus"
    end
    if canonical ~= nil then return canonical, canonical_source end

    if infer_legacy ~= false then
        if stats_counter ~= nil then return stats_counter, "legacy_combo_stats" end
        if step_counter ~= nil then return step_counter, "legacy_step" end
    end
    return TrainingEnvironment.DUMMY_COUNTER.NORMAL, "default"
end

local function is_setup_or_whiff_step(step)
    if type(step) ~= "table" then return true end
    local motion = TrainingEnvironment.strip_counter_tags(step.motion):upper()
    local compact = motion:gsub("[%s_+%-]+", "")
    if motion:find("空挥", 1, true)
        or motion:find("WHIFF", 1, true)
        or motion:find("PARRY", 1, true)
        or motion:find("DRIVE PARRY", 1, true)
        or compact == "DP"
        or compact == "DR"
        or compact == "DRC"
        or compact == "RAWDR"
        or compact == "66"
        or compact == "44"
        or compact == "7"
        or compact == "8"
        or compact == "9" then
        return true
    end
    return false
end

function TrainingEnvironment.find_first_contact_step(sequence)
    if type(sequence) ~= "table" then return nil end
    for i, step in ipairs(sequence) do
        if type(step) == "table"
            and (step.has_contact == true or step.has_hit == true) then
            return i
        end
    end
    for i, step in ipairs(sequence) do
        if type(step) == "table"
            and not is_setup_or_whiff_step(step)
            and (tonumber(step.expected_combo) or 0) > 0 then
            return i
        end
    end
    local previous_damage = 0
    for i, step in ipairs(sequence) do
        if type(step) == "table" then
            local damage = tonumber(step.damage_at_step) or 0
            if not is_setup_or_whiff_step(step) and damage > previous_damage then return i end
            previous_damage = math.max(previous_damage, damage)
        end
    end
    for i, step in ipairs(sequence) do
        local legacy_counter = type(step) == "table" and valid_counter_type(step.counter_type) or nil
        if legacy_counter ~= nil
            and legacy_counter ~= TrainingEnvironment.DUMMY_COUNTER.NORMAL
            and not is_setup_or_whiff_step(step) then
            return i
        end
    end
    return nil
end

function TrainingEnvironment.normalize_counter_policy(sequence, infer_legacy)
    if type(sequence) ~= "table" or type(sequence[1]) ~= "table" then
        return TrainingEnvironment.DUMMY_COUNTER.NORMAL, nil
    end
    local first = sequence[1]
    local counter_type, source =
        TrainingEnvironment.resolve_counter_policy(sequence, infer_legacy)
    local contact_step = TrainingEnvironment.find_first_contact_step(sequence)

    first._xt_meta = type(first._xt_meta) == "table" and first._xt_meta or {}
    local meta = first._xt_meta
    meta.environment = type(meta.environment) == "table" and meta.environment or {}
    if meta.environment.schema == nil then
        meta.environment.schema = "xt.training_environment.v1"
    end
    meta.environment.dummy_counter_type = counter_type
    meta.dummy_counter_type = counter_type
    first.dummy_counter_type = counter_type

    for i, step in ipairs(sequence) do
        if type(step) == "table" then
            if step.has_hit == true then step.has_contact = true end
            step.motion = TrainingEnvironment.strip_counter_tags(step.motion)
            step.counter_type = nil
            if i == contact_step and (counter_type == 1 or counter_type == 2) then
                step.has_contact = true
            end
        end
    end
    if type(first.combo_stats) == "table" then
        first.combo_stats.hit_type = counter_hit_type(counter_type)
    end
    return counter_type, contact_step, source
end

local function recorded_value(first_step, field_name)
    first_step = type(first_step) == "table" and first_step or {}
    local meta = type(first_step._xt_meta) == "table" and first_step._xt_meta or nil
    local env = meta and type(meta.environment) == "table" and meta.environment or nil
    if field_name == "dummy_counter_type" then
        if env and env[field_name] ~= nil then return env[field_name], "environment" end
        if meta and meta[field_name] ~= nil then return meta[field_name], "meta" end
        if first_step[field_name] ~= nil then return first_step[field_name], "step" end
        return nil, "unrecorded"
    end
    if first_step[field_name] ~= nil then return first_step[field_name], "step" end
    if meta and meta[field_name] ~= nil then return meta[field_name], "meta" end
    if env and env[field_name] ~= nil then return env[field_name], "environment" end
    return nil, "unrecorded"
end

function TrainingEnvironment.recorded_value(first_step, field_name)
    return recorded_value(first_step, field_name)
end

function TrainingEnvironment.resolve_recorded_settings(first_step)
    local out = {}
    for _, field_name in ipairs(TrainingEnvironment.OPTIONAL_FIELDS) do
        local value = recorded_value(first_step, field_name)
        if value ~= nil then out[field_name] = value end
    end

    out.dummy_action_type = bounded_int(out.dummy_action_type, 0, 5)
    out.dummy_jump_type = bounded_int(out.dummy_jump_type, 0, 3)
    out.dummy_cpu_level = bounded_int(out.dummy_cpu_level, 1, 8)
    out.dummy_counter_type = bounded_int(out.dummy_counter_type, 0, 3)
    out.dummy_guard_type = bounded_int(out.dummy_guard_type, 0, 5)
    if out.dummy_guard_type == TrainingEnvironment.DUMMY_GUARD.INTERIM_INVALID then
        out.dummy_guard_type = TrainingEnvironment.DUMMY_GUARD.AFTER_FIRST_HIT
    end
    out.dummy_guard_count = bounded_int(out.dummy_guard_count, 1, 30)
    out.dummy_guard_switching = optional_bool(out.dummy_guard_switching)
    out.dummy_guard_only_type = bounded_int(out.dummy_guard_only_type, 0, 3)
    out.dummy_drive_parry_type = bounded_int(out.dummy_drive_parry_type, 0, 3)
    out.dummy_drive_reversal_type = bounded_int(out.dummy_drive_reversal_type, 0, 3)
    out.dummy_drive_reversal_delay = bounded_int(out.dummy_drive_reversal_delay, 0, nil)
    out.dummy_drive_reversal_count = bounded_int(out.dummy_drive_reversal_count, 1, nil)
    out.dummy_throw_escape_type = bounded_int(out.dummy_throw_escape_type, 0, 2)
    out.dummy_wakeup_type = bounded_int(out.dummy_wakeup_type, 0, 2)

    for _, field_name in ipairs({
        "dummy_jump_weight_front",
        "dummy_jump_weight_vertical",
        "dummy_jump_weight_back",
        "dummy_counter_weight_normal",
        "dummy_counter_weight_counter",
        "dummy_counter_weight_punish",
        "dummy_guard_weight",
        "dummy_drive_reversal_weight_none",
        "dummy_drive_reversal_weight_guard",
        "dummy_drive_reversal_weight_wakeup",
        "dummy_throw_escape_weight",
        "dummy_wakeup_weight",
    }) do
        out[field_name] = bounded_int(out[field_name], 0, nil)
    end
    return out
end

function TrainingEnvironment.has_recorded_defense_settings(first_step)
    local settings = TrainingEnvironment.resolve_recorded_settings(first_step)
    for _, field_name in ipairs(TrainingEnvironment.DEFENSE_FIELDS) do
        if settings[field_name] ~= nil then return true end
    end
    return false
end

function TrainingEnvironment.counter_type_from_runtime(nc_type, pc_type)
    nc_type = optional_int(nc_type) or 0
    pc_type = optional_int(pc_type) or 0
    if nc_type == 2 and pc_type == 2 then
        return TrainingEnvironment.DUMMY_COUNTER.RANDOM
    end
    if pc_type == 1 then return TrainingEnvironment.DUMMY_COUNTER.PUNISH_COUNTER end
    if nc_type == 1 then return TrainingEnvironment.DUMMY_COUNTER.COUNTER end
    return TrainingEnvironment.DUMMY_COUNTER.NORMAL
end

function TrainingEnvironment.drive_reversal_count_to_runtime(value)
    local count = bounded_int(value, 1, nil)
    return count and (count - 1) or nil
end

function TrainingEnvironment.drive_reversal_count_from_runtime(value)
    local runtime_count = bounded_int(value, 0, nil)
    return runtime_count and (runtime_count + 1) or nil
end

function TrainingEnvironment.cpu_level_to_runtime(value)
    local level = bounded_int(value, 1, 8)
    return level and (level - 1) or nil
end

function TrainingEnvironment.cpu_level_from_runtime(value)
    local runtime_level = bounded_int(value, 0, 7)
    return runtime_level and (runtime_level + 1) or nil
end

function TrainingEnvironment.resolve_runtime_jump_type(configured_value, random_value)
    local jump_type = optional_int(configured_value)
    if jump_type ~= TrainingEnvironment.DUMMY_JUMP.RANDOM then
        return jump_type, false
    end

    local resolved = optional_int(random_value)
    if resolved == nil then
        resolved = math.random(
            TrainingEnvironment.DUMMY_JUMP.VERTICAL,
            TrainingEnvironment.DUMMY_JUMP.BACK
        )
    end
    if resolved < TrainingEnvironment.DUMMY_JUMP.VERTICAL
        or resolved > TrainingEnvironment.DUMMY_JUMP.BACK then
        return TrainingEnvironment.DUMMY_JUMP.VERTICAL, true
    end
    return resolved, true
end

local function action_from_stance(value)
    if type(value) ~= "string" then return nil end
    local text = value:lower()
    if text == "stand" or text == "standing" then
        return TrainingEnvironment.DUMMY_ACTION.STAND
    end
    if text == "crouch" or text == "crouching" then
        return TrainingEnvironment.DUMMY_ACTION.CROUCH
    end
    if text == "jump" or text == "jumping" or text == "airborne" then
        return TrainingEnvironment.DUMMY_ACTION.JUMP
    end
    return nil
end

function TrainingEnvironment.resolve_dummy_action(first_step)
    first_step = type(first_step) == "table" and first_step or {}
    local meta = type(first_step._xt_meta) == "table" and first_step._xt_meta or nil
    local env = meta and type(meta.environment) == "table" and meta.environment or nil

    -- This semantic flag exists specifically for hitbox-dependent routes. It
    -- must outrank a stale numeric action type from an older recorder; otherwise
    -- a file can say "requires crouch" while the menu is restored to stand.
    for _, candidate in ipairs({
        { value = first_step, source = "step_requires_crouch" },
        { value = meta, source = "meta_requires_crouch" },
        { value = env, source = "environment_requires_crouch" },
    }) do
        if type(candidate.value) == "table"
            and candidate.value.requires_dummy_crouch == true then
            return TrainingEnvironment.DUMMY_ACTION.CROUCH,
                TrainingEnvironment.DUMMY_JUMP.VERTICAL,
                candidate.source
        end
    end

    for _, candidate in ipairs({
        { value = first_step, source = "step" },
        { value = meta, source = "meta" },
        { value = env, source = "environment" },
    }) do
        local value = candidate.value
        if type(value) == "table" then
            local action_type = optional_int(value.dummy_action_type)
            if action_type ~= nil then
                return action_type, optional_int(value.dummy_jump_type), candidate.source
            end
        end
    end

    for _, candidate in ipairs({
        { value = first_step, source = "step_stance" },
        { value = meta, source = "meta_stance" },
        { value = env, source = "environment_stance" },
    }) do
        local value = candidate.value
        if type(value) == "table" then
            local action_type = action_from_stance(value.dummy_stance)
            if action_type ~= nil then
                return action_type, TrainingEnvironment.DUMMY_JUMP.VERTICAL, candidate.source
            end
        end
    end

    local scene = type(first_step.scene_state) == "table" and first_step.scene_state or nil
    local players = scene and type(scene.players) == "table" and scene.players or nil
    if players then
        local recorded_by = tonumber(first_step.recorded_by or scene.recorded_by) == 1 and 1 or 0
        local defender = players[recorded_by == 1 and "p1" or "p2"]
        local status = type(defender) == "table" and defender.status or nil
        local action_type = action_from_stance(type(status) == "table" and status.stance or nil)
        if action_type ~= nil then
            return action_type, TrainingEnvironment.DUMMY_JUMP.VERTICAL, "scene_defender_stance"
        end
    end

    return nil, nil, "unrecorded"
end

local function valid_guard_type(value)
    local guard_type = tonumber(value)
    if guard_type == nil or guard_type < 0 or guard_type > 5 then return nil end
    guard_type = math.floor(guard_type)
    -- A short-lived editor build emitted 1, but the training menu and upstream
    -- WTT use 2 for "guard after first hit". Keep those local files readable.
    if guard_type == TrainingEnvironment.DUMMY_GUARD.INTERIM_INVALID then
        return TrainingEnvironment.DUMMY_GUARD.AFTER_FIRST_HIT
    end
    return guard_type
end

local function valid_guard_count(value)
    local guard_count = tonumber(value)
    if guard_count == nil then return nil end
    guard_count = math.floor(guard_count)
    if guard_count < 1 or guard_count > 30 then return nil end
    return guard_count
end

function TrainingEnvironment.guard_count_to_runtime(value)
    local guard_count = valid_guard_count(value)
    return guard_count and (guard_count - 1) or nil
end

function TrainingEnvironment.guard_count_from_runtime(value)
    local runtime_count = tonumber(value)
    if runtime_count == nil then return nil end
    runtime_count = math.floor(runtime_count)
    if runtime_count < 0 or runtime_count > 29 then return nil end
    return runtime_count + 1
end

local function named_guard_type(value)
    if type(value) ~= "string" then return nil end
    local text = value:lower()
    if text == "none" or text == "no" or text == "off" then
        return TrainingEnvironment.DUMMY_GUARD.NONE
    end
    if text == "after_first_hit" or text == "after-first-hit" or text == "after first hit" then
        return TrainingEnvironment.DUMMY_GUARD.AFTER_FIRST_HIT
    end
    if text == "all" or text == "guard_all" or text == "full" then
        return TrainingEnvironment.DUMMY_GUARD.ALL
    end
    if text == "random" then return TrainingEnvironment.DUMMY_GUARD.RANDOM end
    return nil
end

function TrainingEnvironment.resolve_dummy_guard_type(first_step, fallback)
    first_step = type(first_step) == "table" and first_step or {}
    local meta = type(first_step._xt_meta) == "table" and first_step._xt_meta or nil
    local env = meta and type(meta.environment) == "table" and meta.environment or nil

    local guard_type = valid_guard_type(first_step.dummy_guard_type)
        or (meta and valid_guard_type(meta.dummy_guard_type) or nil)
        or (env and valid_guard_type(env.dummy_guard_type) or nil)
    if guard_type ~= nil then return guard_type, "recorded" end

    local guard_name = first_step.dummy_guard
        or (meta and meta.dummy_guard or nil)
        or (env and env.dummy_guard or nil)
    guard_type = named_guard_type(guard_name)
    if guard_type ~= nil then return guard_type, "recorded_name" end

    -- Legacy recordings did not persist GuardType. A blocked Drive Impact that
    -- caused wall stun is still unambiguous evidence that the dummy guarded.
    if first_step.has_piyo == true and first_step.has_hit ~= true then
        return 3, "legacy_blocked_wall_stun"
    end

    guard_type = valid_guard_type(fallback)
    if guard_type ~= nil then return guard_type, "training_room" end
    return TrainingEnvironment.DUMMY_GUARD.AFTER_FIRST_HIT, "legacy_default"
end

function TrainingEnvironment.resolve_dummy_guard_count(first_step, fallback)
    first_step = type(first_step) == "table" and first_step or {}
    local meta = type(first_step._xt_meta) == "table" and first_step._xt_meta or nil
    local env = meta and type(meta.environment) == "table" and meta.environment or nil

    local guard_count = valid_guard_count(first_step.dummy_guard_count)
        or (meta and valid_guard_count(meta.dummy_guard_count) or nil)
        or (env and valid_guard_count(env.dummy_guard_count) or nil)
    if guard_count ~= nil then return guard_count, "recorded" end

    guard_count = valid_guard_count(fallback)
    if guard_count ~= nil then return guard_count, "training_room" end
    return nil, "unrecorded"
end

return TrainingEnvironment
