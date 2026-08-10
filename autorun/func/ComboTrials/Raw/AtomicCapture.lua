-- AtomicCapture.lua
-- Converts per-frame Runtime Action facts into ordered AtomicTrace instances.
-- Instance boundaries are factual only: a changed Action ID, or an explicit
-- restart signal supplied by RawActionBoundary. An ActionFrame rewind alone is
-- not sufficient because the engine can perform internal frame corrections.

-- A start gate may delay recording until the controller marks the sample with
-- `active = true`. That gate is an explicit factual signal supplied by the
-- controller; this module never infers activity from ActionFrame values.

local AtomicCapture = {
    name = "ComboTrials.Raw.AtomicCapture",
    START_GATE_IMMEDIATE = "immediate",
    START_GATE_EXPLICIT = "explicit",
}

local AtomicTrace = require("func/ComboTrials/Raw/AtomicTrace")

local Capture = {}
Capture.__index = Capture

local function is_integer(value, minimum)
    return type(value) == "number"
        and value % 1 == 0
        and (minimum == nil or value >= minimum)
end

local function valid_sample(sample)
    return type(sample) == "table"
        and is_integer(sample.action_id, 0)
        and is_integer(sample.engine_frame, 0)
        and (sample.action_frame == nil or is_integer(sample.action_frame))
end

function AtomicCapture.new(trace, options)
    if not AtomicTrace.is_trace(trace) or trace:is_finalized() then
        return nil, "mutable_trace_required"
    end
    options = type(options) == "table" and options or {}
    local start_gate = options.start_gate
    if start_gate == nil then
        start_gate = AtomicCapture.START_GATE_IMMEDIATE
    elseif start_gate ~= AtomicCapture.START_GATE_IMMEDIATE
        and start_gate ~= AtomicCapture.START_GATE_EXPLICIT then
        return nil, "invalid_start_gate"
    end
    return setmetatable({
        trace = trace,
        start_gate = start_gate,
        started = start_gate == AtomicCapture.START_GATE_IMMEDIATE,
        current_step = nil,
        current_action_id = nil,
        last_action_frame = nil,
        last_engine_frame = nil,
    }, Capture)
end

function Capture:observe(sample)
    if not valid_sample(sample) then return nil, "invalid_sample" end
    if self.last_engine_frame ~= nil and sample.engine_frame < self.last_engine_frame then
        return nil, "engine_frame_rewind"
    end

    local action_changed = self.current_action_id ~= nil
        and sample.action_id ~= self.current_action_id
    local action_restarted = self.current_action_id == sample.action_id
        and sample.restart == true
    if self.start_gate == AtomicCapture.START_GATE_EXPLICIT
        and self.started ~= true then
        if sample.active ~= true then
            self.current_action_id = sample.action_id
            self.last_action_frame = sample.action_frame
            self.last_engine_frame = sample.engine_frame
            return {
                new_instance = false,
                started = false,
                step = nil,
                action_id = sample.action_id,
            }
        end
        self.started = true
        if not action_changed and not action_restarted then
            self.current_action_id = sample.action_id
            self.last_action_frame = sample.action_frame
            self.last_engine_frame = sample.engine_frame
            return {
                new_instance = false,
                started = true,
                armed = true,
                step = nil,
                action_id = sample.action_id,
            }
        end
    end
    local new_instance = (self.start_gate == AtomicCapture.START_GATE_IMMEDIATE
            and self.current_step == nil)
        or action_changed or action_restarted

    if new_instance and self.current_step ~= nil then
        self.trace:update(self.current_step, {
            exit_frame = math.max(0, sample.engine_frame - 1),
            action_frame_end = self.last_action_frame,
        })
    end

    if new_instance then
        local _, step_or_error = self.trace:append({
            action_id = sample.action_id,
            enter_frame = sample.engine_frame,
            exit_frame = sample.engine_frame,
            action_frame_start = sample.action_frame,
            action_frame_end = sample.action_frame,
        })
        if type(step_or_error) ~= "number" then return nil, step_or_error end
        self.current_step = step_or_error
        self.current_action_id = sample.action_id
    else
        if self.current_step == nil then
            self.current_action_id = sample.action_id
            self.last_action_frame = sample.action_frame
            self.last_engine_frame = sample.engine_frame
            return {
                new_instance = false,
                started = true,
                armed = true,
                step = nil,
                action_id = sample.action_id,
            }
        end
        local _, update_error = self.trace:update(self.current_step, {
            exit_frame = sample.engine_frame,
            action_frame_end = sample.action_frame,
        })
        if update_error ~= nil then return nil, update_error end
    end

    self.last_action_frame = sample.action_frame
    self.last_engine_frame = sample.engine_frame
    return {
        new_instance = new_instance,
        started = true,
        step = self.current_step,
        action_id = sample.action_id,
    }
end

function Capture:is_started()
    return self.started == true
end

function Capture:finish()
    if self.trace:is_finalized() then return self.trace:summary() end
    return self.trace:finalize()
end

return AtomicCapture
