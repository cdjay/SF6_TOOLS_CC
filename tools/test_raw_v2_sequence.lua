package.path = table.concat({
    "./autorun/?.lua",
    "./autorun/?/init.lua",
    package.path,
}, ";")

local AtomicTrace = require("func/ComboTrials/Raw/AtomicTrace")
local RawV2Sequence = require("func/ComboTrials/Raw/RawV2Sequence")

local trace = AtomicTrace.new()
assert(trace:append({ action_id = 600, enter_frame = 10 }))
assert(trace:append({ action_id = 601, enter_frame = 25 }))
assert(trace:append({ action_id = 600, enter_frame = 40 }))
trace:finalize()

local sequence = assert(RawV2Sequence.build(trace, {
    { expected_combo = 1 },
    { expected_combo = 2 },
    { expected_combo = 3 },
}))

assert(#sequence == 3)
assert(sequence[1].id == 600 and sequence[1].motion == "Action 600")
assert(sequence[2].id == 601 and sequence[2].motion == "Action 601")
assert(sequence[3].id == 600 and sequence[3].motion == "Action 600")
assert(sequence[1].expected_combo == 1)
assert(sequence[2].expected_combo == 2)
assert(sequence[3].expected_combo == 3)
assert(sequence[1].delay_from_prev == 0)
assert(sequence[2].delay_from_prev == 15)
assert(sequence[3].delay_from_prev == 15)

print("raw v2 sequence tests passed")
