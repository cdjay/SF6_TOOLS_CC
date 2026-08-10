-- Stage1Runtime.lua
-- Owns the Stage 1 recording, save/load and strict Atomic attempt lifecycle.
-- Attempt finalization is explicit: the controller calls finalize_attempt()
-- or attempt_inactivity_timeout() when a correct prefix stops advancing.
-- Timeout policy is derived from factual expected-trace frame gaps plus a
-- documented tolerance; no wall-clock time is ever used as a semantic input.

local Stage1Runtime = {
    name = "ComboTrials.Raw.Stage1Runtime",
}

local AtomicCapture = require("func/ComboTrials/Raw/AtomicCapture")
local AtomicDetector = require("func/ComboTrials/Raw/AtomicDetector")
local AtomicTrace = require("func/ComboTrials/Raw/AtomicTrace")
local RawTrial = require("func/ComboTrials/Raw/RawTrial")

local Runtime = {}
Runtime.__index = Runtime

local DEFAULT_TIMEOUT_FLOOR = 30
local DEFAULT_TIMEOUT_CAP = 600
local DEFAULT_TIMEOUT_FALLBACK = 120
local DEFAULT_GAP_TOLERANCE = 3

local function is_integer(value, minimum)
    return type(value) == "number"
        and value % 1 == 0
        and (minimum == nil or value >= minimum)
end

local function normalize_player_index(value)
    if value == nil then return nil end
    if not is_integer(value, 0) or value > 1 then return nil, "invalid_player_index" end
    return value
end

local function trace_instances(trace)
    return AtomicTrace.is_trace(trace) and trace:get_instances() or {}
end

