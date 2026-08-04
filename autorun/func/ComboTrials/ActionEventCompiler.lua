-- Compiles WTT-compatible V2 steps from the input stream and the Action IDs
-- that the game actually exposes while those inputs are being executed.
--
-- This module deliberately does not read command tables, character exception
-- files or an existing combo sequence. Those are presentation/compatibility
-- data and must not decide which runtime Action happened.

local ActionMatcher = require("func/ComboTrials/ActionMatcher")
local ActionRestartDetector = require("func/ComboTrials/ActionRestartDetector")

local Compiler = {
    name = "ComboTrials.ActionEventCompiler",
    BIND_WINDOW = ActionMatcher.PLAYER_ACTION_BIND_WINDOW,
    -- Some commands expose one or more short-lived internal Actions before
    -- the durable catalog Action appears. Keep the physical input anchor, but
    -- allow that anchor to follow the observed runtime chain until the next
    -- input-bound event.
    PROMOTION_WINDOW = 60,
    UNMAPPED_PRECURSOR_WINDOW = 20,
    -- Negative-edge commands transition shortly after release. A much older
    -- release must not claim a later low-numbered locomotion/system Action.
    RELEASE_LOW_ACTION_BIND_WINDOW = 8,
    PLAYER_FOLLOWUP_INPUT_WINDOW = 12,
    GHOST_FILTER_FRAMES = 4,
    DIRECTION_ACTION_BIND_WINDOW = 4,
    DASH_TAP_WINDOW = 12,
    RAW_DRIVE_RUSH_EVIDENCE_WINDOW = 12,
    RAW_DRIVE_RUSH_MIN_LOCAL_COST = 9000,
    -- The game exposes Action 740 before its one-bar cost is guaranteed to be
    -- visible in the player gauge. Keep the transition briefly and confirm it
    -- from the same local meter spend before the next Action is bound.
    RAW_DRIVE_RUSH_COST_SETTLE_WINDOW = 30,
    BUTTON_MASK = 0xFFF0,
}

local BUTTONS = {
    { bit = 16, name = "LP" },
    { bit = 32, name = "MP" },
    { bit = 64, name = "HP" },
    { bit = 128, name = "LK" },
    { bit = 256, name = "MK" },
    { bit = 512, name = "HK" },
}

local DIRECTION_NAMES = {
    [0] = "5",
    [1] = "8",
    [2] = "2",
    [4] = "6",
    [8] = "4",
    [5] = "9",
    [6] = "3",
    [9] = "7",
    [10] = "1",
    [15] = "*",
}

local MOVEMENT_ACTIONS = {
    [17] = true,
    [18] = true,
    [36] = true,
    [37] = true,
    [38] = true,
}

local JUMP_ACTIONS = {
    [36] = true,
    [37] = true,
    [38] = true,
}

-- The game can expose JUMP_F_BGN as a short classic-control transition before
-- the durable forward-jump Action. The training validator intentionally
-- ignores the BGN phase, so it must never become a separate V2 step.
local JUMP_STARTUP_TRANSITIONS = {
    [33] = { [36] = true },
    [34] = { [37] = true },
    [35] = { [38] = true },
}

local DASH_ACTIONS = {
    [17] = true,
    [18] = true,
}

local function rounded(value)
    value = tonumber(value)
    return value and math.floor(value + 0.5) or nil
end

local function shallow_copy(value)
    local result = {}
    for key, child in pairs(type(value) == "table" and value or {}) do
        result[key] = child
    end
    return result
end

local function anchor_button_mask(anchor)
    if type(anchor) ~= "table" then return 0 end
    local pressed = tonumber(anchor.pressed_buttons) or 0
    local released = tonumber(anchor.released_buttons) or 0
    local held = tonumber(anchor.held_buttons) or 0
    if pressed ~= 0 then return pressed & Compiler.BUTTON_MASK end
    if released ~= 0 then return released & Compiler.BUTTON_MASK end
    return held & Compiler.BUTTON_MASK
end

local function action_event_projection_rule(session, action_id)
    local rules = type(session) == "table"
        and session.action_event_projection_rules or nil
    if type(rules) ~= "table" then return nil end
    return rules[tonumber(action_id)] or rules[tostring(action_id)]
end

local function session_action_event_rules(session)
    return type(session) == "table" and type(session.action_event_rules) == "table"
        and session.action_event_rules or {}
end

local function quick_successor_rule(session, action_id)
    return ActionMatcher.get_quick_successor_rule(
        session_action_event_rules(session),
        action_id
    )
end

local function project_character_action_owner(event, session)
    if type(event) ~= "table" then return event, nil end
    -- Projection must never mutate the source event retained in
    -- trace.input_bound_events. Every event gets its own table and anchor,
    -- including command owners that later receive merged contact truth.
    local projected = shallow_copy(event)
    if type(event.anchor) == "table" then
        projected.anchor = shallow_copy(event.anchor)
    end
    local rule = action_event_projection_rule(session, event.id)
    local projection_matches = type(rule) == "table"
        and rule.kind == "canonical_owner"
    if type(rule) == "table" and rule.kind == "input_anchor_owner" then
        local anchor = type(event.anchor) == "table" and event.anchor or {}
        projection_matches = anchor.kind == rule.required_anchor_kind
            and (rule.require_no_contact ~= true
                or (event.has_contact ~= true and event.has_hit ~= true))
    end
    if not projection_matches
        or tonumber(rule.owner_id) == nil
        or tonumber(rule.owner_id) == tonumber(event.id) then
        return projected, rule
    end

    projected.id = tonumber(rule.owner_id)
    projected.normalized_from_action_id = tonumber(event.id)
    return projected, rule
end

-- Same-command fold checks shared by canonical owners and release-bound
-- internal phases. A release of the owner's buttons is still the same
-- physical command even when the runtime exposes the child on a later frame.
local function fold_anchor_allows(previous, source_event, rule)
    if type(rule) ~= "table" or rule.require_same_anchor ~= true then
        return true
    end
    local previous_anchor = type(previous.event.anchor) == "table"
        and previous.event.anchor or nil
    local current_anchor = type(source_event.anchor) == "table"
        and source_event.anchor or nil
    local previous_anchor_frame = tonumber(
        previous_anchor and previous_anchor.frame
    )
    local current_anchor_frame = tonumber(
        current_anchor and current_anchor.frame
    )
    local previous_buttons = anchor_button_mask(previous_anchor)
    local current_buttons = anchor_button_mask(current_anchor)
    local same_anchor_frame = previous_anchor_frame ~= nil
        and current_anchor_frame ~= nil
        and previous_anchor_frame == current_anchor_frame
    local release_continuation = type(current_anchor) == "table"
        and current_anchor.kind == "button_release"
        and previous_buttons ~= 0
        and current_buttons ~= 0
        and (previous_buttons & current_buttons) ~= 0
    -- Some multi-phase commands keep exposing their child Action when the
    -- player presses the same buttons again during the command window. That
    -- press is part of the same physical command chain, not a fresh move.
    local press_continuation = rule.allow_same_button_press_fold == true
        and type(current_anchor) == "table"
        and current_anchor.kind == "button_press"
        and previous_buttons ~= 0
        and current_buttons ~= 0
        and previous_buttons == current_buttons
    local continuation = release_continuation or press_continuation
    if previous_anchor_frame ~= nil and current_anchor_frame ~= nil
        and not same_anchor_frame and not continuation then
        return false
    end
    if previous_buttons ~= 0 and current_buttons ~= 0
        and previous_buttons ~= current_buttons
        and not continuation then
        return false
    end
    return true
end

local function character_rule_fold_reason(
    previous,
    source_event,
    session
)
    if type(previous) ~= "table" or type(previous.event) ~= "table"
        or type(source_event) ~= "table" then
        return nil
    end
    local rule = action_event_projection_rule(session, source_event.id)
    if type(rule) ~= "table"
        or tonumber(rule.owner_id) ~= tonumber(previous.event.id) then
        return nil
    end
    if rule.kind == "internal_phase" then
        if rule.require_same_anchor == true then
            local current_frame = tonumber(source_event.frame)
            local previous_frame = tonumber(previous.event.frame)
            if current_frame == nil or previous_frame == nil then
                return nil
            end
            local delay = current_frame - previous_frame
            if delay < 0
                or delay > (tonumber(rule.max_fold_delay_frames) or 0) then
                return nil
            end
            if not fold_anchor_allows(previous, source_event, rule) then
                return nil
            end
        end
        return "character_internal_action_phase"
    end
    if rule.kind == "canonical_owner" then
        local current_frame = tonumber(source_event.frame)
        local previous_frame = tonumber(previous.event.frame)
        if current_frame == nil or previous_frame == nil then
            return nil
        end
        local delay = current_frame - previous_frame
        if delay < 0
            or delay > (tonumber(rule.max_fold_delay_frames) or 0) then
            return nil
        end
        if not fold_anchor_allows(previous, source_event, rule) then
            return nil
        end
        return "character_canonical_owner_variant"
    end
    return nil
end

local function relative_direction(input_mask, facing_right)
    local bits = (tonumber(input_mask) or 0) & 0xF
    if facing_right == false then
        local right = (bits & 4) ~= 0
        local left = (bits & 8) ~= 0
        bits = bits & ~12
        if right then bits = bits | 8 end
        if left then bits = bits | 4 end
    end
    return DIRECTION_NAMES[bits] or "5"
end

