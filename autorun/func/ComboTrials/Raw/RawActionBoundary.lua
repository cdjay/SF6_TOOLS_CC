-- RawActionBoundary.lua
-- Derives factual Atomic Action boundaries from current Action facts only.
-- Input is deliberately not an admission signal: the instruction list records
-- what Action instances the game entered, not what command the player pressed.

local RawActionBoundary = {
    name = "ComboTrials.Raw.RawActionBoundary",
}

local RESTART_FRAME_MAX = 2

local Boundary = {}
Boundary.__index = Boundary

local function integer(value, fallback)
    value = tonumber(value)
    if value == nil or value % 1 ~= 0 then return fallback end
    return value
end

function RawActionBoundary.new(initial_action_id, initial_action_frame)
    return setmetatable({
        last_action_id = integer(initial_action_id),
        last_action_frame = integer(initial_action_frame),
    }, Boundary)
end

function Boundary:observe(sample)
    if type(sample) ~= "table" then return nil, "invalid_sample" end
    local action_id = integer(sample.action_id)
    local engine_frame = integer(sample.engine_frame)
    local action_frame = sample.action_frame == nil
        and nil or integer(sample.action_frame)
    if action_id == nil or action_id < 0 or engine_frame == nil
        or engine_frame < 0 or (sample.action_frame ~= nil and action_frame == nil) then
        return nil, "invalid_sample"
    end

    local action_changed = self.last_action_id ~= nil and action_id ~= self.last_action_id
    local action_rewind = self.last_action_id == action_id
        and self.last_action_frame ~= nil and action_frame ~= nil
        and action_frame < self.last_action_frame
    local restart = action_rewind
        and self.last_action_frame > RESTART_FRAME_MAX
        and action_frame <= RESTART_FRAME_MAX
    local reason = nil

    if action_changed then
        reason = "action_id_changed"
    elseif restart then
        reason = "action_frame_restarted"
    end

    self.last_action_id = action_id
    self.last_action_frame = action_frame
    return {
        active = action_changed or restart,
        restart = restart,
        reason = reason,
        action_changed = action_changed,
        action_frame_rewind = action_rewind,
    }
end

return RawActionBoundary
