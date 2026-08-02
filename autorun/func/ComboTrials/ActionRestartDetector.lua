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
local CONTACT_SIGNAL_SETTLE_FRAMES = 1
M.PERSISTENT_DAMAGE_MAX_TICK = 20
-- Combo growth is sufficient contact truth at any damage. When combo count is
-- unchanged, fallback HP attribution stays above the supported persistent
-- damage envelope (A.K.I. poison can tick for 7, 10 or 20).
local MIN_UNCOUNTED_HIT_HP_DELTA = M.PERSISTENT_DAMAGE_MAX_TICK + 1
-- Match the player-action transition lookup window. A repeated command can be
-- buffered several frames before the engine would expose its next action start;
-- Sagat's recorded consecutive OD projectile reaches the physical edge 5f
-- before that point.
local DEFAULT_EXPECTED_REPEAT_EARLY_WINDOW = 12

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

-- Separate normal hits can both expose combo_cnt == 1 when the polling sample
-- misses the brief reset between them. In that case an HP decrease is accepted
-- only once per fresh normal-hit signal cycle. The fallback delta must also be
-- above the supported 7/10/20 HP persistent-damage envelope. A one-frame token
-- lets HP and hit-stop fields settle in either order without accepting the
-- continued signal level more than once.
function M.evaluate_recording_hit_contact(params)
    params = type(params) == "table" and params or {}
    local result = {
        accepted = false,
        reason = nil,
        current_combo = tonumber(params.current_combo) or 0,
        previous_combo = tonumber(params.previous_combo) or 0,
        current_hp = tonumber(params.current_hp),
        previous_hp = tonumber(params.previous_hp),
        damage_type = tonumber(params.damage_type) or 0,
        hit_stop = tonumber(params.hit_stop) or 0,
        previous_damage_type = tonumber(params.previous_damage_type),
        previous_hit_stop = tonumber(params.previous_hit_stop),
        minimum_hp_delta = tonumber(params.minimum_hp_delta)
            or MIN_UNCOUNTED_HIT_HP_DELTA,
        blocked = params.blocked == true,
        contact_candidate = params.contact_candidate ~= false,
    }
    result.combo_increased = result.current_combo > result.previous_combo
    result.hp_delta = result.current_hp ~= nil
        and result.previous_hp ~= nil
        and math.max(0, result.previous_hp - result.current_hp) or 0
    result.hp_decreased = result.current_hp ~= nil
        and result.previous_hp ~= nil
        and result.current_hp < result.previous_hp
    -- Command throws can keep the victim's ordinary hit-stop/damage-type
    -- signals clear while the game is still executing the input-bound Action.
    -- The caller may opt in to treating a large HP drop in that exact Action as
    -- contact truth. Small drops remain inside the supported persistent-damage
    -- envelope and can never use this bridge.
    result.action_owned_hp_decrease = params.action_owned_hp_decrease == true
        and result.hp_decreased
        and result.hp_delta >= result.minimum_hp_delta
        and not result.blocked
    result.has_hit_signal = result.damage_type == 3 and result.hit_stop > 0
    local has_signal_history = result.previous_damage_type ~= nil
        or result.previous_hit_stop ~= nil
    result.fresh_hit_signal = result.has_hit_signal and (
        not has_signal_history
        or result.previous_damage_type ~= 3
        or (result.previous_hit_stop or 0) <= 0
        or result.hit_stop > (result.previous_hit_stop or 0)
    )
    if params.contact_cycle_available == nil then
        result.contact_cycle_available = result.fresh_hit_signal
    else
        result.contact_cycle_available = params.contact_cycle_available == true
    end

    if result.combo_increased then
        result.accepted = true
        result.reason = "combo_increased"
    elseif result.hp_decreased and result.blocked then
        result.reason = "blocked_hp_decrease"
    elseif result.hp_decreased and not result.has_hit_signal
        and not result.action_owned_hp_decrease then
        result.reason = "hp_decreased_without_hit_signal"
    elseif result.hp_decreased and not result.contact_cycle_available
        and not result.action_owned_hp_decrease then
        result.reason = "hp_decreased_without_new_hit_cycle"
    elseif result.hp_decreased and not result.contact_candidate then
        result.reason = "hp_decreased_without_unconfirmed_action"
    elseif result.hp_decreased and result.hp_delta < result.minimum_hp_delta then
        result.reason = "hp_decrease_within_persistent_damage_range"
    elseif result.hp_decreased then
        result.accepted = true
        result.reason = result.action_owned_hp_decrease
            and "victim_hp_decreased_during_bound_action"
            or "victim_hp_decreased_hit_signal"
    else
        result.reason = "no_new_hit_contact"
    end
    return result
end

