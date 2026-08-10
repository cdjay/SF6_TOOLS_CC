-- RawTrial.lua
-- Stage 1 trial container: owns one AtomicTrace plus references to raw
-- input / timeline replay sources and recording environment/result metadata.
-- References are descriptors only; this module never parses or interprets
-- raw input, timeline, BCM commands, AC relations or Move semantics.
--
-- Serialization lives under the backward-compatible optional namespace
-- `_xt_meta.raw_stage1` as a candidate payload for Main review. Documents
-- without that namespace report `legacy` and keep their existing path.

local RawTrial = {
    name = "ComboTrials.Raw.RawTrial",
    NAMESPACE = "raw_stage1",
    SCHEMA = "sf6cc.raw_stage1.trial.v1",
    VERSION = 1,
    LEGACY_STATUS = "legacy",
    LOADED_STATUS = "loaded",
    INVALID_STATUS = "invalid",
}

local Trial = {}
local TRIAL_STATE = setmetatable({}, { __mode = "k" })
Trial.__index = Trial
Trial.__newindex = function()
    error("RawTrial is read-only", 2)
end
Trial.__metatable = false

local AtomicTrace = require("func/ComboTrials/Raw/AtomicTrace")

local ENVIRONMENT_FIELDS = {
    "fighter_id",
    "game_build",
    "control_mode",
    "recorded_at",
}
local ENVIRONMENT_FIELD_MAP = {
    character = true, fighter_id = true, game_build = true,
    control_mode = true, recorded_at = true,
}
local PAYLOAD_FIELDS = {
    schema = true, version = true, trace = true, environment = true,
    raw_input_ref = true, timeline_ref = true, result = true,
}
local RESULT_FIELDS = { legacy_step_count = true, raw_input_count = true }
local REF_STRING_FIELDS = {
    source = true,
    field = true,
    path = true,
    encoding = true,
    note = true,
}

local function is_integer(value, minimum)
    return type(value) == "number"
        and value % 1 == 0
        and value >= (minimum or 0)
end

