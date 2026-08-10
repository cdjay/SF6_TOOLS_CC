-- AtomicTrace.lua
-- Stage 1 zero-interpretation core: an ordered, duplicate-preserving list of
-- current-game Atomic Action Instances. This module records facts only:
-- action_id, order, occurrence and the frame facts the runtime can currently
-- collect. It never applies owner/alias/absorb/group/AC/compatibility or any
-- other semantic interpretation.
--
-- ActionFrame may rewind, so no frame field is assumed to be monotonic. The
-- trace accepts append/update until finalize() and is immutable afterwards.

local AtomicTrace = {
    name = "ComboTrials.Raw.AtomicTrace",
    SCHEMA = "sf6cc.raw_stage1.atomic_trace.v1",
    VERSION = 1,
    FRAME_FIELDS = {
        "enter_frame",
        "exit_frame",
        "action_frame_start",
        "action_frame_end",
    },
}

local FRAME_FIELD_MAP = {}
for _, field in ipairs(AtomicTrace.FRAME_FIELDS) do
    FRAME_FIELD_MAP[field] = true
end
local SIGNED_FRAME_FIELDS = {
    action_frame_start = true,
    action_frame_end = true,
}
local PAYLOAD_FIELDS = {
    schema = true, version = true, finalized = true, instances = true,
}
local INSTANCE_FIELDS = {
    step = true, occurrence = true, action_id = true,
    enter_frame = true, exit_frame = true,
    action_frame_start = true, action_frame_end = true,
}

local Trace = {}
local TRACE_STATE = setmetatable({}, { __mode = "k" })
Trace.__index = Trace
Trace.__newindex = function()
    error("AtomicTrace is read-only", 2)
end
Trace.__metatable = false

local function is_integer(value, minimum)
    return type(value) == "number"
        and value % 1 == 0
        and value >= (minimum or 0)
end

local function is_frame_value(field, value)
    if type(value) ~= "number" or value % 1 ~= 0 then return false end
    return SIGNED_FRAME_FIELDS[field] == true or value >= 0
end

