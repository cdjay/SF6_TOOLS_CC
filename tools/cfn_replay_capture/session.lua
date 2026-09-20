local M = {}

function M.new(schema, options)
    options = options or {}
    local limit = options.limit or 36000
    assert(type(limit) == "number" and limit >= 1 and limit <= 120000 and limit % 1 == 0)
    local s = {
        schema = schema.version, columns = schema.columns, samples = {},
        metadata = false, state = "waiting", stop_reason = false,
        requested_speed = options.speed or "unspecified", sample_limit = limit,
        created_at = options.created_at or "unknown", issues = {}, issue_counts = {},
        missing_columns = {}, duplicate_clocks = 0, render_tick_max_samples = 0,
        thread_transition_count = 0,
        validation = "pending_live_comparison", full_replay_verified = false,
        round_scope = options.round_scope, stop_at_finish = options.stop_at_finish == true,
    }
    local previous, render_tick, render_count
    local index = schema.index

    function s:is_active() return self.state == "waiting" or self.state == "capturing" end

    function s:issue(kind, detail)
        self.issue_counts[kind] = (self.issue_counts[kind] or 0) + 1
        if #self.issues < 64 then
            self.issues[#self.issues + 1] = { kind = kind, at_sample = #self.samples + 1, detail = detail }
        end
    end

    function s:stop(reason)
        if self:is_active() then self.state, self.stop_reason = "stopped", reason end
    end

    function s:fail(reason, detail)
        if not self:is_active() then return end
        self:issue(reason, tostring(detail or reason):sub(1, 400))
        self.state, self.stop_reason = "stopped", reason
    end

    function s:add(metadata, values)
        if not self:is_active() then return false end
        if #self.samples >= self.sample_limit then self:fail("capacity", self.sample_limit); return false end
        if type(metadata) ~= "table" or type(metadata.replay_id) ~= "string" or metadata.replay_id == "" then
            self:fail("missing_identity"); return false
        end
        if self.metadata and self.metadata.replay_id ~= metadata.replay_id then
            self:fail("replay_changed"); return false
        end
        local row = {}
        for i, name in ipairs(schema.columns) do
            local value = values[name]
            if value == nil then value = false end
            if value ~= false and (type(value) ~= "number" or value ~= value or math.abs(value) == math.huge) then
                self:fail("invalid_value", name); return false
            end
            row[i] = value
        end
        for _, name in ipairs({ "round", "replay_frame", "battle_round", "stage_frame", "thread_id", "render_tick" }) do
            local v = row[index[name]]
            if type(v) ~= "number" or v % 1 ~= 0 or v < 0 then
                self:fail("invalid_clock", name); return false
            end
        end
        local round, frame, stage = row[index.round], row[index.replay_frame], row[index.stage_frame]
        if self.round_scope ~= nil and (round ~= self.round_scope or row[index.battle_round] ~= self.round_scope) then
            self:stop("round_boundary"); return false
        end
        if previous then
            if row[index.thread_id] ~= previous[index.thread_id] then
                self.thread_transition_count = self.thread_transition_count + 1
            end
            local pr = previous[index.round]
            local pf, ps = previous[index.replay_frame], previous[index.stage_frame]
            if round < pr or (round == pr and (frame < pf or stage < ps)) then
                self:issue("rewind_or_reset", { round = round, frame = frame, stage = stage })
            elseif round > pr then
                if round > pr + 1 then self:issue("round_gap", { from = pr, to = round }) end
            else
                if frame > pf + 1 then self:issue("replay_clock_gap", { from = pf, to = frame }) end
                if stage > ps + 1 then self:issue("stage_clock_gap", { from = ps, to = stage }) end
                if frame == pf and stage == ps then self.duplicate_clocks = self.duplicate_clocks + 1 end
            end
        else
            self.metadata = metadata
            self.first_clock = { round = round, replay_frame = frame, stage_frame = stage }
        end
        for i, name in ipairs(schema.columns) do
            if row[i] == false then self.missing_columns[name] = (self.missing_columns[name] or 0) + 1 end
        end
        local tick = row[index.render_tick]
        if render_tick == tick then render_count = render_count + 1 else render_tick, render_count = tick, 1 end
        self.render_tick_max_samples = math.max(self.render_tick_max_samples, render_count)
        self.state = "capturing"
        self.samples[#self.samples + 1] = row
        previous = row
        if self.stop_at_finish then
            local hp1, hp2 = row[index["p1.vital_new"]], row[index["p2.vital_new"]]
            local timer, part = row[index.play_timer], row[index.play_timer_ms]
            if type(hp1) ~= "number" or type(hp2) ~= "number" or type(timer) ~= "number" or type(part) ~= "number" then
                self:fail("missing_finish_state")
            elseif hp1 <= 0 or hp2 <= 0 then
                self:stop("knockout")
            elseif timer == 0 and part == 0 then
                self:stop("time_up")
            end
        end
        return true
    end

    function s:export()
        assert(not self:is_active(), "stop before export")
        local out = {}
        for key, value in pairs(self) do if type(value) ~= "function" then out[key] = value end end
        out.sample_count = #self.samples
        return out
    end
    return s
end

return M
