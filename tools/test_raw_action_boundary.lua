package.path = table.concat({
    "./autorun/?.lua",
    "./autorun/?/init.lua",
    package.path,
}, ";")

local RawActionBoundary = require("func/ComboTrials/Raw/RawActionBoundary")

local function equal(actual, expected, message)
    assert(actual == expected, (message or "values differ")
        .. ": expected=" .. tostring(expected) .. " actual=" .. tostring(actual))
end

local boundary = RawActionBoundary.new()
assert(boundary:observe({ action_id = 1, action_frame = 10, engine_frame = 1,
    direct_input = 0, direction_input = 0, facing_right = true }))
local correction = assert(boundary:observe({ action_id = 1, action_frame = 9,
    engine_frame = 2, direct_input = 0, direction_input = 0, facing_right = true }))
equal(correction.restart, false, "unconfirmed ActionFrame correction is not a restart")

local restarted = assert(boundary:observe({ action_id = 1, action_frame = 0,
    engine_frame = 3, direct_input = 0, direction_input = 0, facing_right = true }))
equal(restarted.restart, true, "ActionFrame restart is independent of player input")
equal(restarted.reason, "action_frame_restarted")
local startup_correction = assert(boundary:observe({ action_id = 1, action_frame = -1,
    engine_frame = 4, direct_input = 0, direction_input = 0, facing_right = true }))
equal(startup_correction.restart, false,
    "rewind inside the Action start region is not a second occurrence")

local dash = RawActionBoundary.new()
assert(dash:observe({ action_id = 1, action_frame = 0, engine_frame = 10,
    direct_input = 0, direction_input = 4, facing_right = true }))
assert(dash:observe({ action_id = 1, action_frame = 1, engine_frame = 11,
    direct_input = 0, direction_input = 0, facing_right = true }))
assert(dash:observe({ action_id = 17, action_frame = 0, engine_frame = 12,
    direct_input = 0, direction_input = 4, facing_right = true,
    repeatable_direction = "6" }))
assert(dash:observe({ action_id = 17, action_frame = 1, engine_frame = 13,
    direct_input = 0, direction_input = 0, facing_right = true,
    repeatable_direction = "6" }))
assert(dash:observe({ action_id = 17, action_frame = 2, engine_frame = 14,
    direct_input = 0, direction_input = 4, facing_right = true,
    repeatable_direction = "6" }))
assert(dash:observe({ action_id = 17, action_frame = 3, engine_frame = 15,
    direct_input = 0, direction_input = 0, facing_right = true,
    repeatable_direction = "6" }))
local repeated_dash = assert(dash:observe({ action_id = 17, action_frame = 4,
    engine_frame = 16, direct_input = 0, direction_input = 4, facing_right = true,
    repeatable_direction = "6" }))
equal(repeated_dash.restart, false,
    "input does not synthesize a new Action occurrence without Runtime restart")

local arbitrary = RawActionBoundary.new()
assert(arbitrary:observe({ action_id = 1, action_frame = 0, engine_frame = 20,
    direct_input = 0, direction_input = 4, facing_right = true }))
assert(arbitrary:observe({ action_id = 1, action_frame = 1, engine_frame = 21,
    direct_input = 0, direction_input = 0, facing_right = true }))
assert(arbitrary:observe({ action_id = 77, action_frame = 0, engine_frame = 22,
    direct_input = 0, direction_input = 4, facing_right = true }))
assert(arbitrary:observe({ action_id = 77, action_frame = 1, engine_frame = 23,
    direct_input = 0, direction_input = 0, facing_right = true }))
assert(arbitrary:observe({ action_id = 77, action_frame = 2, engine_frame = 24,
    direct_input = 0, direction_input = 4, facing_right = true }))
assert(arbitrary:observe({ action_id = 77, action_frame = 3, engine_frame = 25,
    direct_input = 0, direction_input = 0, facing_right = true }))
local arbitrary_pair = assert(arbitrary:observe({ action_id = 77, action_frame = 4,
    engine_frame = 26, direct_input = 0, direction_input = 4, facing_right = true }))
equal(arbitrary_pair.restart, false, "double tap cannot bind an arbitrary action")

print("raw action boundary tests passed")
