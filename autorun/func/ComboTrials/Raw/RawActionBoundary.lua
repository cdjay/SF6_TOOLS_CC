-- RawActionBoundary.lua
-- Derives factual Atomic Action boundaries from current Action facts and
-- physical input edges. It does not consult combo steps, BCM/AC semantics,
-- CharacterRules, compatibility or presentation data.

local RawActionBoundary = {
    name = "ComboTrials.Raw.RawActionBoundary",
}

local INPUT_WINDOW = 12
local DIRECTION_MAP = { [4] = "6", [8] = "4" }

local Boundary = {}
Boundary.__index = Boundary

local function integer(value, fallback)
    value = tonumber(value)
    if value == nil or value % 1 ~= 0 then return fallback end
    return value
end

local function relative_direction_bits(bits, facing_right)
    bits = integer(bits, 0) & 0xF
    if facing_right == false then
        local right = (bits & 4) ~= 0
        local left = (bits & 8) ~= 0
        bits = bits & ~12
        if right then bits = bits | 8 end
        if left then bits = bits | 4 end
    end
    return bits
end

function RawActionBoundary.new(initial_direct_input, initial_direction_input)
    local direct_input = integer(initial_direct_input, 0)
    return setmetatable({
        last_action_id = nil,
        last_action_frame = nil,
        last_direct_input = direct_input,
        last_direction_input = integer(initial_direction_input, direct_input & 0xF),
        last_button_edge_frame = nil,
        pending_direction = nil,
        pending_direction_frame = nil,
        completed_pair = nil,
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

    local direct_input = integer(sample.direct_input, 0)
    local direction_input = integer(sample.direction_input, direct_input & 0xF)
    local pressed = ((direct_input ~ self.last_direct_input) & direct_input)
    local button_edge = pressed & 0xFFF0
    if button_edge ~= 0 then self.last_button_edge_frame = engine_frame end

    local pressed_direction = ((direction_input ~ self.last_direction_input)
        & direction_input) & 0xF
    local relative_bits = relative_direction_bits(direction_input, sample.facing_right)
    local direction = DIRECTION_MAP[relative_bits]
    if direction ~= nil and pressed_direction ~= 0 and button_edge == 0 then
        local delta = engine_frame - (self.pending_direction_frame or -100000)
        if self.pending_direction == direction and delta > 0 and delta <= INPUT_WINDOW then
            self.completed_pair = { direction = direction, frame = engine_frame }
            self.pending_direction = nil
            self.pending_direction_frame = nil
        else
            self.pending_direction = direction
            self.pending_direction_frame = engine_frame
        end
    end

    local action_changed = self.last_action_id ~= nil and action_id ~= self.last_action_id
    local action_rewind = self.last_action_id == action_id
        and self.last_action_frame ~= nil and action_frame ~= nil
        and action_frame < self.last_action_frame
    local pair = self.completed_pair
    local pair_recent = pair ~= nil and engine_frame - pair.frame >= 0
        and engine_frame - pair.frame <= INPUT_WINDOW
    local restart = false
    local reason = nil

    if action_changed then
        reason = "action_id_changed"
        if pair_recent and sample.repeatable_direction == pair.direction then
            self.completed_pair = nil
        end
    elseif pair_recent and sample.repeatable_direction == pair.direction then
        restart = true
        reason = "same_action_double_tap"
        self.completed_pair = nil
    elseif action_rewind then
        local edge_frame = self.last_button_edge_frame
        local edge_age = edge_frame and (engine_frame - edge_frame) or nil
        if edge_age ~= nil and edge_age >= 0 and edge_age <= INPUT_WINDOW then
            restart = true
            reason = "input_confirmed_action_frame_rewind"
            self.last_button_edge_frame = nil
        end
    end

    self.last_action_id = action_id
    self.last_action_frame = action_frame
    self.last_direct_input = direct_input
    self.last_direction_input = direction_input
    return {
        active = pressed ~= 0 or pressed_direction ~= 0,
        restart = restart,
        reason = reason,
        action_changed = action_changed,
        action_frame_rewind = action_rewind,
        button_edge = button_edge,
    }
end

return RawActionBoundary