local function clone(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, item in pairs(value) do
        copy[key] = clone(item)
    end
    return copy
end

local function freeze_view(value)
    if type(value) ~= "table" then return value end
    local proxy = {}
    return setmetatable(proxy, {
        __index = function(_, key)
            return freeze_view(value[key])
        end,
        __newindex = function()
            error("AtomicTrace data is read-only", 2)
        end,
        __len = function() return #value end,
        __pairs = function()
            local function next_value(_, key)
                local next_key, item = next(value, key)
                if next_key ~= nil then
                    return next_key, freeze_view(item)
                end
            end
            return next_value, proxy, nil
        end,
        __metatable = false,
    })
end

local function trace_state(trace)
    local state = TRACE_STATE[trace]
    if state == nil then
        error("invalid AtomicTrace instance", 2)
    end
    return state
end

local function invalid(code)
    return nil, "invalid", code
end

local function has_only_fields(value, allowed)
    for key in pairs(value) do
        if allowed[key] ~= true then return false end
    end
    return true
end

function AtomicTrace.is_trace(value)
    return type(value) == "table" and TRACE_STATE[value] ~= nil
end

function AtomicTrace.new()
    local trace = setmetatable({}, Trace)
    TRACE_STATE[trace] = { instances = {}, occurrence_counts = {}, finalized = false }
    return trace
end

function Trace:append(spec)
    local state = trace_state(self)
    if state.finalized then return nil, "trace_finalized" end
    local action_id
    local fields = {}
    if type(spec) == "number" then
        action_id = spec
    elseif type(spec) == "table" then
        if not has_only_fields(spec, INSTANCE_FIELDS) then
            return nil, "unknown_instance_field"
        end
        action_id = spec.action_id
        fields = spec
    else
        return nil, "action_id_required"
    end
    if not is_integer(action_id, 0) then
        return nil, "action_id_required"
    end
    local instance = clone(fields)
    instance.action_id = action_id
    for _, field in ipairs(AtomicTrace.FRAME_FIELDS) do
        if instance[field] ~= nil and not is_frame_value(field, instance[field]) then
            return nil, "invalid_frame"
        end
    end
    local step = #state.instances + 1
    local occurrence = (state.occurrence_counts[action_id] or 0) + 1
    state.occurrence_counts[action_id] = occurrence
    instance.step = step
    instance.occurrence = occurrence
    state.instances[step] = instance
    return freeze_view(instance), step
end

function Trace:update(step, fields)
    local state = trace_state(self)
    if state.finalized then return nil, "trace_finalized" end
    if not is_integer(step, 1) or type(fields) ~= "table" then
        return nil, "step_not_found"
    end
    local instance = state.instances[step]
    if instance == nil then return nil, "step_not_found" end
    for key, value in pairs(fields) do
        if INSTANCE_FIELDS[key] ~= true then return nil, "unknown_instance_field" end
        if key == "step" or key == "occurrence" or key == "action_id" then
            return nil, "identity_field_frozen"
        end
        if FRAME_FIELD_MAP[key] then
            if not is_frame_value(key, value) then return nil, "invalid_frame" end
            instance[key] = value
        else
            instance[key] = clone(value)
        end
    end
    return freeze_view(instance)
end

function Trace:finalize()
    local state = trace_state(self)
    state.finalized = true
    return self:summary()
end

function Trace:is_finalized()
    return trace_state(self).finalized
end

function Trace:count()
    return #trace_state(self).instances
end

function Trace:get_instances()
    return freeze_view(trace_state(self).instances)
end

function Trace:get_instance(step)
    if not is_integer(step, 1) then return nil end
    local instance = trace_state(self).instances[step]
    if instance == nil then return nil end
    return freeze_view(instance)
end

function Trace:summary()
    local state = trace_state(self)
    local action_counts = {}
    for index = 1, #state.instances do
        local action_id = state.instances[index].action_id
        action_counts[action_id] = (action_counts[action_id] or 0) + 1
    end
    return freeze_view({
        schema = AtomicTrace.SCHEMA,
        version = AtomicTrace.VERSION,
        finalized = state.finalized,
        count = #state.instances,
        action_counts = action_counts,
    })
end

function Trace:to_payload()
    local state = trace_state(self)
    local payload = {
        schema = AtomicTrace.SCHEMA,
        version = AtomicTrace.VERSION,
        finalized = state.finalized,
        instances = {},
    }
    for index = 1, #state.instances do
        payload.instances[index] = clone(state.instances[index])
    end
    return payload
end

function AtomicTrace.from_payload(payload)
    if type(payload) ~= "table" then return invalid("payload_not_object") end
    if not has_only_fields(payload, PAYLOAD_FIELDS) then
        return invalid("unknown_payload_field")
    end
    if payload.schema ~= AtomicTrace.SCHEMA then
        return invalid("unsupported_schema")
    end
    if payload.version ~= AtomicTrace.VERSION then
        return invalid("unsupported_version")
    end
    if payload.finalized ~= true then
        return invalid("finalized_trace_required")
    end
    if type(payload.instances) ~= "table" then
        return invalid("instances_required")
    end
    local trace = AtomicTrace.new()
    local state = trace_state(trace)
    local seen = {}
    local count = 0
    for index, instance in ipairs(payload.instances) do
        if type(instance) ~= "table" then
            return invalid("invalid_instance")
        end
        if not has_only_fields(instance, INSTANCE_FIELDS) then
            return invalid("unknown_instance_field")
        end
        local action_id = instance.action_id
        if not is_integer(action_id, 0) then
            return invalid("invalid_action_id")
        end
        for _, field in ipairs(AtomicTrace.FRAME_FIELDS) do
            if instance[field] ~= nil and not is_frame_value(field, instance[field]) then
                return invalid("invalid_frame")
            end
        end
        if instance.step ~= nil and instance.step ~= index then
            return invalid("step_mismatch")
        end
        local occurrence = (seen[action_id] or 0) + 1
        if instance.occurrence ~= nil and instance.occurrence ~= occurrence then
            return invalid("occurrence_mismatch")
        end
        seen[action_id] = occurrence
        local copy = clone(instance)
        copy.step = index
        copy.occurrence = occurrence
        state.instances[index] = copy
        state.occurrence_counts[action_id] = occurrence
        count = index
    end
    for key in pairs(payload.instances) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 or key > count then
            return invalid("instances_not_array")
        end
    end
    state.finalized = true
    return trace, "loaded"
end

return AtomicTrace
