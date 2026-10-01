local TrainingGuardOverride = {}

local MODE_GUARD_TYPES = {
    [1] = 0,
    [2] = 4,
    [3] = 3,
}

function TrainingGuardOverride.new(settings)
    assert(type(settings) == "table", "guard settings dependency missing")
    local state = {
        last_mode = 0,
        saved = nil,
    }

    local controller = {}

    local function restore()
        if type(state.saved) ~= "table" then return true end
        local ok, err = settings.apply(state.saved)
        if not ok then return false, err end
        state.saved = nil
        return true, nil
    end

    function controller:update(mode)
        mode = tonumber(mode) or 0
        if mode == state.last_mode then return true, nil end

        local previous_owned = MODE_GUARD_TYPES[state.last_mode] ~= nil
        local current_guard_type = MODE_GUARD_TYPES[mode]
        local current_owned = current_guard_type ~= nil

        if previous_owned and not current_owned then
            local ok, err = restore()
            if not ok then return false, err end
        end

        if current_owned then
            if type(state.saved) ~= "table" then
                local captured, capture_err = settings.read()
                if type(captured) ~= "table" then return false, capture_err end
                state.saved = captured
            end
            local ok, err = settings.apply_type(current_guard_type)
            if not ok then return false, err end
        end

        state.last_mode = mode
        return true, nil
    end

    function controller:restore()
        local ok, err = restore()
        if ok then state.last_mode = 0 end
        return ok, err
    end

    function controller:state()
        return {
            last_mode = state.last_mode,
            has_saved_settings = type(state.saved) == "table",
        }
    end

    return controller
end

return TrainingGuardOverride
