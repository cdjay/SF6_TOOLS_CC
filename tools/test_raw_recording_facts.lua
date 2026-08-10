package.path = table.concat({
    "./autorun/?.lua",
    "./autorun/?/init.lua",
    package.path,
}, ";")

local RawRecordingFacts = require("func/ComboTrials/Raw/RawRecordingFacts")

local state = {
    is_recording = true,
    recording_player = 0,
    _rec_pending_snapshot = 2,
    _rec_gauges = nil,
}
local captured = 0
local tracked = 0
local options = {
    trial_state = state,
    player_index = 0,
    victim = "victim",
    player_character = "player",
    capture_gauges = function(player_index)
        assert(player_index == 0)
        captured = captured + 1
        return { hp = 100 }
    end,
    track_gauges = function(victim, player, player_index)
        assert(victim == "victim" and player == "player" and player_index == 0)
        tracked = tracked + 1
    end,
}

assert(RawRecordingFacts.observe(options) == true)
assert(state._rec_pending_snapshot == 1 and captured == 0 and tracked == 0)
assert(RawRecordingFacts.observe(options) == true)
assert(state._rec_pending_snapshot == 0 and captured == 1 and tracked == 1)
assert(RawRecordingFacts.observe(options) == true)
assert(captured == 1 and tracked == 2)

options.player_index = 1
assert(RawRecordingFacts.observe(options) == false)
assert(captured == 1 and tracked == 2)

print("raw recording facts tests passed")
