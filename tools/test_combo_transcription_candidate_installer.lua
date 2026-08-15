local Installer = dofile(
    "autorun/func/ComboTrials/TranscriptionCandidateInstaller.lua"
)

local candidate = {
    {
        id = 603,
        motion = "MP",
        expected_combo = 1,
        _xt_meta = { title = "AKI test combo" },
    },
    { id = 902, motion = "214+HP", expected_combo = 11 },
}
local source = {
    {
        id = 603,
        motion = "MP",
        expected_combo = 1,
        _xt_meta = { title = "AKI test combo" },
    },
    { id = 902, motion = "214+HP", expected_combo = 10 },
    { id = 902, motion = "214+HP", expected_combo = 11 },
}
local item = {
    status = "passed",
    raw_replay_verified = true,
    source_file = "TrainingComboTrials_data\\CustomCombos\\AKI\\AKI_COMBO_MP_3120_D1.5_SA0.json",
    candidate_file = "TrainingComboTrials_data/TranscribedCandidates/AKI/run/AKI_COMBO_MP_3120_D1.5_SA0.json",
}

local writes = {}
local stored = {
    [item.source_file] = source,
    [item.candidate_file] = candidate,
}
local result, install_error = Installer.install(item, {
    run_id = "20260815_151637_single",
    character = "AKI",
    load_file = function(path) return stored[path] end,
    dump_file = function(path, value)
        writes[#writes + 1] = path
        stored[path] = value
        return true
    end,
})
assert(result ~= nil, install_error)
assert(result.target_path ==
        "TrainingComboTrials_data\\CustomCombos\\AKI\\AKI_COMBO_MP_3120_D1.5_SA0_z.json",
    "the verified candidate must be installed as a sibling copy")
assert(#writes == 1 and writes[1] == result.target_path,
    "candidate installation must write only the sibling copy")
assert(#stored[result.target_path] == 2 and stored[result.target_path][2].expected_combo == 11,
    "the installed file must contain the verified candidate")
assert(stored[result.target_path][1]._xt_meta.title == "AKI test comboz",
    "the installed copy title must end with the transcription marker z")
assert(#stored[item.source_file] == 3
        and stored[item.source_file][1]._xt_meta.title == "AKI test combo",
    "candidate installation must not mutate or overwrite the source combo")

local unverified_result, unverified_error = Installer.install({
    status = "passed",
    raw_replay_verified = false,
    source_file = item.source_file,
    candidate_file = item.candidate_file,
}, {})
assert(unverified_result == nil and unverified_error == "candidate_not_raw_replay_verified",
    "an unverified transcription candidate must never enter the runtime combo directory")

local mismatched_result, mismatched_error = Installer.install({
    status = "passed",
    raw_replay_verified = true,
    source_file = item.source_file,
    candidate_file = "TrainingComboTrials_data/TranscribedCandidates/AKI/run/other.json",
}, {})
assert(mismatched_result == nil and mismatched_error == "candidate_source_name_mismatch",
    "candidate installation must fail closed when source and candidate names differ")

stored[item.source_file] = source
stored[item.candidate_file] = candidate
local target_failure, target_error = Installer.install(item, {
    run_id = "run",
    character = "AKI",
    load_file = function(path) return stored[path] end,
    dump_file = function() return false end,
})
assert(target_failure == nil and target_error == "candidate_copy_write_failed"
        and stored[item.source_file] == source,
    "a failed candidate copy write must leave the source combo untouched")

local main_file = assert(io.open("autorun/TrainingComboTrials_v1.0.lua", "rb"))
local main_source = main_file:read("*a")
main_file:close()
assert(main_source:find("ctx.install_transcription_candidate_for_audit", 1, true)
        and main_source:find("installed_copy", 1, true)
        and main_source:find("ctx.start_runtime_audit({", 1, true),
    "the entry script must install and audit the selected verified candidate copy")

local ui_file = assert(io.open("autorun/func/ComboTrials_UI.lua", "rb"))
local ui_source = ui_file:read("*a")
ui_file:close()
assert(ui_source:find("载入当前目录并审计", 1, true),
    "advanced transcription tools must expose the install-and-audit command")

print("combo transcription candidate installer tests passed")
