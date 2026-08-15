local function read_file(path)
    local file = assert(io.open(path, "rb"))
    local value = assert(file:read("*a"))
    file:close()
    return value
end

local source = read_file("autorun/TrainingComboTrials_v1.0.lua")
local first = assert(source:find(
    "CTStunDemoRuntime = CTStunDemoRuntime or {}", 1, true
))
local next_pos = assert(source:find(
    "local function start_demo(opts)", first, true
))
local runtime_source = source:sub(first, next_pos - 1)

local function clone_sequence(sequence)
    local out = {}
    for index, step in ipairs(sequence) do
        out[index] = { frames = step.frames, mask = step.mask }
    end
    return out
end

local function new_runtime(sequence, catch_up_enabled)
    local trial_state = {
        sequence = { { scene_state = catch_up_enabled and { actor = {} } or nil } },
        playing_player = 0,
    }
    local demo_state = {
        sequence = clone_sequence(sequence),
        current_step = 1,
        current_frame = 0,
        _last_tick_frame = nil,
    }
    local env = {
        CTStunDemoRuntime = {},
        trial_state = trial_state,
        demo_state = demo_state,
        engine_frame_count = 0,
        ComboTrialsModules = {
            SceneState = {
                requires_timeline_catch_up = function()
                    return catch_up_enabled
                end,
            },
            SceneStateRuntime = { apply = function() return true end },
        },
        type = type,
        tonumber = tonumber,
        math = math,
    }
    setmetatable(env, { __index = _G })
    assert(load(runtime_source, "demo-timing-runtime", "t", env))()
    return env.CTStunDemoRuntime, demo_state, env
end

local function state_key(state)
    return table.concat({
        state.current_step or 0,
        state.current_frame or 0,
    }, ":")
end

local seed = 0x5F6CC
local function random(maximum)
    seed = (1103515245 * seed + 12345) & 0x7FFFFFFF
    return seed % maximum
end

for iteration = 1, 10000 do
    local sequence = {}
    local step_count = 1 + random(12)
    local total_frames = 0
    for index = 1, step_count do
        local frames = random(18)
        sequence[index] = { frames = frames, mask = random(0x10000) }
        total_frames = total_frames + frames
    end
    local requested = random(total_frames + 25)

    local chunked, chunked_state = new_runtime(sequence, true)
    local singles, singles_state = new_runtime(sequence, true)
    local chunked_advanced = chunked.advance_timeline_frames(requested)
    local singles_advanced = 0
    for _ = 1, requested do
        singles_advanced = singles_advanced
            + singles.advance_timeline_frames(1)
    end

    assert(chunked_advanced == singles_advanced
            and state_key(chunked_state) == state_key(singles_state),
        string.format("chunked timeline drift at iteration %d", iteration))
    assert(chunked_advanced == math.min(requested, total_frames),
        string.format("timeline consumed the wrong frame count at iteration %d", iteration))
end

do
    local runtime, state, env = new_runtime({
        { frames = 2, mask = 0x10 },
        { frames = 3, mask = 0 },
        { frames = 1, mask = 0x20 },
    }, true)
    state._last_tick_frame = 100
    env.engine_frame_count = 104
    assert(runtime.catch_up_missed_engine_frames() == 3
            and state.current_step == 2
            and state.current_frame == 1,
        "wall-stun catch-up must consume exactly the missed engine frames")

    state._last_tick_frame = 110
    env.engine_frame_count = 105
    local before = state_key(state)
    assert(runtime.catch_up_missed_engine_frames() == 0
            and state_key(state) == before,
        "engine-frame rewind must not move the Demo cursor backwards")
end

do
    local runtime, state, env = new_runtime({ { frames = 10, mask = 0x40 } }, false)
    state._last_tick_frame = 10
    env.engine_frame_count = 100
    assert(runtime.catch_up_missed_engine_frames() == 0
            and state.current_step == 1
            and state.current_frame == 0,
        "ordinary scene snapshots must not opt into hitstop catch-up")
end

print("combo Demo timing tests passed")
