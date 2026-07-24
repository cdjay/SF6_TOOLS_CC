package.path = package.path
    .. ";./autorun/?.lua"
    .. ";./autorun/?/init.lua"

json = json or {}
fs = fs or {}
log = log or {}
sdk = sdk or {}

local ComboTrialsFiles = require("func/ComboTrials_Files")

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
    trial_state = {},
    players = {},
    file_system = file_system,
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

print("combo completion display tests passed")
