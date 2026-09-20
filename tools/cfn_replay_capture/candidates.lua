-- Conservative review candidates, not move reach or guaranteed punish verdicts.
-- ACT_ST and fresh ENDSTUN cells are evidence scoped to build 20004000.
local M = {}
local exits = {[0]=true,[1]=true,[3]=true,[4]=true,[5]=true,[6]=true,[8]=true,[9]=true,
    [10]=true,[29]=true,[30]=true,[31]=true}
local function number(n) return type(n) == "number" and n == n and math.abs(n) < math.huge end

function M.new(schema, metadata, round)
    if not metadata or metadata.version ~= 20004000 or metadata.frame_meter_profile ~= "native_cursor_cell_v1" then
        return nil, "unsupported_analysis"
    end
    local ix, previous, guards, windows = schema.index, nil, {}, {}
    local d = {items = {}, round = round, replay_id = metadata.replay_id, gaps = 0, excluded = 0, rows = 0}
    local function value(r, name) return r and r[ix[name]] end
    local function p(r, side, name) return value(r, "p" .. side .. "." .. name) end
    local function close(side, reason)
        local w = windows[side]
        if not w then return end
        -- Four observed cells at an incomplete boundary must not be called an exact four-frame window.
        if w.frames >= 5 or w.frames == 4 and reason == "recovery_end" then
            w.kind = w.frames == 4 and "four_frame_boundary" or "five_plus_punish_candidate"
            w.end_reason, w.lower_bound = reason, reason ~= "recovery_end"
            w.reach_verified, w.actionable_verified = false, false
            d.items[#d.items + 1] = w
        else d.excluded = d.excluded + 1 end
        windows[side] = nil
    end
    local function fresh(r, before, side)
        if value(r, "display_prev_frame") ~= value(r, "stage_frame")
            or value(before, "display_prev_frame") ~= value(before, "stage_frame")
            or not number(value(r, "meter_start_frame"))
            or value(r, "meter_start_frame") ~= value(before, "meter_start_frame") then return false end
        for _, row in ipairs({before, r}) do
            local cursor = p(row, side, "display_meter_index")
            if p(row, side, "display_meter_size") ~= 80 or not number(cursor)
                or cursor < 0 or cursor >= 80 or cursor % 1 ~= 0 then return false end
        end
        for _, flag in ipairs({"empty", "changed", "end", "not_add", "not_whole"}) do
            local n = p(r, side, "display_meter_" .. flag)
            if n ~= 0 and n ~= 1 then return false end
        end
        local kind = p(r, side, "display_meter_type")
        return number(kind) and kind % 1 == 0 and kind >= 0 and kind <= 14
            and p(r, side, "display_meter_empty") == 0 and p(r, side, "display_meter_not_add") == 0
            and p(r, side, "display_meter_not_whole") == 0
            and p(r, side, "display_meter_index") == (p(before, side, "display_meter_index") + 1) % 80
    end
    local function unchanged_action(a, b, side)
        for _, name in ipairs({"action_id", "engine_style_index", "engine_loop_count"}) do
            if not number(p(b, side, name)) or p(a, side, name) ~= p(b, side, name) then return false end
        end
        return number(p(a, side, "action_frame_raw")) and number(p(b, side, "action_frame_raw"))
            and p(b, side, "action_frame_raw") >= p(a, side, "action_frame_raw")
    end
    function d:add(r)
        if self.finished then return end
        local frame, stage = value(r, "replay_frame"), value(r, "stage_frame")
        if value(r, "round") ~= round or value(r, "battle_round") ~= round then
            self:finish("round_boundary"); return
        end
        if not number(frame) or not number(stage) then self:finish("invalid_clock"); return end
        local contiguous = previous and frame == value(previous, "replay_frame") + 1
            and stage == value(previous, "stage_frame") + 1
        if previous and frame == value(previous, "replay_frame") and stage == value(previous, "stage_frame") then
            for i, name in ipairs(schema.columns) do
                if name ~= "render_tick" and name ~= "thread_id" and name ~= "update_result" and r[i] ~= previous[i] then
                    self.items = {}; self:finish("conflicting_samples"); self.items = {}; return
                end
            end
            return
        end
        if previous and (frame < value(previous, "replay_frame") or stage < value(previous, "stage_frame")) then
            self.items = {}; self:finish("rewound_capture"); self.items = {}; return
        end
        if not contiguous or value(r, "fight_st") ~= value(previous, "fight_st") then
            for side = 1, 2 do close(side, "data_gap"); guards[side] = nil end
            if previous then self.gaps = self.gaps + 1 end
            contiguous = false
        end
        for side = 1, 2 do
            local opponent = 3 - side
            local guard = p(r, side, "act_st") == 27 and number(p(r, side, "guard_time")) and p(r, side, "guard_time") > 0
            if not guard and guards[side] then
                if contiguous and guards[side].observed and p(previous, side, "guard_time") == 1
                    and p(r, side, "guard_time") == 0 and exits[p(r, side, "act_st")]
                    and p(r, side, "y_raw") == 0 and p(r, side, "hit_stop") == 0
                    and p(r, side, "vital_new") == p(previous, side, "vital_new") then
                    local x1, x2 = p(r, 1, "x_raw"), p(r, 2, "x_raw")
                    windows[side] = {frame = frame, last_frame = frame, frames = 0, defender = side,
                        opponent = opponent, round = round, replay_id = metadata.replay_id,
                        distance = number(x1) and number(x2) and math.abs(x1 - x2) / 65536 or nil}
                end
                guards[side] = nil
            end
            if guard and not guards[side] then guards[side] = {observed = contiguous == true} end
            local w = windows[side]
            if w then
                local valid = contiguous and p(r, side, "guard_time") == 0 and exits[p(r, side, "act_st")]
                    and p(r, side, "y_raw") == 0
                for s = 1, 2 do
                    valid = valid and p(r, s, "hit_stop") == 0 and number(p(r, s, "vital_new"))
                        and p(r, s, "vital_new") == p(previous, s, "vital_new")
                end
                if not valid then close(side, "new_reaction")
                elseif not fresh(r, previous, opponent) then close(side, "unverified_cell")
                elseif p(r, opponent, "display_meter_type") ~= 8 then close(side, "recovery_end")
                elseif w.frames > 0 and not unchanged_action(previous, r, opponent) then close(side, "action_changed")
                else w.frames, w.last_frame = w.frames + 1, frame end
            end
        end
        previous, self.rows = r, self.rows + 1
    end
    function d:finish(reason)
        if self.finished then return self.items end
        for side = 1, 2 do close(side, reason or "capture_end") end
        self.finished, self.reason = true, reason
        table.sort(self.items, function(a, b) return a.frame < b.frame or a.frame == b.frame and a.defender < b.defender end)
        return self.items
    end
    return d
end
return M
