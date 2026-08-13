package.path = package.path
    .. ";./autorun/?.lua"
    .. ";./autorun/?/init.lua"

local buffer = require("func/ComboTrials/RawDriveRushPrecursorBuffer")

local expected_raw_dr = { id = 500, motion = "drive rush" }
local dash = { id = 17, motion = "66", marker = "dash" }

local state = {}
assert(buffer.should_route(state, {
        expected_step = expected_raw_dr,
        previous_action_id = 17,
        previous_motion = "66",
    }) == true
        and buffer.should_route(state, {
            expected_step = { id = 17, motion = "66" },
            previous_action_id = 17,
            previous_motion = "66",
        }) == false,
    "the pending state machine must only intercept RAW DR precursor candidates")
local decision = buffer.transition(state, {
    expected_step = expected_raw_dr,
    previous_action = dash,
    previous_action_id = 17,
    previous_motion = "66",
    successor_action_id = 480,
    successor_motion = "PARRY",
    elapsed_frames = 3,
})
assert(decision == "hold" and state.pending_dash == dash,
    "a fast 66 may wait only while a possible RAW DR chain is unresolved")

decision = buffer.transition(state, {
    expected_step = expected_raw_dr,
    previous_action_id = 480,
    previous_motion = "PARRY",
    successor_action_id = 500,
    successor_motion = "drive rush",
    elapsed_frames = 10,
})
assert(decision == "discard" and state.pending_dash == nil,
    "the pending 66 and final Parry must be discarded only after RAW DR appears")

state = {}
buffer.transition(state, {
    expected_step = expected_raw_dr,
    previous_action = dash,
    previous_action_id = 17,
    previous_motion = "66",
    successor_action_id = 480,
    successor_motion = "PARRY",
    elapsed_frames = 3,
})
decision, dash = buffer.transition(state, {
    expected_step = expected_raw_dr,
    previous_action_id = 480,
    previous_motion = "PARRY",
    successor_action_id = 600,
    successor_motion = "LP",
    elapsed_frames = 8,
})
assert(decision == "release" and dash.marker == "dash"
        and state.pending_dash == nil,
    "an unresolved chain must release the real 66 before a non-DR successor")

state = {}
buffer.transition(state, {
    expected_step = expected_raw_dr,
    previous_action = { id = 17, marker = "timeout" },
    previous_action_id = 17,
    previous_motion = "66",
    successor_action_id = 480,
    successor_motion = "PARRY",
    elapsed_frames = 3,
})
local pending = buffer.flush(state)
assert(pending.marker == "timeout" and state.pending_dash == nil,
    "timeout publication must recover the pending 66 exactly once")

state = {}
decision = buffer.transition(state, {
    expected_step = { id = 17, motion = "66" },
    previous_action = dash,
    previous_action_id = 17,
    previous_motion = "66",
    successor_action_id = 480,
    successor_motion = "PARRY",
    elapsed_frames = 3,
})
assert(decision == "pass" and state.pending_dash == nil,
    "an explicitly expected standalone 66 must never enter RAW DR pending state")

state = {}
local queue = {}
decision = buffer.route(state, queue, {
    expected_step = { id = 17, motion = "66" },
    previous_action = { id = 17, marker = "explicit" },
    previous_action_id = 17,
    previous_motion = "66",
    successor_action_id = 500,
    successor_motion = "drive rush",
    elapsed_frames = 4,
})
assert(decision == "pass" and #queue == 1
        and queue[1].marker == "explicit",
    "a recorded 66 followed by DR must preserve the explicit 66 checkpoint")

state = { pending_dash = { id = 17, marker = "queued" } }
queue = {}
assert(buffer.flush_into(state, queue) == true
        and #queue == 1 and queue[1].marker == "queued"
        and state.pending_dash == nil,
    "timeout must publish the pending 66 before the current Parry")

print("combo RAW DR precursor buffer tests passed")
