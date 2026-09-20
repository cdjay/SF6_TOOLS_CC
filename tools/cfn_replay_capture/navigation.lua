local M = {}
local function integer(n) return type(n) == "number" and n >= 0 and n % 1 == 0 and n <= 1000000 end
local tiers = {
    { positive = "step", negative = "back", estimate = 1 },
    { positive = "medium_forward", negative = "medium_back", estimate = 8 },
    { positive = "forward", negative = "rewind", estimate = 300 },
}

function M.attach(deps, state, controls)
    local n = { status = "idle", active = false, history = {} }
    local now = deps.now or os.clock
    local function stop(status, reason)
        n.active, n.status, n.reason = false, status, reason
        controls:release(n)
        n.elapsed = n.started_at and math.max(0, now() - n.started_at) or 0
        if n.started_at then
            local result = {status = status, reason = reason, stable_frames = n.stable_frames, round = n.round,
                start_frame = n.start_frame, target = n.target, current = n.current, seconds = n.elapsed,
                presses = n.steps, render_ticks = state.render_tick - n.started_tick,
                prepare_ticks = n.timing.prepare, release_ticks = n.timing.release, confirm_ticks = n.timing.confirm,
                press_ms = n.press_ms, held_ms = n.held_ms, held_samples = n.held_samples}
            table.insert(n.history, 1, result)
            if #n.history > 12 then table.remove(n.history) end
            if deps.navigation_report then
                local ok, err = pcall(deps.navigation_report, result)
                if not ok then deps.report(tostring(err)) end
            end
        end
    end
    local function invalid()
        if not state.alive or not controls.enabled then return "disabled" end
        local s, clock = controls.snapshot, controls.clock
        if not s or state.render_tick - s.render_tick > 120 then return "waiting" end
        if not clock or not clock.position or state.render_tick - clock.render_tick > 2 then return "position_unavailable" end
        if s.replay_id ~= clock.replay_id or s.core_address ~= clock.core_address then return "replay_changed" end
        if not s.paused then return "pause_first" end
        if s.changing_round then return "round_changing" end
        if s.modal then return s.modal_reason or "menu_open" end
        if s.takeover then return "takeover_active" end
    end
    function n:start(target, stable_frames, press_ms)
        if self.active then return false end
        stable_frames = stable_frames or 3
        if stable_frames ~= 1 and stable_frames ~= 2 and stable_frames ~= 3 then return false end
        press_ms = press_ms or 45
        if press_ms ~= 45 and press_ms ~= 30 and press_ms ~= 20 and press_ms ~= 12 then return false end
        if not integer(target) then self.status, self.reason = "invalid_target", nil; return false end
        local reason = invalid()
        if reason then self.status, self.reason = "stopped", reason; return false end
        if not controls:claim(self) then self.status, self.reason = "stopped", "control_busy"; return false end
        local clock = controls.clock
        self.target, self.round, self.replay_id = target, clock.position.round, clock.replay_id
        self.core_address = clock.core_address
        self.current, self.expected = clock.position.frame, clock.position.frame
        self.start_frame, self.stable_frames = self.current, stable_frames
        self.press_ms, self.held_ms, self.held_samples = press_ms, 0, 0
        self.started_at, self.started_tick, self.elapsed, self.final_tick = nil, nil, nil, nil
        self.timing = {prepare = 0, release = 0, confirm = 0}
        self.active, self.status, self.reason = true, "close_overlay", nil
        self.started, self.waiting, self.steps, self.strides = false, nil, 0, {}
        self.max_tier, self.deadline = 3, state.render_tick + 600
        if self.current == target then stop("reached") end
        return true
    end
    function n:cancel() if self.active then stop("cancelled") end end
    local function update()
        if not n.active then return end
        local reason = invalid()
        if reason then stop("stopped", reason); return end
        local clock = controls.clock
        n.current = clock.position.frame
        if clock.replay_id ~= n.replay_id or clock.core_address ~= n.core_address then stop("stopped", "replay_changed"); return end
        if clock.position.round ~= n.round then stop("stopped", "round_changed"); return end
        local overlay = deps.keyboard:overlay_open()
        if overlay and n.started and (controls.pending or controls.awaiting) then stop("cancelled", "overlay_open"); return end
        if not overlay and not n.started then
            n.started, n.deadline = true, state.render_tick + 18000
            n.started_at, n.started_tick = now(), state.render_tick
        end
        if n.started and state.render_tick > n.deadline then stop("stopped", "navigation_limit"); return end
        if n.waiting then
            if controls.pending or controls.awaiting then return end
            local r, w = controls.last_result, n.waiting
            if controls.status ~= "confirmed" then stop("stopped", controls.status); return end
            if not r or r.request_id ~= w.request_id or r.action ~= w.action
                or r.before.round ~= n.round or r.after.round ~= n.round
                or r.before.frame ~= w.before or r.after.frame ~= n.current then
                stop("stopped", "position_changed"); return
            end
            local delta = r.after.frame - r.before.frame
            local direction = n.target > w.before and 1 or -1
            if delta * direction <= 0 or (w.tier == 1 and math.abs(delta) ~= 1) then
                stop("stopped", "position_changed"); return
            end
            if w.tier > 1 then
                n.strides[w.action] = math.abs(delta)
                -- Overshooting retires this size for the run, avoiding oscillation.
                if (n.target - n.current) * direction < 0 then n.max_tier = w.tier - 1 end
            end
            for k in pairs(n.timing) do n.timing[k] = n.timing[k] + ((r.timing or {})[k] or 0) end
            if type(r.held_ms) == "number" then n.held_ms, n.held_samples = n.held_ms + r.held_ms, n.held_samples + 1 end
            n.expected, n.waiting = n.current, nil
        end
        if n.current ~= n.expected then stop("stopped", "position_changed"); return end
        if n.current == n.target then
            -- Faster intermediate confirmation must not weaken the final landing check.
            if n.stable_frames < 3 then
                n.final_tick = n.final_tick or state.render_tick
                if state.render_tick - n.final_tick < 3 then n.status = "settling"; return end
            end
            stop("reached"); return
        end
        if overlay then
            if n.started then stop("cancelled", "overlay_open"); return end
            if state.render_tick > n.deadline then stop("stopped", "expired") end
            return
        end
        if n.steps >= 512 then stop("stopped", "navigation_limit"); return end
        local gap, action, tier = n.target - n.current, nil, 1
        for i = n.max_tier, 1, -1 do
            local spec = tiers[i]
            local candidate = gap > 0 and spec.positive or spec.negative
            local stride = n.strides[candidate] or spec.estimate
            local smaller = i > 1 and tiers[i - 1].estimate or 1
            -- A nearer landing on the other side can save many smaller presses.
            if i == 1 or math.abs(gap) >= stride or math.abs(gap) > (stride + smaller) / 2 then
                action, tier = candidate, i; break
            end
        end
        local accepted, request_id = controls:request(action, n, {replay_id = n.replay_id,
            core_address = n.core_address, round = n.round, frame = n.current, stable_frames = n.stable_frames, press_ms = n.press_ms})
        if not accepted then stop("stopped", "control_busy"); return end
        n.steps, n.waiting, n.status = n.steps + 1,
            {action = action, before = n.current, tier = tier, request_id = request_id}, "seeking"
    end
    deps.re.on_frame(function()
        local ok, err = pcall(update)
        if not ok then stop("stopped", "failed"); deps.report(tostring(err)) end
    end)
    deps.re.on_script_reset(function() if n.active then stop("stopped", "disabled") end end)
    return n
end
return M
