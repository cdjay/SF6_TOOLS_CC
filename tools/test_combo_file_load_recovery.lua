package.path = package.path
    .. ";./autorun/?.lua"
    .. ";./autorun/?/init.lua"

local previous_files_module = package.loaded["func/ComboTrials_Files"]
local previous_json = json
local previous_fs = fs
local previous_log = log
local previous_sdk = sdk

json = { load_file = function() return nil end }
fs = {}
log = {}
sdk = {}

package.loaded["func/ComboTrials_Files"] = nil
local Files = require("func/ComboTrials_Files")

local old_sequence = {
    { id = 1, motion = "LP", delay_from_prev = 0 },
}
local state = {
    sequence = old_sequence,
    source_sequence = old_sequence,
    current_file = "good.json",
    current_file_path = "good.json",
    current_file_name = "good.json",
    current_step = 1,
    is_playing = true,
}
local changes = {}
local mode = "normalization_failure"
local ctx = {
    trial_state = state,
    players = {},
    file_system = {},
    on_combo_file_change = function(info)
        changes[#changes + 1] = info
        state.demo_stopped = true
    end,
}

Files.init(ctx, {
    normalize_sequence_counter_types = function()
        if mode == "preparation_failure" then error("preparation failed") end
    end,
    normalize_action_sequence = function(sequence)
        if mode == "normalization_failure" then
            return { ok = false, reason = "normalization failed" }
        end
        return { ok = true, reason = "unchanged", sequence = sequence }
    end,
    assign_groups = function() end,
})

local rejected = {
    { id = 2, motion = "MP", delay_from_prev = 0 },
}
assert(Files.load_combo_sequence(rejected, "bad-normalization.json", true) == false,
    "a normalization failure must reject the new combo")
assert(#changes == 0 and state.demo_stopped ~= true
        and state.sequence == old_sequence
        and state.current_file_path == "good.json",
    "a normalization failure must not tear down the active combo session")

mode = "preparation_failure"
assert(Files.load_combo_sequence(rejected, "bad-preparation.json", true) == false,
    "a preparation failure must reject the new combo")
assert(#changes == 0 and state.demo_stopped ~= true
        and state.sequence == old_sequence
        and state.current_file_path == "good.json",
    "a preparation failure must not tear down the active combo session")

mode = "success"
local replacement = {
    { id = 3, motion = "HP", delay_from_prev = 0 },
}
assert(Files.load_combo_sequence(replacement, "replacement.json", true) == true,
    "a valid combo must still load after rejected files")
assert(#changes == 1
        and changes[1].old_file == "good.json"
        and changes[1].new_file == "replacement.json"
        and state.demo_stopped == true
        and state.sequence == replacement
        and state.current_file_path == "replacement.json",
    "the lifecycle callback must run exactly once after validation succeeds")

package.loaded["func/ComboTrials_Files"] = previous_files_module
json = previous_json
fs = previous_fs
log = previous_log
sdk = previous_sdk

print("combo file load recovery tests passed")
