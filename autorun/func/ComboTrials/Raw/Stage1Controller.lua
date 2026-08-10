local Stage1Controller = {
    name = "ComboTrials.Raw.Stage1Controller",
}

local RawCatalog = require("func/ComboTrials/Raw/RawCatalog")
local RawActionBoundary = require("func/ComboTrials/Raw/RawActionBoundary")
local RawInstructionList = require("func/ComboTrials/Raw/RawInstructionList")
local RawV2Sequence = require("func/ComboTrials/Raw/RawV2Sequence")
local Stage1Runtime = require("func/ComboTrials/Raw/Stage1Runtime")

local Controller = {}
Controller.__index = Controller

local function control_profile(control_mode)
    return control_mode == "modern" and "easy" or "norm"
end

local function clone(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, item in pairs(value) do copy[key] = clone(item) end
    return copy
end

local function valid_fighter_id(value)
    return type(value) == "number" and value % 1 == 0 and value >= 1
end

local function valid_player_index(value)
    return value == 0 or value == 1
end

function Stage1Controller.new(options)
    options = type(options) == "table" and options or {}
    if type(options.trial_state) ~= "table" then return nil, "trial_state_required" end
    if type(options.target_game_version) ~= "string" or options.target_game_version == "" then
        return nil, "target_game_version_required"
    end
    local controller = setmetatable({
        trial_state = options.trial_state,
        target_game_version = options.target_game_version,
        raw_catalog = options.raw_catalog or RawCatalog,
        instruction_list = options.instruction_list or RawInstructionList,
        runtime = options.runtime or Stage1Runtime.new(),
        catalog = nil,
        catalog_status = nil,
        boundaries = {},
        recording_step_facts = nil,
        recording_observation = nil,
        terminal_result_applied = false,
        get_context = options.get_context,
        write_json = options.write_json,
        ticker = options.ticker,
    }, Controller)
    controller:_reset_visible_state("legacy", nil)
    return controller
end

function Controller:_reset_visible_state(status, code)
    local state = self.trial_state
    state._raw_stage1_status = status
    state._raw_stage1_error = code
    state._raw_stage1_diagnostic = nil
    state._raw_stage1_catalog = self.catalog
    state._raw_stage1_catalog_status = self.catalog_status
    state._raw_stage1_rows = nil
    state._raw_stage1_visual_step = nil
    state._raw_stage1_terminal = nil
end

function Controller:_set_error(status, code)
    self.trial_state._raw_stage1_status = status
    self.trial_state._raw_stage1_error = code
    return nil, status, code
end

function Controller:_load_catalog(fighter_id)
    if not valid_fighter_id(fighter_id) then
        return self:_set_error("catalog_error", "invalid_fighter_id")
    end
    local catalog, status = self.raw_catalog.load({
        dir = self.raw_catalog.DIRECTORY,
        fighter_id = fighter_id,
        expected_display_version = self.target_game_version,
    })
    self.catalog = catalog
    self.catalog_status = status
    self.trial_state._raw_stage1_catalog = catalog
    self.trial_state._raw_stage1_catalog_status = status
    if catalog == nil then
        return self:_set_error("catalog_error",
            status and status.message or "raw_catalog_unavailable")
    end
    local build = catalog:get_build_info()
    _G.SF6CC_RAW_CURRENT_BUILD_UID = build.build_uid
    return catalog
end

function Controller:_audit(preferred_profile, row_count, no_direct_count)
    if self.catalog == nil then return end
    local audit = clone(self.catalog:get_audit_info())
    audit.schema = "sf6cc.raw_stage1.runtime_audit.v1"
    audit.artifact_loaded = true
    audit.current_control_profile = preferred_profile
    audit.atomic_trace_count = row_count
    audit.direct_binding_miss_count = audit.reconciliation
        and audit.reconciliation.direct_binding_miss_count or nil
    audit.no_direct_binding_count = no_direct_count
    audit.detector_first_divergence = self.trial_state._raw_stage1_diagnostic
        and self.trial_state._raw_stage1_diagnostic.detector
        and self.trial_state._raw_stage1_diagnostic.detector.first_divergence or nil
    _G.SF6CC_RAW_STAGE1_AUDIT = audit
end

function Controller:refresh_rows(preferred_profile)
    local trace = self.runtime:display_trace(self.trial_state.is_recording == true)
    if trace == nil or self.catalog == nil then
        self.trial_state._raw_stage1_rows = nil
        return nil
    end
    local rows, rows_error = self.instruction_list.build_rows(trace, self.catalog, preferred_profile)
    self.trial_state._raw_stage1_rows = rows
    if rows == nil then
        self.trial_state._raw_stage1_error = rows_error
        return nil, rows_error
    end
    local no_direct_count = 0
    for _, row in ipairs(rows) do
        if row.status == self.instruction_list.NO_DIRECT_BCM_BINDING then
            no_direct_count = no_direct_count + 1
        end
    end
    self:_audit(preferred_profile, #rows, no_direct_count)
    return rows
end

function Controller:install_sequence(sequence)
    local first = type(sequence) == "table" and sequence[1] or nil
    local meta = type(first) == "table" and first._xt_meta or nil
    local loaded, status, code = self.runtime:load_meta(meta)
    self.catalog = nil
    self.catalog_status = nil
    self.boundaries = {}
    self.terminal_result_applied = false
    self:_reset_visible_state(status, code)
    if status == "legacy" then return nil, status end
    if loaded == nil then return self:_set_error("invalid", code or "invalid_raw_stage1") end

    local environment = loaded:environment()
    if not valid_fighter_id(environment.fighter_id)
        or type(environment.game_build) ~= "string" or environment.game_build == ""
        or type(environment.control_mode) ~= "string" or environment.control_mode == ""
        or type(environment.recorded_at) ~= "string" or environment.recorded_at == "" then
        return self:_set_error("invalid", "raw_trial_environment_incomplete")
    end
    local catalog = self:_load_catalog(environment.fighter_id)
    if catalog == nil then return nil, "catalog_error", self.trial_state._raw_stage1_error end
    local character = catalog:get_character()
    local build = catalog:get_build_info()
    if character.character ~= environment.character then
        self.catalog = nil
        self.trial_state._raw_stage1_catalog = nil
        return self:_set_error("catalog_error", "raw_trial_character_mismatch")
    end
    if build.build_uid ~= environment.game_build then
        self.catalog = nil
        self.trial_state._raw_stage1_catalog = nil
        return self:_set_error("catalog_error", "raw_trial_build_mismatch")
    end
    self.trial_state._raw_stage1_status = "loaded"
    self.trial_state._raw_stage1_error = nil
    self:refresh_rows(control_profile(environment.control_mode))
    return loaded, "loaded"
end

function Controller:prepare_recording(fighter_id)
    local catalog = self:_load_catalog(fighter_id)
    if catalog == nil and type(self.ticker) == "function" then
        pcall(self.ticker, "Raw Catalog 加载失败，录制未开始", 0.4)
    end
    return catalog
end

function Controller:begin_recording(character, options)
    if self.catalog == nil then return self:_set_error("catalog_error", "raw_catalog_unavailable") end
    options = type(options) == "table" and options or {}
    if not valid_player_index(options.player_index) then
        return self:_set_error("invalid", "invalid_player_index")
    end
    local catalog_character = self.catalog:get_character()
    if catalog_character.fighter_id ~= options.fighter_id then
        return self:_set_error("catalog_error", "recording_fighter_mismatch")
    end
    local build = self.catalog:get_build_info()
    options.game_build = build.build_uid
    options.start_gate = "explicit"
    options.recorded_at = options.recorded_at or os.date("!%Y-%m-%dT%H:%M:%SZ")
    local trial, trial_error = self.runtime:begin_recording(character, options)
    self.boundaries[options.player_index] = RawActionBoundary.new(
        options.initial_action_id, options.initial_action_frame)
    self.recording_step_facts = {}
    self.recording_observation = {
        sample_count = 0,
        boundary_count = 0,
        invalid_sample_count = 0,
    }
    self.terminal_result_applied = false
    self.trial_state._raw_stage1_status = trial and "recording" or "invalid"
    self.trial_state._raw_stage1_error = trial_error
    self.trial_state._raw_stage1_diagnostic = nil
    self.trial_state._raw_stage1_rows = {}
    return trial, trial_error
end

function Controller:cancel_recording()
    self.runtime:cancel_recording()
    self.recording_step_facts = nil
    self.boundaries = {}
    self.terminal_result_applied = false
    self.trial_state._raw_stage1_status = "legacy"
    self.trial_state._raw_stage1_error = nil
    self.trial_state._raw_stage1_diagnostic = nil
    self.trial_state._raw_stage1_rows = nil
end

function Controller:finish_recording(preferred_profile)
    local trial, trial_error = self.runtime:finish_recording()
    self.trial_state._raw_stage1_status = trial and "recorded" or "invalid"
    self.trial_state._raw_stage1_error = trial_error
    if trial ~= nil then self:refresh_rows(preferred_profile) end
    return trial, trial_error
end

function Controller:attach_last_recording(xt_meta, options)
    return self.runtime:attach_last_recording(xt_meta, options)
end

function Controller:build_v2_sequence()
    local trial = self.runtime:last_recorded_trial()
    if trial == nil then return nil, "recording_not_finalized" end
    return RawV2Sequence.build(trial:trace(), self.recording_step_facts)
end

function Controller:write_save_diagnostic(code, context)
    context = type(context) == "table" and clone(context) or {}
    context.schema = "sf6cc.raw_stage1.diagnostic.v1"
    context.failure_phase = "save"
    context.failure_code = tostring(code or "save_failed")
    context.game_build = rawget(_G, "SF6CC_RAW_CURRENT_BUILD_UID")
    local diagnostic = self.runtime:diagnostic(context)
    diagnostic.artifact = self.catalog and self.catalog:get_audit_info() or nil
    diagnostic.raw_rows = clone(self.trial_state._raw_stage1_rows)
    diagnostic.controller_status = self.trial_state._raw_stage1_status
    diagnostic.recording_observation = clone(self.recording_observation)
    self.trial_state._raw_stage1_diagnostic = diagnostic
    _G.SF6CC_RAW_STAGE1_DIAGNOSTIC = diagnostic
    if type(self.write_json) == "function" then
        pcall(self.write_json,
            "TrainingComboTrials_data/LastRawStage1Diagnostic.json", diagnostic)
    end
    return diagnostic
end

function Controller:blocks_legacy_detector()
    local status = self.trial_state._raw_stage1_status
    return status ~= nil and status ~= "legacy"
end

function Controller:begin_attempt(engine_frame, player_index,
    initial_action_id, initial_action_frame)
    local status = self.trial_state._raw_stage1_status
    if (status ~= "loaded" and status ~= "recorded") or self.catalog == nil then
        return nil, self.trial_state._raw_stage1_status or "legacy"
    end
    if not valid_player_index(player_index) then return nil, "invalid_player_index" end
    self.boundaries = { [player_index] = RawActionBoundary.new(
        initial_action_id, initial_action_frame) }
    self.terminal_result_applied = false
    return self.runtime:begin_attempt({
        start_gate = "explicit",
        player_index = player_index,
        start_engine_frame = engine_frame,
        initial_action_id = initial_action_id,
        initial_action_frame = initial_action_frame,
    })
end

function Controller:should_collect_sample(player_index)
    local state = self.trial_state
    if state.is_recording and player_index == state.recording_player then return true end
    return state.is_playing and player_index == state.playing_player
        and (state._raw_stage1_status == "loaded"
            or state._raw_stage1_status == "recorded")
end

function Controller:_diagnostic(result, context)
    context = type(context) == "table" and clone(context) or {}
    context.schema = "sf6cc.raw_stage1.diagnostic.v1"
    context.game_build = rawget(_G, "SF6CC_RAW_CURRENT_BUILD_UID")
    local diagnostic = self.runtime:diagnostic(context)
    diagnostic.artifact = self.catalog and self.catalog:get_audit_info() or nil
    local divergence = result and result.first_divergence
    local expected_id = divergence and divergence.expected and divergence.expected.action_id or nil
    local actual_id = divergence and divergence.actual and divergence.actual.action_id or nil
    diagnostic.expected_direct_bindings = expected_id and self.catalog
        and self.catalog:get_bindings_snapshot(expected_id) or nil
    diagnostic.actual_direct_bindings = actual_id and self.catalog
        and self.catalog:get_bindings_snapshot(actual_id) or nil
    self.trial_state._raw_stage1_diagnostic = diagnostic
    _G.SF6CC_RAW_STAGE1_DIAGNOSTIC = diagnostic
    if type(self.write_json) == "function" then
        pcall(self.write_json, "TrainingComboTrials_data/LastRawStage1Diagnostic.json", diagnostic)
    end
    return diagnostic
end

function Controller:_apply_attempt_result(result, context)
    if type(result) ~= "table" then return end
    local state = self.trial_state
    if self.terminal_result_applied
        and (result.status == "passed" or result.status == "failed") then
        return
    end
    local raw_count = type(state._raw_stage1_rows) == "table"
        and #state._raw_stage1_rows or 0
    if result.status == "progress" then
        local step = math.max(1, (tonumber(result.actual_count) or 0) + 1)
        state._raw_stage1_visual_step = math.min(step, math.max(1, raw_count))
        state._raw_stage1_terminal = nil
    elseif result.status == "passed" then
        self.terminal_result_applied = true
        state._raw_stage1_visual_step = raw_count + 1
        state._raw_stage1_terminal = "passed"
        state.success_timer = (context and context.fail_display_frames) or 120
    elseif result.status == "failed" then
        self.terminal_result_applied = true
        state._raw_stage1_terminal = "failed"
        if (state.fail_timer or 0) == 0 and not state.manual_reset_pending then
            state.fail_timer = (context and context.fail_display_frames) or 120
            state.fail_reason = result.first_divergence
                and result.first_divergence.reason == "missing_expected"
                and "RAW ACTION MISSING" or "RAW ACTION DIVERGENCE"
            self:_diagnostic(result, context)
        end
    end
end

function Controller:observe_frame(player_index, engine_frame, action_id, action_frame,
    direct_input, direction_input, facing_right)
    if not self:should_collect_sample(player_index) then return nil, "inactive" end
    local state = self.trial_state
    local sample = {
        player_index = player_index,
        engine_frame = engine_frame,
        action_id = action_id,
        action_frame = action_frame,
        direct_input = direct_input,
        direction_input = direction_input,
        facing_right = facing_right,
    }
    if state.is_recording then
        local observation = self.recording_observation or {
            sample_count = 0,
            boundary_count = 0,
            invalid_sample_count = 0,
        }
        observation.sample_count = observation.sample_count + 1
        observation.last_sample = {
            engine_frame = engine_frame,
            action_id = action_id,
            action_frame = action_frame,
        }
        if observation.first_sample == nil then
            observation.first_sample = clone(observation.last_sample)
        end
        self.recording_observation = observation
    end
    local context = type(self.get_context) == "function"
        and self.get_context(player_index) or {}
    local boundary = self.boundaries[player_index]
    if boundary == nil then
        boundary = RawActionBoundary.new()
        self.boundaries[player_index] = boundary
    end
    local boundary_result, boundary_error = boundary:observe(sample)
    if boundary_result == nil then
        if state.is_recording and self.recording_observation ~= nil then
            self.recording_observation.invalid_sample_count =
                self.recording_observation.invalid_sample_count + 1
            self.recording_observation.last_error = boundary_error
        end
        return nil, boundary_error
    end
    if state.is_recording and self.recording_observation ~= nil
        and boundary_result.active == true then
        self.recording_observation.boundary_count =
            self.recording_observation.boundary_count + 1
        self.recording_observation.last_boundary_reason = boundary_result.reason
    end
    sample.active = boundary_result.active
    sample.restart = boundary_result.restart
    if state.is_recording then
        local observed, observe_error = self.runtime:observe_recording(sample)
        if observed == nil then
            state._raw_stage1_error = observe_error
            if self.recording_observation ~= nil then
                self.recording_observation.last_error = observe_error
            end
        else
            local step = tonumber(observed.step)
            local combo_count = tonumber(context.current_combo)
            if step ~= nil and step % 1 == 0 and step >= 1
                and combo_count ~= nil and combo_count % 1 == 0
                and combo_count >= 0 then
                self.recording_step_facts = self.recording_step_facts or {}
                local fact = self.recording_step_facts[step] or {}
                fact.expected_combo = math.max(
                    tonumber(fact.expected_combo) or 0, combo_count)
                self.recording_step_facts[step] = fact
            end
            if observed.new_instance == true then
                self:refresh_rows(control_profile(context.control_mode))
            end
        end
        return observed, observe_error
    end

    local result, observe_error = self.runtime:observe_attempt(sample)
    if result == nil then
        state._raw_stage1_error = observe_error
        return nil, observe_error
    end
    if result.status == "progress" then
        local timeout_result = self.runtime:attempt_inactivity_timeout(engine_frame)
        if type(timeout_result) == "table" and timeout_result.status ~= "progress" then
            result = timeout_result
        end
    end
    self:_apply_attempt_result(result, context)
    return result
end

return Stage1Controller
