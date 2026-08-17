local function read_all(path)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    return source:gsub("\r\n", "\n")
end

local main_source = read_all("autorun/TrainingComboTrials_v1.0.lua")
local main_chunk, main_compile_error = loadfile(
    "autorun/TrainingComboTrials_v1.0.lua"
)
assert(main_chunk ~= nil, main_compile_error)
assert(main_source:find("show_trial_notes = true", 1, true),
    "trial notes must default to enabled")
assert(main_source:find("auto_next_trial = false", 1, true),
    "automatic next trial must default to disabled")
assert(main_source:find("auto_retry_on_fail = false", 1, true),
    "automatic retry must default to disabled")
assert(main_source:find('ct_default_global_flag("CT_DIAGNOSTIC_TRACE", false)', 1, true),
    "combo diagnostics must default to disabled")
assert(not main_source:find("CTSameActionTrace", 1, true),
    "temporary same-action trace must be removed")
assert(not main_source:find("CT_SAME_ACTION_TRACE", 1, true),
    "temporary same-action trace flags must be removed")
assert(not main_source:find("CT_SAVE_STATE_POC", 1, true),
    "save-state proof-of-concept callback must be removed")
assert(main_source:find(
    "if _G._allow_stun_demo == nil then _G._allow_stun_demo = true end", 1, true),
    "stun trial demo must default to enabled")

local ui_source = read_all("autorun/func/ComboTrials_UI.lua")
local telemetry_source = read_all("autorun/func/ComboTrials/Telemetry.lua")
assert(main_source:find('ct_default_global_flag("CT_TELEMETRY_CHECKPOINT", false)', 1, true),
    "cumulative telemetry checkpoint must default to disabled")
assert(telemetry_source:find("local function checkpoint_enabled()", 1, true),
    "telemetry checkpoint must be gated by an explicit opt-in flag")
assert(telemetry_source:find(
    "if checkpoint_enabled()\n"
    .. '    and type(sf6cc_atomic_file) == "table"', 1, true),
    "checkpoint initialization must not run by default")
assert(telemetry_source:find(
    "if checkpoint_enabled() and attempt.source == \"manual\"", 1, true),
    "checkpoint commit must not run by default")
assert(ui_source:find("local show_trial_overlay = true", 1, true),
    "floating trial window must default to enabled")
assert(ui_source:find("auto_playlist_enabled == true", 1, true),
    "automatic playlist checkbox must remain opt-in")
assert(ui_source:find("d2d_cfg.show_trial_notes = true", 1, true),
    "missing saved note setting must use the enabled default")
assert(ui_source:find("d2d_cfg.auto_next_trial = false", 1, true),
    "missing saved next-trial setting must use the disabled default")
assert(ui_source:find("d2d_cfg.auto_retry_on_fail = false", 1, true),
    "missing saved retry setting must use the disabled default")
local menu_start = assert(ui_source:find("local function draw_combo_trials_menu_ui()", 1, true))
local advanced_start = assert(ui_source:find('if plain_header("高级与调试") then', menu_start, true))
local normal_menu = ui_source:sub(menu_start, advanced_start - 1)
assert(not normal_menu:find("draw_transcription_debug_tools()", 1, true),
    "transcription and runtime audit tools must not appear in the normal combo menu")
assert(ui_source:find("draw_transcription_debug_tools()", advanced_start, true),
    "transcription and runtime audit tools must remain under advanced/debug")
assert(ui_source:find('imgui.checkbox(\n            "记录连段诊断历史"', advanced_start, true),
    "advanced/debug must expose the opt-in diagnostic history toggle")

local product_defaults = read_all("data/TrainingComboTrials_data/CommandLogger_Visualizer.json")
assert(product_defaults:find('"show_trial_notes": true', 1, true),
    "product config must enable trial notes by default")
assert(product_defaults:find('"auto_next_trial": false', 1, true),
    "product config must disable automatic next trial by default")
assert(product_defaults:find('"auto_retry_on_fail": false', 1, true),
    "product config must disable automatic retry by default")

print("combo development defaults tests passed")
