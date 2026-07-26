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
}

local function optional_int(value)
    local number = tonumber(value)
    if number == nil then return nil end
    return math.floor(number)
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
    if guard_type == nil or guard_type < 0 or guard_type > 4 then return nil end
    return math.floor(guard_type)
end

local function named_guard_type(value)
    if type(value) ~= "string" then return nil end
    local text = value:lower()
    if text == "none" or text == "no" or text == "off" then return 0 end
    if text == "after_first_hit" or text == "after-first-hit" or text == "after first hit" then return 2 end
    if text == "all" or text == "guard_all" or text == "full" then return 3 end
    if text == "random" then return 4 end
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
    return 2, "legacy_default"
end

return TrainingEnvironment
