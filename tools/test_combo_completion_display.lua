package.path = package.path
    .. ";./autorun/?.lua"
    .. ";./autorun/?/init.lua"

local dependency_names = {
    "func/ComboTrials_Files",
    "func/ComboTrials/TrialDisplayState",
}
local previous_loaded = {}
for _, name in ipairs(dependency_names) do
    previous_loaded[name] = package.loaded[name]
    package.loaded[name] = nil
end
local previous_json = json
local previous_fs = fs
local previous_log = log
local previous_sdk = sdk

json = { load_file = function() return { {} } end }
fs = {}
log = {}
sdk = {}

local ComboTrialsFiles = require("func/ComboTrials_Files")
local TrialDisplayState = require("func/ComboTrials/TrialDisplayState")

local active_display = TrialDisplayState.resolve({
    { expected_combo = 1, actual_combo = 1 },
    { expected_combo = 3, actual_combo = 0 },
}, 2, 0)
assert(active_display.active_step == 2
        and active_display.is_success == false,
    "an unfinished trial must keep its active cursor on the current step")

local completed_display = TrialDisplayState.resolve({
    { expected_combo = 1, actual_combo = 1 },
    { expected_combo = 3, actual_combo = 3 },
}, 3, 0)
assert(completed_display.active_step == 2
        and completed_display.terminal_visual_complete == true
        and completed_display.is_success == true,
    "a consumed terminal command must leave a green cursor on the final row")

local pending_contact_display = TrialDisplayState.resolve({
    { expected_combo = 1, actual_combo = 1 },
    { expected_combo = 3, actual_combo = 2 },
}, 3, 0)
assert(pending_contact_display.active_step == 2
        and pending_contact_display.terminal_visual_complete == true
        and pending_contact_display.is_success == true,
    "terminal display completion must not depend on stale outcome counters")

local trial_state = {}
local file_system = {
    saved_combos_display_p1 = {
        "[C] [连段一] - One",
        "[C] [连段二] - Two",
    },
    saved_combos_paths_p1 = {
        "TrainingComboTrials_data\\CustomCombos\\Ryu\\One.json",
        "TrainingComboTrials_data\\CustomCombos\\Ryu\\Two.json",
    },
    saved_combos_all_display_p1 = {
        "[C] [连段一] - One",
        "[C] [连段二] - Two",
    },
    saved_combos_all_paths_p1 = {
        "TrainingComboTrials_data\\CustomCombos\\Ryu\\One.json",
        "TrainingComboTrials_data\\CustomCombos\\Ryu\\Two.json",
    },
    saved_combos_display_p2 = {
        "[C] [连段一] - One",
    },
    saved_combos_paths_p2 = {
        "trainingcombotrials_data/customcombos/ryu/one.json",
    },
    saved_combos_all_display_p2 = {
        "[C] [其他连段] - Other",
    },
    saved_combos_all_paths_p2 = {
        "TrainingComboTrials_data/CustomCombos/Ken/Other.json",
    },
}

file_system.completed_trial_key = function(path)
    return (tostring(path or ""):gsub("\\", "/")):lower()
end

ComboTrialsFiles.init({
    trial_state = trial_state,
    players = {},
    file_system = file_system,
    ui_state = { viewed_player = 0 },
}, {
    normalize_sequence_counter_types = function() end,
    assign_groups = function() end,
})

local completed_path = "TRAININGCOMBOTRIALS_DATA/CUSTOMCOMBOS/RYU/ONE.JSON"
local updated = ComboTrialsFiles.mark_combo_display_completed(completed_path)

assert(updated == 3, "expected three cached entries to update, got " .. tostring(updated))
assert(file_system.saved_combos_display_p1[1]:find("^【完】"), "filtered P1 entry was not updated")
assert(file_system.saved_combos_all_display_p1[1]:find("^【完】"), "all P1 entry was not updated")
assert(file_system.saved_combos_display_p2[1]:find("^【完】"), "filtered P2 entry was not updated")
assert(not file_system.saved_combos_display_p1[2]:find("^【完】"), "unrelated P1 entry was modified")
assert(not file_system.saved_combos_all_display_p2[1]:find("^【完】"), "unrelated P2 entry was modified")

local repeated = ComboTrialsFiles.mark_combo_display_completed(completed_path)
assert(repeated == 0, "repeated completion should not duplicate the marker")
assert(not file_system.saved_combos_display_p1[1]:find("^【完】【完】"), "completion marker was duplicated")

file_system.reload_selected_combo_if_idle()
assert(trial_state.current_file_path == file_system.saved_combos_paths_p1[1],
    "cached combo list must reload only the selected trial on mode entry")

for _, name in ipairs(dependency_names) do
    package.loaded[name] = previous_loaded[name]
end
json = previous_json
fs = previous_fs
log = previous_log
sdk = previous_sdk

print("combo completion display tests passed")
