package.path = "autorun/?.lua;" .. package.path
local Policy = require("func/ComboTrials/RecordingPolicy")
assert(Policy.is_training_enabled() == true)
assert(Policy.is_replay_enabled() == false)

local function read(path)
    local file = assert(io.open(path, "rb"))
    local result = file:read("*a")
    file:close()
    return result:gsub("\r\n", "\n")
end

local function between(source, first, following)
    local a = assert(source:find(first, 1, true), first)
    local b = assert(source:find(following, a + #first, true), following)
    return source:sub(a, b - 1)
end

local function compile(source, env)
    return assert(load(source, "recording-scope", "t", env))()
end

local runtime = read("autorun/TrainingComboTrials_v1.0.lua")
local ui = read("autorun/func/ComboTrials_UI.lua")
local function forbidden() error("replay recording reached a side effect") end
local training_allowed = false
local env = {
    ComboTrialsModules = { RecordingPolicy = Policy },
    _G = { CurrentTrainerMode = 4 },
    RuntimeSafety = {
        is_training_allowed = function() return training_allowed end,
        is_replay_allowed = function() return not training_allowed end,
    },
}
local start = compile(between(runtime, "local function start_recording(player_idx)",
    "local function start_trial(player_idx)") .. "\nreturn start_recording", env)
assert(start(0) == false and start(1) == false)

env.ctx = {}
env.can_start_combo_action = function() return true end
local recorded, saved, canceled = 0, 0, 0
env.start_recording = function() recorded = recorded + 1; return true end
env.stop_recording_and_save = function() saved = saved + 1 end
env.cancel_recording = function() canceled = canceled + 1 end
env.ct_ticker = function() end
env.trial_state = { is_recording = false }
local started, demonstrated = 0, 0
env.load_and_start_trial = function() started = started + 1 end
env.start_demo = function() demonstrated = demonstrated + 1 end
compile(between(runtime, "ctx.commands = {", "local TrainingHotkeys ="), env)
training_allowed = true
env.ctx.commands.record_p1()
env.ctx.commands.record_p2()
assert(recorded == 2, "training recording commands must be available")
env.trial_state.is_recording = true
env.ctx.commands.save_recording()
env.ctx.commands.cancel_recording()
assert(saved == 1 and canceled == 1, "training save and cancel must be available")
env.trial_state.is_recording = false
assert(env._G.ComboTrials_ReplaySavePlayer == nil)
assert(env._G.ComboTrials_ReplayCancelPlayer == nil)
training_allowed = false
env.ctx.commands.record_p1()
env.ctx.commands.record_p2()
env.trial_state.is_recording = true
env.ctx.commands.save_recording()
env.ctx.commands.cancel_recording()
env.trial_state.is_recording = false
assert(recorded == 2 and saved == 1 and canceled == 1,
    "training commands must not record in replay")
env.ctx.commands.start_trial()
env.ctx.commands.start_demo()
assert(started == 1 and demonstrated == 1, "training and demo must remain usable")

local bridge_command, timestamp = "", 0
env.file_system = { replay_bridge_poll_frames = 1 }
env.json = { load_file = function()
    timestamp = timestamp + 1
    return { cmd = bridge_command, _web_timestamp = timestamp }
end }
local bridge = compile(between(runtime, "local function _ct_replay_bridge_poll()",
    "local function _ct_detect_piyo()") .. "\nreturn _ct_replay_bridge_poll", env)
for _, name in ipairs({ "record_p1", "record_p2", "stop_save", "cancel" }) do
    bridge_command = name
    bridge()
    assert(env._G._replay_bridge_ts == timestamp, "stale command must be consumed")
end
assert(env._G.ComboTrials_ReplaySavePlayer == nil)
assert(recorded == 2 and saved == 1 and canceled == 1,
    "replay bridge must not start or finish recording")
bridge_command = "hide_ui"
bridge()
assert(env._G._tsm_hide_ui == true, "unrelated bridge action must remain usable")

-- Execute the real web-command dispatcher, including all its recording paths.
local web_source = assert(runtime:match("(local function ct_handle_web_commands%(%).-)\nlocal function "))
local web = compile(web_source .. "\nreturn ct_handle_web_commands", env)
env.ct_ticker = forbidden
for _, name in ipairs({ "record", "cancel_record", "stop_record" }) do
    env._G._tsm_web_cmd = name
    web()
    assert(env._G._tsm_web_cmd == nil, "replay command must not remain queued")
end
assert(recorded == 2 and saved == 1 and canceled == 1,
    "replay web commands must not record")
training_allowed = true
env.ct_ticker = function() end
env._G._tsm_web_cmd = "record"
web()
env.trial_state.is_recording = true
env._G._tsm_web_cmd = "stop_record"
web()
env._G._tsm_web_cmd = "cancel_record"
web()
assert(recorded == 3 and saved == 2 and canceled == 2,
    "training web commands must record, save and cancel")
env.trial_state.is_recording = false

local scope
assert(require("func/ComboTrials_Hotkeys").init(env.ctx, {
    register_scope = function(_, spec) scope = spec end,
}))
local actions = {}
for _, action in ipairs(scope.actions) do actions[action.id] = action end
for _, name in ipairs({ "record_p1", "record_p2", "save_recording", "cancel_recording" }) do
    assert(actions[name] ~= nil, "training recording hotkey must be registered")
end
assert(actions.start_trial and actions.start_demo and actions.open_combo_dropdown)

-- Exercise training and replay in both layouts at narrow and wide sizes.
local single = between(ui, "local function draw_single_line_content()",
    "local function draw_combo_trials_content(is_floating)")
local multi = between(ui, "local function draw_combo_trials_content(is_floating)",
    "\nlocal function ")
for _, width in ipairs({ 220, 800, 1600 }) do
    for _, source in ipairs({ single .. "\nreturn draw_single_line_content",
        multi .. "\nreturn draw_combo_trials_content" }) do
        local labels, clicks = {}, {}
        local replay = false
        local u = setmetatable({
            RecordingPolicy = Policy,
            RuntimeSafety = { is_replay_allowed = function() return replay end },
            ctx = { cached_sw = 1920, cached_sh = 1080 },
            trial_state = { is_recording = false, is_playing = false },
            d2d_cfg = {}, _G = {}, _replay_status_p1 = "waiting",
            COLORS = {}, math = math,
            Vector2f = { new = function(x, y) return { x = x, y = y } end },
            imgui = setmetatable({
                get_window_size = function() return { x = width, y = 100 } end,
            }, { __index = function() return function() end end }),
            file_system = {
                saved_combos_display_p1 = {},
                request_combo_list_refresh = function() clicks.refresh = true end,
            },
            get_max_text_width = function() return 90 end,
            update_replay_recording_status = function() return 0 end,
            combo_empty_text = function() return "empty" end,
            start_recording = function() clicks.recording = true end,
            load_and_start_trial = function() clicks.training = true end,
            styled_sf6_button = function(label)
                labels[label] = true
                return true
            end,
        }, { __index = function(_, key)
            if key:match("^draw_") or key:match("^publish_") then return function() end end
        end })
        local draw = compile(source, u)
        draw(false)
        assert(clicks.training and clicks.recording,
            "training recording and playback controls must work in both layouts")
        assert(labels["录制连段"] or (labels["录制 P1"] and labels["录制 P2"]),
            "training recording button must be visible")
        labels = {}
        replay = true
        draw(false)
        assert(next(labels) == nil, "replay must not expose the old recording panel")
    end
end

local hidden = 0
local frame = between(ui, "re.on_frame(function()", "\nif re.on_script_reset then")
local frame_env = {
    re = { on_frame = function(fn) fn() end },
    RuntimeSafety = { is_replay_allowed = function() return true end },
    RecordingPolicy = Policy,
    _ctui_hide_visual_state = function() hidden = hidden + 1 end,
    _G = { _ct_bar_collapsed = true },
}
compile(frame, frame_env)
assert(hidden == 1 and frame_env._G._ct_bar_collapsed == false,
    "replay must release the bottom window and its collapse control")
print("combo recording scope tests passed")
