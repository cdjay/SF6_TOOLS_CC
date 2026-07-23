-- Pure case-driven hit-confirm state machine. It has no REFramework dependency
-- and can be exercised by tools/test_hit_confirm_engine.lua.

local Engine = {}
Engine.__index = Engine

local function contains(set, value)
    return type(set) == "table" and set[tonumber(value)] == true
end

function Engine.new(case)
    local self = setmetatable({}, Engine)
    self:set_case(case)
    return self
end

function Engine:set_case(case)
    self.case = assert(case, "hit-confirm case is required")
    self:reset()
end

function Engine:reset()
    self.phase = "waiting"
    self.context = nil
    self.starter_frame = 0
    self.contact_frame = 0
    self.followup_frame = nil
    self.followup = nil
    self.followup_action_id = nil
    self.neutral_frames = 0
end

function Engine:_result(sample, correct, failure_code, decision)
    local result = {
        stimulus = self.context,
        correct = correct == true,
        failure_code = failure_code,
        decision = decision,
        decision_frames = self.followup_frame and math.max(0, self.followup_frame - self.contact_frame) or nil,
        elapsed_frames = math.max(0, (tonumber(sample.frame) or 0) - self.contact_frame),
        followup_id = self.followup and self.followup.id or nil,
        followup_command = self.followup and self.followup.command or nil,
        followup_action_id = self.followup_action_id
    }
    self.phase = "cooldown"
    self.neutral_frames = 0
    return result
end

function Engine:step(sample)
    sample = type(sample) == "table" and sample or {}
    local action_id = tonumber(sample.action_id) or -1
    local frame = tonumber(sample.frame) or 0
    local rules = self.case.rules

    if self.phase == "cooldown" then
        local is_case_action = contains(self.case._starter_ids, action_id) or contains(self.case._followup_ids, action_id)
        if not is_case_action and (tonumber(sample.hit_stop) or 0) <= 0 and (tonumber(sample.combo_count) or 0) <= 0 then
            self.neutral_frames = self.neutral_frames + 1
            if self.neutral_frames >= rules.neutral_reset_frames then self:reset() end
        else
            self.neutral_frames = 0
        end
        return nil
    end

    if self.phase == "waiting" then
        if not contains(self.case._starter_ids, action_id) then return nil end
        self.phase = "starter"
        self.starter_frame = frame
    end

    if self.phase == "starter" then
        if sample.contact == "hit" or sample.contact == "block" then
            self.phase = "decision"
            self.context = sample.contact
            self.contact_frame = frame
        elseif not contains(self.case._starter_ids, action_id) then
            self:reset()
            return nil
        end
    end

    if self.phase ~= "decision" and self.phase ~= "followup" then return nil end

    local followup = self.case._followup_by_action[action_id]
    if followup and not self.followup then
        self.followup = followup
        self.followup_frame = frame
        self.followup_action_id = action_id
        if self.context == "block" then
            return self:_result(sample, false, "blocked_misconfirm", "followup")
        end
        self.phase = "followup"
    end

    local elapsed = math.max(0, frame - self.contact_frame)
    if self.context == "hit" then
        if self.followup and (tonumber(sample.combo_count) or 0) >= rules.minimum_combo_count then
            return self:_result(sample, true, nil, "followup")
        end
        local timed_out = self.followup
            and math.max(0, frame - self.followup_frame) >= rules.followup_hit_frames
            or (not self.followup and elapsed >= rules.hit_confirm_frames)
        if timed_out then
            return self:_result(sample, false, self.followup and "followup_did_not_combo" or "missed_confirm",
                self.followup and "followup" or "hold")
        end
    elseif self.context == "block" and elapsed >= rules.block_confirm_frames then
        return self:_result(sample, true, nil, "hold")
    end
    return nil
end

function Engine:get_phase()
    return self.phase
end

return Engine
