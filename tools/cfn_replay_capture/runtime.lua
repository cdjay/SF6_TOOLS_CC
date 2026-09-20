local M = {}

function M.attach(deps)
    local schema, sessions, sampler = deps.schema, deps.sessions, deps.sampler
    local api, hooks, threads = deps.sdk, deps.re, deps.thread
    local state = { session = nil, render_tick = 0, alive = true, status = "ready", exported = false,
        in_flight = 0, post_in_flight = 0 }
    state.preview_until, state.preview_status = -1, "waiting"
    function state:request_preview()
        if self.alive then self.preview_until = self.render_tick + 2 end
    end
    local storage_key = "sf6cc_cfn_capture_session"
    local method = assert(api.find_type_definition("app.BattleFlow"):get_method("UpdateFrameMain"))
    assert(threads and threads.get_hook_storage and threads.get_id, "thread API unavailable")

    function state:can_dispatch_control(tid)
        if not self.alive or tid == nil or self.post_in_flight ~= 0 then return false end
        -- Controls are paused-only; do not dispatch inside any native battle update.
        return self.in_flight == 0
    end

    function state:start(speed, options, owner)
        if not self.alive then return false end
        if self.control_block and (not owner or self.control_owner ~= owner) then self.status = "wait_update"; return false end
        if self.session and self.session:is_active() then return false end
        if self.in_flight ~= 0 then self.status = "wait_update"; return false end
        if self.session and #self.session.samples > 0 and not self.exported then
            self.status = "export_first"; return false
        end
        options = options or {}
        self.wait_for_end = options.wait_for_end == true and owner ~= nil and self.control_owner == owner
        self.missing_replay_tick = nil
        self.session = sessions.new(schema, { speed = speed, created_at = deps.date("!%Y-%m-%dT%H:%M:%SZ"),
            round_scope = options.round_scope, stop_at_finish = options.stop_at_finish, limit = options.limit })
        self.exported, self.saved_path = false, nil
        self.preview_failed = false
        self.status = "waiting"
        return true
    end

    function state:stop()
        if self.session then self.session:stop("manual") end
        local reason = self.session and self.session.stop_reason
        self.status = reason and reason ~= "manual" and reason or "stopped"
    end

    function state:save()
        local session = self.session
        if not session or #session.samples == 0 then self.status = "empty"; return false end
        if session:is_active() then self.status = "stop_first"; return false end
        local ok, result = pcall(function()
            local existing = {}
            for _, path in ipairs(deps.fs.glob([[cfn-capture-.*\.json]])) do
                existing[path:match("[^/\\]+$")] = true
            end
            local replay_id=session.metadata and session.metadata.replay_id
            assert(type(replay_id)=="string" and #replay_id<=64 and replay_id:match("^[A-Za-z0-9_]+$"),"invalid replay ID")
            local stem = "cfn-capture-" .. replay_id .. "-" .. deps.date("%Y%m%d-%H%M%S")
            local path, suffix = stem .. ".json", 1
            while existing[path] do path = stem .. "-" .. suffix .. ".json"; suffix = suffix + 1 end
            assert(deps.json.dump_file(path, session:export(), 2) == true, "export failed")
            return path
        end)
        if not ok then self.status = "export_failed"; deps.report(result); return false end
        self.status, self.exported, self.saved_path = "saved", true, result
        return true
    end

    local function fail(session, code, detail)
        if session then session:fail(code, detail); state.status = code end
        state.latest, state.preview_status, state.preview_until = nil, code, -1
        state.preview_failed = true
        deps.report(tostring(code) .. ": " .. tostring(detail or ""))
    end

    api.hook(method, function()
        local storage = threads.get_hook_storage()
        storage[storage_key] = false
        if not state.alive then return end
        local session = state.session
        if session and not session:is_active() then session = nil end
        local tid = threads.get_id()
        -- REFramework locks each Lua callback, not the entire native call.
        -- Track open invocations, including dormant ones, instead of pinning an OS thread.
        state.in_flight = state.in_flight + 1
        local preview = not state.preview_failed and state.render_tick <= state.preview_until
            and state.last_preview_tick ~= state.render_tick
        storage[storage_key] = { session = session, preview = preview, thread_id = tid, render_tick = state.render_tick }
        if state.in_flight == 1 then state.open_thread = tid end
        if (session or preview) and state.in_flight > 1 then
            fail(session, "overlapping_update", "open=" .. state.in_flight
                .. " first_thread=" .. tostring(state.open_thread) .. " current_thread=" .. tid
                .. " samples=" .. (session and #session.samples or 0))
        end
    end, function(retval)
        local pending = threads.get_hook_storage()[storage_key]
        if not pending or pending.closed then
            if state.alive and ((state.session and state.session:is_active()) or state.render_tick <= state.preview_until) then
                fail(state.session, "unpaired_callback", "open=" .. state.in_flight)
            end
            return retval
        end
        local session = pending.session
        state.post_in_flight = state.post_in_flight + 1
        local ok, err = pcall(function()
            if not state.alive then return end
            if session and (session ~= state.session or not session:is_active()) then return end
            if not session and (not pending.preview or state.preview_failed or state.render_tick > state.preview_until) then return end
            if state.in_flight ~= 1 then fail(session, "overlapping_update", "open=" .. state.in_flight); return end
            local post_thread = threads.get_id()
            if pending.thread_id ~= post_thread then
                fail(session, "callback_thread_mismatch", "pre=" .. pending.thread_id .. " post=" .. post_thread)
                return
            end
            local context = sampler:context()
            if not context then
                state.latest, state.preview_status = nil, "outside"
                state.last_preview_tick = pending.render_tick
                if session and #session.samples > 0 then
                    state.missing_replay_tick = state.missing_replay_tick or state.render_tick
                    if not state.wait_for_end or state.render_tick-state.missing_replay_tick >= 120 then
                        session:stop("left_replay"); state.status = "left_replay"
                    end
                end
                return
            end
            state.missing_replay_tick = nil
            if session and session.metadata and context.replay_id ~= session.metadata.replay_id then
                fail(session, "replay_changed"); return
            end
            local metadata = session and session.metadata or sampler:metadata(context)
            metadata.sampling_policy = "non_overlapping_update_callbacks_v1"
            local values = sampler:sample(context, pending.render_tick, pending.thread_id, api.to_int64(retval) & 0xff)
            if not state.alive or state.preview_failed then return end
            if session then
                if not session:add(metadata, values) then state.status = session.stop_reason; return end
                state.status = session:is_active() and "capturing" or session.stop_reason
            end
            state.latest = { metadata = metadata, values = values, render_tick = pending.render_tick }
            state.last_preview_tick, state.preview_status = pending.render_tick, "ready"
        end)
        state.post_in_flight = state.post_in_flight - 1
        pending.closed = true
        state.in_flight = state.in_flight - 1
        if state.in_flight == 0 then state.open_thread = nil end
        if not ok then fail(session, "read_error", err) end
        return retval
    end)

    hooks.on_frame(function()
        if not state.alive then return end
        state.render_tick = state.render_tick + 1
        if state.missing_replay_tick and state.render_tick-state.missing_replay_tick >= 120
            and state.session and state.session:is_active() then
            state.session:stop("left_replay"); state.status = "left_replay"
        end
    end)
    hooks.on_script_reset(function()
        state.alive = false
        state.latest, state.preview_until = nil, -1
        if state.session then state.session:stop("script_reset") end
    end)
    return state
end

return M
