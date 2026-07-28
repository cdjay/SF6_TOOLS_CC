local function read_all(path)
    local file = assert(io.open(path, "rb"))
    local value = assert(file:read("*a"))
    file:close()
    return value:gsub("\r\n", "\n")
end

local source = read_all("autorun/TrainingComboTrials_v1.0.lua")
local expression = assert(source:match("local time_value = ([^\n]+)"),
    "combo sync signal time marker expression is missing")
local resolve_time_value = assert(load(
    "return function(signal) return " .. expression .. " end",
    "combo-sync-signal-time-value",
    "t",
    {}
))()

assert(resolve_time_value({ time = "legacy-time" }) == "legacy-time",
    "legacy time field must remain supported")
assert(resolve_time_value({ updated_at = "snake-case" }) == "snake-case",
    "canonical updated_at field must remain supported")
assert(resolve_time_value({ updatedAt = "camel-case" }) == "camel-case",
    "SF6CM camel-case updatedAt field must trigger refresh")
assert(resolve_time_value({ timestamp = "legacy-timestamp" }) == "legacy-timestamp",
    "TrialHub timestamp field must trigger refresh")
assert(resolve_time_value({
    time = "preferred",
    updated_at = "canonical",
    updatedAt = "camel-case",
    timestamp = "legacy-timestamp",
}) == "preferred", "existing time-field precedence must remain stable")
assert(resolve_time_value({}) == nil,
    "signals without a supported marker field must remain invalid")

print("combo sync signal tests passed")