local function clone(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, item in pairs(value) do
        copy[key] = clone(item)
    end
    return copy
end

local function has_only_fields(value, allowed)
    for key in pairs(value) do
        if allowed[key] ~= true then return false end
    end
    return true
end

local function trial_state(trial)
    local state = TRIAL_STATE[trial]
    if state == nil then
        error("invalid RawTrial instance", 2)
    end
    return state
end

local function normalize_ref(ref)
    if type(ref) ~= "table" then return nil, "ref_not_object" end
    if not has_only_fields(ref, REF_STRING_FIELDS) then return nil, "invalid_ref" end
    if type(ref.source) ~= "string" or ref.source == "" then
        return nil, "ref_source_required"
    end
    local copy = {}
    for key, value in pairs(ref) do
        if REF_STRING_FIELDS[key] then
            if type(value) ~= "string" or value == "" then
                return nil, "invalid_ref"
            end
        end
        copy[key] = clone(value)
    end
    return copy
end

function RawTrial.new(character, options)
    if type(character) ~= "string" or character == "" then
        return nil, "invalid_character"
    end
    options = type(options) == "table" and options or {}
    local state = {
        trace = AtomicTrace.new(),
        environment = { character = character },
        raw_input_ref = nil,
        timeline_ref = nil,
        result = {},
    }
    for _, field in ipairs(ENVIRONMENT_FIELDS) do
        local value = options[field]
        if value ~= nil then
            if field == "fighter_id" then
                if not is_integer(value, 0) then return nil, "invalid_environment" end
            elseif type(value) ~= "string" or value == "" then
                return nil, "invalid_environment"
            end
            state.environment[field] = value
        end
    end
    if options.raw_input_ref ~= nil then
        local ref, ref_err = normalize_ref(options.raw_input_ref)
        if ref == nil then return nil, ref_err or "invalid_ref" end
        state.raw_input_ref = ref
    end
    if options.timeline_ref ~= nil then
        local ref, ref_err = normalize_ref(options.timeline_ref)
        if ref == nil then return nil, ref_err or "invalid_ref" end
        state.timeline_ref = ref
    end
    if type(options.result) == "table" then
        for key, value in pairs(options.result) do
            if RESULT_FIELDS[key] ~= true or not is_integer(value, 0) then
                return nil, "invalid_result"
            end
            state.result[key] = value
        end
    elseif options.result ~= nil then
        return nil, "invalid_result"
    end
    local trial = setmetatable({}, Trial)
    TRIAL_STATE[trial] = state
    return trial
end

function Trial:trace()
    return trial_state(self).trace
end

function Trial:environment()
    return clone(trial_state(self).environment)
end

function Trial:set_environment(fields)
    local state = trial_state(self)
    if type(fields) ~= "table" then return nil, "invalid_environment" end
    for key, value in pairs(fields) do
        if ENVIRONMENT_FIELD_MAP[key] ~= true then return nil, "invalid_environment" end
        if key == "character" then
            if type(value) ~= "string" or value == "" then
                return nil, "invalid_character"
            end
        elseif key == "fighter_id" then
            if not is_integer(value, 0) then return nil, "invalid_environment" end
        elseif key == "game_build" or key == "control_mode" or key == "recorded_at" then
            if type(value) ~= "string" or value == "" then
                return nil, "invalid_environment"
            end
        end
        state.environment[key] = clone(value)
    end
    return self:environment()
end

function Trial:result()
    return clone(trial_state(self).result)
end

function Trial:set_result(fields)
    local state = trial_state(self)
    if type(fields) ~= "table" then return nil, "invalid_result" end
    for key, value in pairs(fields) do
        if RESULT_FIELDS[key] ~= true or not is_integer(value, 0) then
            return nil, "invalid_result"
        end
        state.result[key] = clone(value)
    end
    return self:result()
end

function Trial:raw_input_ref()
    local ref = trial_state(self).raw_input_ref
    return ref ~= nil and clone(ref) or nil
end

function Trial:timeline_ref()
    local ref = trial_state(self).timeline_ref
    return ref ~= nil and clone(ref) or nil
end

function Trial:set_raw_input_ref(ref)
    local state = trial_state(self)
    if ref == nil then
        state.raw_input_ref = nil
        return true
    end
    local normalized, ref_err = normalize_ref(ref)
    if normalized == nil then return nil, ref_err or "invalid_ref" end
    state.raw_input_ref = normalized
    return true
end

function Trial:set_timeline_ref(ref)
    local state = trial_state(self)
    if ref == nil then
        state.timeline_ref = nil
        return true
    end
    local normalized, ref_err = normalize_ref(ref)
    if normalized == nil then return nil, ref_err or "invalid_ref" end
    state.timeline_ref = normalized
    return true
end

function Trial:finalize()
    return trial_state(self).trace:finalize()
end

function Trial:summary()
    local state = trial_state(self)
    return {
        schema = RawTrial.SCHEMA,
        version = RawTrial.VERSION,
        character = state.environment.character,
        finalized = state.trace:is_finalized(),
        trace_count = state.trace:count(),
        has_raw_input_ref = state.raw_input_ref ~= nil,
        has_timeline_ref = state.timeline_ref ~= nil,
    }
end

function Trial:to_payload()
    local state = trial_state(self)
    local payload = {
        schema = RawTrial.SCHEMA,
        version = RawTrial.VERSION,
        trace = state.trace:to_payload(),
        environment = clone(state.environment),
    }
    if state.raw_input_ref ~= nil then
        payload.raw_input_ref = clone(state.raw_input_ref)
    end
    if state.timeline_ref ~= nil then
        payload.timeline_ref = clone(state.timeline_ref)
    end
    if next(state.result) ~= nil then
        payload.result = clone(state.result)
    end
    return payload
end

function RawTrial.from_payload(payload)
    if type(payload) ~= "table" then
        return nil, RawTrial.INVALID_STATUS, "payload_not_object"
    end
    if not has_only_fields(payload, PAYLOAD_FIELDS) then
        return nil, RawTrial.INVALID_STATUS, "unknown_payload_field"
    end
    if payload.schema ~= RawTrial.SCHEMA then
        return nil, RawTrial.INVALID_STATUS, "unsupported_schema"
    end
    if payload.version ~= RawTrial.VERSION then
        return nil, RawTrial.INVALID_STATUS, "unsupported_version"
    end
    if type(payload.environment) ~= "table" then
        return nil, RawTrial.INVALID_STATUS, "environment_required"
    end
    if not has_only_fields(payload.environment, ENVIRONMENT_FIELD_MAP) then
        return nil, RawTrial.INVALID_STATUS, "unknown_environment_field"
    end
    local character = payload.environment.character
    if type(character) ~= "string" or character == "" then
        return nil, RawTrial.INVALID_STATUS, "invalid_character"
    end
    local options = {}
    for _, field in ipairs(ENVIRONMENT_FIELDS) do
        if payload.environment[field] ~= nil then
            options[field] = payload.environment[field]
        end
    end
    for _, ref_field in ipairs({ "raw_input_ref", "timeline_ref" }) do
        if payload[ref_field] ~= nil then
            options[ref_field] = payload[ref_field]
        end
    end
    if payload.result ~= nil then
        options.result = payload.result
    end
    local trial, new_err = RawTrial.new(character, options)
    if trial == nil then
        return nil, RawTrial.INVALID_STATUS, new_err or "invalid_trial"
    end
    local trace, trace_status, trace_code = AtomicTrace.from_payload(payload.trace)
    if trace == nil then
        return nil, RawTrial.INVALID_STATUS, trace_code or "invalid_trace"
    end
    if trace:count() == 0 then
        return nil, RawTrial.INVALID_STATUS, "empty_atomic_trace"
    end
    local state = trial_state(trial)
    state.trace = trace
    return trial, RawTrial.LOADED_STATUS
end

function RawTrial.build_namespace_block(trial)
    if TRIAL_STATE[trial] == nil then
        return nil, "invalid_trial"
    end
    local block = {}
    block[RawTrial.NAMESPACE] = trial:to_payload()
    return block
end

function RawTrial.parse_namespace_block(xt_meta)
    if type(xt_meta) ~= "table" then
        return nil, RawTrial.LEGACY_STATUS
    end
    local block = xt_meta[RawTrial.NAMESPACE]
    if block == nil then
        return nil, RawTrial.LEGACY_STATUS
    end
    if type(block) ~= "table" then
        return nil, RawTrial.INVALID_STATUS, "raw_stage1_not_object"
    end
    return RawTrial.from_payload(block)
end

return RawTrial
