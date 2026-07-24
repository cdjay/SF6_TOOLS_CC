local M = {}

-- Common movement actions can keep both their Action ID and a continuously
-- advancing ActionFrame when the player starts the same movement again. Their
-- raw double-tap pair is therefore also accepted as a restart signal.
local REPEATABLE_COMMON_ACTIONS = {
    [17] = "66",
    [18] = "44"
}

local DEFAULT_DASH_TAP_WINDOW = 12
local DASH_ACTION_BIND_WINDOW = 12
local DEFAULT_EXPECTED_REPEAT_EARLY_WINDOW = 4

-- pl_input_new uses physical direction bits (right=4, left=8). Normalize them
-- to facing-relative notation before dash pairing; BCM command directions use
-- a different lookup and must not be reused for physical input.
function M.normalize_input_direction_bits(direction_bits, facing_right)
    local bits = (tonumber(direction_bits) or 0) & 0xF
    if facing_right == false then
        local has_right = (bits & 4) ~= 0
        local has_left = (bits & 8) ~= 0
        bits = bits & ~12
        if has_right then bits = bits | 8 end
        if has_left then bits = bits | 4 end
    end
    return bits
end

function M.get_repeatable_motion(action_id)
    return REPEATABLE_COMMON_ACTIONS[tonumber(action_id)]
end

-- Consume horizontal press edges in non-overlapping pairs. This mirrors how
-- repeated dash commands are written: 6666 is two 66 commands, not three
-- overlapping pairs. Direction-to-action binding is learned from the actual
-- Action 17/18 transition, so it does not depend on screen side or coordinates.
function M.observe_dash_direction_edge(state, direction, frame, window)
    if type(state) ~= "table" then return nil end
    direction = tostring(direction or "")
    if direction ~= "6" and direction ~= "4" then return nil end

    frame = tonumber(frame) or -1
    window = tonumber(window) or DEFAULT_DASH_TAP_WINDOW
    local previous_direction = state.pending_direction
    local previous_frame = tonumber(state.pending_frame) or -1
    local delta = frame - previous_frame

    if previous_direction == direction and delta > 0 and delta <= window then
        state.pending_direction = nil
        state.pending_frame = nil
        local pair = {
            direction = direction,
            first_frame = previous_frame,
            second_frame = frame,
            interval = delta
        }
        state.completed_pairs = state.completed_pairs or {}
        table.insert(state.completed_pairs, pair)
        return pair
    end

    state.pending_direction = direction
    state.pending_frame = frame
    return nil
end

local function recent_pair(state, current_tick)
    if type(state) ~= "table" or type(state.completed_pairs) ~= "table" then return nil end
    current_tick = tonumber(current_tick) or -1
    while #state.completed_pairs > 0 do
        local pair = state.completed_pairs[1]
        local pair_tick = tonumber(pair.second_frame) or -1
        local age = current_tick - pair_tick
        if age >= 0 and age <= DASH_ACTION_BIND_WINDOW then return pair end
        table.remove(state.completed_pairs, 1)
    end
    return nil
end

local function consume_pair(state, pair)
    if type(state) ~= "table" or type(state.completed_pairs) ~= "table" then return end
    for index, queued in ipairs(state.completed_pairs) do
        if queued == pair then
            table.remove(state.completed_pairs, index)
            return
        end
    end
end

function M.evaluate_expected_repeat_input(params)
    params = type(params) == "table" and params or {}
    local result = {
        accepted = false,
        reason = nil,
        expected_id = tonumber(params.expected_id),
        previous_id = tonumber(params.previous_id),
        current_id = tonumber(params.current_id),
        buffered_id = tonumber(params.buffered_id),
        current_combo = tonumber(params.current_combo) or 0,
        previous_expected_combo = tonumber(params.previous_expected_combo) or 0,
        frames_since_previous = tonumber(params.frames_since_previous) or 0,
        expected_delay = tonumber(params.expected_delay) or 0,
        early_window = tonumber(params.early_window) or DEFAULT_EXPECTED_REPEAT_EARLY_WINDOW,
        action_button_edge = (tonumber(params.action_button_edge) or 0) & 0xFFF0
    }
    result.earliest_frame = math.max(0, result.expected_delay - result.early_window)

    if result.action_button_edge == 0 then
        result.reason = "missing_attack_edge"
    elseif result.expected_id == nil or result.previous_id == nil then
        result.reason = "missing_expected_id"
    elseif result.expected_id ~= result.previous_id then
        result.reason = "sequence_not_same_action"
    elseif result.current_id ~= result.expected_id or result.buffered_id ~= result.expected_id then
        result.reason = "runtime_action_id_mismatch"
    elseif result.frames_since_previous < result.earliest_frame then
        result.reason = "before_expected_repeat_window"
    else
        result.accepted = true
        result.reason = "expected_repeat_input_ready"
    end
    return result
end

function M.detect(current_id, current_frame, buffered_id, buffered_frame, state, current_tick,
        action_button_edge, expected_repeat_input)
    current_id = tonumber(current_id) or -1
    buffered_id = tonumber(buffered_id) or -1
    current_frame = tonumber(current_frame) or -1
    buffered_frame = tonumber(buffered_frame) or -1
    action_button_edge = (tonumber(action_button_edge) or 0) & 0xFFF0
    local common_motion = REPEATABLE_COMMON_ACTIONS[current_id]
    local pair = recent_pair(state, current_tick)

    if current_id ~= buffered_id then
        if common_motion and pair and type(state) == "table" then
            state.direction_actions = state.direction_actions or {}
            state.direction_actions[pair.direction] = current_id
            consume_pair(state, pair)
        end
        return true, "id_changed"
    end

    if common_motion and pair and type(state) == "table" then
        state.direction_actions = state.direction_actions or {}
        if tonumber(state.direction_actions[pair.direction]) == current_id then
            consume_pair(state, pair)
            return true, "repeatable_common_action_input"
        end
    end

    -- Some commands can be entered again while the engine keeps both the same
    -- Action ID and a monotonically advancing ActionFrame. Only admit a fresh
    -- attack edge when the trial context independently proves that the next
    -- expected step is the same action and its timing gate is ready. Do not
    -- require the previous move's full hit count here: projectile follow-ups
    -- can be entered before all hits from the first command have resolved.
    if expected_repeat_input == true and action_button_edge ~= 0 then
        return true, "expected_repeat_action_input"
    end

    if current_frame >= buffered_frame then
        return false, "no_new_action"
    end

    -- Consecutive uses of the same move can keep the same Action ID. If the
    -- polling sample misses frames 0/1, the ActionFrame still rewinds but the
    -- old near-zero rule cannot see the restart. A fresh/recent physical attack
    -- edge confirms that this rewind is a second player command, rather than an
    -- internal frame correction.
    if action_button_edge ~= 0 then
        return true, "input_confirmed_act_frame_rewind"
    end

    if REPEATABLE_COMMON_ACTIONS[current_id] then
        return true, "repeatable_common_action_rewind"
    end

    if current_frame < 2 then
        return true, "act_frame_rewind"
    end

    return false, "no_new_action"
end

return M