local function prefix_result(expected_trace, actual_trace)
    local expected = trace_instances(expected_trace)
    local actual = trace_instances(actual_trace)
    local compared = math.min(#expected, #actual)
    for step = 1, compared do
        if expected[step].action_id ~= actual[step].action_id
            or expected[step].occurrence ~= actual[step].occurrence then
            local _, report = AtomicDetector.compare(expected_trace, actual_trace)
            report.status = "failed"
            return report
        end
    end
    if #actual > #expected then
        local _, report = AtomicDetector.compare(expected_trace, actual_trace)
        report.status = "failed"
        return report
    end
    if #actual == #expected and #expected > 0 then
        local matched, report = AtomicDetector.compare(expected_trace, actual_trace)
        report.status = matched and "passed" or "failed"
        return report
    end
    return {
        mode = AtomicDetector.MODE,
        status = "progress",
        match = nil,
        expected_count = #expected,
        actual_count = #actual,
        next_step = #actual + 1,
    }
end

function Stage1Runtime.new()
    return setmetatable({
        recording = nil,
        last_recorded = nil,
        loaded = nil,
        load_status = RawTrial.LEGACY_STATUS,
        load_error = nil,
        attempt = nil,
        last_result = nil,
        _timeout_policy = nil,
    }, Runtime)
end

function Runtime:begin_recording(character, options)
    local trial, trial_error = RawTrial.new(character, options)
    if trial == nil then return nil, trial_error end
    options = type(options) == "table" and options or {}
    local player_index, player_error = normalize_player_index(options.player_index)
    if player_error ~= nil then return nil, player_error end
    local capture, capture_error = AtomicCapture.new(trial:trace(), {
        start_gate = options.start_gate,
        initial_action_id = options.initial_action_id,
        initial_action_frame = options.initial_action_frame,
    })
    if capture == nil then return nil, capture_error end
    self.recording = {
        trial = trial,
        capture = capture,
        player_index = player_index,
    }
    self.last_recorded = nil
    return trial
end

function Runtime:observe_recording(sample)
    if self.recording == nil then return nil, "recording_not_active" end
    if self.recording.player_index ~= nil and sample.player_index ~= nil
        and sample.player_index ~= self.recording.player_index then
        return nil, "wrong_recording_player"
    end
    return self.recording.capture:observe(sample)
end

function Runtime:finish_recording()
    if self.recording == nil then return nil, "recording_not_active" end
    if self.recording.trial:trace():count() == 0 then
        self.recording = nil
        self.last_recorded = nil
        return nil, "empty_atomic_trace"
    end
    self.recording.capture:finish()
    self.last_recorded = self.recording.trial
    self.loaded = self.last_recorded
    self.load_status = RawTrial.LOADED_STATUS
    self.load_error = nil
    self.recording = nil
    return self.last_recorded
end

function Runtime:cancel_recording()
    self.recording = nil
    self.last_recorded = nil
end

function Runtime:recording_trial()
    return self.recording and self.recording.trial or nil
end

function Runtime:last_recorded_trial()
    return self.last_recorded
end

function Runtime:attach_last_recording(xt_meta, options)
    if type(xt_meta) ~= "table" then return nil, "meta_required" end
    local trial = self.last_recorded
    if trial == nil then return nil, "recording_not_finalized" end
    options = type(options) == "table" and options or {}
    if options.raw_input_ref ~= nil then
        local ok, ref_error = trial:set_raw_input_ref(options.raw_input_ref)
        if not ok then return nil, ref_error end
    end
    if options.timeline_ref ~= nil then
        local ok, ref_error = trial:set_timeline_ref(options.timeline_ref)
        if not ok then return nil, ref_error end
    end
    if type(options.result) == "table" then
        trial:set_result(options.result)
    end
    xt_meta[RawTrial.NAMESPACE] = trial:to_payload()
    return true
end

function Runtime:load_meta(xt_meta)
    local trial, status, code = RawTrial.parse_namespace_block(xt_meta)
    self.loaded = status == RawTrial.LOADED_STATUS and trial or nil
    self.load_status = status
    self.load_error = code
    self.attempt = nil
    self.last_result = nil
    self._timeout_policy = nil
    return trial, status, code
end

function Runtime:clear_loaded()
    self.loaded = nil
    self.load_status = RawTrial.LEGACY_STATUS
    self.load_error = nil
    self.attempt = nil
    self.last_result = nil
    self._timeout_policy = nil
end

function Runtime:loaded_trial()
    return self.loaded
end

function Runtime:status()
    return self.load_status, self.load_error
end

function Runtime:begin_attempt(options)
    if self.loaded == nil then
        return nil, self.load_status or RawTrial.LEGACY_STATUS
    end
    options = type(options) == "table" and options or {}
    local player_index, player_error = normalize_player_index(options.player_index)
    if player_error ~= nil then return nil, player_error end
    local trace = AtomicTrace.new()
    local expected = trace_instances(self.loaded:trace())
    local admit_initial = options.admit_matching_initial == true
        and expected[1] ~= nil
        and expected[1].action_id == options.initial_action_id
    local capture, capture_error = AtomicCapture.new(trace, {
        start_gate = admit_initial and "immediate" or options.start_gate,
        initial_action_id = admit_initial and nil or options.initial_action_id,
        initial_action_frame = admit_initial and nil or options.initial_action_frame,
    })
    if capture == nil then return nil, capture_error end
    local timeout_policy = self:timeout_policy()
    self.attempt = {
        trace = trace,
        capture = capture,
        timeout_policy = timeout_policy,
        player_index = player_index,
        last_activity_frame = nil,
        terminal = false,
    }
    self.last_result = nil
    if admit_initial then
        local observed, observe_error = capture:observe({
            player_index = player_index,
            engine_frame = options.start_engine_frame,
            action_id = options.initial_action_id,
            action_frame = options.initial_action_frame,
        })
        if observed == nil then
            self.attempt = nil
            return nil, observe_error
        end
        self.attempt.last_activity_frame = options.start_engine_frame
        self.last_result = prefix_result(self.loaded:trace(), trace)
        if self.last_result.status == "passed" or self.last_result.status == "failed" then
            self.attempt.terminal = true
        end
    end
    return trace
end

function Runtime:observe_attempt(sample)
    if self.loaded == nil then
        return nil, self.load_status or RawTrial.LEGACY_STATUS
    end
    if self.attempt == nil then
        local _, begin_error = self:begin_attempt()
        if begin_error ~= nil then return nil, begin_error end
    end
    if self.attempt.player_index ~= nil and sample.player_index ~= nil
        and sample.player_index ~= self.attempt.player_index then
        return nil, "wrong_attempt_player"
    end
    if self.attempt.terminal == true and self.last_result ~= nil then
        return self.last_result
    end
    local observed, observe_error = self.attempt.capture:observe(sample)
    if observed == nil then return nil, observe_error end
    if sample.active == true or observed.new_instance == true then
        self.attempt.last_activity_frame = sample.engine_frame
    end
    if observed.new_instance ~= true and self.last_result ~= nil then
        return self.last_result
    end
    self.last_result = prefix_result(self.loaded:trace(), self.attempt.trace)
    if self.last_result.status == "passed" or self.last_result.status == "failed" then
        self.attempt.terminal = true
    end
    return self.last_result
end

function Runtime:finalize_attempt()
    if self.attempt == nil then return nil, "attempt_not_active" end
    if self.attempt.terminal ~= true then
        self.attempt.terminal = true
        local _, report = AtomicDetector.compare(
            self.loaded:trace(), self.attempt.trace)
        if report == nil then
            self.attempt.terminal = false
            return nil, "detector_failed"
        end
        report.status = report.match == true and "passed" or "failed"
        self.last_result = report
    end
    return self.last_result
end

function Runtime:timeout_policy()
    if self.loaded == nil then return nil end
    if self._timeout_policy ~= nil then return self._timeout_policy end
    local expected = trace_instances(self.loaded:trace())
    local gaps = {}
    local previous = nil
    local maximum_gap = nil
    for index = 1, #expected do
        local enter_frame = expected[index].enter_frame
        if is_integer(enter_frame, 0) and previous ~= nil
            and enter_frame > previous then
            local gap = enter_frame - previous
            gaps[#gaps + 1] = gap
            maximum_gap = math.max(maximum_gap or gap, gap)
        end
        if enter_frame ~= nil and is_integer(enter_frame, 0) then
            previous = enter_frame
        end
    end
    local basis = maximum_gap
    local timeout_frames
    if basis ~= nil then
        timeout_frames = math.max(DEFAULT_TIMEOUT_FLOOR,
            math.min(DEFAULT_TIMEOUT_CAP,
                math.floor(basis * DEFAULT_GAP_TOLERANCE + 10)))
    else
        timeout_frames = DEFAULT_TIMEOUT_FALLBACK
    end
    self._timeout_policy = {
        basis = basis,
        gap_count = #gaps,
        tolerance = DEFAULT_GAP_TOLERANCE,
        timeout_frames = timeout_frames,
    }
    return self._timeout_policy
end

function Runtime:attempt_inactivity_timeout(current_engine_frame)
    if self.attempt == nil then return nil, "attempt_not_active" end
    if not is_integer(current_engine_frame, 0) then
        return nil, "invalid_engine_frame"
    end
    if self.attempt.terminal == true then return self.last_result end
    local instances = self.attempt.trace:get_instances()
    local last_activity_frame = self.attempt.last_activity_frame
    for index = #instances, 1, -1 do
        local enter_frame = instances[index].enter_frame
        if enter_frame ~= nil and is_integer(enter_frame, 0) then
            last_activity_frame = math.max(last_activity_frame or enter_frame, enter_frame)
            break
        end
    end
    if last_activity_frame == nil then
        return {
            mode = AtomicDetector.MODE,
            status = "progress",
            match = nil,
            timed_out = false,
            last_activity_frame = nil,
            timeout_frames = self.attempt.timeout_policy.timeout_frames,
        }
    end
    local elapsed = current_engine_frame - last_activity_frame
    if elapsed < 0 then return nil, "engine_frame_rewind" end
    if elapsed < self.attempt.timeout_policy.timeout_frames then
        return {
            mode = AtomicDetector.MODE,
            status = "progress",
            match = nil,
            timed_out = false,
            last_activity_frame = last_activity_frame,
            timeout_frames = self.attempt.timeout_policy.timeout_frames,
            elapsed_frames = elapsed,
        }
    end
    self.attempt.terminal = true
    local _, report = AtomicDetector.compare(
        self.loaded:trace(), self.attempt.trace)
    if report == nil then
        self.attempt.terminal = false
        return nil, "detector_failed"
    end
    report.status = report.match == true and "passed" or "failed"
    report.timed_out = true
    report.timeout_frames = self.attempt.timeout_policy.timeout_frames
    report.elapsed_frames = elapsed
    self.last_result = report
    return self.last_result
end

function Runtime:should_collect_sample(player_index)
    local _, player_error = normalize_player_index(player_index)
    if player_error ~= nil then return false end
    if self.recording ~= nil then
        if self.recording.player_index == nil or self.recording.player_index == player_index then
            return true
        end
    end
    if self.loaded ~= nil then
        return true
    end
    return false
end

function Runtime:attempt_trace()
    return self.attempt and self.attempt.trace or nil
end

function Runtime:display_trace(is_recording)
    if is_recording and self.recording ~= nil then return self.recording.trial:trace() end
    if self.loaded ~= nil then return self.loaded:trace() end
    return nil
end

function Runtime:diagnostic(context)
    local output = type(context) == "table" and context or {}
    output.raw_stage1_status = self.load_status
    output.raw_stage1_error = self.load_error
    output.detector = self.last_result
    if self.attempt ~= nil then
        output.attempt_timeout_policy = self.attempt.timeout_policy
    end
    output.expected = self.loaded and self.loaded:trace():to_payload() or nil
    output.actual = self.attempt and self.attempt.trace:to_payload() or nil
    return output
end

return Stage1Runtime
