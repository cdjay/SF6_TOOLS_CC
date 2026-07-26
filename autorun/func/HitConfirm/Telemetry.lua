local Transport = require("func/Training_Telemetry")
local SF6CCVersion = require("func/SF6CC_Version")

local Telemetry = {}
Telemetry.__index = Telemetry

Telemetry.ATTEMPT_SCHEMA = "sf6cc.hit_confirm_attempt.v1"
Telemetry.SESSION_SCHEMA = "sf6cc.hit_confirm_session.v1"
Telemetry.OUTPUT_DIR = "SF6_TrainingRemoteControl_data/HitConfirmTelemetry"
Telemetry.OUTPUT_FILE = Telemetry.OUTPUT_DIR .. "/events.jsonl"
Telemetry.MOD_VERSION = SF6CCVersion.PRODUCT_VERSION

local function case_identity(case)
    local followups = {}
    for _, followup in ipairs(case.followups or {}) do
        followups[#followups + 1] = {
            id = followup.id,
            command = followup.command,
            label = followup.label,
            action_ids = followup.action_ids,
            derived = followup.derived == true
        }
    end
    return {
        case_id = case.id,
        revision = case.revision,
        title = case.title,
        character = case.character,
        starter = {
            command = case.starter.command,
            label = case.starter.label,
            action_ids = case.starter.action_ids
        },
        followups = followups
    }
end

function Telemetry.new()
    return setmetatable({ session = nil, last_error = nil }, Telemetry)
end

function Telemetry:_append(event)
    local ok, err = Transport.append_jsonl(Telemetry.OUTPUT_FILE, event, {
        "SF6_TrainingRemoteControl_data",
        Telemetry.OUTPUT_DIR
    })
    self.last_error = ok and nil or err
    if not ok then pcall(print, "[HitConfirm.Telemetry] append failed: " .. tostring(err)) end
    return ok, err
end

function Telemetry:begin_session(case, context)
    context = type(context) == "table" and context or {}
    self.session = {
        id = Transport.new_id("hc-session"),
        started_at = Transport.iso8601_utc(),
        case = case_identity(case),
        context = {
            control_mode = context.control_mode or "unknown",
            player_character_id = context.player_character_id,
            player_character_key = context.player_character_key,
            session_mode = context.session_mode,
            target_attempts = context.target_attempts,
            target_seconds = context.target_seconds
        },
        attempt_sequence = 0
    }
    return self.session.id
end

function Telemetry:record_attempt(case, result, context)
    if not self.session then self:begin_session(case, context) end
    self.session.attempt_sequence = self.session.attempt_sequence + 1
    local event = {
        schema = Telemetry.ATTEMPT_SCHEMA,
        event_id = Transport.new_id("hc-attempt"),
        event_type = "attempt_completed",
        anonymous = true,
        occurred_at = Transport.iso8601_utc(),
        session_id = self.session.id,
        attempt_sequence = self.session.attempt_sequence,
        case = self.session.case,
        runtime = {
            sf6cc_version = Telemetry.MOD_VERSION,
            control_mode = (context and context.control_mode) or self.session.context.control_mode,
            source = "manual"
        },
        opponent = { strategy = case.opponent_strategy and case.opponent_strategy.id or "random_guard" },
        result = {
            stimulus = result.stimulus,
            decision = result.decision,
            correct = result.correct,
            failure_code = result.failure_code,
            decision_frames = result.decision_frames,
            elapsed_frames = result.elapsed_frames,
            followup_id = result.followup_id,
            followup_command = result.followup_command,
            followup_action_id = result.followup_action_id
        }
    }
    return self:_append(event)
end

function Telemetry:finish_session(case, summary, reason, context)
    if not self.session then return false, "no active session" end
    local event = {
        schema = Telemetry.SESSION_SCHEMA,
        event_id = Transport.new_id("hc-summary"),
        event_type = "session_completed",
        anonymous = true,
        occurred_at = Transport.iso8601_utc(),
        started_at = self.session.started_at,
        session_id = self.session.id,
        completion_reason = reason or "stopped",
        case = self.session.case or case_identity(case),
        runtime = {
            sf6cc_version = Telemetry.MOD_VERSION,
            control_mode = (context and context.control_mode) or self.session.context.control_mode,
            source = "manual"
        },
        opponent = { strategy = case.opponent_strategy and case.opponent_strategy.id or "random_guard" },
        session = self.session.context,
        summary = summary
    }
    local ok, err = self:_append(event)
    self.session = nil
    return ok, err
end

function Telemetry:discard_session()
    self.session = nil
end

return Telemetry