local function button_notation(mask)
    mask = (tonumber(mask) or 0) & Compiler.BUTTON_MASK
    local names = {}
    for _, button in ipairs(BUTTONS) do
        if (mask & button.bit) ~= 0 then names[#names + 1] = button.name end
    end
    if #names > 0 then return table.concat(names, "+") end
    if mask ~= 0 then return string.format("BTN_0x%X", mask) end
    return ""
end

local function trim_direction_history(session, frame)
    local history = session.direction_history
    while #history > 0 and frame - history[1].frame > 180 do
        table.remove(history, 1)
    end
end

local function direction_sequence(session, start_frame, end_frame)
    local values = {}
    local last
    for _, entry in ipairs(session.direction_history) do
        if entry.frame >= start_frame and entry.frame <= end_frame
            and entry.direction ~= "5" and entry.direction ~= "*" then
            if entry.direction ~= last then
                values[#values + 1] = entry.direction
                last = entry.direction
            end
        end
    end
    return table.concat(values)
end

local MOTION_SUFFIXES = {
    "236236",
    "214214",
    "63214",
    "41236",
    "236",
    "214",
    "623",
}

local function canonical_direction_motion(sequence, current_direction)
    sequence = tostring(sequence or "")
    for _, suffix in ipairs(MOTION_SUFFIXES) do
        if sequence:sub(-#suffix) == suffix
            or (#sequence > #suffix
                and sequence:sub(-#suffix - 1, -2) == suffix) then
            return suffix
        end
    end
    if sequence:sub(-2) == "66" or sequence:sub(-3, -2) == "66" then
        return "66"
    end
    if sequence:sub(-2) == "44" or sequence:sub(-3, -2) == "44" then
        return "44"
    end
    return current_direction ~= "5" and current_direction or ""
end

local function fallback_motion(event)
    local anchor = event.anchor or {}
    local button_mask =
        (tonumber(anchor.pressed_buttons) or 0) ~= 0 and anchor.pressed_buttons
            or ((tonumber(anchor.held_buttons) or 0) ~= 0 and anchor.held_buttons
                or anchor.released_buttons)
    -- HP+HK is the universal classic Drive Impact input. When a character
    -- exposes an unmapped state-specific DI Action, preserve the real Action
    -- ID while still presenting the player command instead of a directional
    -- fallback such as 6+HP+HK.
    if ((tonumber(button_mask) or 0) & Compiler.BUTTON_MASK) == (64 | 512) then
        return "DI"
    end
    if ((tonumber(button_mask) or 0) & Compiler.BUTTON_MASK) == (32 | 256) then
        return "PARRY"
    end
    local buttons = button_notation(button_mask)
    local direction = canonical_direction_motion(
        tostring(anchor.direction_sequence or ""),
        tostring(anchor.direction or "5")
    )
    if direction ~= "" and buttons ~= "" then return direction .. "+" .. buttons end
    if buttons ~= "" then return buttons end
    if direction ~= "" then return direction end
    return "ACTION_" .. tostring(event.id)
end

local function action_is_recordable(action_id)
    action_id = tonumber(action_id)
    return action_id ~= nil and action_id >= 17
end

local function update_damage(session, sample)
    local victim_hp = rounded(sample.victim_hp)
    if victim_hp == nil then return end

    if not session.input_started then
        session.initial_victim_hp = victim_hp
        session.min_victim_hp = victim_hp
        session.previous_damage_hp = victim_hp
        session.cumulative_damage = 0
    elseif session.initial_victim_hp == nil then
        session.initial_victim_hp = victim_hp
        session.min_victim_hp = victim_hp
        session.previous_damage_hp = victim_hp
        session.cumulative_damage = 0
    else
        session.min_victim_hp = math.min(session.min_victim_hp or victim_hp, victim_hp)
        local previous_hp = tonumber(session.previous_damage_hp)
        if previous_hp ~= nil and victim_hp < previous_hp then
            session.cumulative_damage = (tonumber(session.cumulative_damage) or 0)
                + (previous_hp - victim_hp)
        end
        session.previous_damage_hp = victim_hp
    end
    session.current_damage = math.max(0, tonumber(session.cumulative_damage) or 0)
end

local function record_passive_damage(session, sample)
    if type(session) ~= "table" or type(sample) ~= "table" then return end
    local frame = tonumber(sample.frame)
    local delta = math.max(0, tonumber(sample.delta) or 0)
    if frame == nil or delta <= 0 then return end
    session.passive_damage_ticks =
        (tonumber(session.passive_damage_ticks) or 0) + 1
    session.passive_damage_total =
        (tonumber(session.passive_damage_total) or 0) + delta
    session.passive_damage_max_tick = math.max(
        tonumber(session.passive_damage_max_tick) or 0,
        delta
    )
    session.passive_damage_frames = type(session.passive_damage_frames) == "table"
        and session.passive_damage_frames or {}
    session.passive_damage_frames[#session.passive_damage_frames + 1] = frame
    session.passive_damage_samples = type(session.passive_damage_samples) == "table"
        and session.passive_damage_samples or {}
    session.passive_damage_samples[#session.passive_damage_samples + 1] = {
        frame = frame,
        delta = delta,
    }
end

local function update_actor_resources(session, sample, input_edge_started)
    local drive = rounded(sample.actor_drive)
    local super = rounded(sample.actor_super)
    if drive ~= nil then
        if session.initial_actor_drive == nil then
            session.initial_actor_drive = drive
            session.min_actor_drive = drive
        elseif not session.input_started and input_edge_started ~= true then
            -- Keep following environment refreshes until the first physical
            -- command edge. On the edge itself, gauge cost may already be
            -- visible, so the prior idle sample must remain the baseline.
            session.initial_actor_drive = drive
            session.min_actor_drive = drive
        else
            session.min_actor_drive = math.min(session.min_actor_drive or drive, drive)
        end
    end
    if super ~= nil then
        if session.initial_actor_super == nil then
            session.initial_actor_super = super
            session.min_actor_super = super
        elseif not session.input_started and input_edge_started ~= true then
            session.initial_actor_super = super
            session.min_actor_super = super
        else
            session.min_actor_super = math.min(session.min_actor_super or super, super)
        end
    end
end

local function build_anchor(session, sample, kind, pressed, released, hold_frames)
    local frame = tonumber(sample.frame) or 0
    local previous_event = session.events[#session.events]
    local history_start = previous_event and math.max(previous_event.frame - 5, frame - 90)
        or math.max(session.started_frame or frame, frame - 90)
    return {
        frame = frame,
        kind = kind,
        pressed_buttons = pressed or 0,
        released_buttons = released or 0,
        held_buttons = (tonumber(sample.direct_input) or 0) & Compiler.BUTTON_MASK,
        direction = relative_direction(sample.direct_input, sample.facing_right),
        direction_sequence = direction_sequence(session, history_start, frame),
        initial_action_id = session.previous_action_id,
        initial_action_frame = session.previous_action_frame,
        hold_frames = tonumber(hold_frames) or nil,
    }
end

local function snapshot_anchor(session, sample, kind, pressed, released, hold_frames)
    local anchor = build_anchor(
        session,
        sample,
        kind,
        pressed,
        released,
        hold_frames
    )
    session.input_anchor_count = session.input_anchor_count + 1
    session.input_started = true
    session.pending_anchor = anchor
    return anchor
end

local function update_button_hold_state(session, frame, pressed, released)
    local longest_release = 0
    for bit_index = 4, 15 do
        local bit = 1 << bit_index
        if (pressed & bit) ~= 0 then
            session.button_press_frames[bit] = frame
        end
        if (released & bit) ~= 0 then
            local started = tonumber(session.button_press_frames[bit])
            if started ~= nil then
                longest_release = math.max(longest_release, math.max(0, frame - started))
            end
            session.button_press_frames[bit] = nil
        end
    end
    return longest_release
end

local function recorded_event_projection_owner_id(session, event)
    if type(event) ~= "table" then return nil end
    local owners = type(session) == "table"
        and session.event_projection_owners or nil
    local cached = type(owners) == "table" and owners[event] or nil
    if tonumber(cached) ~= nil then return tonumber(cached) end
    local rule = action_event_projection_rule(session, event.id)
    if type(rule) == "table" and rule.kind == "canonical_owner"
        and tonumber(rule.owner_id) ~= nil then
        return tonumber(rule.owner_id)
    end
    return tonumber(event.id)
end

local function add_event(session, sample, anchor, reason)
    local action_id = tonumber(sample.action_id)
    if not action_is_recordable(action_id) then return nil end

    local frame = tonumber(sample.frame) or 0
    local previous = session.events[#session.events]
    local current_projection_rule = action_event_projection_rule(
        session,
        action_id
    )
    local current_quick_successor_rule = quick_successor_rule(session, action_id)
    local consumed_pending_anchor = type(session.pending_anchor) == "table"
        and session.pending_anchor == anchor
    local event = {
        id = action_id,
        frame = frame,
        action_frame = tonumber(sample.action_frame) or 0,
        actor_hp = rounded(sample.actor_hp),
        actor_drive = rounded(sample.actor_drive),
        facing_right = sample.facing_right ~= false,
        combo_at_start = math.max(0, tonumber(sample.combo_count) or 0),
        expected_combo = 0,
        -- Passive damage may continue after the last real contact (A.K.I.
        -- poison is the common case). New commands inherit only damage that
        -- has been confirmed by combat contact, not arbitrary HP loss.
        damage_at_step = session.confirmed_damage or 0,
        has_hit = false,
        has_contact = false,
        was_blocked = false,
        anchor = shallow_copy(anchor),
        bind_reason = reason,
        delay_from_prev = previous and math.max(0, frame - previous.frame) or 0,
    }
    local projection_fold_reason
    local previous_projection_owner =
        recorded_event_projection_owner_id(session, previous)
    if previous_projection_owner ~= nil then
        local projected_previous = shallow_copy(previous)
        projected_previous.id = previous_projection_owner
        projection_fold_reason = character_rule_fold_reason(
            { event = projected_previous },
            event,
            session
        )
    end
    session.events[#session.events + 1] = event
    if projection_fold_reason then
        session.event_projection_owners =
            type(session.event_projection_owners) == "table"
                and session.event_projection_owners or {}
        session.event_projection_owners[event] = previous_projection_owner
    end
    session.current_event = event
    session.pending_anchor = nil
    if projection_fold_reason == "character_internal_action_phase"
        and consumed_pending_anchor
        and type(current_projection_rule) == "table"
        and current_projection_rule.carry_input_anchor == true then
        -- An internal runtime phase may become visible before the durable
        -- Action that the pending physical input actually launches. Keep the
        -- raw phase event, but return a private copy of that anchor to the
        -- binder. A canonical-owner release already belongs to its owner and
        -- must not be reused by a later ordinary Action.
        local continuation = shallow_copy(anchor)
        continuation.initial_action_id = action_id
        continuation.initial_action_frame = tonumber(sample.action_frame) or 0
        continuation.is_internal_phase_continuation = true
        continuation.internal_phase_owner_id =
            tonumber(current_projection_rule.owner_id)
        session.pending_anchor = continuation
    elseif consumed_pending_anchor and current_quick_successor_rule then
        -- Some explicit cancel Actions are a real player-visible step, while
        -- the attack launched by the same input appears a few frames later as
        -- another durable Action. Keep the original event and lend its input
        -- anchor to that immediate successor so contact belongs to the attack.
        local continuation = shallow_copy(anchor)
        continuation.frame = frame
        continuation.initial_action_id = action_id
        continuation.initial_action_frame = tonumber(sample.action_frame) or 0
        continuation.is_quick_successor_continuation = true
        continuation.quick_successor_source_id = action_id
        continuation.max_delay_frames = math.max(
            1,
            tonumber(current_quick_successor_rule.max_delay_frames) or 1
        )
        session.pending_anchor = continuation
    end
    session.recent_direction_anchor = nil
    session.started = true
    session.started_frame = session.started_frame or frame
    session.last_activity_frame = frame
    return event
end

local function raw_drive_rush_transition_anchor(current_event, sample, input)
    local anchor = shallow_copy(
        type(current_event) == "table" and current_event.anchor or nil
    )
    anchor.frame = tonumber(sample and sample.frame) or 0
    anchor.kind = "drive_cost_confirmed_transition"
    anchor.initial_action_id = tonumber(current_event and current_event.id)
    anchor.initial_action_frame = tonumber(current_event and current_event.action_frame)
    anchor.pressed_buttons = 0
    anchor.released_buttons = 0
    anchor.held_buttons = (tonumber(input) or 0) & Compiler.BUTTON_MASK
    return anchor
end

local function confirm_pending_meter_raw_drive_rush(session, sample)
    local pending = type(session) == "table"
        and session.pending_meter_confirmed_raw_dr or nil
    if type(pending) ~= "table" then return false end

    local frame = tonumber(sample and sample.frame) or 0
    local transition_frame = tonumber(pending.frame) or frame
    local age = frame - transition_frame
    local baseline_drive = tonumber(pending.baseline_drive)
    local current_drive = rounded(sample and sample.actor_drive)
    local local_drive_cost = baseline_drive ~= nil and current_drive ~= nil
        and math.max(0, baseline_drive - current_drive) or 0

    if age >= 0 and age <= Compiler.RAW_DRIVE_RUSH_COST_SETTLE_WINDOW
        and local_drive_cost >= Compiler.RAW_DRIVE_RUSH_MIN_LOCAL_COST then
        session.pending_meter_confirmed_raw_dr = nil
        add_event(
            session,
            pending.sample,
            pending.anchor,
            "deferred_drive_cost_confirmed_raw_dr_transition"
        )
        return true
    end

    local current_action_id = tonumber(sample and sample.action_id)
    local left_raw_drive_rush = current_action_id ~= nil
        and not ActionMatcher.is_raw_drive_rush_action_id(current_action_id)
    if age > Compiler.RAW_DRIVE_RUSH_COST_SETTLE_WINDOW
        or left_raw_drive_rush then
        session.pending_meter_confirmed_raw_dr = nil
        session.expired_meter_raw_dr_count =
            (tonumber(session.expired_meter_raw_dr_count) or 0) + 1
    end
    return false
end

local function event_button_mask(event)
    local anchor = type(event) == "table" and event.anchor or nil
    return anchor_button_mask(anchor)
end

local function merge_event_outcome_truth(target, source)
    if type(target) ~= "table" or type(source) ~= "table" then return end
    target.expected_combo = math.max(
        tonumber(target.expected_combo) or 0,
        tonumber(source.expected_combo) or 0
    )
    if target.first_contact_frame == nil then
        target.first_contact_frame = source.first_contact_frame
    elseif source.first_contact_frame ~= nil then
        target.first_contact_frame = math.min(
            tonumber(target.first_contact_frame) or source.first_contact_frame,
            tonumber(source.first_contact_frame) or target.first_contact_frame
        )
    end
    target.damage_at_step = math.max(
        tonumber(target.damage_at_step) or 0,
        tonumber(source.damage_at_step) or 0
    )
    target.has_hit = target.has_hit == true or source.has_hit == true
    target.has_contact = target.has_contact == true or source.has_contact == true
    target.was_blocked = target.was_blocked == true or source.was_blocked == true
end

local function merge_event_truth(target, source)
    if type(target) ~= "table" or type(source) ~= "table" then return end
    merge_event_outcome_truth(target, source)
    target.hold_frames = math.max(
        tonumber(target.hold_frames) or 0,
        tonumber(source.hold_frames)
            or tonumber(type(source.anchor) == "table" and source.anchor.hold_frames)
            or 0
    )
    if type(source.anchor) == "table"
        and source.anchor.kind == "button_release"
        and source.has_contact == true then
        local hold_frames = tonumber(source.anchor.hold_frames) or 0
        if hold_frames >= 15 then
            target.is_holdable = true
            target.hold_partial_check = true
        end
    end
end

local function compact_motion(value)
    return tostring(value or ""):upper():gsub("[%s_+%-]+", "")
end

local function is_direction_only_motion(value)
    return compact_motion(value):match("^[1-9]+$") ~= nil
end

local function is_quick_drive_parry_precursor(previous, current)
    if type(previous) ~= "table" or type(current) ~= "table" then return false end
    if previous.event.has_contact == true or previous.event.has_hit == true then return false end
    local delay = (tonumber(current.event.frame) or 0)
        - (tonumber(previous.event.frame) or 0)
    return delay >= 0 and delay <= 4
        and compact_motion(previous.motion) == "DP"
        and compact_motion(current.motion) == "RAWDR"
end

local function is_jump_startup_precursor(previous, current)
    if type(previous) ~= "table" or type(current) ~= "table" then return false end
    if type(previous.event) ~= "table" or type(current.event) ~= "table" then return false end
    local destinations = JUMP_STARTUP_TRANSITIONS[tonumber(previous.event.id)]
    if type(destinations) ~= "table"
        or destinations[tonumber(current.event.id)] ~= true then
        return false
    end
    local delay = (tonumber(current.event.frame) or 0)
        - (tonumber(previous.event.frame) or 0)
    return delay >= 0 and delay <= 8
end

local function is_unmapped_input_precursor(previous, current)
    if type(previous) ~= "table" or type(current) ~= "table" then return false end
    if previous.motion ~= nil or current.motion == nil then return false end
    if previous.event.has_contact == true or previous.event.has_hit == true then return false end
    local delay = (tonumber(current.event.frame) or 0)
        - (tonumber(previous.event.frame) or 0)
    if delay < 0 or delay > Compiler.UNMAPPED_PRECURSOR_WINDOW then return false end
    local previous_buttons = event_button_mask(previous.event)
    local current_buttons = event_button_mask(current.event)
    if previous_buttons ~= 0
        and current_buttons ~= 0
        and (previous_buttons & current_buttons) ~= 0 then
        return true
    end
    local previous_anchor = type(previous.event.anchor) == "table"
        and previous.event.anchor or {}
    local current_anchor = type(current.event.anchor) == "table"
        and current.event.anchor or {}
    if previous_buttons == 0
        and current_buttons ~= 0
        and (previous_anchor.kind == "double_tap"
            or previous_anchor.kind == "direction_action") then
        -- Quarter-circle repetitions inside a super input can briefly look
        -- like a standalone directional double tap. If no catalog Action or
        -- contact resulted before the following button Action, it is only the
        -- direction buffer of that command.
        return previous_anchor.kind == "double_tap"
            or delay < Compiler.GHOST_FILTER_FRAMES
    end
    local movement_motion = compact_motion(current.motion)
    return previous_buttons == 0
        and current_buttons == 0
        and (movement_motion == "66" or movement_motion == "44")
        and (previous_anchor.kind == "double_tap"
            or previous_anchor.kind == "movement_action")
        and (current_anchor.kind == "double_tap"
            or current_anchor.kind == "movement_action")
end

-- Pure direction input is necessary evidence for mapped mechanics such as C.
-- Viper's 28 high-jump cancel. An Action with no command-map entry, no
-- physical button and no contact is different: it is only a transient stance
-- or direction-buffer state and must not become an unresolved V2 command.
local function is_unmapped_direction_transition(current)
    if type(current) ~= "table" or type(current.event) ~= "table" then
        return false
    end
    local anchor = type(current.event.anchor) == "table"
        and current.event.anchor or {}
    return current.motion == nil
        and current.resolution_status == "action_id_missing"
        and anchor.kind == "direction_action"
        and event_button_mask(current.event) == 0
        and current.event.has_contact ~= true
        and current.event.has_hit ~= true
end

-- RAW DR can expose a later 741 execution state after the already-recorded
-- 740 owner Action. Both IDs are runtime facts, but the second state has no
-- independent physical command and must not create another V2 instruction.
local function is_redundant_drive_rush_phase(previous, current)
    if type(previous) ~= "table" or type(current) ~= "table"
        or type(previous.event) ~= "table"
        or type(current.event) ~= "table" then
        return false
    end
    if not ActionMatcher.is_drive_rush_action_id(previous.event.id)
        or not ActionMatcher.is_drive_rush_action_id(current.event.id)
        or not ActionMatcher.is_drive_rush_motion(previous.motion)
        or current.event.has_contact == true
        or current.event.has_hit == true then
        return false
    end
    local delay = (tonumber(current.event.frame) or 0)
        - (tonumber(previous.event.frame) or 0)
    return delay >= 0 and delay <= Compiler.BIND_WINDOW
end

-- A mapped attack can change to an unmapped execution/contact state while a
-- direction buffer is already being entered for the next command. The owner
-- Action may not yet contain the hit: Marisa 686 -> 684 and 902 -> 907 expose
-- their contact only on the second state. With no attack button on that anchor,
-- and with the anchor having started during the mapped owner, the direction did
-- not cause the contact Action. Merge the observed truth into the owner instead
-- of drawing a fabricated directional instruction.
local function is_unmapped_contact_continuation(previous, current)
    if type(previous) ~= "table" or type(current) ~= "table"
        or type(previous.event) ~= "table"
        or type(current.event) ~= "table" then
        return false
    end
    local anchor = type(current.event.anchor) == "table"
        and current.event.anchor or {}
    if previous.motion == nil
        or current.motion ~= nil
        or current.resolution_status ~= "action_id_missing"
        or event_button_mask(current.event) ~= 0
        or (anchor.kind ~= "double_tap"
            and anchor.kind ~= "direction_action"
            and anchor.kind ~= "movement_action")
        or (current.event.has_contact ~= true
            and current.event.has_hit ~= true) then
        return false
    end
    local delay = (tonumber(current.event.frame) or 0)
        - (tonumber(previous.event.frame) or 0)
    if delay < 0 or delay > Compiler.BIND_WINDOW then return false end
    if previous.event.has_contact == true or previous.event.has_hit == true then
        return true
    end
    return tonumber(anchor.initial_action_id) == tonumber(previous.event.id)
end

local function is_character_transient_input_precursor(previous, current, rules)
    if type(previous) ~= "table" or type(current) ~= "table"
        or type(previous.event) ~= "table"
        or type(current.event) ~= "table"
        or previous.event.has_contact == true
        or previous.event.has_hit == true then
        return false
    end
    local transitions = type(rules) == "table"
        and rules.transient_input_precursor_transitions or nil
    local destinations = type(transitions) == "table"
        and transitions[tonumber(previous.event.id)] or nil
    if type(destinations) ~= "table"
        or destinations[tonumber(current.event.id)] ~= true then
        return false
    end
    local delay = (tonumber(current.event.frame) or 0)
        - (tonumber(previous.event.frame) or 0)
    return delay >= 0 and delay <= Compiler.UNMAPPED_PRECURSOR_WINDOW
end

local function resolve_motion(resolver, event, session)
    if type(resolver) ~= "function" then return nil, nil end
    local ok, value, status, metadata = pcall(resolver, event.id, event, session)
    if not ok then return nil, "resolver_error" end
    return type(value) == "string" and value ~= "" and value or nil,
        status, type(metadata) == "table" and metadata or nil
end

local function promote_unmapped_event(
    event,
    next_event_frame,
    observed_actions,
    resolver,
    session
)
    if type(event.anchor) == "table" and event.anchor.kind == "button_release" then
        return nil
    end
    local event_frame = tonumber(event and event.frame) or 0
    local latest_frame = event_frame + Compiler.PROMOTION_WINDOW
    if tonumber(next_event_frame) ~= nil then
        latest_frame = math.min(latest_frame, tonumber(next_event_frame) - 1)
    end
    if latest_frame <= event_frame then return nil end

    for _, observed in ipairs(type(observed_actions) == "table" and observed_actions or {}) do
        local observed_frame = tonumber(observed and observed.frame)
        local observed_id = tonumber(observed and observed.id)
        if observed_frame and observed_id
            and observed_frame > event_frame
            and observed_frame <= latest_frame
            and observed_id ~= tonumber(event.id) then
            local candidate = shallow_copy(event)
            candidate.promoted_from_id = event.id
            candidate.promoted_from_frame = event.frame
            candidate.id = observed_id
            candidate.frame = observed_frame
            candidate.action_frame = tonumber(observed.action_frame) or 0
            candidate.bind_reason = "unmapped_precursor_promoted_to_observed_action"
            local motion, status, metadata = resolve_motion(resolver, candidate, session)
            if motion ~= nil and status ~= "suppress_transition" then
                return candidate, motion, status, metadata
            end
        end
    end
    return nil
end

-- A direction-only Action can briefly own the runtime slot when an attack
-- button is pressed, even though that button actually launches a different
-- durable Action a few frames later. A genuine direction command is captured
-- from its direction edge; a direction-only route bound to an attack press is
-- therefore an unexplained precursor and may follow that same input to the
-- first strictly resolved runtime Action.
local function promote_unverified_direction_precursor(
    event,
    next_event_frame,
    observed_actions,
    resolver,
    session,
    motion,
    resolution_status
)
    local anchor = type(event) == "table" and type(event.anchor) == "table"
        and event.anchor or {}
    if resolution_status ~= "route_unverified"
        or anchor.kind ~= "button_press"
        or event_button_mask(event) == 0
        or not is_direction_only_motion(motion) then
        return nil
    end

    local event_frame = tonumber(event.frame) or 0
    for _, observed in ipairs(type(observed_actions) == "table" and observed_actions or {}) do
        local observed_frame = tonumber(observed and observed.frame)
        local observed_id = tonumber(observed and observed.id)
        local delay = observed_frame and (observed_frame - event_frame) or nil
        if delay and delay > 0 and delay < Compiler.GHOST_FILTER_FRAMES
            and (tonumber(next_event_frame) == nil
                or observed_frame < tonumber(next_event_frame))
            and observed_id ~= nil
            and observed_id ~= tonumber(event.id) then
            local candidate = shallow_copy(event)
            candidate.promoted_from_id = event.id
            candidate.promoted_from_frame = event.frame
            candidate.id = observed_id
            candidate.frame = observed_frame
            candidate.action_frame = tonumber(observed.action_frame) or 0
            candidate.bind_reason =
                "unverified_direction_precursor_promoted_to_observed_action"
            local candidate_motion, candidate_status, candidate_metadata =
                resolve_motion(resolver, candidate, session)
            if candidate_motion ~= nil
                and candidate_status ~= "route_unverified"
                and candidate_status ~= "suppress_transition"
                and candidate_status ~= "resolver_error" then
                return candidate, candidate_motion, candidate_status,
                    candidate_metadata
            end
        end
    end
    return nil
end

-- Type-20 relations can expose both the BCM owner Action and a short internal
-- execution phase for one physical command. Keep a phase when it appears on
-- its own, but collapse it when its declared owner was just recorded with the
-- same command and neither Action produced contact.
local function is_redundant_inherited_action_phase(previous, current)
    if type(previous) ~= "table" or type(current) ~= "table" then return false end
    local previous_event = previous.event
    local current_event = current.event
    local metadata = current.resolution_metadata
    if type(previous_event) ~= "table" or type(current_event) ~= "table"
        or type(metadata) ~= "table"
        or metadata.ownership ~= "type20_action_phase"
        or tonumber(metadata.inherited_from_action_id) ~= tonumber(previous_event.id) then
        return false
    end
    if previous_event.has_contact == true or previous_event.has_hit == true
        or current_event.has_contact == true or current_event.has_hit == true then
        return false
    end
    local delay = (tonumber(current_event.frame) or 0)
        - (tonumber(previous_event.frame) or 0)
    return delay >= 0 and delay <= 4
        and compact_motion(previous.motion) ~= ""
        and compact_motion(previous.motion) == compact_motion(current.motion)
end

-- Direction jitter can complete another double-tap pair one frame after a
-- dash Action starts. The game does not restart the dash and the training UI
-- cannot consume a second dash so soon, so that synthetic event must never
-- become a separate step.
local function is_redundant_dash_transition(previous, current)
    if type(previous) ~= "table" or type(current) ~= "table"
        or type(previous.event) ~= "table" or type(current.event) ~= "table" then
        return false
    end
    local previous_id = tonumber(previous.event.id)
    local current_id = tonumber(current.event.id)
    if previous_id == nil or current_id ~= previous_id
        or not DASH_ACTIONS[current_id]
        or current.event.has_contact == true
        or current.event.has_hit == true then
        return false
    end
    local anchor = type(current.event.anchor) == "table"
        and current.event.anchor or {}
    if anchor.kind ~= "double_tap" then return false end
    local delay = (tonumber(current.event.frame) or 0)
        - (tonumber(previous.event.frame) or 0)
    return delay > 0 and delay <= Compiler.GHOST_FILTER_FRAMES
end

-- Character JSON may declare a current Action as a non-command tail after an
-- exact predecessor. The compiler owns the generic timing/contact semantics;
-- JSON owns only the Action identities and configured window.
local function is_mapped_suppressed_transition(previous, current, rules)
    if type(previous) ~= "table" or type(current) ~= "table"
        or type(previous.event) ~= "table" or type(current.event) ~= "table" then
        return false
    end
    local suppressions = type(rules) == "table" and rules.suppress_after or nil
    local rule = type(suppressions) == "table"
        and suppressions[tonumber(current.event.id)] or nil
    if type(rule) ~= "table" or type(rule.previous_ids) ~= "table"
        or rule.previous_ids[tonumber(previous.event.id)] ~= true then
        return false
    end
    local anchor = type(current.event.anchor) == "table"
        and current.event.anchor or {}
    if anchor.kind ~= rule.anchor_kind then return false end
    if rule.require_no_contact == true
        and (current.event.has_contact == true or current.event.has_hit == true) then
        return false
    end
    local delay = (tonumber(current.event.frame) or 0)
        - (tonumber(previous.event.frame) or 0)
    return delay > 0 and delay <= (tonumber(rule.max_delay_frames) or 0)
end

-- The live validator debounces a short non-contact Action that starts on a
-- release edge and is replaced by the next deliberate button Action. Apply
-- the same rule during transcription so a self-consistent compiler replay
-- cannot emit a step that the training UI will always classify as Ghost.
local function is_release_ghost_precursor(previous, current)
    if type(previous) ~= "table" or type(current) ~= "table"
        or type(previous.event) ~= "table" or type(current.event) ~= "table" then
        return false
    end
    local previous_anchor = type(previous.event.anchor) == "table"
        and previous.event.anchor or {}
    local current_anchor = type(current.event.anchor) == "table"
        and current.event.anchor or {}
    if previous_anchor.kind ~= "button_release"
        or current_anchor.kind ~= "button_press"
        or previous.resolution_status ~= "route_unverified"
        or previous.event.has_contact == true
        or previous.event.has_hit == true
        or event_button_mask(current.event) == 0 then
        return false
    end
    local delay = (tonumber(current.event.frame) or 0)
        - (tonumber(previous.event.frame) or 0)
    return delay > 0 and delay < Compiler.GHOST_FILTER_FRAMES
end

-- The durable Action may already have its own source event. In that case the
-- promotion pass deliberately stops before it, and projection collapses the
-- unexplained direction-only button phase into that following strict Action.
local function is_unverified_direction_button_precursor(previous, current)
    if type(previous) ~= "table" or type(current) ~= "table"
        or type(previous.event) ~= "table" or type(current.event) ~= "table" then
        return false
    end
    local anchor = type(previous.event.anchor) == "table"
        and previous.event.anchor or {}
    if previous.resolution_status ~= "route_unverified"
        or anchor.kind ~= "button_press"
        or event_button_mask(previous.event) == 0
        or not is_direction_only_motion(previous.motion)
        or current.motion == nil
        or current.resolution_status == "route_unverified"
        or current.resolution_status == "suppress_transition"
        or current.resolution_status == "resolver_error" then
        return false
    end
    local delay = (tonumber(current.event.frame) or 0)
        - (tonumber(previous.event.frame) or 0)
    return delay > 0 and delay < Compiler.GHOST_FILTER_FRAMES
end

local function is_underspecified_catalog_motion(motion)
    local compact = compact_motion(motion)
    return compact == "NORMAL" or compact:match("^[1-9]$") ~= nil
end

-- Some character command tables identify a follow-up Action but only describe
-- it as "Normal" or a direction. When it immediately follows a non-contact
-- setup Action, the physical button edge is the missing player-visible fact.
local function derive_contextual_followup_motion(previous, current)
    if type(previous) ~= "table" or type(current) ~= "table"
        or type(previous.event) ~= "table" or type(current.event) ~= "table"
        or not is_underspecified_catalog_motion(current.motion)
        or previous.motion == nil or is_underspecified_catalog_motion(previous.motion)
        or previous.event.has_contact == true or previous.event.has_hit == true then
        return nil
    end
    local delay = (tonumber(current.event.frame) or 0)
        - (tonumber(previous.event.frame) or 0)
    if delay < 0 or delay > Compiler.PLAYER_FOLLOWUP_INPUT_WINDOW then return nil end
    local buttons = button_notation(event_button_mask(current.event))
    if buttons == "" then return nil end
    return ">" .. buttons
end

local function next_promotion_boundary(
    source_events,
    event_index,
    resolver,
    session
)
    for index = event_index + 1, #source_events do
        local event = source_events[index]
        local anchor = type(event.anchor) == "table" and event.anchor or {}
        local motion, status = resolve_motion(resolver, event, session)
        local suppressible_release = anchor.kind == "button_release"
            and (motion == nil or status == "suppress_transition")
        if not suppressible_release then return event.frame end
    end
    return nil
end

local function observe_dash_anchor(session, sample, direction, direction_changed)
    if not direction_changed or (direction ~= "6" and direction ~= "4") then return nil end
    local frame = tonumber(sample.frame) or 0
    local tap = session.last_direction_tap[direction]
    session.last_direction_tap[direction] = frame
    if tap and frame > tap and frame - tap <= Compiler.DASH_TAP_WINDOW then
        session.last_direction_tap[direction] = nil
        return snapshot_anchor(session, sample, "double_tap", 0, 0)
    end
    return nil
end

function Compiler.new(options)
    options = type(options) == "table" and options or {}
    return {
        character = options.character or "Unknown",
        control_mode = options.control_mode or "classic",
        source = options.source or "recording",
        action_event_projection_rules =
            type(options.action_event_projection_rules) == "table"
                and options.action_event_projection_rules or {},
        action_event_rules = type(options.action_event_rules) == "table"
                and options.action_event_rules or {},
        created_frame = tonumber(options.frame) or 0,
        previous_input = 0,
        previous_direction = "5",
        previous_action_id = nil,
        previous_action_frame = nil,
        previous_combo = 0,
        previous_victim_hp = nil,
        recording_contact_state = {},
        started = false,
        input_started = false,
        started_frame = nil,
        input_anchor_count = 0,
        unresolved_anchor_count = 0,
        expired_internal_continuation_count = 0,
        expired_quick_successor_continuation_count = 0,
        expired_meter_raw_dr_count = 0,
        pending_anchor = nil,
        pending_meter_confirmed_raw_dr = nil,
        recent_direction_anchor = nil,
        button_press_frames = {},
        last_direction_tap = {},
        direction_history = {},
        observed_actions = {},
        events = {},
        event_projection_owners = {},
        current_event = nil,
        max_combo = 0,
        hit_contacts = 0,
        block_contacts = 0,
        current_damage = 0,
        cumulative_damage = 0,
        confirmed_damage = 0,
        passive_damage_ticks = 0,
        passive_damage_total = 0,
        passive_damage_max_tick = 0,
        passive_damage_frames = {},
        passive_damage_samples = {},
        combo_reset_frames = {},
        previous_damage_hp = nil,
        initial_victim_hp = nil,
        min_victim_hp = nil,
        initial_actor_drive = nil,
        min_actor_drive = nil,
        initial_actor_super = nil,
        min_actor_super = nil,
        first_sample = nil,
        last_sample = nil,
        last_activity_frame = tonumber(options.frame) or 0,
    }
end

function Compiler.observe(session, sample)
    if type(session) ~= "table" or type(sample) ~= "table" then return false end
    local frame = tonumber(sample.frame) or 0
    local input = tonumber(sample.direct_input) or 0
    local buttons = input & Compiler.BUTTON_MASK
    local previous_buttons = (tonumber(session.previous_input) or 0) & Compiler.BUTTON_MASK
    local pressed = buttons & (~previous_buttons) & Compiler.BUTTON_MASK
    local released = previous_buttons & (~buttons) & Compiler.BUTTON_MASK
    local direction = relative_direction(input, sample.facing_right)
    local direction_changed = direction ~= session.previous_direction
    local release_hold_frames =
        update_button_hold_state(session, frame, pressed, released)

    sample.frame = frame
    session.first_sample = session.first_sample or shallow_copy(sample)
    session.last_sample = shallow_copy(sample)

    if direction_changed then
        session.direction_history[#session.direction_history + 1] = {
            frame = frame,
            direction = direction,
        }
        trim_direction_history(session, frame)
        if pressed == 0 and released == 0
            and direction ~= "5" and direction ~= "*" then
            -- Direction-only Actions can become visible a few engine frames
            -- after the physical edge. Keep a non-blocking candidate separate
            -- from button/dash anchors: unused direction changes are ordinary
            -- motion input and must not count as unresolved commands.
            session.recent_direction_anchor = build_anchor(
                session,
                sample,
                "direction_action",
                0,
                0
            )
        end
    end

    update_damage(session, sample)
    update_actor_resources(session, sample, pressed ~= 0 or released ~= 0)
    -- Resolve a delayed one-bar spend before observing this frame's new input
    -- edge. If the cost first becomes visible on the following attack frame,
    -- Action 740 is inserted at its original transition frame and the attack's
    -- physical anchor remains available for its own Action.
    confirm_pending_meter_raw_drive_rush(session, sample)

    local anchor
    if pressed ~= 0 or released ~= 0 then
        if released ~= 0 and type(session.current_event) == "table"
            and (event_button_mask(session.current_event) & released) ~= 0 then
            session.current_event.hold_frames = math.max(
                tonumber(session.current_event.hold_frames) or 0,
                release_hold_frames
            )
        end
        local pending_press = type(session.pending_anchor) == "table"
            and session.pending_anchor or nil
        local pending_buttons = pending_press
            and ((tonumber(pending_press.pressed_buttons) or 0)
                & Compiler.BUTTON_MASK) or 0
        local release_completes_pending_press = pressed == 0
            and released ~= 0
            and pending_press ~= nil
            and pending_press.kind == "button_press"
            and (pending_buttons & released) ~= 0
        if release_completes_pending_press then
            -- A buffered/cancel Action can become visible only after the player
            -- has already released the triggering button. Retain the press as
            -- the command truth; replacing it with the release prevents later
            -- internal phases from being promoted to the durable Action.
            pending_press.hold_frames = math.max(
                tonumber(pending_press.hold_frames) or 0,
                release_hold_frames
            )
            pending_press.release_frame = frame
            anchor = pending_press
        else
            anchor = snapshot_anchor(
                session,
                sample,
                pressed ~= 0 and "button_press" or "button_release",
                pressed,
                released,
                released ~= 0 and release_hold_frames or nil
            )
        end
    elseif ActionMatcher.should_observe_dash_direction_edge(pressed, released) then
        anchor = observe_dash_anchor(session, sample, direction, direction_changed)
    end

    local action_id = tonumber(sample.action_id)
    local action_frame = tonumber(sample.action_frame) or 0
    local action_changed = session.previous_action_id ~= nil
        and action_id ~= session.previous_action_id
    local action_restarted = session.previous_action_id ~= nil
        and action_id == session.previous_action_id
        and session.previous_action_frame ~= nil
        and action_frame < session.previous_action_frame
    local actual_action_start = action_changed or action_restarted
    if actual_action_start
        and (session.input_started or (MOVEMENT_ACTIONS[action_id] and direction ~= "5")) then
        session.observed_actions[#session.observed_actions + 1] = {
            id = action_id,
            frame = frame,
            action_frame = action_frame,
            reason = action_restarted and "action_frame_rewind" or "action_id_changed",
        }
        session.last_activity_frame = frame
    end

    local action_start_absorbed = false

    -- A neutral Drive Rush briefly exposes the Drive Parry input Action before
    -- switching to RAW DR. When that switch happens immediately, it is one
    -- player command and the later Action ID is the durable truth. A held
    -- parry followed by a later rush remains two commands.
    if actual_action_start
        and type(session.current_event) == "table"
        and ActionMatcher.is_drive_parry_action_id(session.current_event.id)
        and ActionMatcher.is_raw_drive_rush_action_id(action_id)
        and frame - (tonumber(session.current_event.frame) or frame) <= 4
        and session.current_event.has_contact ~= true then
        session.current_event.promoted_from_id = session.current_event.id
        session.current_event.id = action_id
        session.current_event.action_frame = action_frame
        session.current_event.bind_reason = "quick_drive_parry_promoted_to_raw_dr"
        session.pending_anchor = nil
        action_start_absorbed = true
    end

    -- A few raw Drive Rush recordings expose PARRY long enough to miss the
    -- immediate four-frame precursor fold, yet do not provide another physical
    -- edge for RAW DR to bind. A real local one-bar Drive spend is independent
    -- runtime proof that this later Action is a separate rush, while a held or
    -- re-pressed parry phase without the cost remains ignored.
    if actual_action_start
        and not action_start_absorbed
        and session.pending_anchor == nil
        and type(session.current_event) == "table"
        and ActionMatcher.is_drive_parry_action_id(session.current_event.id)
        and ActionMatcher.is_raw_drive_rush_action_id(action_id)
        and frame - (tonumber(session.current_event.frame) or frame) > 4
        and frame - (tonumber(session.current_event.frame) or frame)
            <= Compiler.RAW_DRIVE_RUSH_EVIDENCE_WINDOW
        and session.current_event.has_contact ~= true then
        local parry_drive = tonumber(session.current_event.actor_drive)
        local current_drive = rounded(sample.actor_drive)
        local local_drive_cost = parry_drive ~= nil and current_drive ~= nil
            and math.max(0, parry_drive - current_drive) or 0
        local rush_anchor = raw_drive_rush_transition_anchor(
            session.current_event,
            sample,
            input
        )
        if local_drive_cost >= Compiler.RAW_DRIVE_RUSH_MIN_LOCAL_COST then
            add_event(
                session,
                sample,
                rush_anchor,
                "drive_cost_confirmed_raw_dr_transition"
            )
            action_start_absorbed = true
        elseif parry_drive ~= nil and current_drive ~= nil then
            session.pending_meter_confirmed_raw_dr = {
                frame = frame,
                baseline_drive = parry_drive,
                sample = shallow_copy(sample),
                anchor = rush_anchor,
            }
            action_start_absorbed = true
        end
    end

    local pending = session.pending_anchor
    local pending_bind_window = pending
        and pending.is_quick_successor_continuation == true
        and math.max(1, tonumber(pending.max_delay_frames) or 1)
        or Compiler.BIND_WINDOW
    if pending and frame - pending.frame > pending_bind_window then
        -- Every ordinary button release is still captured because negative-edge
        -- actions can bind to it. An unbound release is not itself evidence that
        -- transcription failed.
        if pending.is_internal_phase_continuation == true then
            session.expired_internal_continuation_count =
                (tonumber(session.expired_internal_continuation_count) or 0) + 1
        elseif pending.is_quick_successor_continuation == true then
            session.expired_quick_successor_continuation_count =
                (tonumber(session.expired_quick_successor_continuation_count) or 0)
                    + 1
        elseif pending.kind ~= "button_release"
            and pending.is_movement_continuation ~= true then
            session.unresolved_anchor_count = session.unresolved_anchor_count + 1
        end
        session.pending_anchor = nil
        pending = nil
    end

    local action_bound = false
    if pending and action_is_recordable(action_id) then
        local pending_age = frame - (tonumber(pending.frame) or frame)
        local stale_release_low_action = pending.kind == "button_release"
            and action_id <= 50
            and pending_age > Compiler.RELEASE_LOW_ACTION_BIND_WINDOW
        local changed_after_anchor = pending.initial_action_id ~= nil
            and action_id ~= pending.initial_action_id
        local restarted_after_anchor = action_restarted and frame >= pending.frame
        local dash_already_active = pending.kind == "double_tap"
            and DASH_ACTIONS[action_id] == true
        local continuation_target_allowed = true
        if pending.is_internal_phase_continuation == true then
            local target_rule = action_event_projection_rule(session, action_id)
            if type(target_rule) == "table"
                and target_rule.kind == "internal_phase" then
                continuation_target_allowed =
                    tonumber(target_rule.owner_id)
                        == tonumber(pending.internal_phase_owner_id)
            else
                -- Common locomotion/system Actions must never steal an attack
                -- edge that an internal phase temporarily consumed.
                continuation_target_allowed = action_id > 50
            end
        elseif pending.is_quick_successor_continuation == true then
            continuation_target_allowed = action_id > 50
                and action_id ~= tonumber(pending.quick_successor_source_id)
        end
        if not stale_release_low_action
            and continuation_target_allowed
            and (actual_action_start or changed_after_anchor
                or restarted_after_anchor or dash_already_active) then
            local bound_anchor = pending
            local bound_event = add_event(
                session,
                sample,
                bound_anchor,
                pending.is_quick_successor_continuation == true
                    and "quick_successor_action_changed"
                    or (action_restarted and "action_frame_rewind"
                        or (dash_already_active and "double_tap_action" or "action_id_changed"))
            )
            action_bound = bound_event ~= nil
            -- A jump direction + attack can first expose the jump Action, then
            -- the airborne normal one frame later. A direction edge or button
            -- release may replace the original press anchor before the jump
            -- Action appears, so retain any attack button carried by the jump
            -- anchor rather than requiring its kind to remain button_press.
            if bound_event
                and JUMP_ACTIONS[action_id] == true
                and event_button_mask(bound_event) ~= 0 then
                local continuation = shallow_copy(bound_anchor)
                continuation.initial_action_id = action_id
                continuation.initial_action_frame = action_frame
                continuation.is_movement_continuation = true
                session.pending_anchor = continuation
            end
        end
    end

    if not action_bound and actual_action_start
        and MOVEMENT_ACTIONS[action_id] and direction ~= "5" then
        local movement_anchor = anchor or snapshot_anchor(session, sample, "movement_action", 0, 0)
        add_event(session, sample, movement_anchor, "movement_action_started")
        action_bound = true
    end

    local direction_anchor = session.recent_direction_anchor
    local direction_anchor_age = type(direction_anchor) == "table"
        and (frame - (tonumber(direction_anchor.frame) or frame)) or nil
    if not action_bound
        and actual_action_start
        and not action_start_absorbed
        and direction_anchor_age ~= nil
        and direction_anchor_age >= 0
        and direction_anchor_age <= Compiler.DIRECTION_ACTION_BIND_WINDOW
        and not ActionMatcher.is_raw_drive_rush_action_id(action_id)
        and JUMP_STARTUP_TRANSITIONS[action_id] == nil
        and action_is_recordable(action_id) then
        -- Some character mechanics are completed by direction alone (for
        -- example a high-jump cancel). They have no attack-button or dash
        -- anchor, but a recent pure direction edge plus real Action start is
        -- still direct input truth and must become a visible V2 step.
        session.input_anchor_count = session.input_anchor_count + 1
        session.input_started = true
        add_event(session, sample, direction_anchor, "direction_action_started")
    end

    local current = session.current_event
    local combo = math.max(0, tonumber(sample.combo_count) or 0)
    session.max_combo = math.max(session.max_combo or 0, combo)
    local victim_hp = rounded(sample.victim_hp)
    local contact_truth = ActionRestartDetector.observe_recording_contacts(
        session.recording_contact_state,
        {
            frame = frame,
            current_combo = combo,
            previous_combo = session.previous_combo,
            current_hp = victim_hp,
            previous_hp = session.previous_victim_hp,
            damage_type = sample.victim_damage_type,
            hit_stop = sample.victim_hit_stop,
            contact_candidate = current ~= nil and current.has_hit ~= true,
            action_owned_hp_decrease = current ~= nil
                and current.has_hit ~= true
                and tonumber(current.id) == action_id,
        }
    )
    local hit_contact = contact_truth.hit_contact
    local hit_confirmed = hit_contact.accepted == true
    local block_active = contact_truth.block_contact.active == true
    local block_started = contact_truth.block_contact.started == true
    local block_damage_confirmed = contact_truth.block_damage_confirmed == true
    local hit_damage_confirmed = contact_truth.hit_damage_confirmed == true
    for _, passive_sample in ipairs(
        type(contact_truth.passive_damage_samples) == "table"
            and contact_truth.passive_damage_samples or {}
    ) do
        record_passive_damage(session, passive_sample)
    end
    if hit_confirmed or hit_damage_confirmed or block_damage_confirmed then
        session.confirmed_damage = math.max(
            tonumber(session.confirmed_damage) or 0,
            tonumber(session.current_damage) or 0
        )
    end

    if current then
        if hit_confirmed then
            current.first_contact_frame = current.first_contact_frame or frame
            current.has_hit = true
            current.has_contact = true
            current.expected_combo = math.max(current.expected_combo or 0, combo)
            current.damage_at_step = math.max(
                current.damage_at_step or 0,
                session.confirmed_damage or 0
            )
            session.hit_contacts = session.hit_contacts + 1
            session.last_activity_frame = frame
        elseif combo > 0 and current.has_hit then
            current.expected_combo = math.max(current.expected_combo or 0, combo)
        end
        if block_damage_confirmed then
            current.damage_at_step = math.max(
                current.damage_at_step or 0,
                session.confirmed_damage or 0
            )
        end
        if hit_damage_confirmed then
            current.damage_at_step = math.max(
                current.damage_at_step or 0,
                session.confirmed_damage or 0
            )
        end
        if block_started and current.was_blocked ~= true then
            current.has_contact = true
            current.was_blocked = true
            session.block_contacts = session.block_contacts + 1
            session.last_activity_frame = frame
        elseif block_started then
            session.last_activity_frame = frame
        end
    end

    if (tonumber(session.previous_combo) or 0) > 0 and combo == 0 then
        session.combo_reset_frames = type(session.combo_reset_frames) == "table"
            and session.combo_reset_frames or {}
        session.combo_reset_frames[#session.combo_reset_frames + 1] = frame
    end
    session.previous_input = input
    session.previous_direction = direction
    session.previous_action_id = action_id
    session.previous_action_frame = action_frame
    session.previous_combo = combo
    session.previous_victim_hp = victim_hp
    return true
end

function Compiler.finalize(session, options)
    options = type(options) == "table" and options or {}
    if type(session) == "table" and options.flush_recording_contacts ~= false then
        for _, passive_sample in ipairs(
            ActionRestartDetector.flush_recording_contact_state(
                session.recording_contact_state
            )
        ) do
            record_passive_damage(session, passive_sample)
        end
    end
    local resolver = options.motion_resolver
    local steps = {}
    local projected = {}
    local suppressed_events = {}
    local promoted_events = {}
    local resolved_motion_actions = 0
    local fallback_motion_actions = 0
    local input_derived_motion_actions = 0
    local input_derived_noncontact_motion_actions = 0
    local input_refined_motion_actions = 0
    local unresolved_motion_actions = 0
    local resolver_error_actions = 0
    local cumulative_damage = 0
    local unresolved_anchors = type(session) == "table"
        and (session.unresolved_anchor_count or 0) or 0
    if type(session) == "table" and type(session.pending_anchor) == "table"
        and session.pending_anchor.kind ~= "button_release"
        and session.pending_anchor.is_internal_phase_continuation ~= true
        and session.pending_anchor.is_quick_successor_continuation ~= true then
        unresolved_anchors = unresolved_anchors + 1
    end

    local source_events = type(session) == "table" and session.events or {}
    for event_index, source_event in ipairs(source_events) do
        local event = project_character_action_owner(
            source_event,
            session
        )
        local previous_before_projection = projected[#projected]
        local character_rule_fold =
            character_rule_fold_reason(
                previous_before_projection,
                source_event,
                session
            )
        local motion, resolution_status, resolution_metadata
        if not character_rule_fold then
            motion, resolution_status, resolution_metadata =
                resolve_motion(resolver, event, session)
        end
        if not character_rule_fold
            and type(resolver) == "function"
            and resolution_status == "route_unverified" then
            local promoted, promoted_motion, promoted_status, promoted_metadata =
                promote_unverified_direction_precursor(
                    event,
                    next_promotion_boundary(
                        source_events,
                        event_index,
                        resolver,
                        session
                    ),
                    session.observed_actions,
                    resolver,
                    session,
                    motion,
                    resolution_status
                )
            if promoted then
                event = promoted
                motion = promoted_motion
                resolution_status = promoted_status
                resolution_metadata = promoted_metadata
                promoted_events[#promoted_events + 1] = {
                    from_id = source_event.id,
                    from_frame = source_event.frame,
                    to_id = event.id,
                    to_frame = event.frame,
                    motion = motion,
                    reason = event.bind_reason,
                }
            end
        end
        if not character_rule_fold
            and type(resolver) == "function"
            and motion == nil
            and resolution_status ~= "resolver_error"
            and resolution_status ~= "suppress_transition" then
            local promoted, promoted_motion, promoted_status, promoted_metadata =
                promote_unmapped_event(
                    event,
                    next_promotion_boundary(
                        source_events,
                        event_index,
                        resolver,
                        session
                    ),
                    session.observed_actions,
                    resolver,
                    session
                )
            if promoted then
                event = promoted
                motion = promoted_motion
                resolution_status = promoted_status
                resolution_metadata = promoted_metadata
                promoted_events[#promoted_events + 1] = {
                    from_id = source_event.id,
                    from_frame = source_event.frame,
                    to_id = event.id,
                    to_frame = event.frame,
                    motion = motion,
                    reason = event.bind_reason,
                }
            end
        end

        local previous = projected[#projected]
        local release_transition = type(event.anchor) == "table"
            and event.anchor.kind == "button_release"
            and previous ~= nil
            and (resolution_status == "suppress_transition" or motion == nil)
        if character_rule_fold then
            -- Character phase rules merge only combat outcome. The child
            -- Action's coincident input/release and hold classification do not
            -- belong to the command owner.
            merge_event_outcome_truth(previous.event, event)
            suppressed_events[#suppressed_events + 1] = {
                id = source_event.id,
                frame = event.frame,
                merged_into = previous.event.id,
                reason = character_rule_fold,
            }
            goto continue_projection
        end
        if resolution_status == "suppress_transition" or release_transition then
            if previous then merge_event_outcome_truth(previous.event, event) end
            suppressed_events[#suppressed_events + 1] = {
                id = event.id,
                frame = event.frame,
                merged_into = previous and previous.event.id or nil,
                reason = resolution_status == "suppress_transition"
                    and "command_map_suppressed_transition"
                    or "unmapped_button_release_transition",
            }
        else
            local current = {
                event = event,
                motion = motion,
                resolution_status = resolution_status,
                resolution_metadata = resolution_metadata,
            }
            previous = projected[#projected]
            local redundant_drive_rush =
                is_redundant_drive_rush_phase(previous, current)
            local contact_continuation =
                is_unmapped_contact_continuation(previous, current)
            if redundant_drive_rush or contact_continuation then
                merge_event_outcome_truth(previous.event, event)
                suppressed_events[#suppressed_events + 1] = {
                    id = event.id,
                    frame = event.frame,
                    merged_into = previous.event.id,
                    reason = redundant_drive_rush
                            and "redundant_drive_rush_phase"
                        or "unmapped_contact_continuation",
                }
                goto continue_projection
            end
            local unmapped_direction =
                is_unmapped_direction_transition(current)
            if unmapped_direction then
                suppressed_events[#suppressed_events + 1] = {
                    id = event.id,
                    frame = event.frame,
                    reason = "unmapped_direction_transition",
                }
                goto continue_projection
            end
            previous = projected[#projected]
            local release_ghost =
                is_release_ghost_precursor(previous, current)
            if release_ghost then
                projected[#projected] = nil
                suppressed_events[#suppressed_events + 1] = {
                    id = previous.event.id,
                    frame = previous.event.frame,
                    merged_into = event.id,
                    reason = "ghost_release_transition",
                }
                previous = projected[#projected]
            end
            local redundant_action_phase =
                is_redundant_inherited_action_phase(previous, current)
            local redundant_dash =
                is_redundant_dash_transition(previous, current)
            local mapped_suppression = is_mapped_suppressed_transition(
                previous,
                current,
                session_action_event_rules(session)
            )
            local quick_drive_parry =
                is_quick_drive_parry_precursor(previous, current)
            local jump_startup = is_jump_startup_precursor(previous, current)
            local unmapped_input = is_unmapped_input_precursor(previous, current)
            local unverified_direction =
                is_unverified_direction_button_precursor(previous, current)
            local transient_input =
                is_character_transient_input_precursor(
                    previous,
                    current,
                    session_action_event_rules(session)
                )
            if redundant_action_phase or redundant_dash or mapped_suppression then
                merge_event_outcome_truth(previous.event, event)
                suppressed_events[#suppressed_events + 1] = {
                    id = event.id,
                    frame = event.frame,
                    merged_into = previous.event.id,
                    reason = redundant_dash
                            and "redundant_dash_transition"
                        or (mapped_suppression and "character_action_event_suppression"
                            or "redundant_inherited_action_phase"),
                }
            else
                if quick_drive_parry or jump_startup or unmapped_input
                    or unverified_direction or transient_input then
                    if jump_startup then
                        -- The hit can be sampled on the short BGN phase before
                        -- the durable jump Action appears. Preserve that truth
                        -- on the command-owning jump instead of retaining an
                        -- unresolved startup instruction.
                        merge_event_truth(current.event, previous.event)
                    end
                    projected[#projected] = nil
                    suppressed_events[#suppressed_events + 1] = {
                        id = previous.event.id,
                        frame = previous.event.frame,
                        merged_into = event.id,
                        reason = quick_drive_parry
                                and "quick_drive_parry_raw_dr_precursor"
                            or (jump_startup and "jump_startup_transition"
                                or (unmapped_input and "unmapped_input_precursor"
                                    or (transient_input
                                        and "character_transient_input_precursor"
                                        or "unverified_direction_button_precursor"))),
                    }
                end
                projected[#projected + 1] = current
            end
        end
        ::continue_projection::
    end

    local previous_event = nil
    local previous_resolved = nil
    local projected_events = {}
    for index, resolved in ipairs(projected) do
        local event = resolved.event
        cumulative_damage = math.max(cumulative_damage, tonumber(event.damage_at_step) or 0)
        local motion = resolved.motion
        local refined_motion =
            derive_contextual_followup_motion(previous_resolved, resolved)
        if refined_motion ~= nil then
            motion = refined_motion
            resolved.motion = refined_motion
            resolved.resolution_status = "input_derived_followup"
            input_refined_motion_actions = input_refined_motion_actions + 1
        end
        if motion then
            resolved_motion_actions = resolved_motion_actions + 1
        else
            fallback_motion_actions = fallback_motion_actions + 1
            if resolved.resolution_status == "resolver_error" then
                resolver_error_actions = resolver_error_actions + 1
            end
            if resolved.resolution_status ~= "resolver_error"
                and event_button_mask(event) ~= 0
                and ((event.has_contact == true or event.has_hit == true)
                    or (type(event.anchor) == "table"
                        and event.anchor.kind == "button_press")) then
                -- The Action ID and contact are runtime facts. A missing
                -- command-catalog row only makes the display notation input-
                -- derived. A physical button press is also sufficient truth
                -- for a whiff or setup Action that intentionally has no
                -- contact.
                input_derived_motion_actions =
                    input_derived_motion_actions + 1
                if event.has_contact ~= true and event.has_hit ~= true then
                    input_derived_noncontact_motion_actions =
                        input_derived_noncontact_motion_actions + 1
                end
            else
                unresolved_motion_actions = unresolved_motion_actions + 1
            end
            motion = fallback_motion(event)
        end
        local step = {
            id = event.id,
            motion = motion,
            expected_combo = math.max(0, tonumber(event.expected_combo) or 0),
            expected_hp = event.actor_hp,
            delay_from_prev = index == 1 and 0 or math.max(
                0,
                (tonumber(event.frame) or 0)
                    - (tonumber(previous_event and previous_event.frame) or 0)
            ),
            damage_at_step = cumulative_damage,
            facing_left = event.facing_right == false,
            has_hit = event.has_hit == true,
            has_contact = event.has_contact == true,
        }
        if (tonumber(event.hold_frames) or 0) > 0 then
            step.hold_frames = tonumber(event.hold_frames)
        end
        if event.is_holdable == true then step.is_holdable = true end
        if event.hold_partial_check == true then step.hold_partial_check = true end
        if event.was_blocked == true then
            step.was_blocked = true
            step.hit_result = "block"
        end
        steps[#steps + 1] = step
        projected_events[#projected_events + 1] = {
            id = event.id,
            frame = event.frame,
            first_contact_frame = event.first_contact_frame,
            combo_at_start = math.max(0, tonumber(event.combo_at_start) or 0),
            expected_combo = math.max(0, tonumber(event.expected_combo) or 0),
            motion = motion,
            resolution_status = resolved.resolution_status,
            bind_reason = event.bind_reason,
            promoted_from_id = event.promoted_from_id,
            normalized_from_action_id = event.normalized_from_action_id,
            anchor_kind = type(event.anchor) == "table" and event.anchor.kind or nil,
            anchor_buttons = event_button_mask(event),
            has_hit = event.has_hit == true,
            has_contact = event.has_contact == true,
        }
        previous_event = event
        previous_resolved = resolved
    end

    local last_sample = type(session) == "table" and session.last_sample or nil
    local reported_damage = type(session) == "table" and math.max(
        tonumber(session.confirmed_damage) or 0,
        tonumber(cumulative_damage) or 0
    ) or 0
    return {
        steps = steps,
        stats = {
            damage = reported_damage,
            observed_hp_loss = type(session) == "table"
                and (session.current_damage or 0) or 0,
            unconfirmed_hp_loss = type(session) == "table" and math.max(
                0,
                (tonumber(session.current_damage) or 0)
                    - reported_damage
            ) or 0,
            passive_damage_ticks = type(session) == "table"
                and (tonumber(session.passive_damage_ticks) or 0) or 0,
            passive_damage_total = type(session) == "table"
                and (tonumber(session.passive_damage_total) or 0) or 0,
            passive_damage_max_tick = type(session) == "table"
                and (tonumber(session.passive_damage_max_tick) or 0) or 0,
            max_combo = type(session) == "table" and (session.max_combo or 0) or 0,
            hit_contacts = type(session) == "table" and (session.hit_contacts or 0) or 0,
            block_contacts = type(session) == "table" and (session.block_contacts or 0) or 0,
            action_events = #steps,
            input_anchors = type(session) == "table" and (session.input_anchor_count or 0) or 0,
            unresolved_anchors = unresolved_anchors,
            observed_action_transitions = type(session) == "table"
                and #(session.observed_actions or {}) or 0,
            motion_resolver_available = type(resolver) == "function",
            resolved_motion_actions = resolved_motion_actions,
            fallback_motion_actions = fallback_motion_actions,
            input_derived_motion_actions = input_derived_motion_actions,
            input_derived_noncontact_motion_actions =
                input_derived_noncontact_motion_actions,
            input_refined_motion_actions = input_refined_motion_actions,
            unresolved_motion_actions = unresolved_motion_actions,
            resolver_error_actions = resolver_error_actions,
            suppressed_action_events = #suppressed_events,
            promoted_action_events = #promoted_events,
            drive_used = type(session) == "table" and session.initial_actor_drive
                and math.max(0, session.initial_actor_drive - (session.min_actor_drive
                    or session.initial_actor_drive)) or 0,
            super_used = type(session) == "table" and session.initial_actor_super
                and math.max(0, session.initial_actor_super - (session.min_actor_super
                    or session.initial_actor_super)) or 0,
            actor_hp = last_sample and rounded(last_sample.actor_hp) or nil,
            victim_hp = last_sample and rounded(last_sample.victim_hp) or nil,
        },
        trace = {
            source = type(session) == "table" and session.source or nil,
            character = type(session) == "table" and session.character or nil,
            first_frame = type(session) == "table" and session.started_frame or nil,
            last_activity_frame = type(session) == "table" and session.last_activity_frame or nil,
            observed_actions = type(session) == "table" and session.observed_actions or {},
            input_bound_events = type(session) == "table" and session.events or {},
            projected_events = projected_events,
            suppressed_events = suppressed_events,
            promoted_events = promoted_events,
            passive_damage_frames = type(session) == "table"
                and shallow_copy(session.passive_damage_frames) or {},
            passive_damage_samples = type(session) == "table"
                and shallow_copy(session.passive_damage_samples) or {},
            combo_reset_frames = type(session) == "table"
                and shallow_copy(session.combo_reset_frames) or {},
            pending_anchor = type(session) == "table"
                and session.pending_anchor or nil,
            expired_anchor_count = type(session) == "table"
                and (session.unresolved_anchor_count or 0) or 0,
            expired_internal_continuation_count = type(session) == "table"
                and (session.expired_internal_continuation_count or 0) or 0,
            expired_quick_successor_continuation_count = type(session) == "table"
                and (session.expired_quick_successor_continuation_count or 0) or 0,
            expired_meter_raw_dr_count = type(session) == "table"
                and (session.expired_meter_raw_dr_count or 0) or 0,
        },
    }
end

Compiler.relative_direction = relative_direction
Compiler.button_notation = button_notation
Compiler.fallback_motion = fallback_motion

return Compiler
