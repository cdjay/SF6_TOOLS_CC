-- Compiles WTT-compatible V2 steps from the input stream and the Action IDs
-- that the game actually exposes while those inputs are being executed.
--
-- This module deliberately does not read command tables, character exception
-- files or an existing combo sequence. Those are presentation/compatibility
-- data and must not decide which runtime Action happened.

local ActionMatcher = require("func/ComboTrials/ActionMatcher")

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
    DASH_TAP_WINDOW = 12,
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
    [34] = { [37] = true },
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
    local buttons = button_notation(
        (tonumber(anchor.pressed_buttons) or 0) ~= 0 and anchor.pressed_buttons
            or ((tonumber(anchor.held_buttons) or 0) ~= 0 and anchor.held_buttons
                or anchor.released_buttons)
    )
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

local function update_actor_resources(session, sample)
    local drive = rounded(sample.actor_drive)
    local super = rounded(sample.actor_super)
    if drive ~= nil then
        if not session.input_started or session.initial_actor_drive == nil then
            session.initial_actor_drive = drive
            session.min_actor_drive = drive
        else
            session.min_actor_drive = math.min(session.min_actor_drive or drive, drive)
        end
    end
    if super ~= nil then
        if not session.input_started or session.initial_actor_super == nil then
            session.initial_actor_super = super
            session.min_actor_super = super
        else
            session.min_actor_super = math.min(session.min_actor_super or super, super)
        end
    end
end

