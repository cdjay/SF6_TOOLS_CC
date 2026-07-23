local Strategies = {
    registry = {},
    active_id = nil
}

local function set_guard_type(guard_type)
    local success = false
    pcall(function()
        local manager = sdk.get_managed_singleton("app.training.TrainingManager")
        if not manager then return end
        local guard_func = manager:call("get_GuardFunc")
        if guard_func then pcall(function() guard_func:call("ChangeGuardType", 1, guard_type) end) end
        local training_data = manager:get_field("_tData")
        local setting = training_data and training_data:get_field("GuardSetting")
        local dummy_data = setting and setting:get_field("DummyData")
        if dummy_data then dummy_data.GuardType = guard_type end
        pcall(function() manager:call("set_IsReqRefresh", true) end)
        success = true
    end)
    return success
end

function Strategies.register(strategy_id, definition)
    if type(strategy_id) ~= "string" or strategy_id == "" or type(definition) ~= "table" then return false end
    Strategies.registry[strategy_id] = definition
    return true
end

function Strategies.apply(case)
    local config = type(case) == "table" and case.opponent_strategy or nil
    local strategy_id = type(config) == "table" and config.id or "random_guard"
    local strategy = Strategies.registry[strategy_id]
    if not strategy then return false, "unknown opponent strategy: " .. tostring(strategy_id) end
    local ok = strategy.apply(config or {})
    if ok then Strategies.active_id = strategy_id end
    return ok
end

function Strategies.describe(case)
    local config = type(case) == "table" and case.opponent_strategy or nil
    local strategy_id = type(config) == "table" and config.id or "random_guard"
    local strategy = Strategies.registry[strategy_id]
    return (type(config) == "table" and config.label) or (strategy and strategy.label) or strategy_id
end

Strategies.register("random_guard", {
    label = "随机防御",
    apply = function(config)
        return set_guard_type(tonumber(config.guard_type) or 4)
    end
})

return Strategies
