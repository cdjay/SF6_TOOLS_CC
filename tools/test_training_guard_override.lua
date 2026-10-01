package.path = package.path
    .. ";./autorun/?.lua"
    .. ";./autorun/?/init.lua"

local current = {
    GuardType = 2,
    GuardWeight = 55,
    GuardCount = 3,
    IsGuardSwitching = true,
    GuardOnlyType = 1,
}
local reads = 0
local writes = 0

local function clone(value)
    local result = {}
    for key, child in pairs(value) do result[key] = child end
    return result
end

local settings = {}
function settings.read()
    reads = reads + 1
    return clone(current)
end
function settings.apply(value)
    writes = writes + 1
    current = clone(value)
    return true
end
function settings.apply_type(guard_type)
    writes = writes + 1
    current.GuardType = guard_type
    return true
end

local Override = require("func/TrainingGuardOverride")
local controller = Override.new(settings)

assert(controller:update(3))
assert(current.GuardType == 3 and reads == 1)
assert(controller:update(2))
assert(current.GuardType == 4 and reads == 1)
assert(controller:update(0))
assert(current.GuardType == 2 and current.GuardWeight == 55
    and current.GuardCount == 3 and current.IsGuardSwitching == true
    and current.GuardOnlyType == 1)
assert(controller:state().has_saved_settings == false)

assert(controller:update(1))
assert(current.GuardType == 0 and reads == 2)
assert(controller:update(4))
assert(current.GuardType == 2, "entering a separately-owned mode must restore the user setting")

assert(controller:update(3))
assert(current.GuardType == 3 and reads == 3)
assert(controller:restore())
assert(current.GuardType == 2, "script reset must restore the captured setting")

local available = false
local applied = 0
local retry_settings = {
    read = function()
        if not available then return nil, "not ready" end
        return { GuardType = 1 }
    end,
    apply = function(value)
        current = clone(value)
        return true
    end,
    apply_type = function(value)
        applied = applied + 1
        current.GuardType = value
        return true
    end,
}
local retry_controller = Override.new(retry_settings)
local ok = retry_controller:update(3)
assert(not ok and applied == 0 and retry_controller:state().last_mode == 0,
    "an unreadable baseline must never be overwritten")
available = true
assert(retry_controller:update(3) and applied == 1 and current.GuardType == 3,
    "the same transition must retry after native settings become available")

print("training guard override tests passed: " .. tostring(writes) .. " writes")