-- Stateful contact observation shared by the legacy recorder and the V2
-- compiler. Each hit/block signal edge creates a short-lived token. Combo
-- growth or the first HP decrease consumes the hit token; the first HP
-- decrease consumes the block-damage token. All later HP drops in the same
-- signal period are passive damage rather than duplicate contacts/chip.
function M.observe_recording_contacts(state, params)
    state = type(state) == "table" and state or {}
    params = type(params) == "table" and params or {}
    local frame = tonumber(params.frame) or 0
    local damage_type = tonumber(params.damage_type) or 0
    local hit_stop = tonumber(params.hit_stop) or 0
    local combo_increased = (tonumber(params.current_combo) or 0)
        > (tonumber(params.previous_combo) or 0)
    local previous_damage_type = tonumber(state.previous_damage_type)
    local previous_hit_stop = tonumber(state.previous_hit_stop)
    if state.suppress_hit_cycle_until ~= nil
        and frame > state.suppress_hit_cycle_until then
        state.suppress_hit_cycle_until = nil
    end
    local hit_signal = damage_type == 3 and hit_stop > 0
    local hit_cycle_started = hit_signal and (
        previous_damage_type ~= 3
        or (previous_hit_stop or 0) <= 0
        or hit_stop > (previous_hit_stop or 0)
    )
    if hit_cycle_started then
        state.hit_cycle_expires = frame + CONTACT_SIGNAL_SETTLE_FRAMES
        state.hit_cycle_consumed = state.suppress_hit_cycle_until ~= nil
            and frame <= state.suppress_hit_cycle_until or false
        if state.hit_cycle_consumed then
            state.suppress_hit_cycle_until =
                frame + CONTACT_SIGNAL_SETTLE_FRAMES
        end
    end
    local hit_cycle_available = state.hit_cycle_consumed ~= true
        and state.hit_cycle_expires ~= nil
        and frame <= state.hit_cycle_expires

    -- Combo growth is stronger hit truth than a one-frame-late block type.
    -- Keep hit/block mutually exclusive when runtime fields settle out of order.
    local block_active = damage_type == 30 and not combo_increased
    local block_edge_observed = block_active and (
        previous_damage_type ~= 30
        or (hit_stop > 0 and hit_stop > (previous_hit_stop or 0))
    )
    local block_cycle_started = false
    if block_edge_observed then
        local same_settling_cycle = state.last_block_contact_frame ~= nil
            and frame - state.last_block_contact_frame
                <= CONTACT_SIGNAL_SETTLE_FRAMES
        if same_settling_cycle then
            state.last_block_contact_frame = frame
            state.block_cycle_expires = math.max(
                tonumber(state.block_cycle_expires) or frame,
                frame + CONTACT_SIGNAL_SETTLE_FRAMES
            )
        else
            block_cycle_started = true
            state.last_block_contact_frame = frame
            state.block_cycle_expires = frame + CONTACT_SIGNAL_SETTLE_FRAMES
            state.block_cycle_consumed = false
        end
    end
    local block_cycle_available = state.block_cycle_consumed ~= true
        and state.block_cycle_expires ~= nil
        and frame <= state.block_cycle_expires

    local hit_contact = M.evaluate_recording_hit_contact({
        current_combo = params.current_combo,
        previous_combo = params.previous_combo,
        current_hp = params.current_hp,
        previous_hp = params.previous_hp,
        damage_type = damage_type,
        hit_stop = hit_stop,
        previous_damage_type = previous_damage_type,
        previous_hit_stop = previous_hit_stop,
        blocked = block_active,
        contact_candidate = params.contact_candidate,
        contact_cycle_available = hit_cycle_available,
        action_owned_hp_decrease = params.action_owned_hp_decrease,
    })
    local current_hp_decreased = hit_contact.hp_decreased == true
    local current_delta = math.max(0, tonumber(hit_contact.hp_delta) or 0)
    local passive_damage_samples = {}
    local pending_hp_drop = state.pending_hp_drop
    state.pending_hp_drop = nil
    local pending_hit_damage_confirmed = false
    local pending_hit_cycle_consumed = false
    local pending_block_damage_confirmed = false
    if type(pending_hp_drop) == "table" then
        local pending_age = frame - (tonumber(pending_hp_drop.frame) or frame)
        local pending_delta = math.max(
            0,
            tonumber(pending_hp_drop.delta) or 0
        )
        if pending_age == 1
            and (not current_hp_decreased
                or current_delta < MIN_UNCOUNTED_HIT_HP_DELTA)
            and not block_active
            and (hit_contact.combo_increased or hit_cycle_available)
            and pending_delta >= MIN_UNCOUNTED_HIT_HP_DELTA then
            pending_hit_cycle_consumed = true
            pending_hit_damage_confirmed = true
            if hit_contact.accepted ~= true
                and params.contact_candidate ~= false then
                hit_contact.accepted = true
                hit_contact.reason = "previous_hp_decrease_new_hit_cycle"
                hit_contact.hp_decreased = true
                hit_contact.hp_delta = tonumber(pending_hp_drop.delta) or 0
            end
        elseif pending_age == 1
            and (not current_hp_decreased
                or current_delta < MIN_UNCOUNTED_HIT_HP_DELTA)
            and block_active and block_cycle_available
            and pending_delta >= MIN_UNCOUNTED_HIT_HP_DELTA then
            pending_block_damage_confirmed = true
        else
            passive_damage_samples[#passive_damage_samples + 1] =
                pending_hp_drop
        end
    end

    local delayed_hit_damage_confirmed = false
    if current_hp_decreased
        and state.pending_hit_damage_until ~= nil
        and frame <= state.pending_hit_damage_until
        and current_delta >= MIN_UNCOUNTED_HIT_HP_DELTA then
        delayed_hit_damage_confirmed = true
        state.pending_hit_damage_until = nil
    elseif state.pending_hit_damage_until ~= nil
        and frame > state.pending_hit_damage_until then
        state.pending_hit_damage_until = nil
    end
    if delayed_hit_damage_confirmed then
        -- A combo edge from the previous sample already proved this HP update
        -- belongs to a hit. A late block type on the HP sample must not create
        -- a second, mutually contradictory contact for the same damage.
        block_active = false
        block_cycle_started = false
        block_cycle_available = false
        state.block_cycle_consumed = true
    end
    local current_hit_cycle_consumed = current_hp_decreased
        and not block_active
        and hit_cycle_available
        and current_delta >= MIN_UNCOUNTED_HIT_HP_DELTA
    local current_hit_damage_confirmed = current_hp_decreased
        and not block_active
        and current_delta >= MIN_UNCOUNTED_HIT_HP_DELTA
        and (hit_cycle_available or hit_contact.combo_increased
            or hit_contact.action_owned_hp_decrease)
    if current_hit_damage_confirmed
        and hit_contact.accepted ~= true
        and params.contact_candidate ~= false then
        hit_contact.accepted = true
        hit_contact.reason = "hp_decrease_pending_hit_cycle"
    end
    local hit_damage_confirmed = current_hit_damage_confirmed
        or delayed_hit_damage_confirmed
        or pending_hit_damage_confirmed
    if hit_contact.accepted or hit_damage_confirmed
        or current_hit_cycle_consumed or pending_hit_cycle_consumed then
        state.hit_cycle_consumed = true
        state.suppress_hit_cycle_until = frame + CONTACT_SIGNAL_SETTLE_FRAMES
        if hit_contact.combo_increased then
            -- Some fields expose combo growth one sample before a fresh
            -- hit-stop edge. Consume that immediately-following cycle too.
            if not hit_damage_confirmed then
                state.pending_hit_damage_until =
                    frame + CONTACT_SIGNAL_SETTLE_FRAMES
            end
        end
    end

    local current_block_damage_confirmed = current_hp_decreased
        and block_cycle_available
        and not current_hit_damage_confirmed
        and current_delta >= MIN_UNCOUNTED_HIT_HP_DELTA
    local block_damage_confirmed = pending_block_damage_confirmed
        or current_block_damage_confirmed
    local block_cycle_hp_observed = current_hp_decreased
        and block_cycle_available
        and not current_hit_damage_confirmed
        and current_delta >= MIN_UNCOUNTED_HIT_HP_DELTA
    if block_damage_confirmed or block_cycle_hp_observed then
        state.block_cycle_consumed = true
    end
    if current_hp_decreased
        and not current_hit_damage_confirmed
        and not delayed_hit_damage_confirmed
        and not current_block_damage_confirmed then
        local supported_persistent_tick = current_delta > 0
            and current_delta < MIN_UNCOUNTED_HIT_HP_DELTA
            and (hit_cycle_available or block_cycle_available)
        if current_hit_cycle_consumed or block_cycle_hp_observed
            or hit_contact.combo_increased or supported_persistent_tick then
            passive_damage_samples[#passive_damage_samples + 1] = {
                frame = frame,
                delta = current_delta,
            }
        else
            state.pending_hp_drop = {
                frame = frame,
                delta = current_delta,
            }
        end
    end

    state.previous_damage_type = damage_type
    state.previous_hit_stop = hit_stop
    return {
        hit_contact = hit_contact,
        block_contact = {
            active = block_active,
            started = block_cycle_started,
        },
        block_damage_confirmed = block_damage_confirmed,
        hit_damage_confirmed = hit_damage_confirmed,
        passive_damage_samples = passive_damage_samples,
        hp_delta = hit_contact.hp_delta,
        hit_cycle_started = hit_cycle_started,
    }
end

function M.flush_recording_contact_state(state)
    if type(state) ~= "table" or type(state.pending_hp_drop) ~= "table" then
        return {}
    end
    local pending = state.pending_hp_drop
    state.pending_hp_drop = nil
    return { pending }
end

function M.evaluate_block_contact(damage_type, was_active)
    local active = tonumber(damage_type) == 30
    return {
        active = active,
        started = active and was_active ~= true
    }
end

function M.detect(current_id, current_frame, buffered_id, buffered_frame, state, current_tick,
        action_button_edge, confirmed_repeat_input)
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

    -- Playback may admit a fresh edge when the recorded sequence independently
    -- proves that the next expected step is the same action. Recording never
    -- uses input or contact alone to synthesize a new action instance.
    if confirmed_repeat_input and action_button_edge ~= 0 then
        local confirmation_reason = type(confirmed_repeat_input) == "string"
            and confirmed_repeat_input or "expected_repeat_action_input"
        return true, confirmation_reason
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
