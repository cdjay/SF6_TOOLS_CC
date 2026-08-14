local M = {
    name = "TrainingParameterRefresh",
}

local function read_field(object, name)
    if not object then return nil, false end
    local ok, value = pcall(function() return object:get_field(name) end)
    if ok then return value, true end
    ok, value = pcall(function() return object[name] end)
    return ok and value or nil, ok == true
end

function M.request(expected)
    expected = type(expected) == "table" and expected or {}
    if not sdk or type(sdk.get_managed_singleton) ~= "function" then
        return false, "sdk_unavailable"
    end

    local tm = sdk.get_managed_singleton("app.training.TrainingManager")
    if not tm then return false, "training_manager_unavailable" end
    if expected.tm ~= nil and tm ~= expected.tm then
        return false, "stale_training_manager"
    end

    local training_data = select(1, read_field(tm, "_tData"))
    if not training_data then return false, "training_data_unavailable" end
    if expected.training_data ~= nil and training_data ~= expected.training_data then
        return false, "stale_training_data"
    end

    local parameter_setting = select(1, read_field(training_data, "ParameterSetting"))
    if not parameter_setting then return false, "parameter_setting_unavailable" end
    if expected.parameter_setting ~= nil
        and parameter_setting ~= expected.parameter_setting then
        return false, "stale_parameter_setting"
    end

    local refreshing, refresh_state_ok = read_field(tm, "_IsReqRefresh")
    if not refresh_state_ok
        or (refreshing ~= false and refreshing ~= true) then
        return false, "refresh_state_unavailable"
    end
    if refreshing == true then return false, "refresh_in_progress" end

    local ok = pcall(function() tm:set_field("_IsReqRefresh", true) end)
    if not ok then ok = pcall(function() tm._IsReqRefresh = true end) end
    if not ok then return false, "refresh_request_failed" end

    local requested, request_read_ok = read_field(tm, "_IsReqRefresh")
    if not request_read_ok or requested ~= true then
        return false, "refresh_request_unconfirmed"
    end
    return true, "refresh_requested"
end

return M
