local function read_all(path)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    return source
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
assert(main_source:find(
    "if _G._allow_stun_demo == nil then _G._allow_stun_demo = true end", 1, true),
    "stun trial demo must default to enabled")

local ui_source = read_all("autorun/func/ComboTrials_UI.lua")
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

local product_defaults = read_all("data/TrainingComboTrials_data/CommandLogger_Visualizer.json")
assert(product_defaults:find('"show_trial_notes": true', 1, true),
    "product config must enable trial notes by default")
assert(product_defaults:find('"auto_next_trial": false', 1, true),
    "product config must disable automatic next trial by default")
assert(product_defaults:find('"auto_retry_on_fail": false', 1, true),
    "product config must disable automatic retry by default")

print("combo development defaults tests passed")
