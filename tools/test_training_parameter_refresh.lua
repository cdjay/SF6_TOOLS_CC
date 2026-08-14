package.path = package.path
    .. ";./autorun/?.lua"
    .. ";./autorun/?/init.lua"

local function object(fields)
    fields = fields or {}
    function fields:get_field(name)
        return self[name]
    end
    return fields
end

local parameter_setting = object({})
local training_data = object({ ParameterSetting = parameter_setting })
local manager = object({
    _tData = training_data,
    _IsReqRefresh = false,
})

sdk = {
    get_managed_singleton = function(name)
        if name == "app.training.TrainingManager" then return manager end
        return nil
    end,
}

local Refresh = require("func/TrainingParameterRefresh")
local ok, reason = Refresh.request({
    tm = manager,
    training_data = training_data,
    parameter_setting = parameter_setting,
})
assert(ok == true and reason == "refresh_requested"
        and manager._IsReqRefresh == true,
    "a stable current ParameterSetting identity must request one refresh")

manager._IsReqRefresh = false
local stale_parameter_setting = parameter_setting
parameter_setting = object({})
training_data.ParameterSetting = parameter_setting
ok, reason = Refresh.request({
    tm = manager,
    training_data = training_data,
    parameter_setting = stale_parameter_setting,
})
assert(ok == false and reason == "stale_parameter_setting"
        and manager._IsReqRefresh == false,
    "a replaced ParameterSetting must fail closed without invoking stale state")

local stale_training_data = training_data
training_data = object({ ParameterSetting = object({}) })
manager._tData = training_data
ok, reason = Refresh.request({
    tm = manager,
    training_data = stale_training_data,
    parameter_setting = stale_training_data.ParameterSetting,
})
assert(ok == false and reason == "stale_training_data"
        and manager._IsReqRefresh == false,
    "a replaced training-data container must fail closed")

local replacement_manager = object({
    _tData = training_data,
    _IsReqRefresh = false,
})
local stale_manager = manager
manager = replacement_manager
ok, reason = Refresh.request({
    tm = stale_manager,
    training_data = training_data,
    parameter_setting = training_data.ParameterSetting,
})
assert(ok == false and reason == "stale_training_manager"
        and replacement_manager._IsReqRefresh == false,
    "a replaced TrainingManager must fail closed")

replacement_manager._IsReqRefresh = true
ok, reason = Refresh.request({
    tm = replacement_manager,
    training_data = training_data,
    parameter_setting = training_data.ParameterSetting,
})
assert(ok == false and reason == "refresh_in_progress",
    "an active training refresh must not start a second refresh transaction")

local unreadable_manager = setmetatable({ _tData = training_data }, {
    __index = function(_, name)
        if name == "get_field" then
            return function(self, field)
                if field == "_IsReqRefresh" then error("injected read failure") end
                return rawget(self, field)
            end
        end
        if name == "_IsReqRefresh" then error("injected read failure") end
        return nil
    end,
})
manager = unreadable_manager
ok, reason = Refresh.request({
    tm = unreadable_manager,
    training_data = training_data,
    parameter_setting = training_data.ParameterSetting,
})
assert(ok == false and reason == "refresh_state_unavailable"
        and rawget(unreadable_manager, "_IsReqRefresh") == nil,
    "an unreadable refresh state must fail closed before writing")

local missing_state_manager = object({ _tData = training_data })
manager = missing_state_manager
ok, reason = Refresh.request({
    tm = missing_state_manager,
    training_data = training_data,
    parameter_setting = training_data.ParameterSetting,
})
assert(ok == false and reason == "refresh_state_unavailable"
        and missing_state_manager._IsReqRefresh == nil,
    "an absent refresh state must not be treated as a stable false value")

local unconfirmed_manager = object({
    _tData = training_data,
    _IsReqRefresh = false,
})
function unconfirmed_manager:set_field() end
manager = unconfirmed_manager
ok, reason = Refresh.request({
    tm = unconfirmed_manager,
    training_data = training_data,
    parameter_setting = training_data.ParameterSetting,
})
assert(ok == false and reason == "refresh_request_unconfirmed"
        and unconfirmed_manager._IsReqRefresh == false,
    "a refresh write that cannot be observed must fail closed")

print("training parameter refresh tests passed")
