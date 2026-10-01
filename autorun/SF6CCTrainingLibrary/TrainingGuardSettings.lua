local TrainingGuardSettings = {}

TrainingGuardSettings.FIELDS = {
    "GuardType",
    "GuardWeight",
    "GuardCount",
    "IsGuardSwitching",
    "GuardOnlyType",
}

local allowed_fields = {}
for _, field_name in ipairs(TrainingGuardSettings.FIELDS) do
    allowed_fields[field_name] = true
end

local function read_value(object, field_name)
    if not object then return nil end
    local ok, value = pcall(function() return object:get_field(field_name) end)
    if ok and value ~= nil then return value end
    ok, value = pcall(function() return object[field_name] end)
    return ok and value or nil
end

local function write_value(object, field_name, value)
    if not object or value == nil then return false end
    local ok = pcall(function() object:set_field(field_name, value) end)
    if ok then return true end
    ok = pcall(function() object[field_name] = value end)
    return ok
end

local function context()
    if not sdk or not sdk.get_managed_singleton then
        return nil, "sdk unavailable"
    end
    local manager = sdk.get_managed_singleton("app.training.TrainingManager")
    if not manager then return nil, "TrainingManager unavailable" end
    local training_data = read_value(manager, "_tData")
    local guard_setting = training_data and read_value(training_data, "GuardSetting") or nil
    local dummy_data = guard_setting and read_value(guard_setting, "DummyData") or nil
    if not dummy_data then return nil, "dummy guard settings unavailable" end
    return { manager = manager, dummy_data = dummy_data }, nil
end

local function find_guard_function(manager)
    local funcs = manager and read_value(manager, "_tfFuncs") or nil
    local entries = funcs and read_value(funcs, "_entries") or nil
    if not entries then return nil end
    local count = 0
    pcall(function() count = tonumber(entries:call("get_Count")) or 0 end)
    for index = 0, count - 1 do
        local value = nil
        pcall(function()
            local entry = entries:call("get_Item", index)
            value = entry and read_value(entry, "value") or nil
        end)
        if value then
            local full_name = ""
            pcall(function()
                local definition = value:get_type_definition()
                full_name = definition and definition:get_full_name() or ""
            end)
            if full_name:find("tf_GuardSetting", 1, true) then return value end
        end
    end
    return nil
end

function TrainingGuardSettings.normalize(fields)
    local normalized = {}
    if type(fields) ~= "table" then return normalized end
    for field_name, value in pairs(fields) do
        if allowed_fields[field_name]
            and (type(value) == "number" or type(value) == "boolean") then
            normalized[field_name] = value
        end
    end
    return normalized
end

function TrainingGuardSettings.read()
    local ctx, err = context()
    if not ctx then return nil, err end
    local result = {}
    for _, field_name in ipairs(TrainingGuardSettings.FIELDS) do
        local value = read_value(ctx.dummy_data, field_name)
        if value ~= nil then result[field_name] = value end
    end
    if result.GuardType == nil then return nil, "GuardType unavailable" end
    return result, nil
end

function TrainingGuardSettings.apply(fields)
    local normalized = TrainingGuardSettings.normalize(fields)
    if normalized.GuardType == nil then return false, "GuardType missing" end
    local ctx, err = context()
    if not ctx then return false, err end
    for _, field_name in ipairs(TrainingGuardSettings.FIELDS) do
        local value = normalized[field_name]
        if value ~= nil and not write_value(ctx.dummy_data, field_name, value) then
            return false, "failed to write " .. field_name
        end
    end
    local guard_function = find_guard_function(ctx.manager)
    if guard_function then
        local ok, apply_err = pcall(function() guard_function:call("bApply") end)
        if not ok then return false, tostring(apply_err) end
    end
    return true, nil
end

function TrainingGuardSettings.apply_type(guard_type)
    local current, err = TrainingGuardSettings.read()
    if not current then return false, err end
    current.GuardType = guard_type
    return TrainingGuardSettings.apply(current)
end

return TrainingGuardSettings
