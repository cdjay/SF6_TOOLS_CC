local ActionMatcher = require("func/ComboTrials/ActionMatcher")

local RawDriveRushPrecursorBuffer = {
    name = "ComboTrials.RawDriveRushPrecursorBuffer",
}

function RawDriveRushPrecursorBuffer.reset(state)
    if type(state) == "table" then state.pending_dash = nil end
end

function RawDriveRushPrecursorBuffer.flush(state)
    if type(state) ~= "table" then return nil end
    local pending = state.pending_dash
    state.pending_dash = nil
    return pending
end

function RawDriveRushPrecursorBuffer.should_route(state, params)
    if type(state) == "table" and state.pending_dash ~= nil then return true end
    params = type(params) == "table" and params or {}
    if not ActionMatcher.is_raw_drive_rush_step(params.expected_step) then
        return false
    end
    return ActionMatcher.raw_drive_rush_precursor_kind({
        precursor_action_id = params.previous_action_id,
        precursor_motion = params.previous_motion,
        precursor_input_anchor_kind = params.previous_input_anchor_kind,
        precursor_input_anchor_motion = params.previous_input_anchor_motion,
    }) ~= nil
end

function RawDriveRushPrecursorBuffer.transition(state, params)
    state = type(state) == "table" and state or {}
    params = type(params) == "table" and params or {}

    if not ActionMatcher.is_raw_drive_rush_step(params.expected_step) then
        local pending = RawDriveRushPrecursorBuffer.flush(state)
        return pending and "release" or "pass", pending
    end

    local previous_kind = ActionMatcher.raw_drive_rush_precursor_kind({
        precursor_action_id = params.previous_action_id,
        precursor_motion = params.previous_motion,
        precursor_input_anchor_kind = params.previous_input_anchor_kind,
        precursor_input_anchor_motion = params.previous_input_anchor_motion,
    })
    local successor_kind = ActionMatcher.raw_drive_rush_precursor_kind({
        precursor_action_id = params.successor_action_id,
        precursor_motion = params.successor_motion,
        precursor_input_anchor_kind = params.successor_input_anchor_kind,
        precursor_input_anchor_motion = params.successor_input_anchor_motion,
    })

    if ActionMatcher.is_quick_raw_drive_rush_precursor({
        precursor_action_id = params.previous_action_id,
        precursor_motion = params.previous_motion,
        precursor_input_anchor_kind = params.previous_input_anchor_kind,
        precursor_input_anchor_motion = params.previous_input_anchor_motion,
        precursor_has_contact = params.previous_has_contact,
        precursor_has_hit = params.previous_has_hit,
        successor_action_id = params.successor_action_id,
        successor_motion = params.successor_motion,
        elapsed_frames = params.elapsed_frames,
    }) then
        state.pending_dash = nil
        return "discard", nil
    end

    -- A dash followed by Parry is not yet proven to be RAW DR. Hold it until
    -- the rush appears; otherwise release it before the Parry in original order.
    if previous_kind == "dash"
        and successor_kind == "parry"
        and tonumber(params.elapsed_frames) ~= nil
        and tonumber(params.elapsed_frames) >= 0
        and tonumber(params.elapsed_frames)
            <= ActionMatcher.RAW_DRIVE_RUSH_DASH_PRECURSOR_WINDOW
        and type(params.previous_action) == "table" then
        state.pending_dash = params.previous_action
        return "hold", nil
    end

    local pending = RawDriveRushPrecursorBuffer.flush(state)
    return pending and "release" or "pass", pending
end

function RawDriveRushPrecursorBuffer.route(state, queue, params)
    queue = type(queue) == "table" and queue or {}
    params = type(params) == "table" and params or {}
    local decision, pending = RawDriveRushPrecursorBuffer.transition(state, params)
    if pending then queue[#queue + 1] = pending end
    if (decision == "pass" or decision == "release")
        and type(params.previous_action) == "table" then
        queue[#queue + 1] = params.previous_action
    end
    return decision
end

function RawDriveRushPrecursorBuffer.flush_into(state, queue)
    queue = type(queue) == "table" and queue or {}
    local pending = RawDriveRushPrecursorBuffer.flush(state)
    if pending then queue[#queue + 1] = pending end
    return pending ~= nil
end

return RawDriveRushPrecursorBuffer
