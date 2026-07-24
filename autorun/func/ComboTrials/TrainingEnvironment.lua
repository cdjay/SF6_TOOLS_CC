local TrainingEnvironment = {
    name = "ComboTrials.TrainingEnvironment"
}

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