local function snapshot_anchor(session, sample, kind, pressed, released, hold_frames)
    local frame = tonumber(sample.frame) or 0
    local previous_event = session.events[#session.events]
    local history_start = previous_event and math.max(previous_event.frame - 5, frame - 90)
        or math.max(session.started_frame or frame, frame - 90)
    local anchor = {
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

local function add_event(session, sample, anchor, reason)
    local action_id = tonumber(sample.action_id)
    if not action_is_recordable(action_id) then return nil end

    local frame = tonumber(sample.frame) or 0
    local previous = session.events[#session.events]
    local event = {
        id = action_id,
        frame = frame,
        action_frame = tonumber(sample.action_frame) or 0,
        actor_hp = rounded(sample.actor_hp),
        facing_right = sample.facing_right ~= false,
        expected_combo = 0,
        damage_at_step = session.current_damage or 0,
        has_hit = false,
        has_contact = false,
        was_blocked = false,
        anchor = shallow_copy(anchor),
        bind_reason = reason,
        delay_from_prev = previous and math.max(0, frame - previous.frame) or 0,
    }
    session.events[#session.events + 1] = event
    session.current_event = event
    session.pending_anchor = nil
    session.started = true
    session.started_frame = session.started_frame or frame
    session.last_activity_frame = frame
    return event
end

local function event_button_mask(event)
    local anchor = type(event) == "table" and event.anchor or nil
    if type(anchor) ~= "table" then return 0 end
    local pressed = tonumber(anchor.pressed_buttons) or 0
    local released = tonumber(anchor.released_buttons) or 0
    local held = tonumber(anchor.held_buttons) or 0
    if pressed ~= 0 then return pressed & Compiler.BUTTON_MASK end
    if released ~= 0 then return released & Compiler.BUTTON_MASK end
    return held & Compiler.BUTTON_MASK
end

local function merge_event_truth(target, source)
    if type(target) ~= "table" or type(source) ~= "table" then return end
    target.expected_combo = math.max(
        tonumber(target.expected_combo) or 0,
        tonumber(source.expected_combo) or 0
    )
    target.damage_at_step = math.max(
        tonumber(target.damage_at_step) or 0,
        tonumber(source.damage_at_step) or 0
    )
    target.has_hit = target.has_hit == true or source.has_hit == true
    target.has_contact = target.has_contact == true or source.has_contact == true
    target.was_blocked = target.was_blocked == true or source.was_blocked == true
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
    if previous.event.has_contact == true or previous.event.has_hit == true then return false end
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
        and previous_anchor.kind == "double_tap" then
        -- Quarter-circle repetitions inside a super input can briefly look
        -- like a standalone directional double tap. If no catalog Action or
        -- contact resulted before the following button Action, it is only the
        -- direction buffer of that command.
        return true
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
        created_frame = tonumber(options.frame) or 0,
        previous_input = 0,
        previous_direction = "5",
        previous_action_id = nil,
        previous_action_frame = nil,
        previous_combo = 0,
        previous_victim_hp = nil,
        block_active = false,
        started = false,
        input_started = false,
        started_frame = nil,
        input_anchor_count = 0,
        unresolved_anchor_count = 0,
        pending_anchor = nil,
        button_press_frames = {},
        last_direction_tap = {},
        direction_history = {},
        observed_actions = {},
        events = {},
        current_event = nil,
        max_combo = 0,
        hit_contacts = 0,
        block_contacts = 0,
        current_damage = 0,
        cumulative_damage = 0,
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
    end

    update_damage(session, sample)
    update_actor_resources(session, sample)

    local anchor
    if pressed ~= 0 or released ~= 0 then
        if released ~= 0 and type(session.current_event) == "table"
            and (event_button_mask(session.current_event) & released) ~= 0 then
            session.current_event.hold_frames = math.max(
                tonumber(session.current_event.hold_frames) or 0,
                release_hold_frames
            )
        end
        anchor = snapshot_anchor(
            session,
            sample,
            pressed ~= 0 and "button_press" or "button_release",
            pressed,
            released,
            released ~= 0 and release_hold_frames or nil
        )
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
    end

    local pending = session.pending_anchor
    if pending and frame - pending.frame > Compiler.BIND_WINDOW then
        -- Every ordinary button release is still captured because negative-edge
        -- actions can bind to it. An unbound release is not itself evidence that
        -- transcription failed.
        if pending.kind ~= "button_release"
            and pending.is_movement_continuation ~= true then
            session.unresolved_anchor_count = session.unresolved_anchor_count + 1
        end
        session.pending_anchor = nil
        pending = nil
    end

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
        if not stale_release_low_action
            and (actual_action_start or changed_after_anchor
                or restarted_after_anchor or dash_already_active) then
            local bound_anchor = pending
            local bound_event = add_event(
                session,
                sample,
                bound_anchor,
                action_restarted and "action_frame_rewind"
                    or (dash_already_active and "double_tap_action" or "action_id_changed")
            )
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
    elseif actual_action_start and MOVEMENT_ACTIONS[action_id] and direction ~= "5" then
        local movement_anchor = anchor or snapshot_anchor(session, sample, "movement_action", 0, 0)
        add_event(session, sample, movement_anchor, "movement_action_started")
    end

    local current = session.current_event
    local combo = math.max(0, tonumber(sample.combo_count) or 0)
    session.max_combo = math.max(session.max_combo or 0, combo)
    local victim_hp = rounded(sample.victim_hp)
    local hp_decreased = victim_hp ~= nil and session.previous_victim_hp ~= nil
        and victim_hp < session.previous_victim_hp
    local block_active = tonumber(sample.victim_damage_type) == 30
    local block_started = block_active and not session.block_active
    local combo_increased = combo > (session.previous_combo or 0)

    if current then
        if combo_increased or hp_decreased then
            current.has_hit = true
            current.has_contact = true
            current.expected_combo = math.max(current.expected_combo or 0, combo)
            current.damage_at_step = math.max(
                current.damage_at_step or 0,
                session.current_damage or 0
            )
            session.hit_contacts = session.hit_contacts + 1
            session.last_activity_frame = frame
        elseif combo > 0 and current.has_hit then
            current.expected_combo = math.max(current.expected_combo or 0, combo)
        end
        if block_started then
            current.has_contact = true
            current.was_blocked = true
            session.block_contacts = session.block_contacts + 1
            session.last_activity_frame = frame
        end
    end

    session.block_active = block_active
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
    local resolver = options.motion_resolver
    local steps = {}
    local projected = {}
    local suppressed_events = {}
    local promoted_events = {}
    local resolved_motion_actions = 0
    local fallback_motion_actions = 0
    local input_derived_motion_actions = 0
    local input_refined_motion_actions = 0
    local unresolved_motion_actions = 0
    local resolver_error_actions = 0
    local cumulative_damage = 0
    local unresolved_anchors = type(session) == "table"
        and (session.unresolved_anchor_count or 0) or 0
    if type(session) == "table" and type(session.pending_anchor) == "table"
        and session.pending_anchor.kind ~= "button_release" then
        unresolved_anchors = unresolved_anchors + 1
    end

    local source_events = type(session) == "table" and session.events or {}
    for event_index, source_event in ipairs(source_events) do
        local event = source_event
        local motion, resolution_status, resolution_metadata =
            resolve_motion(resolver, event, session)
        if type(resolver) == "function"
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
        if resolution_status == "suppress_transition" or release_transition then
            if previous then merge_event_truth(previous.event, event) end
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
            local redundant_action_phase =
                is_redundant_inherited_action_phase(previous, current)
            local quick_drive_parry =
                is_quick_drive_parry_precursor(previous, current)
            local jump_startup = is_jump_startup_precursor(previous, current)
            local unmapped_input = is_unmapped_input_precursor(previous, current)
            if redundant_action_phase then
                merge_event_truth(previous.event, event)
                suppressed_events[#suppressed_events + 1] = {
                    id = event.id,
                    frame = event.frame,
                    merged_into = previous.event.id,
                    reason = "redundant_inherited_action_phase",
                }
            else
                if quick_drive_parry or jump_startup or unmapped_input then
                    projected[#projected] = nil
                    suppressed_events[#suppressed_events + 1] = {
                        id = previous.event.id,
                        frame = previous.event.frame,
                        merged_into = event.id,
                        reason = quick_drive_parry
                                and "quick_drive_parry_raw_dr_precursor"
                            or (jump_startup and "jump_startup_transition"
                                or "unmapped_input_precursor"),
                    }
                end
                projected[#projected + 1] = current
            end
        end
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
                and (event.has_contact == true or event.has_hit == true)
                and event_button_mask(event) ~= 0 then
                -- The Action ID and contact are runtime facts. A missing
                -- command-catalog row only makes the display notation
                -- input-derived; it does not make the player Action unknown.
                input_derived_motion_actions =
                    input_derived_motion_actions + 1
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
            motion = motion,
            resolution_status = resolved.resolution_status,
            bind_reason = event.bind_reason,
            promoted_from_id = event.promoted_from_id,
            anchor_kind = type(event.anchor) == "table" and event.anchor.kind or nil,
            anchor_buttons = event_button_mask(event),
            has_hit = event.has_hit == true,
            has_contact = event.has_contact == true,
        }
        previous_event = event
        previous_resolved = resolved
    end

    local last_sample = type(session) == "table" and session.last_sample or nil
    return {
        steps = steps,
        stats = {
            damage = type(session) == "table" and (session.current_damage or 0) or 0,
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
        },
    }
end

Compiler.relative_direction = relative_direction
Compiler.button_notation = button_notation
Compiler.fallback_motion = fallback_motion

return Compiler
